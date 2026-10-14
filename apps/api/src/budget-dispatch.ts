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
  if (identity.slotId)
    return {
      sql: "EXISTS(SELECT 1 FROM ai_free_receipt_slots s JOIN ai_free_account_receipts r ON r.id=s.receipt_id AND r.account_id=s.account_id WHERE s.slot_id=? AND s.account_id=? AND s.generation=? AND s.receipt_id=? AND r.receipt_json=? AND r.revoked_at IS NULL) AND julianday(?)>julianday('now')",
      params: [
        identity.slotId,
        identity.accountId,
        identity.generation!,
        identity.receiptId,
        identity.receiptJson,
        identity.expiresAt,
      ],
    };
  return {
    sql: "EXISTS(SELECT 1 FROM ai_free_account_receipts r WHERE r.id=? AND r.account_id=? AND r.receipt_json=? AND r.revoked_at IS NULL) AND julianday(?)>julianday('now')",
    params: [identity.receiptId, identity.accountId, identity.receiptJson, identity.expiresAt],
  };
}
