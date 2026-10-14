import { MODEL_TERMS_POLICY_VERSION } from '@bible/ai-harness';
import { describe, it, expect } from 'vitest';
import { app } from '../src/index';
import { TestDatabase, testEnv, seedUser } from './helpers/db';
import { PRICING_VERSION } from '@bible/ai-harness';
const model = '@cf/google/gemma-4-26b-a4b-it';
async function setup(db = new TestDatabase()) {
  let calls = 0;
  const env = {
    ...testEnv(db),
    AI_ENABLED: 'true',
    CONNECTED_MODELS: JSON.stringify([model]),
    TERMS_REVIEWED_MODELS: JSON.stringify([model]), // Synthetic local fixture only.
    TERMS_REVIEW_VERSION: MODEL_TERMS_POLICY_VERSION,
    AI: {
      async run() {
        calls++;
        return { response: JSON.stringify({ status: 'answer', claimKeys: ['s0c0'] }) };
      },
    },
  };
  const user = await seedUser(env);
  await env.DB.prepare('UPDATE users SET settings_json=? WHERE id=?')
    .bind('{"workersAiConsent":true}', user.id)
    .run();
  await env.DB.prepare(
    'INSERT INTO model_budget_proofs(model_id,pricing_version,bounds_json,created_at) VALUES(?,?,?,?)',
  )
    .bind(
      model,
      PRICING_VERSION,
      JSON.stringify({
        modelId: model,
        pricingVersion: PRICING_VERSION,
        inputTokenUpperBound: 100000,
        outputTokenUpperBound: 2048,
        includesHiddenReasoning: true,
        evidenceRef: 'synthetic-unit-test-only-not-live-proof',
        expiresAt: new Date(Date.now() + 3600000).toISOString(),
      }),
      1,
    )
    .run();
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
      { method: 'POST', headers: user.headers, body: JSON.stringify({ importId: imported.id }) },
      env,
    )
  ).json()) as { id: string };
  return { env, user, conversation, calls: () => calls, db };
}
describe('durable request identity and pre-claim cancellation', () => {
  it('persists cancellation before the original POST reaches its claim', async () => {
    const { env, user, conversation, calls, db } = await setup();
    const requestId = crypto.randomUUID();
    let release!: () => void, entered!: () => void;
    const pause = new Promise<void>((r) => (release = r)),
      ready = new Promise<void>((r) => (entered = r));
    const original = db.prepare.bind(db);
    let gated = false;
    db.prepare = (sql: string) => {
      const statement = original(sql);
      if (sql === 'SELECT version FROM source_policy_state WHERE id=1' && !gated) {
        gated = true;
        const first = statement.first.bind(statement);
        statement.first = async function <T>(column?: string) {
          entered();
          await pause;
          return first<T>(column);
        };
      }
      return statement;
    };
    const payload = { requestId, question: '誓願について' };
    const post = () =>
      app.request(
        `/v1/conversations/${conversation.id}/questions`,
        { method: 'POST', headers: user.headers, body: JSON.stringify(payload) },
        env,
      );
    const pending = post();
    await ready;
    // At this instant a read alone is inconclusive, while DELETE creates a durable stop record.
    expect(
      (await app.request(`/v1/requests/${requestId}`, { headers: user.headers }, env)).status,
    ).toBe(404);
    expect(
      (
        await app.request(
          `/v1/requests/${requestId}`,
          { method: 'DELETE', headers: user.headers },
          env,
        )
      ).status,
    ).toBe(200);
    release();
    expect((await pending).status).toBe(409);
    expect((await post()).status).toBe(409);
    expect(calls()).toBe(0);
    expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM generation_requests').first()).toEqual({
      n: 0,
    });
    expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM budget_reservations').first()).toEqual({
      n: 0,
    });
    const status = (await (
      await app.request(`/v1/requests/${requestId}`, { headers: user.headers }, env)
    ).json()) as { status: string };
    expect(status.status).toBe('cancelled');
    const other = await seedUser(env);
    expect(
      (await app.request(`/v1/requests/${requestId}`, { headers: other.headers }, env)).status,
    ).toBe(404);
  });
  it('simultaneous retries with the same frozen UUID never dispatch twice', async () => {
    const { env, user, conversation, calls } = await setup();
    const payload = { requestId: crypto.randomUUID(), question: '髪を切ったのはなぜ？' };
    const post = () =>
      app.request(
        `/v1/conversations/${conversation.id}/questions`,
        { method: 'POST', headers: user.headers, body: JSON.stringify(payload) },
        env,
      );
    const responses = await Promise.all([post(), post()]);
    expect(responses.some((r) => r.status === 200)).toBe(true);
    expect(responses.every((r) => [200, 409].includes(r.status))).toBe(true);
    expect(calls()).toBe(1);
    expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM budget_reservations').first()).toEqual({
      n: 1,
    });
    expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM messages').first()).toEqual({ n: 2 });
    expect((await post()).status).toBe(200);
    expect(calls()).toBe(1);
  });
  it('rejects a malformed cancellation ID without storing a tombstone', async () => {
    const { env, user } = await setup();
    expect(
      (
        await app.request(
          '/v1/requests/not-a-uuid',
          { method: 'DELETE', headers: user.headers },
          env,
        )
      ).status,
    ).toBe(400);
    expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM request_cancellations').first()).toEqual(
      { n: 0 },
    );
  });
});
