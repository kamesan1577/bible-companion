import { MODEL_TERMS_POLICY_VERSION, PUBLISHED_MODEL_TERMS } from './model-terms.ts';
export { MODEL_TERMS_POLICY_VERSION } from './model-terms.ts';
import { PRICING_DATA } from './pricing-data.ts';
import { CATALOG_DATA } from './catalog.ts';
import { HarnessError } from './errors.ts';
import type { ModelAuthorization, ModelSettings } from './types.ts';
export const REGISTRY_VERSION = 'workers-ai-2026-10-13.v2';
export const DEFAULT_MODEL_ID = '@cf/google/gemma-4-26b-a4b-it';
export type ModelDefinition = (typeof CATALOG_DATA)[number];
const models = new Map<string, ModelDefinition>(
  CATALOG_DATA.map((model) => [model.id, Object.freeze(model)]),
);
export function getModel(modelId: string): ModelDefinition {
  if (typeof modelId !== 'string' || !models.has(modelId)) throw new HarnessError('UNKNOWN_MODEL');
  return models.get(modelId)!;
}
export function assertModelAuthorized(
  modelId: string,
  authorization: ModelAuthorization,
): ModelDefinition {
  const model = getModel(modelId);
  if (
    !authorization ||
    typeof authorization.ownerId !== 'string' ||
    !authorization.ownerId.trim() ||
    !Array.isArray(authorization.connectedModelIds) ||
    authorization.connectedModelIds.some((id) => typeof id !== 'string') ||
    (authorization.paidModelIds !== undefined &&
      (!Array.isArray(authorization.paidModelIds) ||
        authorization.paidModelIds.some((id) => typeof id !== 'string')))
  )
    throw new HarnessError('INVALID_INPUT');
  if (model.billingTier === 'paid-required' && !authorization.paidModelIds?.includes(model.id)) {
    throw new HarnessError('MODEL_DISABLED');
  }
  if (!authorization.connectedModelIds.includes(model.id))
    throw new HarnessError('MODEL_UNCONNECTED');
  if (!hasCurrentTermsReview(model.id, authorization))
    throw new HarnessError('MODEL_TERMS_UNREVIEWED');
  return model;
}
function hasCurrentTermsReview(modelId: string, authorization?: ModelAuthorization): boolean {
  return (
    authorization?.termsReviewVersion === MODEL_TERMS_POLICY_VERSION &&
    Array.isArray(authorization.termsReviewedModelIds) &&
    authorization.termsReviewedModelIds.every((id) => typeof id === 'string') &&
    authorization.termsReviewedModelIds.includes(modelId)
  );
}
/** No secrets, owner IDs or mutable global connectivity are exposed. Authorization comes from server state. */
export function listModels(authorization?: ModelAuthorization) {
  return [...models.values()].map((model) => {
    const paidApproved =
      model.billingTier !== 'paid-required' ||
      authorization?.paidModelIds?.includes(model.id) === true;
    const connected = authorization?.connectedModelIds?.includes(model.id) === true;
    const termsReviewed = hasCurrentTermsReview(model.id, authorization);
    return {
      ...model,
      termsReview: {
        status: termsReviewed ? ('reviewed' as const) : ('unreviewed' as const),
        policyVersion: MODEL_TERMS_POLICY_VERSION,
        modelTermsUrl: PUBLISHED_MODEL_TERMS[model.id] ?? null,
        evidenceUrl: model.officialUrl,
        evidenceCheckedAt: '2026-10-13',
        acceptancePerformed: false as const,
      },
      pricing: PRICING_DATA.find((rate) => rate.modelId === model.id),
      connectionStatus: connected ? ('connected' as const) : ('unconnected' as const),
      enabled: connected && paidApproved && termsReviewed,
      disabledReason: !paidApproved
        ? 'PAID_APPROVAL_REQUIRED'
        : !connected
          ? 'CONNECTION_NOT_VERIFIED'
          : !termsReviewed
            ? 'MODEL_TERMS_UNREVIEWED'
            : null,
      settingsSchema: {
        maxOutputTokens: { type: 'integer', minimum: 64, maximum: 2048, default: 512 },
        temperature: { type: 'number', minimum: 0, maximum: model.temperatureMax, default: 0.2 },
        timeoutMs: { type: 'integer', minimum: 1000, maximum: 60000, default: 15000 },
        stream: { type: 'boolean', supported: model.streamSupported, default: false },
        reasoning: { supported: false, reason: 'No verified binding parameter mapping; omitted.' },
      },
      runtimeValidation: 'not-run' as const,
    };
  });
}
export interface ValidatedSettings {
  requested: ModelSettings;
  effective: Record<string, unknown>;
  timeoutMs: number;
  maxOutputTokens: number;
  stream: boolean;
}
export function validateSettings(modelId: string, settings: ModelSettings = {}): ValidatedSettings {
  const model = getModel(modelId);
  if (settings === null || typeof settings !== 'object' || Array.isArray(settings))
    throw new HarnessError('INVALID_SETTINGS');
  if (
    Object.keys(settings).some(
      (key) =>
        !['maxOutputTokens', 'temperature', 'timeoutMs', 'stream', 'reasoning'].includes(key),
    )
  ) {
    throw new HarnessError('INVALID_SETTINGS');
  }
  if (Object.values(settings).some((value) => value === null))
    throw new HarnessError('INVALID_SETTINGS');
  if (settings.reasoning !== undefined) throw new HarnessError('UNSUPPORTED_SETTING');
  const maxOutputTokens = settings.maxOutputTokens ?? 512;
  const temperature = settings.temperature ?? 0.2;
  const timeoutMs = settings.timeoutMs ?? 15000;
  const stream = settings.stream ?? false;
  if (
    !Number.isInteger(maxOutputTokens) ||
    maxOutputTokens < 64 ||
    maxOutputTokens > 2048 ||
    !Number.isFinite(temperature) ||
    temperature < 0 ||
    temperature > model.temperatureMax ||
    !Number.isInteger(timeoutMs) ||
    timeoutMs < 1000 ||
    timeoutMs > 60000 ||
    typeof stream !== 'boolean'
  )
    throw new HarnessError('INVALID_SETTINGS');
  if (stream && !model.streamSupported) throw new HarnessError('UNSUPPORTED_SETTING');
  return {
    requested: { ...settings },
    effective: { [model.tokenParameter]: maxOutputTokens, temperature, stream },
    timeoutMs,
    maxOutputTokens,
    stream,
  };
}
/** Shared context admission rule; the estimate is not provider tokenization or a billing proof.
 * Returns maximum admitted input estimate so server policies need not duplicate template headroom. */
export function validatePreparedInputCapacity(
  modelId: string,
  inputTokens: number,
  maxOutputTokens: number,
): number {
  const settings = validateSettings(modelId, { maxOutputTokens });
  if (!Number.isSafeInteger(inputTokens) || inputTokens < 0)
    throw new HarnessError('INVALID_INPUT');
  const capacity = getModel(modelId).contextWindowTokens - settings.maxOutputTokens - 1024;
  if (inputTokens > capacity) throw new HarnessError('CONTEXT_TOO_LARGE');
  return capacity;
}
export class ProviderAdapterRegistry {
  get(provider: string, modelId: string) {
    if (provider !== 'cloudflare-workers-ai') throw new HarnessError('UNKNOWN_MODEL');
    return getModel(modelId);
  }
  list(authorization?: ModelAuthorization) {
    return listModels(authorization);
  }
}
