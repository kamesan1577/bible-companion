import {
  getModel,
  prepareCompanionRequest,
  DEFAULT_MODEL_ID,
  estimateModelBudget,
  PRICING_VERSION,
} from '../src/index.ts';
import type { ModelSettings } from '../src/types.ts';
import { BIBLE_QUESTIONS, inputForCase } from '../fixtures/questions.ts';
export interface EvaluationPlan {
  kind: 'evaluation-plan-not-executed';
  mode: 'reviewed-claim-selection' | 'grounded-generation';
  modelIds: string[];
  caseIds: string[];
  repetitions: number;
  callCount: number;
  estimatedInputTokenUpperBound: number;
  maxOutputTokens: number;
  estimatedNeurons: number;
  estimatedCostUsd: number;
  pricingVersion: string;
  budgetBoundVerified: false;
  executionEligible: false;
  costApprovalRequired: true;
  sequential: true;
  jobs: { caseId: string; modelId: string; repetition: number }[];
}
export function createEvaluationPlan(
  options: {
    modelIds?: string[];
    caseIds?: string[];
    repetitions?: number;
    settings?: ModelSettings;
    mode?: EvaluationPlan['mode'];
  } = {},
): EvaluationPlan {
  const modelIds = options.modelIds ?? [DEFAULT_MODEL_ID];
  const caseIds = options.caseIds ?? BIBLE_QUESTIONS.slice(0, 10).map((test) => test.id);
  const repetitions = options.repetitions ?? 1;
  const mode = options.mode ?? 'grounded-generation';
  if (!modelIds.length || modelIds.length > 2 || new Set(modelIds).size !== modelIds.length)
    throw new Error('Select one or two distinct model IDs.');
  if (
    !caseIds.length ||
    caseIds.length > 12 ||
    new Set(caseIds).size !== caseIds.length ||
    caseIds.some((id) => !BIBLE_QUESTIONS.some((test) => test.id === id))
  )
    throw new Error('Unknown or duplicate evaluation case.');
  if (!Number.isInteger(repetitions) || repetitions < 1 || repetitions > 3)
    throw new Error('Repetitions must be 1–3.');
  modelIds.forEach(getModel);
  const jobs: EvaluationPlan['jobs'] = [];
  let estimatedInputTokenUpperBound = 0;
  let maxOutputTokens = 0;
  let estimatedNeurons = 0;
  let estimatedCostUsd = 0;
  for (let repetition = 0; repetition < repetitions; repetition++) {
    const order = repetition % 2 === 0 ? modelIds : [...modelIds].reverse();
    for (const caseId of caseIds)
      for (const modelId of order) {
        const test = BIBLE_QUESTIONS.find((test) => test.id === caseId)!;
        const request = prepareCompanionRequest(
          { ...inputForCase(test), modelId, settings: options.settings },
          { authorization: { ownerId: 'plan-only', connectedModelIds: [] }, answerMode: mode },
        );
        estimatedInputTokenUpperBound += request.usage.estimated.inputTokens;
        maxOutputTokens += request.settings.maxOutputTokens;
        const priced = estimateModelBudget(
          modelId,
          request.usage.estimated.inputTokens,
          request.settings.maxOutputTokens,
        );
        estimatedNeurons += priced.estimatedNeurons;
        estimatedCostUsd += priced.estimatedUsd;
        jobs.push({ caseId, modelId, repetition });
      }
  }
  return {
    kind: 'evaluation-plan-not-executed',
    mode,
    modelIds: [...modelIds],
    caseIds: [...caseIds],
    repetitions,
    callCount: jobs.length,
    estimatedInputTokenUpperBound,
    maxOutputTokens,
    estimatedNeurons,
    estimatedCostUsd,
    pricingVersion: PRICING_VERSION,
    budgetBoundVerified: false,
    executionEligible: false,
    costApprovalRequired: true,
    sequential: true,
    jobs,
  };
}
