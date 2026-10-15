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
