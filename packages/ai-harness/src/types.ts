/** Server-only contract. Never accept authorization or reviewed sources from client JSON. */
export interface VersePosition {
  chapter: number;
  verse: number;
}
export interface Passage {
  book: string;
  start: VersePosition;
  end: VersePosition;
}
export type ClaimKind = 'fact' | 'inference' | 'faith';
export interface GroundedClaim {
  id: string;
  /** Reviewed display text, not text produced by the model. */
  text: string;
  kind: ClaimKind;
  /** Exact short excerpt in the parent source; required even for interpretations. */
  evidenceQuote: string;
  /** Explicit attribution is required for faith interpretations. */
  tradition?: string;
}
export interface PrimaryTextVerification {
  kind: 'trusted-primary-text';
  corpusId: string;
  edition: string;
  language: 'en';
  manifestSha256: string;
  referenceSystem: 'web-protestant';
  /** Structural coordinates only; never equivalence to JCB or another translation. */
  referenceAlignment: 'canonical-compatible' | 'unverified' | 'unsupported';
}
export interface MaterialSourceReference {
  id: string;
  title: string;
  url: string;
  publisher: string;
  license: 'public-domain' | 'original-commentary' | 'citation-only' | 'cc-by-3.0' | 'odbl-1.0';
  licenseUrl?: string;
  attribution?: string;
  checkedAt?: string;
}
export interface MaterialSummaryProvenance {
  kind: 'reviewed-material-summary';
  materialId: string;
  materialVersion: string;
  materialKind: 'person' | 'place' | 'artwork';
  references: MaterialSourceReference[];
}
export interface GroundingSource extends Passage {
  /** Original reviewed card summary, not copied external article text or scripture. */
  materialProvenance?: MaterialSummaryProvenance;
  /** Trusted ingestion provenance. Primary text remains reviewed:false and contains no curated claims. */
  verification?: PrimaryTextVerification;
  id: string;
  kind: 'scripture' | 'commentary';
  title: string;
  text: string;
  url?: string;
  version: string;
  license: 'public-domain' | 'licensed' | 'user-provided' | 'original-commentary';
  generationAllowed: boolean;
  visibility: 'public' | 'private';
  ownerId?: string;
  /** Set only by the trusted ingestion/curation service, never by an import client. */
  reviewed: boolean;
  /** Entire source (including title, claims, interpretation) has no events after this point. */
  spoilerEnd: VersePosition;
  claims: GroundedClaim[];
}
export interface ModelSettings {
  maxOutputTokens?: number;
  temperature?: number;
  timeoutMs?: number;
  stream?: boolean;
  /** Explicit setting requests unsupported by the selected schema are rejected. */
  reasoning?: 'off' | 'low' | 'medium' | 'high';
}
export interface HistoryTurn {
  role: 'user' | 'assistant';
  content: string;
  /** Filled from authenticated database state, never client-supplied context. */
  ownerId?: string;
  scope?: {
    passage: Passage;
    readingBoundary?: Passage;
    spoilerAllowed: boolean;
    sourceIds: string[];
    sourceVersions?: Record<string, string>;
  };
}
export interface AnswerInput {
  passage: Passage;
  /** Already available reading range; defaults to target passage and must contain it. */
  readingBoundary?: Passage;
  question: string;
  spoilerAllowed: boolean;
  sources: GroundingSource[];
  history?: HistoryTurn[];
  modelId?: string;
  settings?: ModelSettings;
  translation?: string;
  language?: 'ja';
}
export interface ModelAuthorization {
  ownerId: string;
  /** Server-controlled per-owner IDs that have passed a real connection check. */
  connectedModelIds: readonly string[];
  /** Connection alone never enables paid candidates. Requires explicit budget approval. */
  paidModelIds?: readonly string[];
  /** Server-owned review records only. These fields never authorize accepting legal terms. */
  termsReviewedModelIds?: readonly string[];
  /** Must match MODEL_TERMS_POLICY_VERSION; invalidate when model/catalog/terms change. */
  termsReviewVersion?: string;
}
export interface WorkersAiBinding {
  run(modelId: string, inputs: Record<string, unknown>): Promise<unknown>;
}
export interface AnswerDependencies {
  ai?: WorkersAiBinding;
  signal?: AbortSignal;
  authorization: ModelAuthorization;
  /** For deterministic fixture timing only; absent uses performance.now(). */
  now?: () => number;
  /** Server policy only. Generated prose is experimental and not spoiler-proof. */
  answerMode?: 'reviewed-claim-selection' | 'grounded-generation';
}
export interface Citation {
  sourceKind: GroundingSource['kind'];
  materialProvenance?: MaterialSummaryProvenance;
  sourceId: string;
  title: string;
  url?: string;
  passage: Passage;
  version: string;
  license: GroundingSource['license'];
  verification?: PrimaryTextVerification;
}
export interface AnswerClaim {
  id: string;
  text: string;
  kind: ClaimKind;
  evidenceQuote: string;
  sourceId: string;
  tradition?: string;
}
export interface ProviderPromptCacheReport {
  status: 'unknown' | 'not-applicable';
  basis: 'not-reported-by-verified-provider-schema' | 'model-not-invoked';
  /** Unknown cached input count is never zero. No cache discounts are inferred. */
  cachedInputTokens: null;
}
export interface UsageReport {
  /** No verified separate reasoning-token counter is available in the current binding schemas. */
  reasoningTokens: null;
  actual: { inputTokens: number; outputTokens: number; totalTokens?: number } | null;
  estimated: { inputTokens: number; maxOutputTokens: number; method: 'utf8-byte-upper-bound' };
  /** No conversion from tokens to neurons without model-specific verified rates. */
  neurons: null;
  costUsd: null;
}
export interface ReferenceSystemNotice {
  canon: 'protestant-66';
  versification: 'standard-kjv';
  requestedTranslation: string | null;
  translationAlignment: 'unverified';
  noticeJa: string;
}
export interface AnswerResult {
  referenceSystem: ReferenceSystemNotice;
  answer: string;
  claims: AnswerClaim[];
  citations: Citation[];
  status: 'answered' | 'insufficient-evidence' | 'spoiler-boundary';
  provider: 'cloudflare-workers-ai';
  modelId: string;
  modelInvoked: boolean;
  modelVersion: 'provider-managed-unpinned';
  providerReportedModelVersion: null;
  providerPromptCache: ProviderPromptCacheReport;
  promptVersion: string;
  registryVersion: string;
  mode: 'reviewed-claim-selection' | 'grounded-generation' | 'source-only';
  validation: {
    citations: 'validated';
    semanticGrounding: 'reviewed-source' | 'literal-source-excerpt' | 'unverified';
    spoilerProtection:
      | 'reviewed-source-boundary'
      | 'primary-text-reference-boundary'
      | 'retrieval-and-reference-checks';
  };
  /** Personal questions/history/results never enter a shared cache. */
  cacheScope: 'private';
  requestedSettings: ModelSettings;
  effectiveSettings: Record<string, unknown>;
  usage: UsageReport;
  timing: {
    durationMs: number;
    providerFirstTextMs: number | null;
    /** Server-side validated readiness, not a measurement of mobile display. */
    visibleAnswerMs: number;
    validatedReadyMs: number;
    clientVisibleMs: null;
    measurementScope: 'server-harness';
    streamed: boolean;
  };
  warnings: string[];
}
