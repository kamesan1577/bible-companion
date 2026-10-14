import { describe, it, expect } from 'vitest';
import {
  listModels,
  getModelPricing,
  estimateModelBudget,
  requireVerifiedBudgetReservation,
  settleEstimatedReservation,
  DEFAULT_MODEL_ID,
  PRICING_VERSION,
} from '../src/index.ts';
describe('published neuron pricing with explicit unverified bounds', () => {
  it('has official-rate metadata for every candidate without claiming live calibration', () => {
    for (const model of listModels())
      expect(getModelPricing(model.id).outputLimitIncludesReasoning).toBe('unverified');
  });
  it('converts token estimates with exact published neuron rates', () => {
    const result = estimateModelBudget(DEFAULT_MODEL_ID, 1000, 512);
    expect(result.estimatedNeurons).toBeCloseTo(9.091 + 13.963776, 6);
    expect(result.billingMeasured).toBe(false);
    expect(result.hardCapVerified).toBe(false);
    expect(result.warnings).toContain('HIDDEN_REASONING_BUDGET_NOT_VERIFIED');
  });
  it('expensive output differs materially from a small model and from token counts', () => {
    const cheap = estimateModelBudget('@cf/meta/llama-3.2-1b-instruct', 1000, 2000);
    const expensive = estimateModelBudget(
      '@cf/deepseek-ai/deepseek-r1-distill-qwen-32b',
      1000,
      2000,
    );
    expect(expensive.estimatedNeurons).toBeGreaterThan(cheap.estimatedNeurons * 20);
    expect(expensive.estimatedNeurons).not.toBe(3000);
  });
  it('cannot unlock inference from an estimate or unknown hidden-reasoning bound', () => {
    expect(() =>
      requireVerifiedBudgetReservation(estimateModelBudget(DEFAULT_MODEL_ID, 1000, 512), 10000),
    ).toThrow('BUDGET_UNVERIFIED');
  });
  it('requires current model-matching verified budget evidence, then enforces remaining neurons', () => {
    const estimate = estimateModelBudget(DEFAULT_MODEL_ID, 1000, 512);
    const bounds = {
      modelId: DEFAULT_MODEL_ID,
      pricingVersion: PRICING_VERSION,
      inputTokenUpperBound: 2048,
      outputTokenUpperBound: 1024,
      includesHiddenReasoning: true as const,
      evidenceRef: 'test-fixture-only',
      expiresAt: '2030-01-01T00:00:00Z',
    };
    expect(requireVerifiedBudgetReservation(estimate, 10000, bounds, 0)).toBe(47);
    expect(() => requireVerifiedBudgetReservation(estimate, 5, bounds, 0)).toThrow(
      'BUDGET_EXCEEDED',
    );
    expect(() =>
      requireVerifiedBudgetReservation(
        estimate,
        10000,
        { ...bounds, includesHiddenReasoning: false as true },
        0,
      ),
    ).toThrow('BUDGET_UNVERIFIED');
    expect(() =>
      requireVerifiedBudgetReservation(estimate, 10000, { ...bounds, pricingVersion: 'old' }, 0),
    ).toThrow('BUDGET_UNVERIFIED');
    expect(() =>
      requireVerifiedBudgetReservation(estimate, 10000, { ...bounds, inputTokenUpperBound: 2 }, 0),
    ).toThrow('BUDGET_UNVERIFIED');
    expect(() =>
      requireVerifiedBudgetReservation(estimate, 10000, bounds, Date.parse('2031-01-01')),
    ).toThrow('BUDGET_UNVERIFIED');
  });
  it('retains reservations after partial/failed/cancelled inference with unknown usage', () => {
    expect(settleEstimatedReservation(100, { dispatched: true, usageUnknown: true })).toMatchObject(
      { accountedNeurons: 100, kind: 'reservation-retained' },
    );
    expect(
      settleEstimatedReservation(100, { dispatched: true, usageUnknown: false }),
    ).toMatchObject({ accountedNeurons: 100, kind: 'reservation-retained' });
    expect(
      settleEstimatedReservation(100, { dispatched: false, usageUnknown: false }).accountedNeurons,
    ).toBe(0);
  });
  it('reported-token estimates remain estimates and do not hide an overrun', () => {
    const result = settleEstimatedReservation(1, {
      dispatched: true,
      usageUnknown: false,
      reportedEstimate: estimateModelBudget(
        DEFAULT_MODEL_ID,
        1000,
        512,
        'provider-reported-token-counts',
      ),
    });
    expect(result.accountedNeurons).toBe(24);
    expect(result.billingMeasured).toBe(false);
    expect(result.exceededReservation).toBe(true);
  });
  it.each([NaN, Infinity, -1, 1.5])('rejects invalid token count %s', (count) =>
    expect(() => estimateModelBudget(DEFAULT_MODEL_ID, count, 512)).toThrow('INVALID_INPUT'),
  );
});

describe('budget helpers fail closed on malformed accounting state', () => {
  it('recomputes cost rather than trusting a caller-overridden neuron field', () => {
    const reported = estimateModelBudget(
      DEFAULT_MODEL_ID,
      1000,
      512,
      'provider-reported-token-counts',
    );
    expect(
      settleEstimatedReservation(100, {
        dispatched: true,
        usageUnknown: false,
        reportedEstimate: { ...reported, estimatedNeurons: 0 },
      }).accountedNeurons,
    ).toBe(24);
  });
  it('rejects absent dispatch evidence rather than refunding by default', () => {
    expect(() => settleEstimatedReservation(100, { usageUnknown: false } as never)).toThrow(
      'INVALID_INPUT',
    );
  });
  it('rejects stale pricing metadata for reported-token settlement', () => {
    const reported = estimateModelBudget(
      DEFAULT_MODEL_ID,
      1000,
      512,
      'provider-reported-token-counts',
    );
    expect(() =>
      settleEstimatedReservation(100, {
        dispatched: true,
        usageUnknown: false,
        reportedEstimate: { ...reported, pricingVersion: 'stale' },
      }),
    ).toThrow('INVALID_INPUT');
  });
});
