import { describe, it, expect } from 'vitest';
import { app } from '../src/index';
import { testEnv, seedUser } from './helpers/db';
import { MODEL_TERMS_POLICY_VERSION } from '@bible/ai-harness';
import { GROUNDED_POLICY_VERSION } from '../src/answer-mode';
async function setup() {
  const env = testEnv();
  let calls = 0;
  Object.assign(env, {
    SHARE_AI_ENABLED: 'true',
    AI_ENABLED: 'true',
    CONNECTED_MODELS: '["@cf/google/gemma-4-26b-a4b-it"]',
    TERMS_REVIEWED_MODELS: '["@cf/google/gemma-4-26b-a4b-it"]',
    TERMS_REVIEW_VERSION: MODEL_TERMS_POLICY_VERSION,
    ALLOWED_ANSWER_MODES: '["grounded-generation"]',
    AI_BUDGET_MODE: 'free-provider-hard-stop',
    WORKERS_AI_ACCOUNT_ID: 'a'.repeat(32),
    AI_FREE_RECEIPT_ID: 'share-fixture',
    AI: {
      async run() {
        calls++;
        return {
          response: JSON.stringify({
            status: 'answer',
            claims: [
              {
                text: 'プリスキラとアキラは神の道をより正確に説明しました。',
                kind: 'fact',
                sourceId: 'act-18-24-26',
                evidenceQuote: 'explained to him the way of God more accurately',
              },
            ],
          }),
        };
      },
    },
  });
  const user = await seedUser(env);
  const request = (path: string, body: unknown, headers: Record<string, string> = user.headers) =>
    app.request(path, { method: 'POST', headers, body: JSON.stringify(body) }, env);
  const consent = () =>
    request('/v1/me/consents', {
      workersAi: true,
      groundedGeneration: { accepted: true, policyVersion: GROUNDED_POLICY_VERSION },
    });
  const issue = async () => {
    await consent();
    const r = await request('/v1/me/share-access', { enabled: true });
    expect(r.status).toBe(200);
    const v = (await r.json()) as { token: string; ownerId: string; expiresAt: number };
    return {
      ...v,
      headers: { Authorization: 'Bearer ' + v.token, 'Content-Type': 'application/json' },
    };
  };
  const start = async (headers: { Authorization: string; 'Content-Type': string }) => {
    const r = await request(
      '/share/start',
      { requestId: crypto.randomUUID(), sharedText: '使徒18:24-26' },
      headers,
    );
    expect(r.status).toBe(200);
    return (await r.json()) as { items: { conversationId: string }[] };
  };
  return { env, user, request, consent, issue, start, calls: () => calls };
}

const claim = {
  text: 'プリスキラとアキラは神の道をより正確に説明しました。',
  kind: 'fact',
  sourceId: 'act-18-24-26',
  evidenceQuote: 'explained to him the way of God more accurately',
};
function streamChunks(chunks: string[], close = true) {
  return new ReadableStream<Uint8Array>({
    start(c) {
      for (const response of chunks)
        c.enqueue(new TextEncoder().encode('data: ' + JSON.stringify({ response }) + '\n\n'));
      if (close) c.enqueue(new TextEncoder().encode('data: [DONE]\n\n'));
      c.close();
    },
  });
}
describe('private conversation SSE transport', () => {
  it('emits real validated previews before provider completion, persists one pair and preserves history', async () => {
    const x = await setup(),
      a = await x.issue(),
      start = await x.start(a.headers),
      id = start.items[0].conversationId;
    let controller!: ReadableStreamDefaultController<Uint8Array>;
    let calls = 0;
    const seen: unknown[] = [];
    x.env.AI = {
      async run(model, inputs) {
        calls++;
        expect(model).toBe('@cf/google/gemma-4-26b-a4b-it');
        expect(inputs.stream).toBe(true);
        seen.push(JSON.parse((inputs.messages as { content: string }[])[1].content));
        return new ReadableStream<Uint8Array>({
          start(c) {
            controller = c;
          },
        });
      },
    };
    const requestId = crypto.randomUUID();
    const headers = { ...a.headers, Accept: 'text/event-stream' };
    const response = await x.request(
      '/share/conversations/' + id + '/questions',
      { requestId, question: 'PRIVATE 誰？', answerMode: 'grounded-generation' },
      headers,
    );
    expect(response.headers.get('content-type')).toContain('text/event-stream');
    expect(response.headers.get('cache-control')).toContain('no-store');
    const reader = response.body!.getReader(),
      decoder = new TextDecoder();
    let wire = '';
    while (!wire.includes('"stage":"generating"')) {
      const part = await reader.read();
      expect(part.done).toBe(false);
      wire += decoder.decode(part.value);
    }
    // Generation has been dispatched; no final model response has been delivered.
    while (!controller) await new Promise((r) => setTimeout(r, 0));
    const raw = JSON.stringify({ status: 'answer', claims: [claim] });
    controller.enqueue(
      new TextEncoder().encode('data: ' + JSON.stringify({ response: raw.slice(0, -2) }) + '\n\n'),
    );
    while (!wire.includes('event: preview')) {
      const part = await reader.read();
      expect(part.done).toBe(false);
      wire += decoder.decode(part.value);
    }
    expect(wire).toContain(claim.text);
    expect(wire).not.toContain('event: complete');
    controller.enqueue(
      new TextEncoder().encode(
        'data: ' + JSON.stringify({ response: raw.slice(-2) }) + '\n\ndata: [DONE]\n\n',
      ),
    );
    controller.close();
    while (true) {
      const part = await reader.read();
      if (part.done) break;
      wire += decoder.decode(part.value);
    }
    expect(wire).toContain('event: complete');
    expect(wire).toContain('"cache":"private"');
    expect(
      (
        await x.env.DB.prepare('SELECT COUNT(*) AS n FROM messages WHERE conversation_id=?')
          .bind(id)
          .first<{ n: number }>()
      )?.n,
    ).toBe(2);
    x.env.AI = {
      async run(_, inputs) {
        seen.push(JSON.parse((inputs.messages as { content: string }[])[1].content));
        return streamChunks([raw]);
      },
    };
    const second = await x.request(
      '/share/conversations/' + id + '/questions',
      { requestId: crypto.randomUUID(), question: 'その人は？', answerMode: 'grounded-generation' },
      headers,
    );
    expect(await second.text()).toContain('event: complete');
    expect(JSON.stringify(seen[1])).toContain('PRIVATE 誰？');
    expect(JSON.stringify(seen[1])).toContain(claim.text);
    expect(
      (
        await x.env.DB.prepare('SELECT COUNT(*) AS n FROM standard_explanations').first<{
          n: number;
        }>()
      )?.n,
    ).toBe(0);
    expect(calls).toBe(1);
  });
  it('reports truncated generation as failure, never saves preview, and scopes cancellation to the exact share capability', async () => {
    const x = await setup(),
      a = await x.issue(),
      start = await x.start(a.headers),
      id = start.items[0].conversationId;
    x.env.AI = {
      async run() {
        return streamChunks(
          [JSON.stringify({ status: 'answer', claims: [claim] }).slice(0, -2)],
          false,
        );
      },
    };
    const requestId = crypto.randomUUID();
    const response = await x.request(
      '/share/conversations/' + id + '/questions',
      { requestId, question: '途中失敗', answerMode: 'grounded-generation' },
      { ...a.headers, Accept: 'text/event-stream' },
    );
    const wire = await response.text();
    expect(wire).toContain('event: preview');
    expect(wire).toContain('event: failure');
    expect(wire).not.toContain('event: complete');
    expect(
      (
        await x.env.DB.prepare('SELECT COUNT(*) AS n FROM messages WHERE conversation_id=?')
          .bind(id)
          .first<{ n: number }>()
      )?.n,
    ).toBe(0);
    const b = await x.issue();
    expect(
      (
        await app.request(
          '/share/requests/' + requestId,
          { method: 'DELETE', headers: b.headers },
          x.env,
        )
      ).status,
    ).toBe(404);
    expect(
      (
        await app.request(
          '/share/requests/' + requestId,
          { method: 'DELETE', headers: a.headers },
          x.env,
        )
      ).status,
    ).toBe(200);
    expect(
      (await app.request('/share/requests/' + requestId, { headers: b.headers }, x.env)).status,
    ).toBe(404);
  });
  it('keeps transport choice out of the fixed public explanation cache', async () => {
    const x = await setup(),
      a = await x.issue(),
      start = await x.start(a.headers),
      id = start.items[0].conversationId;
    expect(
      (
        await x.request(
          '/share/conversations/' + id + '/explanation',
          { requestId: crypto.randomUUID() },
          a.headers,
        )
      ).status,
    ).toBe(200);
    x.env.AI = {
      async run() {
        throw Error('cache must bypass provider');
      },
    };
    const other = await seedUser(x.env);
    await x.request(
      '/v1/me/consents',
      {
        workersAi: true,
        groundedGeneration: { accepted: true, policyVersion: GROUNDED_POLICY_VERSION },
      },
      other.headers,
    );
    const cap = (await (
      await x.request('/v1/me/share-access', { enabled: true }, other.headers)
    ).json()) as { token: string };
    const headers = {
      Authorization: 'Bearer ' + cap.token,
      'Content-Type': 'application/json',
      Accept: 'text/event-stream',
    };
    const reading = await x.start(headers);
    const wire = await (
      await x.request(
        '/share/conversations/' + reading.items[0].conversationId + '/explanation',
        { requestId: crypto.randomUUID() },
        headers,
      )
    ).text();
    expect(wire).toContain('public-standard-hit');
    expect(wire).not.toContain(a.ownerId);
    expect(wire).toContain('event: complete');
  });
});

describe('renewable share credentials', () => {
  it('renews expired access without new consent or inference and preserves conversation scope', async () => {
    const f = await setup();
    const access = (await f.issue()) as Awaited<ReturnType<typeof f.issue>> & {
      refreshToken: string;
      scopeId: string;
      refreshExpiresAt: number;
    };
    const started = await f.start(access.headers);
    const id = started.items[0].conversationId;
    await f.env.DB.prepare('UPDATE share_ai_tokens SET expires_at=0 WHERE access_hash=?')
      .bind(access.scopeId)
      .run();
    await f.env.DB.prepare('UPDATE share_ai_access SET expires_at=0 WHERE token_hash=?')
      .bind(access.scopeId)
      .run();
    const expired = await f.request(
      '/share/conversations/' + id + '/questions',
      { requestId: crypto.randomUUID(), question: '解説して' },
      access.headers,
    );
    expect(expired.status).toBe(401);
    const r = await f.request(
      '/share/renew',
      {},
      { Authorization: 'Bearer ' + access.refreshToken, 'Content-Type': 'application/json' },
    );
    expect(r.status).toBe(200);
    const renewed = (await r.json()) as typeof access;
    expect(renewed.scopeId).toBe(access.scopeId);
    expect(renewed.token).not.toBe(access.token);
    expect(renewed.refreshToken).toBe(access.refreshToken);
    expect(f.calls()).toBe(0);
    const oldAfterRenewal = await f.request(
      '/share/conversations/' + id + '/questions',
      { requestId: crypto.randomUUID(), question: '解説して' },
      access.headers,
    );
    expect(oldAfterRenewal.status).toBe(401);
    const continued = await f.request(
      '/share/conversations/' + id + '/questions',
      {
        requestId: crypto.randomUUID(),
        question: '何を教えた？',
        answerMode: 'grounded-generation',
      },
      { Authorization: 'Bearer ' + renewed.token, 'Content-Type': 'application/json' },
    );
    expect(continued.status).toBe(200);
    expect(f.calls()).toBe(1);
    const general = await app.request(
      '/v1/me',
      { headers: { Authorization: 'Bearer ' + renewed.token } },
      f.env,
    );
    expect(general.status).toBe(401);
  });
  it.each(['logout', 'withdraw', 'epoch', 'parent-expiry', 'refresh-expiry'] as const)(
    'rejects renewal after %s',
    async (reason) => {
      const f = await setup();
      const a = (await f.issue()) as Awaited<ReturnType<typeof f.issue>> & {
        refreshToken: string;
        scopeId: string;
      };
      if (reason === 'logout')
        await f.env.DB.prepare('DELETE FROM sessions WHERE user_id=?').bind(f.user.id).run();
      if (reason === 'withdraw') await f.request('/v1/me/consents', { workersAi: false });
      if (reason === 'epoch')
        await f.env.DB.prepare('UPDATE users SET data_epoch=data_epoch+1 WHERE id=?')
          .bind(f.user.id)
          .run();
      if (reason === 'parent-expiry')
        await f.env.DB.prepare('UPDATE sessions SET expires_at=0 WHERE user_id=?')
          .bind(f.user.id)
          .run();
      if (reason === 'refresh-expiry')
        await f.env.DB.prepare('UPDATE share_ai_access SET refresh_expires_at=0 WHERE token_hash=?')
          .bind(a.scopeId)
          .run();
      const r = await f.request(
        '/share/renew',
        {},
        { Authorization: 'Bearer ' + a.refreshToken, 'Content-Type': 'application/json' },
      );
      expect(r.status).toBe(401);
      expect(f.calls()).toBe(0);
    },
  );
  it('does not resurrect old refresh credentials after consent is granted again', async () => {
    const f = await setup();
    const a = (await f.issue()) as Awaited<ReturnType<typeof f.issue>> & { refreshToken: string };
    await f.request('/v1/me/consents', { workersAi: false });
    await f.consent();
    const r = await f.request(
      '/share/renew',
      {},
      { Authorization: 'Bearer ' + a.refreshToken, 'Content-Type': 'application/json' },
    );
    expect(r.status).toBe(401);
    expect(f.calls()).toBe(0);
  });
  it('keeps different scopes isolated and retries renewal safely after a lost response', async () => {
    const f = await setup();
    const a = (await f.issue()) as Awaited<ReturnType<typeof f.issue>> & {
      refreshToken: string;
      scopeId: string;
    };
    const b = await f.issue();
    const started = await f.start(b.headers);
    const headers = {
      Authorization: 'Bearer ' + a.refreshToken,
      'Content-Type': 'application/json',
    };
    const x = await f.request('/share/renew', {}, headers);
    expect(x.status).toBe(200);
    const y = await f.request('/share/renew', {}, headers);
    expect(y.status).toBe(200);
    const fresh = (await y.json()) as typeof a;
    const cross = await f.request(
      '/share/conversations/' + started.items[0].conversationId + '/questions',
      { requestId: crypto.randomUUID(), question: '解説して' },
      { Authorization: 'Bearer ' + fresh.token, 'Content-Type': 'application/json' },
    );
    expect(cross.status).toBe(404);
    expect(f.calls()).toBe(0);
  });
});
