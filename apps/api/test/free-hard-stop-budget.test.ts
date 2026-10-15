import { describe, it, expect, vi, afterEach } from 'vitest';
import { testEnv } from './helpers/db';
import {
  loadBudgetAuthority,
  estimateModelReservation,
  modelBudgetReadiness,
  assertBudgetDispatchConfiguration,
} from '../src/budget';
import { budgetDispatchGuard } from '../src/budget-dispatch';
import { DEFAULT_MODEL_ID, listModels } from '@bible/ai-harness';
function configured() {
  const env = testEnv();
  env.AI_BUDGET_MODE = 'free-provider-hard-stop';
  return env;
}
afterEach(() => vi.useRealTimers());
describe('provider Free quota with no renewable contract gate', () => {
  it('loads no contract rows or credentials and honestly retains estimated accounting', async () => {
    const env = configured(),
      spy = vi.spyOn(env.DB, 'prepare');
    const a = await loadBudgetAuthority(env, [DEFAULT_MODEL_ID]);
    expect(spy).not.toHaveBeenCalled();
    const p = estimateModelReservation(env, DEFAULT_MODEL_ID, 512, a, 1234);
    expect(p.amount).toBe(Math.ceil(p.estimate.estimatedNeurons * 1.25));
    expect(p.budgetBoundVerified).toBe(false);
    expect(p.warnings).toContain('PROVIDER_FREE_QUOTA_IS_FINAL_STOP');
    expect(p.dispatchIdentity).not.toHaveProperty('receiptId');
    expect(p.dispatchIdentity).not.toHaveProperty('accountId');
    expect({ ...p }).not.toHaveProperty('dispatchIdentity');
    expect(Object.isFrozen(p.dispatchIdentity)).toBe(true);
  });
  it('does not expire at noon or depend on a Mac renewal', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-10-15T11:59:59Z'));
    const env = configured(),
      a = await loadBudgetAuthority(env, [DEFAULT_MODEL_ID]);
    const p = estimateModelReservation(env, DEFAULT_MODEL_ID, 512, a, 1000);
    vi.setSystemTime(new Date('2026-10-15T12:00:01Z'));
    expect(() => assertBudgetDispatchConfiguration(env, p.dispatchIdentity)).not.toThrow();
    expect((await modelBudgetReadiness(env, DEFAULT_MODEL_ID)).ready).toBe(true);
    expect(() => estimateModelReservation(env, DEFAULT_MODEL_ID, 512, a, 1000)).not.toThrow();
  });
  it('fresh requests work next day while old daily reservations cannot cross the budget reset', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-10-15T23:59:59Z'));
    const env = configured(),
      a = await loadBudgetAuthority(env, [DEFAULT_MODEL_ID]),
      old = estimateModelReservation(env, DEFAULT_MODEL_ID, 512, a, 1000);
    vi.setSystemTime(new Date('2026-10-16T00:00:01Z'));
    expect(() => assertBudgetDispatchConfiguration(env, old.dispatchIdentity)).toThrow();
    const fresh = estimateModelReservation(
      env,
      DEFAULT_MODEL_ID,
      512,
      await loadBudgetAuthority(env, [DEFAULT_MODEL_ID]),
      1000,
    );
    expect(() => assertBudgetDispatchConfiguration(env, fresh.dispatchIdentity)).not.toThrow();
  });
  it('retains model restrictions, input bounds and positive budgets', async () => {
    const env = configured(),
      a = await loadBudgetAuthority(env, [DEFAULT_MODEL_ID]);
    for (const m of listModels().filter((m) => m.billingTier === 'paid-required'))
      expect(() => estimateModelReservation(env, m.id, 512, a)).toThrow('MODEL_DISABLED');
    for (const n of [64001, NaN, Infinity, -1, 0.5])
      expect(() => estimateModelReservation(env, DEFAULT_MODEL_ID, 512, a, n)).toThrow();
    env.DAILY_APP_BUDGET = '1';
    expect(() => estimateModelReservation(env, DEFAULT_MODEL_ID, 512, a)).toThrow(
      'BUDGET_EXCEEDED',
    );
  });
  it('keeps strict-proof default and rejects unknown modes', async () => {
    const env = testEnv();
    expect((await loadBudgetAuthority(env, [DEFAULT_MODEL_ID])).mode).toBe('strict-proof');
    expect(() =>
      estimateModelReservation(env, DEFAULT_MODEL_ID, 512, {
        mode: 'strict-proof',
        proofs: new Map(),
      }),
    ).toThrow();
    env.AI_BUDGET_MODE = 'auto';
    await expect(loadBudgetAuthority(env, [DEFAULT_MODEL_ID])).rejects.toThrow();
  });
  it('rejects a limit change between reservation and dispatch', async () => {
    const env = configured(),
      a = await loadBudgetAuthority(env, [DEFAULT_MODEL_ID]),
      p = estimateModelReservation(env, DEFAULT_MODEL_ID, 512, a, 1000);
    env.DAILY_USER_BUDGET = '1';
    expect(() => budgetDispatchGuard(env, p.dispatchIdentity)).toThrow();
  });
});
