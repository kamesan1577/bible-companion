import { describe, it, expect, vi, afterEach } from 'vitest';
import { testEnv, seedUser } from './helpers/db';
import { app } from '../src/index';
import {
  FREE_HARD_STOP_POLICY_VERSION,
  loadBudgetAuthority,
  estimateModelReservation,
  estimateReservation,
  modelBudgetReadiness,
  assertBudgetDispatchConfiguration,
  type FreeAccountReceipt,
} from '../src/budget';
import {
  DEFAULT_MODEL_ID,
  listModels,
  prepareCompanionRequest,
  MODEL_TERMS_POLICY_VERSION,
} from '@bible/ai-harness';
import { BIBLE_QUESTIONS, inputForCase } from '../../../packages/ai-harness/fixtures/questions';
import type { Env } from '../src/types';
const account = 'a'.repeat(32);
function receipt(): FreeAccountReceipt {
  return {
    schemaVersion: 1,
    policyVersion: FREE_HARD_STOP_POLICY_VERSION,
    accountId: account,
    verifiedAt: new Date(Date.now() - 60000).toISOString(),
    expiresAt: new Date(Date.now() + 3600000).toISOString(),
    evidenceRef: 'synthetic-test-only-no-real-account-check',
    accountPlan: 'free',
    providerRoute: 'direct-workers-binding',
    gatewayCredits: false,
    paidModels: false,
    fallbacks: false,
  };
}
async function configured(patch: Record<string, unknown> = {}, raw?: string) {
  const env = testEnv();
  env.AI_BUDGET_MODE = 'free-provider-hard-stop';
  env.WORKERS_AI_ACCOUNT_ID = account;
  env.AI_FREE_RECEIPT_ID = crypto.randomUUID();
  await env.DB.prepare(
    'INSERT INTO ai_free_account_receipts(id,account_id,receipt_json,created_at) VALUES(?,?,?,?)',
  )
    .bind(
      env.AI_FREE_RECEIPT_ID,
      account,
      raw ?? JSON.stringify({ ...receipt(), ...patch }),
      Math.floor(Date.now() / 1000),
    )
    .run();
  return env;
}
afterEach(() => vi.useRealTimers());
describe('fixed UTC half-day deadline',()=>{
 afterEach(()=>vi.useRealTimers());
 it('cannot retain an older 23-hour receipt even when control-plane writes are unreachable',async()=>{
  vi.useFakeTimers();vi.setSystemTime(new Date('2026-10-15T01:00:00Z'));
  const env=await configured({verifiedAt:'2026-10-15T00:00:00.000Z',expiresAt:'2026-10-15T23:00:00.000Z'});env.AI_FREE_DEADLINE_MODE='utc-halfday';
  const a=await loadBudgetAuthority(env,[DEFAULT_MODEL_ID]);expect(()=>estimateModelReservation(env,DEFAULT_MODEL_ID,512,a)).toThrow();
 });
 it('expires at the next scheduled boundary without any external revocation call',async()=>{
  vi.useFakeTimers();vi.setSystemTime(new Date('2026-10-15T01:00:00Z'));
  const env=await configured({verifiedAt:'2026-10-15T00:00:00.000Z',expiresAt:'2026-10-15T12:00:00.000Z'});env.AI_FREE_DEADLINE_MODE='utc-halfday';
  const a=await loadBudgetAuthority(env,[DEFAULT_MODEL_ID]);expect(()=>estimateModelReservation(env,DEFAULT_MODEL_ID,512,a)).not.toThrow();
  vi.setSystemTime(new Date('2026-10-15T12:00:00Z'));expect(()=>estimateModelReservation(env,DEFAULT_MODEL_ID,512,a)).toThrow();
 });
});
describe('explicit provider-Free hard-stop authority, never a mathematical token proof', () => {
  it('default strict mode stays closed even when a Free receipt exists', async () => {
    const env = await configured();
    delete env.AI_BUDGET_MODE;
    const authority = await loadBudgetAuthority(env, [DEFAULT_MODEL_ID]);
    expect(authority.mode).toBe('strict-proof');
    expect(() => estimateModelReservation(env, DEFAULT_MODEL_ID, 512, authority)).toThrow(
      'BUDGET_UNVERIFIED',
    );
  });
  it('loads one receipt for all models and reports stable estimated reservations honestly', async () => {
    const env = await configured(),
      prepare = vi.spyOn(env.DB, 'prepare');
    const authority = await loadBudgetAuthority(
      env,
      listModels().map((m) => m.id),
    );
    expect(prepare).toHaveBeenCalledTimes(1);
    const plan = estimateModelReservation(env, DEFAULT_MODEL_ID, 512, authority, 1234);
    const dispatched = estimateModelReservation(env, DEFAULT_MODEL_ID, 512, authority, 1234);
    expect(plan.amount).toBe(dispatched.amount);
    expect(plan.proofFingerprint).toBe(dispatched.proofFingerprint);
    expect(plan.estimate.inputTokens).toBe(1234);
    expect(plan.amount).toBeLessThan(
      estimateModelReservation(env, DEFAULT_MODEL_ID, 512, authority).amount,
    );
    expect(plan.proofFingerprint).not.toBe(
      estimateModelReservation(env, DEFAULT_MODEL_ID, 512, authority, 1235).proofFingerprint,
    );
    expect(plan.amount).toBe(Math.ceil(plan.estimate.estimatedNeurons * 1.25));
    expect(plan.budgetBoundVerified).toBe(false);
    expect(plan.estimate.budgetBoundVerified).toBe(false);
    expect(plan.estimate.hardCapVerified).toBe(false);
    expect(plan.estimate.billingMeasured).toBe(false);
    expect(plan.reservationBasis).toBe('estimated-reservation-provider-free-hard-stop');
    expect(plan.warnings).toContain('HIDDEN_REASONING_USAGE_UNKNOWN');
    expect(plan.dispatchIdentity.mode).toBe('free-provider-hard-stop');
    expect(JSON.stringify(plan)).not.toContain(account);
    expect(JSON.stringify(plan)).not.toContain('synthetic-test-only');
    expect({ ...plan }).not.toHaveProperty('dispatchIdentity');
    expect(Object.isFrozen(plan.dispatchIdentity)).toBe(true);
    const ready = await modelBudgetReadiness(env, DEFAULT_MODEL_ID, 512, undefined, authority);
    expect(ready.ready).toBe(true);
    expect(ready.budgetBoundVerified).toBe(false);
    expect(prepare).toHaveBeenCalledTimes(1);
  });
  it('catalog readiness validates Free authority without substituting a worst-case prompt for actual request cost', async () => {
    const env = await configured();
    env.DAILY_USER_BUDGET = '2000';
    const free = listModels().filter((m) => m.billingTier === 'free-allocation-candidate');
    const authority = await loadBudgetAuthority(
      env,
      free.map((m) => m.id),
    );
    let expensive: string | undefined;
    for (const model of free) {
      const ready = await modelBudgetReadiness(env, model.id, 512, undefined, authority);
      expect(ready.ready, model.id).toBe(true);
      expect(ready.preparedRequestBudgetRequired).toBe(true);
      expect(ready.readinessScope).toBe('provider-policy-only');
      try {
        if (
          estimateModelReservation(env, model.id, 512, authority).amount > 2000 &&
          estimateModelReservation(env, model.id, 512, authority, 2000).amount < 2000
        )
          expensive = model.id;
      } catch {
        /* Oversized worst-case estimates may exceed the app allowance; that is not a catalog denial. */
      }
    }
    expect(expensive).toBeDefined();
    const user = await seedUser(env, crypto.randomUUID(), 'owner');
    env.CONNECTED_MODELS = JSON.stringify([expensive]);
    env.TERMS_REVIEWED_MODELS = env.CONNECTED_MODELS;
    env.TERMS_REVIEW_VERSION = MODEL_TERMS_POLICY_VERSION;
    env.AI_ENABLED = 'true';
    const catalog = (await (
      await app.request('/v1/developer/models', { headers: user.headers }, env)
    ).json()) as any;
    expect(catalog.models.find((m: any) => m.id === expensive).enabled).toBe(true);
    expect(
      catalog.models
        .filter((m: any) => m.billingTier === 'paid-required')
        .every((m: any) => !m.enabled),
    ).toBe(true);
    const selected = await app.request(
      '/v1/developer/model-preference',
      {
        method: 'PUT',
        headers: user.headers,
        body: JSON.stringify({ modelId: expensive, settings: { maxOutputTokens: 512 } }),
      },
      env,
    );
    expect(selected.status).toBe(200);
    await env.DB.prepare('UPDATE ai_free_account_receipts SET revoked_at=1').run();
    expect((await modelBudgetReadiness(env, expensive!)).ready).toBe(false);
  });
  it('refuses paid models and any input beyond the stable reservation envelope', async () => {
    const env = await configured(),
      authority = await loadBudgetAuthority(env, [DEFAULT_MODEL_ID]);
    const plan = estimateModelReservation(env, DEFAULT_MODEL_ID, 512, authority);
    for (const model of listModels().filter((m) => m.billingTier === 'paid-required'))
      expect(() => estimateModelReservation(env, model.id, 512, authority)).toThrow(
        'MODEL_DISABLED',
      );
    for (const tokens of [plan.estimatedInputTokenCeiling + 1, NaN, Infinity, -1, 1.5])
      expect(() => estimateModelReservation(env, DEFAULT_MODEL_ID, 512, authority, tokens)).toThrow(
        'BUDGET_UNVERIFIED',
      );
    env.DAILY_APP_BUDGET = '1';
    expect(() => estimateModelReservation(env, DEFAULT_MODEL_ID, 512, authority)).toThrow(
      'BUDGET_EXCEEDED',
    );
  });
  it('missing, revoked, expired, future, stale or incompatible account snapshots stay closed', async () => {
    const invalid = [
      { accountId: 'b'.repeat(32) },
      { accountPlan: 'paid' },
      { providerRoute: 'gateway' },
      { gatewayCredits: true },
      { paidModels: true },
      { fallbacks: true },
      { policyVersion: 'old' },
      { expiresAt: new Date(Date.now() - 1000).toISOString() },
      { verifiedAt: new Date(Date.now() + 10000).toISOString() },
      { expiresAt: new Date(Date.now() + 25 * 3600000).toISOString() },
      { extraAuthority: true },
    ];
    for (const patch of invalid) {
      const env = await configured(patch),
        authority = await loadBudgetAuthority(env, [DEFAULT_MODEL_ID]);
      expect(() => estimateModelReservation(env, DEFAULT_MODEL_ID, 512, authority)).toThrow(
        'BUDGET_UNVERIFIED',
      );
    }
    const env = await configured();
    await env.DB.prepare('UPDATE ai_free_account_receipts SET revoked_at=? WHERE id=?')
      .bind(Math.floor(Date.now() / 1000), env.AI_FREE_RECEIPT_ID)
      .run();
    expect(() =>
      estimateModelReservation(env, DEFAULT_MODEL_ID, 512, {
        mode: 'free-provider-hard-stop',
        accountId: account,
        receiptId: env.AI_FREE_RECEIPT_ID!,
        receipt: null,
      }),
    ).toThrow('BUDGET_UNVERIFIED');
    const revoked = await loadBudgetAuthority(env, [DEFAULT_MODEL_ID]);
    expect(() => estimateModelReservation(env, DEFAULT_MODEL_ID, 512, revoked)).toThrow(
      'BUDGET_UNVERIFIED',
    );
    env.AI_FREE_RECEIPT_ID = crypto.randomUUID();
    const missing = await loadBudgetAuthority(env, [DEFAULT_MODEL_ID]);
    expect(() => estimateModelReservation(env, DEFAULT_MODEL_ID, 512, missing)).toThrow(
      'BUDGET_UNVERIFIED',
    );
  });
  it('rechecks configuration and expiry after loading, and immutable receipt revocation breaks exact dispatch identity', async () => {
    const env = await configured(),
      authority = await loadBudgetAuthority(env, [DEFAULT_MODEL_ID]);
    const plan = estimateModelReservation(env, DEFAULT_MODEL_ID, 512, authority);
    const identity = plan.dispatchIdentity;
    if (identity.mode !== 'free-provider-hard-stop') throw new Error('wrong mode');
    const matches = () =>
      env.DB.prepare(
        "SELECT id FROM ai_free_account_receipts WHERE id=? AND account_id=? AND receipt_json=? AND revoked_at IS NULL AND julianday(?)>julianday('now')",
      )
        .bind(identity.receiptId, identity.accountId, identity.receiptJson, identity.expiresAt)
        .first();
    expect(await matches()).not.toBeNull();
    await expect(
      env.DB.prepare('UPDATE ai_free_account_receipts SET receipt_json=? WHERE id=?')
        .bind('{}', identity.receiptId)
        .run(),
    ).rejects.toThrow('free_account_receipt_immutable');
    await env.DB.prepare('UPDATE ai_free_account_receipts SET revoked_at=? WHERE id=?')
      .bind(Math.floor(Date.now() / 1000), identity.receiptId)
      .run();
    expect(await matches()).toBeNull();
    env.WORKERS_AI_ACCOUNT_ID = 'b'.repeat(32);
    expect(() => assertBudgetDispatchConfiguration(env, identity)).toThrow('BUDGET_UNVERIFIED');
    env.WORKERS_AI_ACCOUNT_ID = account;
    env.AI_BUDGET_MODE = 'strict-proof';
    expect(() => assertBudgetDispatchConfiguration(env, identity)).toThrow('BUDGET_UNVERIFIED');
    env.AI_BUDGET_MODE = 'free-provider-hard-stop';
    vi.useFakeTimers();
    vi.setSystemTime(Date.now() + 2 * 3600000);
    expect(() => estimateModelReservation(env, DEFAULT_MODEL_ID, 512, authority)).toThrow(
      'BUDGET_UNVERIFIED',
    );
    expect(() => assertBudgetDispatchConfiguration(env, identity)).toThrow('BUDGET_UNVERIFIED');
  });
  it('replacement receipts change comparison identity and actual request preparation uses the same bounded policy', async () => {
    const env = await configured(),
      first = estimateModelReservation(
        env,
        DEFAULT_MODEL_ID,
        512,
        await loadBudgetAuthority(env, [DEFAULT_MODEL_ID]),
      );
    const oldId = env.AI_FREE_RECEIPT_ID;
    env.AI_FREE_RECEIPT_ID = crypto.randomUUID();
    await env.DB.prepare(
      'INSERT INTO ai_free_account_receipts(id,account_id,receipt_json,created_at) VALUES(?,?,?,?)',
    )
      .bind(
        env.AI_FREE_RECEIPT_ID,
        account,
        JSON.stringify(receipt()),
        Math.floor(Date.now() / 1000),
      )
      .run();
    const second = estimateModelReservation(
      env,
      DEFAULT_MODEL_ID,
      512,
      await loadBudgetAuthority(env, [DEFAULT_MODEL_ID]),
    );
    expect(second.proofFingerprint).not.toBe(first.proofFingerprint);
    expect(env.AI_FREE_RECEIPT_ID).not.toBe(oldId);
    const prepared = await estimateReservation(
      env,
      inputForCase(BIBLE_QUESTIONS[0]),
      { ownerId: 'owner', connectedModelIds: [] },
      'grounded-generation',
    );
    const request = prepareCompanionRequest(inputForCase(BIBLE_QUESTIONS[0]), {
      authorization: { ownerId: 'owner', connectedModelIds: [] },
      answerMode: 'grounded-generation',
    });
    const expected = estimateModelReservation(
      env,
      DEFAULT_MODEL_ID,
      request.settings.maxOutputTokens,
      await loadBudgetAuthority(env, [DEFAULT_MODEL_ID]),
      request.usage.estimated.inputTokens,
    );
    expect(prepared.amount).toBe(expected.amount);
    expect(prepared.proofFingerprint).toBe(expected.proofFingerprint);
    expect(prepared.amount).toBeLessThan(second.amount);
    expect(prepared.budgetBoundVerified).toBe(false);
  });
  it('unknown modes and malformed server account/receipt identifiers cannot silently fall back', async () => {
    for (const change of [
      { AI_BUDGET_MODE: 'auto' },
      { WORKERS_AI_ACCOUNT_ID: '' },
      { WORKERS_AI_ACCOUNT_ID: 'UPPER' },
      { AI_FREE_RECEIPT_ID: '../receipt' },
    ]) {
      const env = { ...(await configured()), ...change } as Env;
      await expect(loadBudgetAuthority(env, [DEFAULT_MODEL_ID])).rejects.toThrow(
        'BUDGET_UNVERIFIED',
      );
    }
  });
});
