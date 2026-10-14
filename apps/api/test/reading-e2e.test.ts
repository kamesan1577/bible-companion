import { MODEL_TERMS_POLICY_VERSION } from '@bible/ai-harness';
import { describe, it, expect } from 'vitest';
import { app } from '../src/index';
import { testEnv, seedUser } from './helpers/db';
import type { Env } from '../src/types';
async function setup(env: Env = testEnv(), spoilerAllowed = false) {
  const user = await seedUser(env);
  const imported = (await (
    await app.request(
      '/v1/imports',
      {
        method: 'POST',
        headers: user.headers,
        body: JSON.stringify({ idempotencyKey: crypto.randomUUID(), sharedText: '使徒18:18 JCB' }),
      },
      env,
    )
  ).json()) as { id: string };
  const conversation = (await (
    await app.request(
      '/v1/conversations',
      {
        method: 'POST',
        headers: user.headers,
        body: JSON.stringify({ importId: imported.id, spoilerAllowed }),
      },
      env,
    )
  ).json()) as { id: string };
  return { env, user, imported, conversation };
}
describe('reading to question integration', () => {
  it('imports, serves a reviewed reading overview, answers source-only, and resumes ordered history', async () => {
    const { env, user, imported, conversation } = await setup();
    const reading = await app.request(
      `/v1/imports/${imported.id}/reading`,
      { headers: user.headers },
      env,
    );
    expect(reading.status).toBe(200);
    const page = (await reading.json()) as {
      cache: string;
      overview: { modelInvoked: boolean; text: string };
      sources: { id: string }[];
    };
    expect(page.cache).toBe('public-miss');
    expect(page.overview.modelInvoked).toBe(false);
    expect(page.overview.text).toContain('AIによる回答ではありません');
    expect(page.sources.some((s) => s.id === 'act-18-24-26')).toBe(false);
    const cache = (await (
      await app.request(`/v1/imports/${imported.id}/reading`, { headers: user.headers }, env)
    ).json()) as { cache: string };
    expect(cache.cache).toBe('public-hit');
    const question = {
      requestId: crypto.randomUUID(),
      question: '髪を切ったのはなぜ？',
      sourceOnly: true,
    };
    const ask = () =>
      app.request(
        `/v1/conversations/${conversation.id}/questions`,
        { method: 'POST', headers: user.headers, body: JSON.stringify(question) },
        env,
      );
    const answer = await ask();
    expect(answer.status).toBe(200);
    const result = (await answer.json()) as {
      result: { answer: string; modelInvoked: boolean; citations: unknown[] };
    };
    expect(result.result.modelInvoked).toBe(false);
    expect(result.result.answer).toContain('誓願');
    expect(result.result.citations.length).toBeGreaterThan(0);
    expect((await ask()).status).toBe(200);
    const history = (await (
      await app.request(`/v1/conversations/${conversation.id}`, { headers: user.headers }, env)
    ).json()) as { messages: { role: string }[] };
    expect(history.messages.map((m) => m.role)).toEqual(['user', 'assistant']);
    expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM budget_reservations').first()).toEqual({
      n: 0,
    });
  });
  it('revoking a source bypasses previously valid public cache immediately', async () => {
    const { env, user, imported } = await setup();
    const path = `/v1/imports/${imported.id}/reading`;
    const before = (await (await app.request(path, { headers: user.headers }, env)).json()) as {
      sourceVersion: string;
    };
    await env.DB.prepare(
      "UPDATE public_sources SET rights_status='revoked' WHERE id='act-18-18'",
    ).run();
    const after = (await (await app.request(path, { headers: user.headers }, env)).json()) as {
      sourceVersion: string;
      cache: string;
      sources: { id: string }[];
    };
    expect(after.sourceVersion).not.toBe(before.sourceVersion);
    expect(after.cache).toBe('public-miss');
    expect(after.sources.some((s) => s.id === 'act-18-18')).toBe(false);
  });
  it('hides prior spoiler-on answers after changing the setting', async () => {
    const { env, user, conversation } = await setup(testEnv(), true);
    const requestId = crypto.randomUUID();
    expect(
      (
        await app.request(
          `/v1/conversations/${conversation.id}/questions`,
          {
            method: 'POST',
            headers: user.headers,
            body: JSON.stringify({ requestId, question: 'ここについて', sourceOnly: true }),
          },
          env,
        )
      ).status,
    ).toBe(200);
    await app.request(
      `/v1/conversations/${conversation.id}`,
      { method: 'PATCH', headers: user.headers, body: '{"spoilerAllowed":false}' },
      env,
    );
    const history = (await (
      await app.request(`/v1/conversations/${conversation.id}`, { headers: user.headers }, env)
    ).json()) as { messages: { role: string; content: { hidden?: boolean } }[] };
    expect(history.messages.find((x) => x.role === 'assistant')?.content.hidden).toBe(true);
    const request = (await (
      await app.request(`/v1/requests/${requestId}`, { headers: user.headers }, env)
    ).json()) as { result: unknown };
    expect(request.result).toBeNull();
  });
  it('requires consent before any external inference and does not charge rejected requests', async () => {
    let calls = 0;
    const env = {
      ...testEnv(),
      AI_ENABLED: 'true',
      CONNECTED_MODELS: '["@cf/google/gemma-4-26b-a4b-it"]',
      TERMS_REVIEWED_MODELS: '["@cf/google/gemma-4-26b-a4b-it"]', // Synthetic local fixture only.
      TERMS_REVIEW_VERSION: MODEL_TERMS_POLICY_VERSION,
      AI: {
        async run() {
          calls++;
          return { response: '{}' };
        },
      },
    };
    const { user, conversation } = await setup(env);
    const r = await app.request(
      `/v1/conversations/${conversation.id}/questions`,
      {
        method: 'POST',
        headers: user.headers,
        body: JSON.stringify({ requestId: crypto.randomUUID(), question: 'どうして？' }),
      },
      env,
    );
    expect(r.status).toBe(403);
    expect(calls).toBe(0);
    expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM budget_reservations').first()).toEqual({
      n: 0,
    });
  });
  it('does not let raw clients provide model URLs, trusted source records or ownership', async () => {
    const { env, user, conversation } = await setup();
    for (const extra of [{ sources: [] }, { modelId: 'https://evil.test' }, { userId: 'other' }])
      expect(
        (
          await app.request(
            `/v1/conversations/${conversation.id}/questions`,
            {
              method: 'POST',
              headers: user.headers,
              body: JSON.stringify({
                requestId: crypto.randomUUID(),
                question: '背景は？',
                sourceOnly: true,
                ...extra,
              }),
            },
            env,
          )
        ).status,
      ).toBe(400);
  });
});
