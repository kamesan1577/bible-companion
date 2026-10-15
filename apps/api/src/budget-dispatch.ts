import { assertBudgetDispatchConfiguration, type BudgetDispatchIdentity } from './budget';
import type { Env } from './types';
/** SQL fragments are constant server code; only validated evidence values become bound parameters. */
export function budgetDispatchGuard(env: Env, identity: BudgetDispatchIdentity) {
  assertBudgetDispatchConfiguration(env, identity);
  if (identity.mode === 'strict-proof')
    return {
      sql: "EXISTS(SELECT 1 FROM model_budget_proofs p WHERE p.model_id=? AND p.pricing_version=? AND p.bounds_json=?) AND julianday(?)>julianday('now')",
      params: [identity.modelId, identity.pricingVersion, identity.boundsJson, identity.expiresAt],
    };
  // A request prepared before daily budget reset cannot dispatch against yesterday's reservation.
  return { sql: "?=strftime('%Y-%m-%d','now')", params: [identity.budgetDay] };
}
