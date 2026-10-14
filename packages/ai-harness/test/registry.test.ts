import { offlineFixtureAuthorization } from '../fixtures/authorization.ts';
import { describe, it, expect } from 'vitest';
import {
  listModels,
  getModel,
  validateSettings,
  assertModelAuthorized,
  ProviderAdapterRegistry,
  DEFAULT_MODEL_ID,
} from '../src/index.ts';
describe('model registry: offline metadata is not a connection check', () => {
  it('registers exactly 22 IDs, 15 free-allocation candidates and 7 paid candidates, all unconnected', () => {
    const models = listModels();
    expect(models).toHaveLength(22);
    expect(models.filter((m) => m.billingTier === 'free-allocation-candidate')).toHaveLength(15);
    expect(models.filter((m) => m.billingTier === 'paid-required')).toHaveLength(7);
    expect(
      models.every(
        (m) =>
          m.connectionStatus === 'unconnected' && !m.enabled && m.runtimeValidation === 'not-run',
      ),
    ).toBe(true);
  });
  it.each([
    '@cf/evil/model',
    'https://example.com/model',
    '__proto__',
    '@cf/swiss-ai/apertus-v1.5-8b',
  ])('rejects unknown or gated unregistered %s', (id) =>
    expect(() => getModel(id)).toThrow('UNKNOWN_MODEL'),
  );
  it('rejects providers even for a valid model', () =>
    expect(() => new ProviderAdapterRegistry().get('openai', DEFAULT_MODEL_ID)).toThrow(
      'UNKNOWN_MODEL',
    ));
  it('requires per-owner connection evidence', () =>
    expect(() =>
      assertModelAuthorized(DEFAULT_MODEL_ID, { ownerId: 'owner', connectedModelIds: [] }),
    ).toThrow('MODEL_UNCONNECTED'));
  it('paid approval and connection are independent requirements', () => {
    const id = '@cf/moonshotai/kimi-k2.6';
    expect(() => assertModelAuthorized(id, { ownerId: 'owner', connectedModelIds: [id] })).toThrow(
      'MODEL_DISABLED',
    );
    expect(() =>
      assertModelAuthorized(id, { ownerId: 'owner', connectedModelIds: [], paidModelIds: [id] }),
    ).toThrow('MODEL_UNCONNECTED');
    expect(assertModelAuthorized(id, offlineFixtureAuthorization('owner', id)).id).toBe(id);
    expect(
      listModels({ ownerId: 'owner', connectedModelIds: [id] }).find((m) => m.id === id)?.enabled,
    ).toBe(false);
  });
  it('requires exact version-bound server terms review independently from connection', () => {
    const auth = offlineFixtureAuthorization('owner', DEFAULT_MODEL_ID);
    for (const denied of [
      { ...auth, termsReviewedModelIds: [] },
      { ...auth, termsReviewVersion: undefined },
      { ...auth, termsReviewVersion: 'stale-policy' },
    ]) {
      expect(() => assertModelAuthorized(DEFAULT_MODEL_ID, denied)).toThrow(
        'MODEL_TERMS_UNREVIEWED',
      );
      expect(listModels(denied).find((m) => m.id === DEFAULT_MODEL_ID)?.enabled).toBe(false);
    }
    expect(listModels(auth).find((m) => m.id === DEFAULT_MODEL_ID)?.termsReview.status).toBe(
      'reviewed',
    );
    expect(listModels().every((m) => m.termsReview.status === 'unreviewed')).toBe(true);
    expect(
      listModels().find((m) => m.id === '@cf/qwen/qwen3-30b-a3b-fp8')?.termsReview.modelTermsUrl,
    ).toBeNull();
  });
  it('maps output token parameter per documented model', () => {
    expect(validateSettings(DEFAULT_MODEL_ID).effective).toEqual({
      max_completion_tokens: 512,
      temperature: 0.2,
      stream: false,
      chat_template_kwargs: { enable_thinking: false },
      response_format: { type: 'json_object' },
    });
    expect(validateSettings('@cf/qwen/qwen3-30b-a3b-fp8').effective).toEqual({
      max_tokens: 512,
      temperature: 0.2,
      stream: false,
    });
    expect(validateSettings('@cf/zai-org/glm-4.7-flash').effective).toHaveProperty(
      'max_completion_tokens',
      512,
    );
  });
  it.each([NaN, Infinity, -1, 5.1, '0.2', null])('rejects invalid temperature %s', (value) => {
    expect(() => validateSettings(DEFAULT_MODEL_ID, { temperature: value as number })).toThrow(
      'INVALID_SETTINGS',
    );
  });
  it.each([0, 63, 2049, 512.5, NaN, null])('rejects invalid output budget %s', (value) =>
    expect(() => validateSettings(DEFAULT_MODEL_ID, { maxOutputTokens: value as number })).toThrow(
      'INVALID_SETTINGS',
    ),
  );
  it.each([999, 60001, Infinity, null])('rejects invalid timeout %s', (value) =>
    expect(() => validateSettings(DEFAULT_MODEL_ID, { timeoutMs: value as number })).toThrow(
      'INVALID_SETTINGS',
    ),
  );
  it('never silently accepts common but unverified reasoning controls', () =>
    expect(() => validateSettings(DEFAULT_MODEL_ID, { reasoning: 'off' })).toThrow(
      'UNSUPPORTED_SETTING',
    ));
  it('rejects arbitrary provider options and endpoints', () =>
    expect(() =>
      validateSettings(DEFAULT_MODEL_ID, { url: 'https://evil.example' } as never),
    ).toThrow('INVALID_SETTINGS'));
  it('returned registry cannot mutate trusted model metadata', () => {
    const row = listModels()[0];
    row.temperatureMax = 99 as 2;
    expect(getModel(row.id).temperatureMax).toBe(2);
  });
});
