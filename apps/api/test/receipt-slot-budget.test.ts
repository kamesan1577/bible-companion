import { it, expect, vi } from 'vitest';
import { testEnv } from './helpers/db';
import { loadBudgetAuthority, estimateModelReservation } from '../src/budget';
import { DEFAULT_MODEL_ID } from '@bible/ai-harness';
it('historical expired/revoked receipts and slot settings are irrelevant and remain unmodified', async () => {
  const env = testEnv();
  Object.assign(env, {
    AI_BUDGET_MODE: 'free-provider-hard-stop',
    AI_FREE_RECEIPT_MODE: 'slot',
    AI_FREE_RECEIPT_SLOT: 'old',
    AI_FREE_DEADLINE_MODE: 'utc-halfday',
  });
  await env.DB.prepare(
    'INSERT INTO ai_free_account_receipts VALUES(\'old\',?,\'{"expiresAt":"2000-01-01T00:00:00Z"}\',1,2)',
  )
    .bind('a'.repeat(32))
    .run();
  const before = await env.DB.prepare('SELECT * FROM ai_free_account_receipts').all();
  const spy = vi.spyOn(env.DB, 'prepare');
  const p = estimateModelReservation(
    env,
    DEFAULT_MODEL_ID,
    512,
    await loadBudgetAuthority(env, [DEFAULT_MODEL_ID]),
    1000,
  );
  expect(p.amount).toBeGreaterThan(0);
  expect(spy).not.toHaveBeenCalled();
  spy.mockRestore();
  expect(await env.DB.prepare('SELECT * FROM ai_free_account_receipts').all()).toEqual(before);
});
