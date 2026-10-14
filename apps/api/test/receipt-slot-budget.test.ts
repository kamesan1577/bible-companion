import { describe, it, expect, vi } from 'vitest';
import { testEnv } from './helpers/db';
import {
  loadBudgetAuthority,
  estimateModelReservation,
  FREE_HARD_STOP_POLICY_VERSION,
} from '../src/budget';
import { budgetDispatchGuard } from '../src/budget-dispatch';
import { DEFAULT_MODEL_ID } from '@bible/ai-harness';

async function configured() {
  const env = testEnv();
  Object.assign(env, {
    AI_BUDGET_MODE: 'free-provider-hard-stop',
    WORKERS_AI_ACCOUNT_ID: 'a'.repeat(32),
    AI_FREE_RECEIPT_MODE: 'slot',
    AI_FREE_RECEIPT_SLOT: 'main',
  });
  for (const id of ['receipt-a', 'receipt-b']) {
    const receipt = {
      schemaVersion: 1,
      policyVersion: FREE_HARD_STOP_POLICY_VERSION,
      accountId: env.WORKERS_AI_ACCOUNT_ID,
      verifiedAt: new Date(Date.now() - 60000).toISOString(),
      expiresAt: new Date(Date.now() + 3600000).toISOString(),
      evidenceRef: 'synthetic-test-only-' + id,
      accountPlan: 'free',
      providerRoute: 'direct-workers-binding',
      gatewayCredits: false,
      paidModels: false,
      fallbacks: false,
    };
    await env.DB.prepare('INSERT INTO ai_free_account_receipts VALUES(?,?,?,1,NULL)')
      .bind(id, env.WORKERS_AI_ACCOUNT_ID, JSON.stringify(receipt))
      .run();
  }
  await env.DB.prepare('INSERT INTO ai_free_receipt_slots VALUES(?,?,?,1,1)')
    .bind('main', env.WORKERS_AI_ACCOUNT_ID, 'receipt-a')
    .run();
  return env;
}

describe('optional stable slot authority', () => {
  it('loads one joined snapshot and binds generation into private dispatch identity and public fingerprint', async () => {
    const env = await configured();
    const prepare = vi.spyOn(env.DB, 'prepare');
    const authority = await loadBudgetAuthority(env, [DEFAULT_MODEL_ID]);
    expect(prepare).toHaveBeenCalledTimes(1);
    const before = estimateModelReservation(env, DEFAULT_MODEL_ID, 512, authority, 1000);
    expect(before.dispatchIdentity).toMatchObject({
      slotId: 'main',
      generation: 1,
      receiptId: 'receipt-a',
    });
    expect(Object.isFrozen(before.dispatchIdentity)).toBe(true);
    expect(JSON.stringify(before)).not.toContain('receipt-a');
    const guard = budgetDispatchGuard(env, before.dispatchIdentity);
    expect(
      await env.DB.prepare('SELECT 1 AS allowed WHERE ' + guard.sql)
        .bind(...guard.params)
        .first(),
    ).not.toBeNull();
    await env.DB.prepare(
      'UPDATE ai_free_receipt_slots SET receipt_id=?,generation=2,updated_at=2 WHERE slot_id=? AND generation=1',
    )
      .bind('receipt-b', 'main')
      .run();
    expect(
      await env.DB.prepare('SELECT 1 AS allowed WHERE ' + guard.sql)
        .bind(...guard.params)
        .first(),
    ).toBeNull();
    const after = estimateModelReservation(
      env,
      DEFAULT_MODEL_ID,
      512,
      await loadBudgetAuthority(env, [DEFAULT_MODEL_ID]),
      1000,
    );
    expect(after.dispatchIdentity).toMatchObject({ generation: 2, receiptId: 'receipt-b' });
    expect(before.proofFingerprint).not.toBe(after.proofFingerprint);
  });
  it('missing, malformed, ambiguous and changed config never fall back to pinned evidence', async () => {
    const env = await configured();
    const authority = await loadBudgetAuthority(env, [DEFAULT_MODEL_ID]);
    const reservation = estimateModelReservation(env, DEFAULT_MODEL_ID, 512, authority, 1000);
    for (const patch of [
      { AI_FREE_RECEIPT_ID: 'receipt-a' },
      { AI_FREE_RECEIPT_MODE: 'pinned' },
      { AI_FREE_RECEIPT_MODE: undefined },
      { AI_FREE_RECEIPT_SLOT: '../main' },
    ])
      await expect(loadBudgetAuthority({ ...env, ...patch }, [DEFAULT_MODEL_ID])).rejects.toThrow(
        'BUDGET_UNVERIFIED',
      );
    for (const patch of [
      { AI_FREE_RECEIPT_SLOT: 'other' },
      { WORKERS_AI_ACCOUNT_ID: 'b'.repeat(32) },
    ]) {
      const changed = { ...env, ...patch };
      expect(() => budgetDispatchGuard(changed, reservation.dispatchIdentity)).toThrow(
        'BUDGET_UNVERIFIED',
      );
      const missing = await loadBudgetAuthority(changed, [DEFAULT_MODEL_ID]);
      expect(() => estimateModelReservation(changed, DEFAULT_MODEL_ID, 512, missing, 1000)).toThrow(
        'BUDGET_UNVERIFIED',
      );
    }
  });
  it('revocation invalidates both the joined lookup and already loaded dispatch identity', async () => {
    const env = await configured();
    const reservation = estimateModelReservation(
      env,
      DEFAULT_MODEL_ID,
      512,
      await loadBudgetAuthority(env, [DEFAULT_MODEL_ID]),
      1000,
    );
    await env.DB.prepare('UPDATE ai_free_account_receipts SET revoked_at=1 WHERE id=?')
      .bind('receipt-a')
      .run();
    const guard = budgetDispatchGuard(env, reservation.dispatchIdentity);
    expect(
      await env.DB.prepare('SELECT 1 AS allowed WHERE ' + guard.sql)
        .bind(...guard.params)
        .first(),
    ).toBeNull();
    const missing = await loadBudgetAuthority(env, [DEFAULT_MODEL_ID]);
    expect(() => estimateModelReservation(env, DEFAULT_MODEL_ID, 512, missing, 1000)).toThrow(
      'BUDGET_UNVERIFIED',
    );
  });
});
