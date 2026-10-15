import { sha256 } from '@bible/core';
import {
  prepareCompanionRequest,
  validatePreparedInputCapacity,
  PRICING_VERSION,
  getModel,
  validateSettings,
  HarnessError,
  estimateModelBudget,
  requireVerifiedBudgetReservation,
  type AnswerInput,
  type ModelAuthorization,
  type VerifiedBudgetBounds,
} from '@bible/ai-harness';
import type { Env } from './types';
import { fail, now, configuredBudget } from './http';
export async function rateLimit(
  env: Env,
  scope: string,
  limit: number,
  seconds = 60,
): Promise<void> {
  const window = Math.floor(now() / seconds);
  const result = await env.DB.prepare(
    'INSERT INTO rate_windows(scope,window,count) VALUES(?,?,1) ON CONFLICT(scope,window) DO UPDATE SET count=count+1 RETURNING count',
  )
    .bind(await sha256(scope), window)
    .first<{ count: number }>();
  if (!result || result.count > limit)
    fail(429, 'rate_limited', 'Too many requests. Please wait and try again.');
}
export async function reserveBudget(
  env: Env,
  userId: string,
  id: string,
  amount?: number,
): Promise<void> {
  const day = new Date().toISOString().slice(0, 10);
  const reserve = amount ?? configuredBudget(env.AI_RESERVATION_UNITS);
  try {
    await env.DB.batch([
      env.DB.prepare('INSERT OR IGNORE INTO budget_days(day) VALUES(?)').bind(day),
      env.DB.prepare('INSERT OR IGNORE INTO user_budget_days(user_id,day) VALUES(?,?)').bind(
        userId,
        day,
      ),
      env.DB.prepare(
        'INSERT INTO budget_reservations(id,user_id,day,amount,created_at,app_limit,user_limit) VALUES(?,?,?,?,?,?,?)',
      ).bind(
        id,
        userId,
        day,
        reserve,
        now(),
        configuredBudget(env.DAILY_APP_BUDGET),
        configuredBudget(env.DAILY_USER_BUDGET),
      ),
    ]);
  } catch (e) {
    if (String(e).includes('budget_exceeded'))
      fail(
        429,
        'daily_budget_exceeded',
        'Today’s generation budget is exhausted. Resets at 00:00 UTC. Saved reading remains available.',
      );
    throw e;
  }
}
/** Unknown/failed/cancelled provider usage consumes the whole reservation, never a fabricated zero. */
export async function settleBudget(
  env: Env,
  id: string,
  actual: number | null = null,
): Promise<void> {
  if (actual !== null && (!Number.isSafeInteger(actual) || actual < 0))
    throw new Error('Invalid usage');
  await env.DB.prepare(
    "UPDATE budget_reservations SET actual=?,state='settled' WHERE id=? AND state='reserved'",
  )
    .bind(actual, id)
    .run();
}

/** Server-loaded immutable evidence. Never construct from HTTP request data. */
export interface LoadedBudgetProof {
  readonly bounds: Readonly<VerifiedBudgetBounds> | undefined;
  /** Hash binds the exact stored proof bytes, model ID and current pricing version. */
  readonly proofFingerprint: string;
  readonly storageIdentity: Readonly<{
    modelId: string;
    pricingVersion: string;
    boundsJson: string;
  }>;
}
export interface DispatchProofIdentity {
  readonly modelId: string;
  readonly pricingVersion: string;
  readonly boundsJson: string;
  readonly expiresAt: string;
}

/** One D1 query for a bounded catalog, avoiding one connection per model. */
export async function loadBudgetProofs(
  env: Env,
  modelIds: readonly string[],
): Promise<ReadonlyMap<string, LoadedBudgetProof | null>> {
  const ids = [...new Set(modelIds)];
  if (ids.length > 22) throw new Error('Too many model IDs');
  for (const id of ids) estimateModelBudget(id, 0, 0); // Exact registry allowlist.
  const result = new Map<string, LoadedBudgetProof | null>(ids.map((id) => [id, null]));
  if (!ids.length) return result;
  const rows = await env.DB.prepare(
    `SELECT model_id,bounds_json FROM model_budget_proofs WHERE pricing_version=? AND model_id IN (${ids.map(() => '?').join(',')})`,
  )
    .bind(PRICING_VERSION, ...ids)
    .all<{ model_id: string; bounds_json: string }>();
  await Promise.all(
    rows.results.map(async (row) => {
      if (!result.has(row.model_id)) return;
      let bounds: Readonly<VerifiedBudgetBounds> | undefined;
      try {
        const parsed = JSON.parse(row.bounds_json);
        if (parsed !== null && typeof parsed === 'object' && !Array.isArray(parsed))
          bounds = Object.freeze(parsed) as Readonly<VerifiedBudgetBounds>;
      } catch {
        // Corrupt evidence stays present-but-invalid, never an approval.
      }
      result.set(
        row.model_id,
        Object.freeze({
          bounds,
          storageIdentity: Object.freeze({
            modelId: row.model_id,
            pricingVersion: PRICING_VERSION,
            boundsJson: row.bounds_json,
          }),
          proofFingerprint: await sha256(
            JSON.stringify([row.model_id, PRICING_VERSION, row.bounds_json]),
          ),
        }),
      );
    }),
  );
  return result;
}

/** Pure planning/dispatch check. Zero input means plan against the proof's full bound, not free input.
 * At dispatch pass the actual prepared input estimate and recheck the stored fingerprint/expiry. */
export function estimateReservationFromProof(
  modelId: string,
  maxOutputTokens: number,
  remainingNeurons: number,
  proof: LoadedBudgetProof | null | undefined,
  inputTokens = 0,
) {
  const estimate = estimateModelBudget(modelId, inputTokens, maxOutputTokens);
  const amount = requireVerifiedBudgetReservation(estimate, remainingNeurons, proof?.bounds);
  return {
    amount,
    estimate,
    proofVersion: proof!.bounds!.evidenceRef,
    proofFingerprint: proof!.proofFingerprint,
    expiresAt: proof!.bounds!.expiresAt,
  };
}

export const FREE_HARD_STOP_POLICY_VERSION = 'workers-ai-free-hard-stop.v2';
export const FREE_ESTIMATE_POLICY_VERSION = 'free-reservation-prepared-input-125pct.v2';
const FREE_INPUT_RESERVATION_CEILING = 64000;
const FREE_ESTIMATE_MULTIPLIER = 1.25;
export type LoadedBudgetAuthority =
  | {
      readonly mode: 'strict-proof';
      readonly proofs: ReadonlyMap<string, LoadedBudgetProof | null>;
    }
  | { readonly mode: 'free-provider-hard-stop' };
export type BudgetDispatchIdentity =
  | ({ readonly mode: 'strict-proof' } & DispatchProofIdentity)
  | {
      readonly mode: 'free-provider-hard-stop';
      readonly budgetDay: string;
      readonly appLimit: number;
      readonly userLimit: number;
      readonly expiresAt: string;
    };
export function budgetMode(env: Env): LoadedBudgetAuthority['mode'] {
  const mode = env.AI_BUDGET_MODE ?? 'strict-proof';
  if (mode !== 'strict-proof' && mode !== 'free-provider-hard-stop')
    throw new HarnessError('BUDGET_UNVERIFIED');
  return mode;
}
/** Free mode depends on provider quota and atomic app reservations, not a renewable certificate. */
export async function loadBudgetAuthority(
  env: Env,
  modelIds: readonly string[],
): Promise<LoadedBudgetAuthority> {
  const mode = budgetMode(env);
  if (mode === 'strict-proof') return { mode, proofs: await loadBudgetProofs(env, modelIds) };
  if (new Set(modelIds).size > 22) throw new HarnessError('INVALID_INPUT');
  modelIds.forEach(getModel);
  return Object.freeze({ mode });
}
function freeBudgetWindow(env: Env) {
  const budgetDay = new Date().toISOString().slice(0, 10);
  return {
    mode: 'free-provider-hard-stop' as const,
    budgetDay,
    appLimit: configuredBudget(env.DAILY_APP_BUDGET),
    userLimit: configuredBudget(env.DAILY_USER_BUDGET),
    expiresAt: new Date(Date.parse(budgetDay + 'T00:00:00Z') + 86400000).toISOString(),
  };
}
function withDispatchIdentity<T extends object>(
  value: T,
  identity: BudgetDispatchIdentity,
): T & { readonly dispatchIdentity: BudgetDispatchIdentity } {
  return Object.defineProperty(value, 'dispatchIdentity', {
    value: Object.freeze(identity),
    enumerable: false,
    writable: false,
  }) as T & { readonly dispatchIdentity: BudgetDispatchIdentity };
}
/** Prepared-input estimates must match at planning and dispatch. Zero input is catalog-only worst-case planning, never a token proof. */
export function estimateModelReservation(
  env: Env,
  modelId: string,
  maxOutputTokens: number,
  authority: LoadedBudgetAuthority,
  inputTokens = 0,
) {
  if (budgetMode(env) !== authority.mode) throw new HarnessError('BUDGET_UNVERIFIED');
  const remaining = configuredBudget(env.DAILY_APP_BUDGET);
  if (authority.mode === 'strict-proof') {
    const proof = authority.proofs.get(modelId);
    const reservation = estimateReservationFromProof(
      modelId,
      maxOutputTokens,
      remaining,
      proof,
      inputTokens,
    );
    return withDispatchIdentity(
      {
        ...reservation,
        budgetMode: 'strict-proof' as const,
        reservationBasis: 'verified-proof-bounds' as const,
        budgetBoundVerified: true as const,
        estimatedInputTokenCeiling: proof!.bounds!.inputTokenUpperBound,
        estimateSafetyMultiplier: 1,
        warnings: [] as string[],
      },
      { mode: 'strict-proof', ...proof!.storageIdentity, expiresAt: reservation.expiresAt },
    );
  }
  const model = getModel(modelId);
  if (model.billingTier !== 'free-allocation-candidate') throw new HarnessError('MODEL_DISABLED');
  validateSettings(modelId, { maxOutputTokens });
  const window = freeBudgetWindow(env);
  const ceiling = Math.min(
    FREE_INPUT_RESERVATION_CEILING,
    validatePreparedInputCapacity(modelId, 0, maxOutputTokens),
  );
  if (!Number.isSafeInteger(inputTokens) || inputTokens < 0 || inputTokens > ceiling)
    throw new HarnessError('BUDGET_UNVERIFIED');
  const reservationInput = inputTokens > 0 ? inputTokens : ceiling;
  const estimate = estimateModelBudget(modelId, reservationInput, maxOutputTokens);
  const amount = Math.ceil(estimate.estimatedNeurons * FREE_ESTIMATE_MULTIPLIER);
  if (!Number.isSafeInteger(amount) || amount < 1 || amount > remaining)
    throw new HarnessError('BUDGET_EXCEEDED');
  return withDispatchIdentity(
    {
      amount,
      estimate,
      proofVersion: FREE_HARD_STOP_POLICY_VERSION,
      // Bind this request to its UTC budget day and configured limits; no contract certificate.
      proofFingerprint: JSON.stringify([
        authority.mode,
        window.budgetDay,
        window.appLimit,
        window.userLimit,
        PRICING_VERSION,
        FREE_ESTIMATE_POLICY_VERSION,
        modelId,
        ceiling,
        reservationInput,
        maxOutputTokens,
        amount,
      ]),
      expiresAt: window.expiresAt,
      budgetMode: 'free-provider-hard-stop' as const,
      reservationBasis: 'estimated-reservation-provider-free-hard-stop' as const,
      budgetBoundVerified: false as const,
      estimatedInputTokenCeiling: ceiling,
      estimatedInputTokenReservation: reservationInput,
      inputEstimateBasis:
        inputTokens > 0
          ? ('prepared-request-utf8-byte-upper-bound' as const)
          : ('catalog-policy-ceiling' as const),
      estimateSafetyMultiplier: FREE_ESTIMATE_MULTIPLIER,
      warnings: [
        'ESTIMATED_RESERVATION_NOT_TOKEN_PROOF',
        'PROVIDER_FREE_QUOTA_IS_FINAL_STOP',
        'HIDDEN_REASONING_USAGE_UNKNOWN',
        'OTHER_ACCOUNT_USAGE_NOT_RESERVED',
        'NO_AUTOMATIC_PAID_FALLBACK',
      ],
    },
    window,
  );
}
/** Recheck request configuration immediately before the atomic evidence-row dispatch CAS. */
export function assertBudgetDispatchConfiguration(env: Env, identity: BudgetDispatchIdentity) {
  if (
    budgetMode(env) !== identity.mode ||
    Date.parse(identity.expiresAt) <= Date.now() ||
    !Number.isFinite(Date.parse(identity.expiresAt))
  )
    throw new HarnessError('BUDGET_UNVERIFIED');
  if (
    identity.mode === 'free-provider-hard-stop' &&
    (identity.budgetDay !== new Date().toISOString().slice(0, 10) ||
      identity.appLimit !== configuredBudget(env.DAILY_APP_BUDGET) ||
      identity.userLimit !== configuredBudget(env.DAILY_USER_BUDGET))
  )
    throw new HarnessError('BUDGET_UNVERIFIED');
}

/** Default strict-proof behavior remains separate; Free mode needs no contract certificate. */
export async function estimateReservation(
  env: Env,
  input: AnswerInput,
  authorization: ModelAuthorization,
  answerMode: 'reviewed-claim-selection' | 'grounded-generation' = 'reviewed-claim-selection',
) {
  const prepared = prepareCompanionRequest(input, {
    authorization,
    answerMode,
    allowGeneralKnowledge: env.GENERAL_KNOWLEDGE_ENABLED === 'true',
  });
  const authority = await loadBudgetAuthority(env, [prepared.model.id]);
  return estimateModelReservation(
    env,
    prepared.model.id,
    prepared.settings.maxOutputTokens,
    authority,
    prepared.usage.estimated.inputTokens,
  );
}
export async function modelBudgetReadiness(
  env: Env,
  modelId: string,
  maxOutputTokens = 512,
  preloadedProof?: LoadedBudgetProof | null,
  preloadedAuthority?: LoadedBudgetAuthority,
) {
  const estimate = estimateModelBudget(modelId, 0, maxOutputTokens);
  try {
    const authority =
      preloadedAuthority ??
      (budgetMode(env) === 'strict-proof' && preloadedProof !== undefined
        ? { mode: 'strict-proof' as const, proofs: new Map([[modelId, preloadedProof]]) }
        : await loadBudgetAuthority(env, [modelId]));
    if (budgetMode(env) !== authority.mode) throw new HarnessError('BUDGET_UNVERIFIED');
    if (authority.mode === 'free-provider-hard-stop') {
      const model = getModel(modelId);
      if (model.billingTier !== 'free-allocation-candidate')
        throw new HarnessError('MODEL_DISABLED');
      validateSettings(modelId, { maxOutputTokens });
      validatePreparedInputCapacity(modelId, 0, maxOutputTokens);
      const window = freeBudgetWindow(env);
      configuredBudget(env.DAILY_APP_BUDGET);
      configuredBudget(env.DAILY_USER_BUDGET);
      return {
        ready: true,
        reason: null,
        pricingVersion: estimate.pricingVersion,
        expiresAt: window.expiresAt,
        budgetMode: authority.mode,
        readinessScope: 'provider-policy-only' as const,
        preparedRequestBudgetRequired: true,
        reservationBasis: 'prepared-request-estimate-required',
        budgetBoundVerified: false,
        warnings: [
          'EXACT_REQUEST_BUDGET_CHECK_REQUIRED',
          'ESTIMATED_RESERVATION_NOT_TOKEN_PROOF',
          'PROVIDER_FREE_QUOTA_IS_FINAL_STOP',
          'NO_AUTOMATIC_PAID_FALLBACK',
        ],
      };
    }
    const reservation = estimateModelReservation(env, modelId, maxOutputTokens, authority);
    if (reservation.amount > configuredBudget(env.DAILY_USER_BUDGET))
      throw new HarnessError('BUDGET_EXCEEDED');
    return {
      ready: true,
      reason: null,
      readinessScope: 'verified-proof-bounds' as const,
      preparedRequestBudgetRequired: true,
      pricingVersion: estimate.pricingVersion,
      expiresAt: reservation.expiresAt,
      proofFingerprint: reservation.proofFingerprint,
      budgetMode: reservation.budgetMode,
      reservationBasis: reservation.reservationBasis,
      budgetBoundVerified: reservation.budgetBoundVerified,
      warnings: reservation.warnings,
    };
  } catch (error) {
    return {
      ready: false,
      reason: error instanceof HarnessError ? error.code : 'BUDGET_UNVERIFIED',
      pricingVersion: estimate.pricingVersion,
      expiresAt: null,
      budgetBoundVerified: false,
    };
  }
}

/** Only plausible direct-provider metering can release an estimate. Missing/invalid usage consumes it all. */
export function reportedBudgetConsumption(
  modelId: string,
  usage: { inputTokens: number; outputTokens: number; providerNeurons?: number } | null,
): number | null {
  if (
    !usage ||
    !Number.isSafeInteger(usage.inputTokens) ||
    !Number.isSafeInteger(usage.outputTokens) ||
    usage.inputTokens + usage.outputTokens < 1
  )
    return null;
  const value = usage.providerNeurons;
  if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0 || value > 1000000)
    return null;
  const estimate = estimateModelBudget(
    modelId,
    usage.inputTokens,
    usage.outputTokens,
    'provider-reported-token-counts',
  ).estimatedNeurons;
  if (Math.abs(value - estimate) > Math.max(0.001, estimate * 0.02)) return null;
  return Math.ceil(value);
}
