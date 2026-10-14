import { describe, it, expect } from 'vitest';
import { createEvaluationPlan } from '../eval/plan.ts';
import { DEFAULT_MODEL_ID } from '../src/index.ts';
describe('bounded reproducible evaluation planning without inference', () => {
  it('defaults to the ten requested Bible questions', () => {
    const plan = createEvaluationPlan();
    expect(plan.callCount).toBe(10);
    expect(plan.kind).toBe('evaluation-plan-not-executed');
    expect(plan.estimatedCostUsd).toBeGreaterThan(0);
    expect(plan.budgetBoundVerified).toBe(false);
    expect(plan.executionEligible).toBe(false);
    expect(plan.costApprovalRequired).toBe(true);
  });
  it('allows at most two distinct models', () => {
    expect(() =>
      createEvaluationPlan({ modelIds: [DEFAULT_MODEL_ID, DEFAULT_MODEL_ID] }),
    ).toThrow();
    expect(() =>
      createEvaluationPlan({
        modelIds: [
          DEFAULT_MODEL_ID,
          '@cf/meta/llama-3.2-1b-instruct',
          '@cf/meta/llama-3.2-3b-instruct',
        ],
      }),
    ).toThrow();
  });
  it('alternates pair order across repetitions and stays sequential', () => {
    const ids = [DEFAULT_MODEL_ID, '@cf/meta/llama-3.2-1b-instruct'];
    const plan = createEvaluationPlan({ modelIds: ids, repetitions: 2 });
    expect(plan.callCount).toBe(40);
    expect(plan.sequential).toBe(true);
    expect(plan.jobs.slice(0, 2).map((j) => j.modelId)).toEqual(ids);
    expect(plan.jobs.slice(20, 22).map((j) => j.modelId)).toEqual([...ids].reverse());
  });
  it('rejects unknown cases and forged models before execution', () => {
    expect(() => createEvaluationPlan({ modelIds: ['https://evil.example'] })).toThrow(
      'UNKNOWN_MODEL',
    );
    expect(() => createEvaluationPlan({ caseIds: ['invented-case'] })).toThrow();
    expect(() => createEvaluationPlan({ repetitions: 100 })).toThrow();
  });
});
