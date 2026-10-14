import { PRICING_DATA } from './pricing-data.ts';
import { getModel } from './registry.ts';
import { HarnessError } from './errors.ts';
export const PRICING_VERSION = 'cf-pricing-2026-10-09-checked-2026-10-13';
export const PRICING_URL = 'https://developers.cloudflare.com/workers-ai/platform/pricing/';
export const getModelPricing = (modelId: string) => {
  getModel(modelId);
  return PRICING_DATA.find((row) => row.modelId === modelId)!;
};
export interface BudgetEstimate {
  modelId: string;
  estimatedNeurons: number;
  estimatedUsdEquivalent: number;
  estimatedUsd: number;
  budgetBoundVerified: false;
  eligible: false;
  reason: 'TOKEN_AND_HIDDEN_REASONING_BOUNDS_UNVERIFIED';
  inputTokens: number;
  outputTokens: number;
  basis: 'estimated-token-counts' | 'provider-reported-token-counts';
  pricingVersion: string;
  billingMeasured: false;
  hardCapVerified: false;
  warnings: string[];
}
function validCount(count: number): boolean {
  return Number.isSafeInteger(count) && count >= 0 && count <= 10_000_000;
}
/** Uses published neuron rates directly, not the rounded dollar table. Cached discounts are never assumed. */
export function estimateModelBudget(
  modelId: string,
  inputTokens: number,
  outputTokens: number,
  basis: BudgetEstimate['basis'] = 'estimated-token-counts',
): BudgetEstimate {
  const rates = getModelPricing(modelId);
  if (
    !validCount(inputTokens) ||
    !validCount(outputTokens) ||
    !['estimated-token-counts', 'provider-reported-token-counts'].includes(basis)
  )
    throw new HarnessError('INVALID_INPUT');
  const estimatedNeurons =
    (inputTokens * rates.inputNeuronsPerMillionTokens +
      outputTokens * rates.outputNeuronsPerMillionTokens) /
    1_000_000;
  return {
    modelId,
    estimatedNeurons,
    estimatedUsdEquivalent: (estimatedNeurons * 0.011) / 1000,
    estimatedUsd: (estimatedNeurons * 0.011) / 1000,
    budgetBoundVerified: false,
    eligible: false,
    reason: 'TOKEN_AND_HIDDEN_REASONING_BOUNDS_UNVERIFIED',
    inputTokens,
    outputTokens,
    basis,
    pricingVersion: PRICING_VERSION,
    billingMeasured: false,
    hardCapVerified: false,
    warnings: [
      'NOT_A_PROVIDER_BILL',
      'ACCOUNT_FREE_ALLOCATION_NOT_APPLIED',
      ...(basis === 'estimated-token-counts' ? ['TOKEN_COUNTS_NOT_MEASURED'] : []),
      ...(rates.hasReasoning ? ['HIDDEN_REASONING_BUDGET_NOT_VERIFIED'] : []),
    ],
  };
}
/** Persist this only after an authorized provider/account check. It must never come from client JSON. */
export interface VerifiedBudgetBounds {
  modelId: string;
  pricingVersion: string;
  inputTokenUpperBound: number;
  outputTokenUpperBound: number;
  includesHiddenReasoning: true;
  /** Verified document/test record, not a user-controlled boolean. */
  evidenceRef: string;
  expiresAt: string;
}
/** Estimates alone cannot unlock inference or act as proof of the free-tier limit. */
export function requireVerifiedBudgetReservation(
  estimate: BudgetEstimate,
  remainingNeurons: number,
  bounds?: VerifiedBudgetBounds,
  now = Date.now(),
): number {
  if (
    !Number.isFinite(remainingNeurons) ||
    remainingNeurons < 0 ||
    !Number.isFinite(now) ||
    !validCount(estimate.inputTokens) ||
    !validCount(estimate.outputTokens) ||
    estimate.pricingVersion !== PRICING_VERSION
  )
    throw new HarnessError('BUDGET_UNVERIFIED');
  if (
    !bounds ||
    bounds.modelId !== estimate.modelId ||
    bounds.pricingVersion !== PRICING_VERSION ||
    !validCount(bounds.inputTokenUpperBound) ||
    !validCount(bounds.outputTokenUpperBound) ||
    bounds.inputTokenUpperBound < estimate.inputTokens ||
    bounds.outputTokenUpperBound < estimate.outputTokens ||
    bounds.includesHiddenReasoning !== true ||
    typeof bounds.evidenceRef !== 'string' ||
    bounds.evidenceRef.trim().length < 8 ||
    typeof bounds.expiresAt !== 'string' ||
    !Number.isFinite(Date.parse(bounds.expiresAt)) ||
    Date.parse(bounds.expiresAt) <= now
  )
    throw new HarnessError('BUDGET_UNVERIFIED');
  const reservation = Math.ceil(
    estimateModelBudget(estimate.modelId, bounds.inputTokenUpperBound, bounds.outputTokenUpperBound)
      .estimatedNeurons,
  );
  if (reservation > remainingNeurons) throw new HarnessError('BUDGET_EXCEEDED');
  return reservation;
}
/** No zero-cost refunds after uncertain dispatch/stream failures. This is accounting, not proof of billing. */
export function settleEstimatedReservation(
  reservedNeurons: number,
  result: { dispatched: boolean; usageUnknown: boolean; reportedEstimate?: BudgetEstimate },
): {
  accountedNeurons: number;
  kind: 'not-dispatched' | 'reservation-retained' | 'reported-tokens-estimate';
  billingMeasured: false;
  exceededReservation: boolean;
} {
  if (
    !Number.isSafeInteger(reservedNeurons) ||
    reservedNeurons < 0 ||
    typeof result.dispatched !== 'boolean' ||
    typeof result.usageUnknown !== 'boolean'
  )
    throw new HarnessError('INVALID_INPUT');
  if (!result.dispatched)
    return {
      accountedNeurons: 0,
      kind: 'not-dispatched',
      billingMeasured: false,
      exceededReservation: false,
    };
  if (result.usageUnknown || !result.reportedEstimate)
    return {
      accountedNeurons: reservedNeurons,
      kind: 'reservation-retained',
      billingMeasured: false,
      exceededReservation: false,
    };
  if (
    result.reportedEstimate.basis !== 'provider-reported-token-counts' ||
    result.reportedEstimate.pricingVersion !== PRICING_VERSION
  )
    throw new HarnessError('INVALID_INPUT');
  // Never trust a caller-supplied precomputed price; recompute from validated counters and immutable rates.
  const accountedNeurons = Math.ceil(
    estimateModelBudget(
      result.reportedEstimate.modelId,
      result.reportedEstimate.inputTokens,
      result.reportedEstimate.outputTokens,
      'provider-reported-token-counts',
    ).estimatedNeurons,
  );
  return {
    accountedNeurons,
    kind: 'reported-tokens-estimate',
    billingMeasured: false,
    exceededReservation: accountedNeurons > reservedNeurons,
  };
}
