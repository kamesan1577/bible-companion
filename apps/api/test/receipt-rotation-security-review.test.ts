import { it, expect, describe } from 'vitest';
import { app } from '../src/index';
import { TestDatabase, testEnv, seedUser } from './helpers/db';
import { seedAssetCorpus, realAssetBinding } from './helpers/scripture-assets';
import { DEFAULT_MODEL_ID, MODEL_TERMS_POLICY_VERSION } from '@bible/ai-harness';
import { FREE_HARD_STOP_POLICY_VERSION } from '../src/budget';
import { GROUNDED_POLICY_VERSION } from '../src/answer-mode';
async function fixture(promptSpecific = false) {
  const db = new TestDatabase(),
    env = testEnv(db),
    user = await seedUser(env, crypto.randomUUID(), 'owner');
  let calls = 0;
  Object.assign(env, {
    AI_ENABLED: 'true',
    CONNECTED_MODELS: JSON.stringify([DEFAULT_MODEL_ID]),
    TERMS_REVIEWED_MODELS: JSON.stringify([DEFAULT_MODEL_ID]),
    TERMS_REVIEW_VERSION: MODEL_TERMS_POLICY_VERSION,
    ALLOWED_ANSWER_MODES: JSON.stringify(['reviewed-claim-selection', 'grounded-generation']),
    AI_BUDGET_MODE: 'free-provider-hard-stop',
    WORKERS_AI_ACCOUNT_ID: 'a'.repeat(32),
    AI_FREE_RECEIPT_MODE: 'slot',
    AI_FREE_RECEIPT_SLOT: 'review-slot',
    AI: {
      async run(_model: string, inputs: Record<string, unknown>) {
        calls++;
        if (promptSpecific) {
          const messages = inputs.messages as { content: string }[],
            source = JSON.parse(messages[1].content).sources[0];
          return {
            response: JSON.stringify(
              source
                ? {
                    status: 'answer',
                    claims: [
                      {
                        text: source.text.slice(0, 150),
                        kind: 'fact',
                        sourceId: source.id,
                        evidenceQuote: source.text.slice(0, 150),
                      },
                    ],
                  }
                : { status: 'insufficient', claims: [] },
            ),
          };
        }
        return {
          response: JSON.stringify({
            status: 'answer',
            claims: [
              {
                text: '創世記の冒頭では、神が天と地を創造したと記されています。',
                kind: 'fact',
                sourceId: 'webp:GEN:1:1',
                evidenceQuote: 'In the beginning, God created the heavens and the earth.',
              },
            ],
          }),
        };
      },
    },
  });
  const receipt = {
    schemaVersion: 1,
    policyVersion: FREE_HARD_STOP_POLICY_VERSION,
    accountId: env.WORKERS_AI_ACCOUNT_ID,
    verifiedAt: new Date(Date.now() - 60000).toISOString(),
    expiresAt: new Date(Date.now() + 3600000).toISOString(),
    evidenceRef: 'synthetic-security-test-not-a-real-account-verification',
    accountPlan: 'free',
    providerRoute: 'direct-workers-binding',
    gatewayCredits: false,
    paidModels: false,
    fallbacks: false,
  };
  await env.DB.prepare(
    'INSERT INTO ai_free_account_receipts(id,account_id,receipt_json,created_at) VALUES(?,?,?,1)',
  )
    .bind('review-receipt-A', env.WORKERS_AI_ACCOUNT_ID, JSON.stringify(receipt))
    .run();
  await env.DB.prepare(
    'INSERT INTO ai_free_receipt_slots(slot_id,account_id,receipt_id,generation,updated_at) VALUES(?,?,?,1,1)',
  )
    .bind(env.AI_FREE_RECEIPT_SLOT, env.WORKERS_AI_ACCOUNT_ID, 'review-receipt-A')
    .run();
  await env.DB.prepare('UPDATE users SET settings_json=? WHERE id=?')
    .bind(
      JSON.stringify({
        workersAiConsent: true,
        groundedGenerationConsent: true,
        groundedGenerationPolicyVersion: GROUNDED_POLICY_VERSION,
      }),
      user.id,
    )
    .run();
  seedAssetCorpus(db);
  env.SCRIPTURE_ASSETS = realAssetBinding();
  const passage = { book: 'GEN', start: { chapter: 1, verse: 1 }, end: { chapter: 1, verse: 3 } },
    post = (path: string, value: unknown) =>
      app.request(
        '/v1' + path,
        { method: 'POST', headers: user.headers, body: JSON.stringify(value) },
        env,
      );
  const imported = (await (
    await post('/imports', { idempotencyKey: crypto.randomUUID(), ranges: [passage] })
  ).json()) as { id: string };
  const chat = (await (await post('/conversations', { importId: imported.id })).json()) as {
    id: string;
  };
  return {
    db,
    env,
    user,
    post,
    passage,
    chat,
    receipt,
    calls: () => calls,
    ask: () =>
      post(`/conversations/${chat.id}/questions`, {
        requestId: crypto.randomUUID(),
        question: 'この箇所を説明してください',
        answerMode: 'grounded-generation',
      }),
  };
}
function pauseDispatch(db: TestDatabase, comparison: boolean) {
  let entered!: () => void,
    resume!: () => void,
    paused = false;
  const reached = new Promise<void>((r) => (entered = r)),
    gate = new Promise<void>((r) => (resume = r)),
    original = db.prepare.bind(db);
  db.prepare = (sql: string) => {
    const statement = original(sql);
    if (
      sql.startsWith(
        comparison
          ? 'UPDATE comparison_trials SET dispatched=1'
          : 'UPDATE generation_requests SET updated_at=',
      ) &&
      sql.includes('ai_free_account_receipts')
    ) {
      const bind = statement.bind.bind(statement);
      statement.bind = (...params: unknown[]) => {
        const bound = bind(...params),
          first = bound.first.bind(bound);
        bound.first = async <T = Record<string, unknown>>(column?: string): Promise<T | null> => {
          if (!paused) {
            paused = true;
            entered();
            await gate;
          }
          return first<T>(column);
        };
        return bound;
      };
    }
    return statement;
  };
  return { reached, resume };
}

async function rotate(f: Awaited<ReturnType<typeof fixture>>, id = 'review-receipt-B') {
  await f.env.DB.prepare(
    'INSERT INTO ai_free_account_receipts(id,account_id,receipt_json,created_at) VALUES(?,?,?,1)',
  )
    .bind(id, f.env.WORKERS_AI_ACCOUNT_ID, JSON.stringify(f.receipt))
    .run();
  await f.env.DB.prepare(
    'UPDATE ai_free_receipt_slots SET receipt_id=?,generation=generation+1,updated_at=updated_at+1 WHERE slot_id=? AND account_id=?',
  )
    .bind(id, f.env.AI_FREE_RECEIPT_SLOT, f.env.WORKERS_AI_ACCOUNT_ID)
    .run();
}
async function comparison(f: Awaited<ReturnType<typeof fixture>>, two = false) {
  const question = { passage: f.passage, question: 'この箇所を説明してください' };
  const plan = {
    requestId: crypto.randomUUID(),
    models: [{ modelId: DEFAULT_MODEL_ID, answerMode: 'grounded-generation' }],
    questions: two
      ? [question, { ...question, question: '冒頭の内容を説明してください' }]
      : [question],
  };
  const preview = (await (await f.post('/developer/comparisons/plan', plan)).json()) as {
    confirmationHash: string;
  };
  expect(
    (await f.post('/developer/comparisons', { plan, confirmationHash: preview.confirmationHash }))
      .status,
  ).toBe(202);
  return {
    plan,
    step: (trialIndex = 0) =>
      f.post(`/developer/comparisons/${plan.requestId}/steps`, {
        plan,
        confirmationHash: preview.confirmationHash,
        trialIndex,
      }),
  };
}

describe('independent receipt-slot rotation review: synthetic local authority only', () => {
  for (const isComparison of [false, true])
    it(
      'rotation wins atomic ' +
        (isComparison ? 'comparison' : 'question') +
        ' dispatch and refunds proven undispatched work',
      async () => {
        const f = await fixture();
        const job = isComparison ? await comparison(f) : undefined;
        const gate = pauseDispatch(f.db, isComparison),
          pending = job ? job.step() : f.ask();
        await gate.reached;
        try {
          await rotate(f);
        } finally {
          gate.resume();
        }
        expect((await pending).status).toBeGreaterThanOrEqual(400);
        expect(f.calls()).toBe(0);
        expect(await f.env.DB.prepare('SELECT reserved,consumed FROM budget_days').first()).toEqual(
          { reserved: 0, consumed: 0 },
        );
      },
    );
  it('completed comparison replay stays inert after rotation; queued stale plan refunds only its own allowance', async () => {
    const f = await fixture(),
      job = await comparison(f, true);
    expect((await job.step()).status).toBe(200);
    expect(f.calls()).toBe(1);
    const first = await f.env.DB.prepare(
      'SELECT amount FROM comparison_trials WHERE job_id=? AND trial_index=0',
    )
      .bind(job.plan.requestId)
      .first<{ amount: number }>();
    await rotate(f);
    const replay = await job.step();
    expect(replay.status).toBe(200);
    expect(((await replay.json()) as { replayed: boolean }).replayed).toBe(true);
    expect(f.calls()).toBe(1);
    expect((await job.step(1)).status).toBe(409);
    expect(f.calls()).toBe(1);
    expect(await f.env.DB.prepare('SELECT reserved,consumed FROM budget_days').first()).toEqual({
      reserved: 0,
      consumed: first!.amount,
    });
  });
  for (const isComparison of [false, true])
    it(
      'rotation during uncertain ' +
        (isComparison ? 'comparison' : 'question') +
        ' provider outcome retains charged allowance',
      async () => {
        const f = await fixture(),
          job = isComparison ? await comparison(f) : undefined;
        let entered!: () => void, reject!: (error: Error) => void;
        const reached = new Promise<void>((r) => (entered = r));
        f.env.AI = {
          run: async () => {
            entered();
            return await new Promise((_r, j) => (reject = j));
          },
        } as unknown as typeof f.env.AI;
        const pending = job ? job.step() : f.ask();
        await reached;
        await rotate(f);
        reject(new Error('synthetic provider acknowledgement lost'));
        await pending;
        const budget = await f.env.DB.prepare('SELECT reserved,consumed FROM budget_days').first<{
          reserved: number;
          consumed: number;
        }>();
        expect(budget!.reserved).toBe(0);
        expect(budget!.consumed).toBeGreaterThan(0);
      },
    );
  it('lost comparison dispatch-CAS acknowledgement never replays provider work or invents zero usage', async () => {
    const f = await fixture(),
      job = await comparison(f),
      original = f.db.prepare.bind(f.db);
    let thrown = false;
    f.db.prepare = (sql: string) => {
      const statement = original(sql);
      if (sql.startsWith('UPDATE comparison_trials SET dispatched=1')) {
        const bind = statement.bind.bind(statement);
        statement.bind = (...params: unknown[]) => {
          const bound = bind(...params),
            first = bound.first.bind(bound);
          bound.first = async <T = Record<string, unknown>>(column?: string): Promise<T | null> => {
            const row = await first<T>(column);
            if (!thrown) {
              thrown = true;
              throw new Error('synthetic committed CAS lost acknowledgement');
            }
            return row;
          };
          return bound;
        };
      }
      return statement;
    };
    expect((await job.step()).status).toBeGreaterThanOrEqual(400);
    expect(f.calls()).toBe(0);
    const budget = await f.env.DB.prepare('SELECT reserved,consumed FROM budget_days').first<{
      reserved: number;
      consumed: number;
    }>();
    expect(budget!.reserved).toBe(0);
    expect(budget!.consumed).toBeGreaterThan(0);
    await rotate(f);
    expect((await job.step()).status).toBe(409);
    expect(f.calls()).toBe(0);
  });
});

import { loadBudgetAuthority, estimateModelReservation } from '../src/budget';
import { budgetDispatchGuard } from '../src/budget-dispatch';
it('independent review: stable slot binds exact account, slot, generation and receipt while pinned authority stays isolated', async () => {
  const f = await fixture();
  const proof = async () =>
    estimateModelReservation(
      f.env,
      DEFAULT_MODEL_ID,
      512,
      await loadBudgetAuthority(f.env, [DEFAULT_MODEL_ID]),
      1000,
    );
  const first = await proof(),
    guard = budgetDispatchGuard(f.env, first.dispatchIdentity);
  expect(
    await f.env.DB.prepare('SELECT 1 AS valid WHERE ' + guard.sql)
      .bind(...guard.params)
      .first(),
  ).toEqual({ valid: 1 });
  await f.env.DB.prepare(
    'INSERT INTO ai_free_account_receipts(id,account_id,receipt_json,created_at) VALUES(?,?,?,1)',
  )
    .bind('installed-only', f.env.WORKERS_AI_ACCOUNT_ID, JSON.stringify(f.receipt))
    .run();
  expect((await proof()).proofFingerprint).toBe(first.proofFingerprint);
  await f.env.DB.prepare(
    'INSERT INTO ai_free_receipt_slots(slot_id,account_id,receipt_id,generation,updated_at) VALUES(?,?,?,1,1)',
  )
    .bind('other-slot', f.env.WORKERS_AI_ACCOUNT_ID, 'review-receipt-A')
    .run();
  f.env.AI_FREE_RECEIPT_SLOT = 'other-slot';
  expect((await proof()).proofFingerprint).not.toBe(first.proofFingerprint);
  expect(() => budgetDispatchGuard(f.env, first.dispatchIdentity)).toThrow();
  f.env.AI_FREE_RECEIPT_SLOT = 'review-slot';
  await rotate(f);
  expect(
    await f.env.DB.prepare('SELECT 1 AS valid WHERE ' + guard.sql)
      .bind(...guard.params)
      .first(),
  ).toBe(null);
  expect((await proof()).proofFingerprint).not.toBe(first.proofFingerprint);
  delete f.env.AI_FREE_RECEIPT_SLOT;
  delete f.env.AI_FREE_RECEIPT_MODE;
  f.env.AI_FREE_RECEIPT_ID = 'review-receipt-A';
  const pinned = await proof();
  await f.env.DB.prepare(
    'UPDATE ai_free_receipt_slots SET receipt_id=?,generation=generation+1,updated_at=updated_at+1 WHERE slot_id=?',
  )
    .bind('installed-only', 'review-slot')
    .run();
  expect((await proof()).proofFingerprint).toBe(pinned.proofFingerprint);
  f.env.AI_FREE_RECEIPT_MODE = 'slot';
  f.env.AI_FREE_RECEIPT_SLOT = 'review-slot';
  await expect(proof()).rejects.toThrow();
  delete f.env.AI_FREE_RECEIPT_ID;
  f.env.WORKERS_AI_ACCOUNT_ID = 'b'.repeat(32);
  await expect(proof()).rejects.toThrow();
});
it('independent review: comparison preview cannot start against an older receipt generation', async () => {
  const f = await fixture(),
    plan = {
      requestId: crypto.randomUUID(),
      models: [{ modelId: DEFAULT_MODEL_ID, answerMode: 'grounded-generation' }],
      questions: [{ passage: f.passage, question: 'この箇所を説明してください' }],
    };
  const preview = (await (await f.post('/developer/comparisons/plan', plan)).json()) as {
    confirmationHash: string;
  };
  await rotate(f);
  expect(
    (await f.post('/developer/comparisons', { plan, confirmationHash: preview.confirmationHash }))
      .status,
  ).toBe(409);
  expect(f.calls()).toBe(0);
  expect(await f.env.DB.prepare('SELECT COUNT(*) AS n FROM budget_reservations').first()).toEqual({
    n: 0,
  });
});
