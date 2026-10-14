import { describe, it, expect } from 'vitest';
import { writeFileSync } from 'node:fs';
import { MODEL_TERMS_POLICY_VERSION, PRICING_VERSION } from '@bible/ai-harness';
import { app } from '../src/index';
import { TestDatabase, testEnv, seedUser } from './helpers/db';
function fixture(name: string, value: unknown) {
  if (process.env.UPDATE_API_FIXTURES !== '1') return;
  const normalize = (v: unknown, key = ''): unknown =>
    Array.isArray(v)
      ? v.map((x) => normalize(x))
      : v && typeof v === 'object'
        ? Object.fromEntries(Object.entries(v).map(([k, x]) => [k, normalize(x, k)]))
        : typeof v === 'number' && ['createdAt', 'expiresAt', 'leaseExpiresAt'].includes(key)
          ? 1791907200 + (key === 'expiresAt' ? 900 : key === 'leaseExpiresAt' ? 90 : 0)
          : typeof v === 'string' && /^[0-9a-f]{8}-[0-9a-f-]{27}$/.test(v)
            ? '00000000-0000-4000-8000-000000000001'
            : v;
  writeFileSync(
    new URL('../../../docs/fixtures/' + name + '.json', import.meta.url),
    JSON.stringify(normalize(value), null, 2) + '\n',
  );
}
const model = '@cf/google/gemma-4-26b-a4b-it';
async function setup(saveResults = false) {
  const db = new TestDatabase();
  let calls = 0;
  const env = {
    ...testEnv(db),
    AI_ENABLED: 'true',
    CONNECTED_MODELS: JSON.stringify([model]),
    TERMS_REVIEWED_MODELS: JSON.stringify([model]),
    TERMS_REVIEW_VERSION: MODEL_TERMS_POLICY_VERSION,
    AI: {
      async run() {
        calls++;
        return { response: JSON.stringify({ status: 'answer', claimKeys: ['s0c0'] }) };
      },
    },
  };
  const user = await seedUser(env, crypto.randomUUID(), 'owner');
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
        evidenceRef: 'synthetic-test-only',
        expiresAt: new Date(Date.now() + 3600000).toISOString(),
      }),
      1,
    )
    .run();
  const plan = {
    requestId: crypto.randomUUID(),
    models: [{ modelId: model, settings: {} }],
    questions: [
      {
        passage: {
          book: 'ACT',
          start: { chapter: 18, verse: 18 },
          end: { chapter: 18, verse: 18 },
        },
        question: 'この節の内容は？',
        spoilerAllowed: false,
      },
      {
        passage: {
          book: 'ACT',
          start: { chapter: 18, verse: 18 },
          end: { chapter: 18, verse: 18 },
        },
        question: 'どのような行動ですか？',
        spoilerAllowed: false,
      },
    ],
    saveResults,
  };
  const request = (path: string, method = 'GET', value?: unknown) =>
    app.request(
      '/v1/developer/comparisons' + path,
      { method, headers: user.headers, ...(value ? { body: JSON.stringify(value) } : {}) },
      env,
    );
  const prepared = await request('/plan', 'POST', plan);
  expect(prepared.status, await prepared.clone().text()).toBe(200);
  const { confirmationHash } = (await prepared.json()) as { confirmationHash: string };
  const payload = { plan, confirmationHash };
  return { env, db, user, plan, payload, request, calls: () => calls };
}
describe('single-trial durable comparison ledger', () => {
  it('starts without invocation and acknowledges each trial exactly once', async () => {
    const s = await setup(true);
    const start = await s.request('', 'POST', s.payload);
    expect(start.status, await start.clone().text()).toBe(202);
    fixture('comparison-start', await start.clone().json());
    expect(s.calls()).toBe(0);
    for (let trialIndex = 0; trialIndex < 2; trialIndex++) {
      const answer = await s.request('/' + s.plan.requestId + '/steps', 'POST', {
        ...s.payload,
        trialIndex,
      });
      expect(answer.status, await answer.clone().text()).toBe(200);
      if (trialIndex === 0) fixture('comparison-step', await answer.clone().json());
      const replay = await s.request('/' + s.plan.requestId + '/steps', 'POST', {
        ...s.payload,
        trialIndex,
      });
      expect(replay.status).toBe(200);
      expect(((await replay.json()) as { replayed: boolean }).replayed).toBe(true);
    }
    expect(s.calls()).toBe(2);
    const state = (await (await s.request('/' + s.plan.requestId)).json()) as {
      status: string;
      completedCount: number;
    };
    expect(state.status).toBe('complete');
    expect(state.completedCount).toBe(2);
    fixture('comparison-list', await (await s.request('')).json());
  });
  it('cancellation before start is durable and reserves nothing', async () => {
    const s = await setup();
    expect((await s.request('/' + s.plan.requestId, 'DELETE')).status).toBe(200);
    expect((await s.request('', 'POST', s.payload)).status).toBe(409);
    fixture(
      'comparison-cancelled-before-start',
      await (await s.request('/' + s.plan.requestId)).json(),
    );
    expect(s.calls()).toBe(0);
    expect(s.db.sqlite.prepare('SELECT COUNT(*) n FROM budget_reservations').get()?.n).toBe(0);
  });
  it('releases all undispatched allowance on idle expiry', async () => {
    const s = await setup();
    expect((await s.request('', 'POST', s.payload)).status).toBe(202);
    s.db.sqlite.prepare('UPDATE comparison_jobs SET expires_at=1 WHERE id=?').run(s.plan.requestId);
    const state = (await (await s.request('/' + s.plan.requestId)).json()) as { status: string };
    expect(state.status).toBe('expired');
    fixture('comparison-expired', state);
    expect(s.db.sqlite.prepare('SELECT actual,state FROM budget_reservations').get()).toMatchObject(
      { actual: 0, state: 'settled' },
    );
  });
  it('does not reconstruct an unsaved answer after a lost acknowledgment', async () => {
    const s = await setup();
    await s.request('', 'POST', s.payload);
    await s.request('/' + s.plan.requestId + '/steps', 'POST', { ...s.payload, trialIndex: 0 });
    const replay = (await (
      await s.request('/' + s.plan.requestId + '/steps', 'POST', { ...s.payload, trialIndex: 0 })
    ).json()) as { result: unknown; resultAvailability: string };
    expect(replay.result).toBeNull();
    expect(replay.resultAvailability).toBe('not_saved');
    expect(s.calls()).toBe(1);
  });
  it('refuses a queued trial whose frozen proof/runtime identity no longer matches', async () => {
    const s = await setup();
    expect((await s.request('', 'POST', s.payload)).status).toBe(202);
    s.db.sqlite
      .prepare(
        "UPDATE comparison_trials SET proof_fingerprint=proof_fingerprint||'|old-deployment' WHERE job_id=?",
      )
      .run(s.plan.requestId);
    const response = await s.request('/' + s.plan.requestId + '/steps', 'POST', {
      ...s.payload,
      trialIndex: 0,
    });
    expect(response.status).toBe(409);
    expect(s.calls()).toBe(0);
    expect(s.db.sqlite.prepare('SELECT actual,state FROM budget_reservations').get()).toMatchObject(
      { actual: 0, state: 'settled' },
    );
  });
});
