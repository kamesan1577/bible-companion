import { HarnessError } from './errors.ts';
import {
  getModel,
  assertModelAuthorized,
  validateSettings,
  validatePreparedInputCapacity,
  DEFAULT_MODEL_ID,
  REGISTRY_VERSION,
} from './registry.ts';
import {
  retrieveGrounding,
  eligibleClaims,
  validateAnswerInput,
  scopedHistory,
  isTrustedPrimaryTextSource,
  comparePosition,
} from './grounding.ts';
import { PROMPT_VERSION, buildMessages } from './prompts.ts';
import {
  validateSelection,
  validateGeneratedAnswer,
  insufficientAnswer,
  citationForSource,
} from './output.ts';
import { invokeWorkersAi } from './provider.ts';
import type {
  AnswerInput,
  AnswerDependencies,
  AnswerResult,
  UsageReport,
  ReferenceSystemNotice,
  ProviderPromptCacheReport,
} from './types.ts';
export * from './types.ts';
export * from './primary-text-manifests.ts';
export * from './budget.ts';
export * from './errors.ts';
export * from './registry.ts';
export * from './grounding.ts';
export * from './prompts.ts';
export * from './output.ts';
export * from './provider.ts';

/** Structural verse validity never establishes translation-specific numbering or wording. */
export function referenceSystemNotice(translation?: string): ReferenceSystemNotice {
  return {
    canon: 'protestant-66',
    versification: 'standard-kjv',
    requestedTranslation: translation ?? null,
    translationAlignment: 'unverified',
    noticeJa:
      '章・節の検証はプロテスタント66巻の標準KJV区分に基づきます。JCBなど各訳との節番号・本文の対応は未検証です。引用資料は表示された出典の訳に従います。',
  };
}

/** Provider prompt caching is distinct from application answer caching and is not observable here. */
function providerCacheReport(modelInvoked: boolean): ProviderPromptCacheReport {
  return {
    status: modelInvoked ? 'unknown' : 'not-applicable',
    basis: modelInvoked ? 'not-reported-by-verified-provider-schema' : 'model-not-invoked',
    cachedInputTokens: null,
  };
}

/** Cost planning is conservative and explicitly non-measured. Never interpret bytes as actual tokens. */
export function estimateUsage(messages: unknown, maxOutputTokens: number): UsageReport {
  return {
    actual: null,
    reasoningTokens: null,
    estimated: {
      inputTokens: new TextEncoder().encode(JSON.stringify(messages)).byteLength,
      maxOutputTokens,
      method: 'utf8-byte-upper-bound',
    },
    neurons: null,
    costUsd: null,
  };
}
export function prepareCompanionRequest(
  input: AnswerInput,
  dependencies: Pick<AnswerDependencies, 'authorization' | 'answerMode'>,
) {
  validateAnswerInput(input);
  const mode = dependencies.answerMode ?? 'reviewed-claim-selection';
  if (!['reviewed-claim-selection', 'grounded-generation'].includes(mode))
    throw new HarnessError('INVALID_INPUT');
  const model = getModel(input.modelId ?? DEFAULT_MODEL_ID);
  const settings = validateSettings(model.id, input.settings);
  const retrieval = retrieveGrounding(input, dependencies.authorization?.ownerId);
  const history = scopedHistory(input, retrieval.sources, dependencies.authorization.ownerId);
  const messages = buildMessages(input, retrieval.sources, mode, history);
  const usage = estimateUsage(messages, settings.maxOutputTokens);
  validatePreparedInputCapacity(model.id, usage.estimated.inputTokens, settings.maxOutputTokens);
  return { model, settings, retrieval, messages, usage, mode, history };
}
export async function createCompanionAnswer(
  input: AnswerInput,
  dependencies: AnswerDependencies,
): Promise<AnswerResult> {
  // Freeze the effective request by value before the first asynchronous boundary.
  let snapshot: AnswerInput;
  try {
    snapshot = structuredClone(input);
  } catch {
    throw new HarnessError('INVALID_INPUT');
  }
  const now = dependencies.now ?? (() => performance.now());
  const started = now();
  const prepared = prepareCompanionRequest(snapshot, dependencies);
  assertModelAuthorized(prepared.model.id, dependencies.authorization);
  if (dependencies.signal?.aborted) throw new HarnessError('ABORTED');
  const { model, settings, retrieval, messages, mode, usage } = prepared;
  const usable =
    mode === 'grounded-generation'
      ? retrieval.sources.length > 0
      : eligibleClaims(retrieval.sources).length > 0;
  const common = {
    referenceSystem: referenceSystemNotice(snapshot.translation),
    provider: 'cloudflare-workers-ai' as const,
    modelId: model.id,
    modelVersion: model.modelVersion,
    providerReportedModelVersion: null,
    promptVersion: PROMPT_VERSION,
    registryVersion: REGISTRY_VERSION,
    mode,
    cacheScope: 'private' as const,
    requestedSettings: settings.requested,
    effectiveSettings: settings.effective,
    validation: {
      citations: 'validated' as const,
      semanticGrounding:
        mode === 'grounded-generation' ? ('unverified' as const) : ('reviewed-source' as const),
      spoilerProtection:
        mode === 'grounded-generation'
          ? ('retrieval-and-reference-checks' as const)
          : ('reviewed-source-boundary' as const),
    },
    warnings: [
      ...((snapshot.history?.length ?? 0) > prepared.history.length
        ? ['UNSAFE_OR_OVERSIZED_HISTORY_OMITTED']
        : []),
      ...(mode === 'grounded-generation'
        ? ['GENERATED_PROSE_ENTAILMENT_NOT_PROVEN', 'PRETRAINED_SPOILERS_NOT_FULLY_DETECTABLE']
        : []),
      ...(retrieval.excluded.contextLimit ? ['SOURCE_CONTEXT_TRUNCATED_BY_ITEM'] : []),
    ],
  };
  if (!usable) {
    const durationMs = Math.max(0, now() - started);
    return {
      ...common,
      ...insufficientAnswer(retrieval.excluded.boundary > 0),
      modelInvoked: false,
      providerPromptCache: providerCacheReport(false),
      usage,
      timing: {
        durationMs,
        providerFirstTextMs: null,
        visibleAnswerMs: durationMs,
        validatedReadyMs: durationMs,
        clientVisibleMs: null,
        measurementScope: 'server-harness',
        streamed: false,
      },
    };
  }
  if (!dependencies.ai) throw new HarnessError('MODEL_UNCONNECTED');
  const provider = await invokeWorkersAi({
    ai: dependencies.ai,
    modelId: model.id,
    inputs: { messages, ...settings.effective },
    timeoutMs: settings.timeoutMs,
    signal: dependencies.signal,
    now,
  });
  if (dependencies.signal?.aborted) throw new HarnessError('ABORTED', true);
  const validated =
    mode === 'grounded-generation'
      ? validateGeneratedAnswer(
          provider.text,
          retrieval.sources,
          snapshot.readingBoundary ?? snapshot.passage,
          snapshot.spoilerAllowed,
        )
      : validateSelection(provider.text, retrieval.sources);
  const durationMs = Math.max(0, now() - started);
  return {
    ...common,
    ...validated,
    modelInvoked: true,
    providerPromptCache: providerCacheReport(true),
    usage: { ...usage, actual: provider.usage },
    timing: {
      durationMs,
      providerFirstTextMs: provider.firstTextMs,
      visibleAnswerMs: durationMs,
      validatedReadyMs: durationMs,
      clientVisibleMs: null,
      measurementScope: 'server-harness',
      streamed: provider.streamed,
    },
  };
}
/** Explicit non-AI fallback. Displays curated claims or literal verified-provenance text overlapping the target. */
export function createSourceOnlyAnswer(input: AnswerInput, ownerId: string): AnswerResult {
  const started = performance.now();
  const prepared = prepareCompanionRequest(input, {
    authorization: { ownerId, connectedModelIds: [] },
  });
  const sources = prepared.retrieval.sources.filter(
    (source) =>
      source.book === input.passage.book &&
      (source.end.chapter > input.passage.start.chapter ||
        (source.end.chapter === input.passage.start.chapter &&
          source.end.verse >= input.passage.start.verse)) &&
      (source.start.chapter < input.passage.end.chapter ||
        (source.start.chapter === input.passage.end.chapter &&
          source.start.verse <= input.passage.end.verse)),
  );
  const keys = eligibleClaims(sources)
    .slice(0, 3)
    .map((claim) => claim.key);
  const literalSources = keys.length
    ? []
    : sources
        .filter(isTrustedPrimaryTextSource)
        .sort((a, b) => comparePosition(a.start, b.start))
        .slice(0, 3);
  const answer = keys.length
    ? validateSelection(JSON.stringify({ status: 'answer', claimKeys: keys }), sources)
    : literalSources.length
      ? {
          status: 'answered' as const,
          claims: [],
          citations: literalSources.map(citationForSource),
          answer: literalSources
            .map(
              (source) =>
                `${source.book} ${source.start.chapter}:${source.start.verse}\n${source.text}`,
            )
            .join('\n\n'),
        }
      : insufficientAnswer(prepared.retrieval.excluded.boundary > 0);
  const durationMs = Math.max(0, performance.now() - started);
  return {
    ...answer,
    referenceSystem: referenceSystemNotice(input.translation),
    answer: `AIによる回答ではありません。${keys.length ? '選択箇所の確認済み資料を表示します。\n' : literalSources.length ? '出典の原文抜粋（英語・WEB）を表示します。日本語の解説やJCB本文ではありません。\n' : '\n'}${answer.answer}`,
    provider: 'cloudflare-workers-ai',
    modelId: prepared.model.id,
    modelInvoked: false,
    modelVersion: prepared.model.modelVersion,
    providerReportedModelVersion: null,
    providerPromptCache: providerCacheReport(false),
    promptVersion: PROMPT_VERSION,
    registryVersion: REGISTRY_VERSION,
    mode: 'source-only',
    validation: {
      citations: 'validated',
      semanticGrounding: literalSources.length ? 'literal-source-excerpt' : 'reviewed-source',
      spoilerProtection: literalSources.length
        ? 'primary-text-reference-boundary'
        : 'reviewed-source-boundary',
    },
    cacheScope: 'private',
    requestedSettings: prepared.settings.requested,
    effectiveSettings: {},
    usage: {
      ...prepared.usage,
      estimated: { ...prepared.usage.estimated, inputTokens: 0, maxOutputTokens: 0 },
    },
    timing: {
      durationMs,
      providerFirstTextMs: null,
      visibleAnswerMs: durationMs,
      validatedReadyMs: durationMs,
      clientVisibleMs: null,
      measurementScope: 'server-harness',
      streamed: false,
    },
    warnings: [
      'SOURCE_ONLY_NO_AI_ANSWER',
      ...(literalSources.length
        ? ['LITERAL_PRIMARY_TEXT_NOT_EDITORIAL_REVIEW', 'TRANSLATION_ALIGNMENT_UNVERIFIED']
        : []),
    ],
  };
}
function canonical(value: unknown): string {
  if (value === null || typeof value !== 'object') return JSON.stringify(value) ?? 'null';
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  return `{${Object.entries(value as Record<string, unknown>)
    .filter(([, v]) => v !== undefined)
    .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
    .map(([k, v]) => `${JSON.stringify(k)}:${canonical(v)}`)
    .join(',')}}`;
}
/** No public-chat cache API exists. Owner, question, exact sources, policy and versions are part of the key. */
export async function createPrivateCacheKey(
  input: AnswerInput,
  dependencies: Pick<AnswerDependencies, 'authorization' | 'answerMode'>,
): Promise<string> {
  const prepared = prepareCompanionRequest(input, dependencies);
  const identity = {
    ownerId: dependencies.authorization.ownerId,
    question: input.question,
    passage: input.passage,
    readingBoundary: input.readingBoundary ?? input.passage,
    spoilerAllowed: input.spoilerAllowed,
    translation: input.translation ?? null,
    language: 'ja',
    provider: 'cloudflare-workers-ai',
    modelId: prepared.model.id,
    modelVersion: prepared.model.modelVersion,
    registryVersion: REGISTRY_VERSION,
    promptVersion: PROMPT_VERSION,
    mode: prepared.mode,
    settings: { ...prepared.settings.effective, timeoutMs: prepared.settings.timeoutMs },
    sources: prepared.retrieval.sources,
    history: prepared.history,
  };
  const digest = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(canonical(identity)),
  );
  return `private:${[...new Uint8Array(digest)].map((x) => x.toString(16).padStart(2, '0')).join('')}`;
}
