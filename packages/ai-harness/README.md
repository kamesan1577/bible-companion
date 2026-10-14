# Bible Companion AI harness

Server-only TypeScript harness for Cloudflare Workers AI. No OpenAI API integration, API keys, arbitrary endpoints, or network inference are configured here.

## Current status

- **22 registered candidates:** 15 free-allocation candidates and 7 paid-method-required candidates from specification §10a. Every candidate starts **unconnected**. Published metadata is not a connection test.
- Official model IDs, documented parameters, context windows and pricing were checked on **2026-10-13**. `docs/catalog-evidence.json` and `docs/pricing-evidence.json` retain links and document fingerprints, not credentials.
- **No real model quality, TTFT, latency, consumption, or “Luna-equivalent” result has been measured.** Offline fixtures are deliberately scripted.
- All real budget bounds currently fail closed. Token/hidden-reasoning cost limits need genuine provider/account evidence. A price table and a safety multiplier are not proof of a hard spending cap.

## Run locally

From repository root (Node 24; npm dependencies installed by the backend workspace):

```sh
npm run typecheck
npx vitest run packages/ai-harness/test
node --experimental-strip-types packages/ai-harness/eval/cli.ts --offline
node --experimental-strip-types packages/ai-harness/eval/cli.ts --offline --mode=reviewed-claim-selection
node --experimental-strip-types packages/ai-harness/eval/cli.ts --plan --models=@cf/google/gemma-4-26b-a4b-it,@cf/meta/llama-3.2-1b-instruct --questions=10 --repetitions=2
node --experimental-strip-types packages/ai-harness/scripts/check-catalog.ts
```

The first four commands make no inference/network requests. `--plan` describes future work only. `--live` is intentionally rejected: authorized connected inference belongs behind backend authentication, data-sharing consent and atomic budget reservation. The optional catalog checker `--remote` reads only official public documentation; it never marks a model connected or edits the registry.

## Integration contract

```ts
import { createCompanionAnswer, createSourceOnlyAnswer } from '@bible/ai-harness';

const result = await createCompanionAnswer(
  {
    passage: { book: 'ACT', start: { chapter: 18, verse: 17 }, end: { chapter: 18, verse: 17 } },
    question: 'ソステネは誰？',
    spoilerAllowed: false,
    sources: serverOwnedReviewedSources,
    modelId: '@cf/google/gemma-4-26b-a4b-it',
    settings: { maxOutputTokens: 512, temperature: 0.2, timeoutMs: 15000, stream: false },
  },
  {
    ai: env.AI,
    authorization: {
      ownerId: authenticatedUser.id,
      connectedModelIds: verifiedConnectionIds,
      termsReviewedModelIds: serverReviewedTermsIds,
      termsReviewVersion: serverTermsReviewVersion,
    },
    signal: request.signal,
    answerMode: 'reviewed-claim-selection',
  },
);
```

`authorization`, `answerMode`, source review/rights flags, approved claims and scoped history are **trusted backend state**, not client JSON. The harness is not an authentication system. Backend responsibilities: authenticate, verify owner-only developer actions, load only this conversation/user's records, obtain applicable consent, reserve budgets atomically, enforce rate/idempotency limits, and persist private answers. Do not let HTTP callers construct dependencies.

`createSourceOnlyAnswer(input, ownerId)` is a separate explicit fallback. It displays overlapping curated material or explicitly labelled literal English primary-text excerpts, does not interpret the question using AI, includes a Japanese “This is not an AI answer” notice, and returns `mode:'source-only'`, `modelInvoked:false`. A successful fallback is not an AI connection or model evaluation.

## Two answer modes and their limits

### Reviewed-claim selection: strict baseline

Retrieval removes wrong-owner, unreviewed/unverified, unauthorized, cross-book and beyond-boundary source material **before** prompting. The model chooses up to three temporary claim IDs. Only server-reviewed text and verified citation metadata are rendered. Arbitrary prose, unknown IDs, extra JSON fields and invented citations are rejected. Later source chunks are excluded whole, including titles and all claims.

This containment is useful for limited curated coverage, not a claim that arbitrary Bible questions are solved. It can return insufficient evidence or irrelevant-but-in-scope selections; relevance still requires a real evaluation. The safety boundary relies on truthful trusted curation: `spoilerEnd` must cover all events in the source/title/claims, and approved claims must accurately reflect their cited material. `reviewed:true` must never be copied from an import request.

### Grounded generation: implemented experimental pipeline

`answerMode:'grounded-generation'` lets a connected model compose short new Japanese fact/inference/faith claims from eligible sources. Every claim must have a valid source ID and an exact supporting quote. Faith claims require attribution. Explicit out-of-bound references, extra answer fields, ungrounded links, tool calls, malformed/truncated output and uncited claims are rejected. Only complete validated structured results are returned.

**An exact quote does not prove the claim follows from it.** A model can attach a genuine quote to a false claim, or leak a later event without mentioning a verse number. The tests intentionally expose this limitation. This mode returns `semanticGrounding:'unverified'` and explicit warning codes; it is not accessible through ordinary client JSON in the initial backend. Retrieval filtering and prompt instructions cannot perfectly block pretrained spoilers. Before production adoption, evaluate entailment, relevance and spoiler leakage with independent human review and decide the product tradeoff. Do not describe this mode as spoiler-proof or the baseline as complete Bible chat.

## Context and continuity

- Canonical chapter/verse existence uses the shared 66-book metadata under `packages/core`; source-specific versification beyond that canon is not implemented.
- `passage` is the selected target. Optional `readingBoundary` is the already available reading range and must contain the target in the same book. Retrieval and history use its end; source-only excerpts stay on the target. Omission defaults to the target boundary. Both scopes are cache-keyed separately.
- Only source text, source IDs, display metadata and bounded scoped history enter the provider payload. Owner IDs, credentials, backend settings and other users' content do not.
- Source strings, imported text, user questions and prior replies remain **untrusted data** inside one JSON user payload. They cannot create system messages or tools.
- `HistoryTurn` requires server-owned `ownerId` and scope metadata. Same-owner/book/boundary turns can be reused; store the actual available `scope.readingBoundary` on every new turn, independently of target `scope.passage`; old spoiler-enabled assistant turns are excluded when spoilers are off. Assistant source IDs **and versions** must match current retrieval. Untagged legacy history is omitted. Retain at most six eligible turns and 4,000 characters; omit oversized turns whole.
- Treat each `(source ID, version)` as immutable. Corrections and permission/content changes require a new version. A SQL row edit without version advancement can invalidate provenance guarantees.
- Source limits and UTF-8 byte upper estimates protect context size. These are conservative estimates, not model tokenization or a billing measurement.

## Registry and provider behavior

`listModels()` reports billing class separately from connection state, plus schema and verification links. Gemma 4/GLM Flash/newer schemas use `max_completion_tokens`; Qwen3 and legacy schemas use `max_tokens`. Only documented parameters are sent. Unknown IDs/providers, client URLs, extra settings, nonfinite values and unsupported reasoning controls are rejected. Reasoning parameters are omitted, not falsely labeled “off.” Context length is vendor-reported and not live-validated.

This implementation uses **Workers bindings only**. It does not route every model through Responses API. Cloudflare's Responses route is GPT-OSS-only and nonstreaming; if a future adapter uses it, provider TTFT must remain “not applicable.” Official references:

- https://developers.cloudflare.com/workers-ai/configuration/bindings/
- https://developers.cloudflare.com/workers-ai/configuration/open-ai-compatibility/
- https://developers.cloudflare.com/workers-ai/models/

Provider parsing supports legacy `response` and chat `choices.message.content`, plus fragmented UTF-8 SSE `response` and `choices.delta.content`. Tool calls, internal reasoning, unsafe extra output and provider error details are never displayed or persisted by this package. Streams are held privately until structural validation succeeds. `providerFirstTextMs` measures the first textual protocol payload, **not** the first user-visible answer; `validatedReadyMs` measures server completion after validation (`visibleAnswerMs` is a compatibility alias). `measurementScope` is `server-harness`; `clientVisibleMs` is always null because this package cannot measure mobile display or network delay. Nonstreaming TTFT is `null`.

Cancellation stops local waiting and cancels stream readers, including streams returned late. **Workers binding cancellation does not prove upstream inference/billing stopped.** No undocumented AbortSignal is passed to `AI.run`. Deadline/abort/provider failures after dispatch report `usageUnknown:true`; backend accounting must retain the reservation until reconciled. There are no automatic provider retries that could duplicate charges. Empty/chunk/byte limits also bound synchronous stream parsing. Deployed Workers clocks only advance after I/O, so reported server timings are not CPU-time measurements and may legitimately be zero for source-only local work. Local Node timing behavior differs. See https://developers.cloudflare.com/workers/runtime-apis/performance/ .

## Usage, budget and cache accounting

`usage.actual` is populated only from valid provider-returned token counters. Missing/invalid counters remain `null`. Actual neurons and actual USD remain `null`; model rates do not turn token counts into a provider bill. Published uncached neuron rates are available through `getModelPricing` / `estimateModelBudget`. The estimate includes a pricing version, approximate USD equivalent, `billingMeasured:false`, and `budgetBoundVerified:false` / `eligible:false` until genuine bound evidence exists. Never enable a provider by treating an estimated daily allowance as guaranteed free spend.

`requireVerifiedBudgetReservation` requires matching, unexpired server-owned budget evidence including hidden-reasoning coverage; no such real evidence is bundled. `settleEstimatedReservation` retains reservations when consumption is unknown and flags overruns instead of masking them. Billing and free allocation are account-wide; backend coordination must also account for other callers and UTC-day changes.

`createPrivateCacheKey` hashes owner, exact question, eligible scoped history, model/version, registry/prompt version, effective settings, translation/language, passage/boundary, mode and exact current sources. All personal questions and answers are private. There is no shared-chat-cache API. Logs should contain request IDs, error codes, aggregate counts and timing only, never raw questions, prayers, context, model prose or hidden reasoning.

## Sources and evaluation evidence

`fixtures/acts-sources.ts` holds small public-domain **English** WEB excerpts, inspected against eBible primary text, with original Japanese commentary. These are not JCB text and are not a replacement licensed Japanese Bible corpus. Rights notice: https://ebible.org/engwebp/copyright.htm . References: https://ebible.org/engwebp/ACT16.htm , https://ebible.org/engwebp/ACT17.htm , https://ebible.org/engwebp/ACT18.htm . Broad theological/geographical/art coverage and expert editorial review remain outstanding.

`fixtures/questions.ts` contains 12 real Japanese questions, including the specification's ten, each with required points, forbidden assertions and reference scope. It includes intentional insufficient-evidence and spoiler-boundary cases. The scripted provider uses authored expected outputs and cannot demonstrate model intelligence or Japanese fluency. `docs/offline-contract-report.json` is a deterministic plumbing report only. `docs/live-evaluation-plan.json` is **unexecuted**. Its rate-derived costs are estimates, and `executionEligible:false` prevents confusing a plan with permission or a proven spending bound.

For a future authorized live evaluation: select at most two models, approve the exact question count and budget first, run sequentially, alternate model order between repetitions, support cancellation, separate warm/cold cache samples, record actual provider counters when present, and grade all answers manually against the rubric. Preserve private results only for the owner; do not publish personal questions.

### Model terms and reference-system notices

Published price/schema metadata does not establish permission to use a model. The registry exposes
`termsReview` separately: all models start unreviewed. `modelTermsUrl` is a link explicitly published
on the official model page; `null` means no link was found there, not that terms are absent. These
links are discovery evidence, not legal conclusions, acceptance, or verified license compatibility.
Cloudflare service terms must also be considered. Before a real invocation, server-owned
`termsReviewedModelIds` and `termsReviewVersion` must match `MODEL_TERMS_POLICY_VERSION`. No HTTP
client can supply those approvals. Connection, paid approval and verified budgeting remain separate
gates. Review records must be invalidated when model/catalog/terms policy changes; upstream weights
and terms are not pinned or automatically monitored by this package. Reading, planning and explicitly
labelled source-only responses do not require model-use approval because they invoke no model.
The offline fixture helper synthesizes these fields only for scripted tests; it performs no actual
connection, review, legal acceptance or spending authorization.

Each answer now includes `referenceSystem`: a 66-book Protestant / standard KJV structural baseline,
the requested translation if supplied, and `translationAlignment: unverified`. Its Japanese notice
should be visible beside references. JCB-specific numbering and textual alignment have not been
validated. This does not assert that a specific JCB verse differs; it avoids implying that structural
validation proves translation equivalence. Bundled English scripture is WEB, and Japanese commentary
is original commentary, not a JCB quotation or translation.

Provider prompt-cache attribution is explicit on every answer: `unknown` after model invocation,
with basis `not-reported-by-verified-provider-schema`, and `not-applicable` when no model was invoked.
Cached-input tokens and separate reasoning-token usage remain `null`; they are not fabricated zeros
and no cache discount is inferred. This is separate from the backend's application-answer cache
status. `modelVersion: provider-managed-unpinned` and `providerReportedModelVersion: null` distinguish
an exact routing ID from an unavailable immutable provider revision. Neither a registry version nor
a cached answer establishes that upstream weights were pinned.


### Trusted primary scripture is not editorial review

The optional `verification` object is a server-ingestion marker for public-domain English WEB
primary text. These records remain `reviewed:false`, `claims:[]`, public, single-verse scripture.
`isTrustedPrimaryTextSource` requires structurally valid metadata and an exact pinned
`TRUSTED_PRIMARY_TEXT_MANIFESTS` match (corpus ID, edition, manifest hash, source version, language,
reference system). Unsupported/unverified alignment stays ineligible. A primary marker cannot be
attached to private content, commentary, multi-verse chunks or invented reviewed claims.

This is **manifest identity validation, not per-verse content authentication inside the harness**.
The backend must verify the official artifact digest at ingestion, seal immutable verse rows,
require an approved ready corpus revision, and reject row changes or mismatched source versions.
No client/import request may confer this trust by supplying a hash or boolean. The exported
`isTrustedPrimaryCorpus` is a metadata-only check, suitable for a list/history precondition, not
permission to render arbitrary text without the source validation and backend row-integrity gates.

`referenceAlignment: canonical-compatible` means the literal stored coordinates pass the current
structural bounds. It does not mean verified semantic alignment to KJV or JCB. Imported coordinates
are never silently shifted to fill missing or relocated verses. Empty/footnote-only and unsupported
verses must remain unavailable, with corpus coverage limitations surfaced by the backend.

Source-only fallback prefers available curated claims; otherwise it displays up to three literal
verse excerpts in canonical order, labelled English WEB rather than Japanese explanation/JCB.
It returns no invented claims and marks `semanticGrounding: literal-source-excerpt` and
`spoilerProtection: primary-text-reference-boundary`. Citations preserve the primary provenance.
Reviewed-claim selection cannot answer from raw primary text alone. Experimental grounded generation
can use eligible primary text, but still reports semantic grounding unverified and requires separate
real-model/human evaluation before adoption. Additional corpus coverage is not broader proven AI quality.

### Reviewed card summaries

Approved original Japanese card summaries may enter grounding as `commentary`, with
`original-commentary` rights and version-bound `materialProvenance`. Citations retain
all 1–10 underlying references, publishers, license/attribution fields and optional
check dates. The provider receives only compact material identity and the main URL.
The exact quote validates correspondence to the approved summary; it does not independently
verify the external references or prove semantic entailment. Artwork reading advice can
be labeled `inference`; the renderer preserves that label. These summaries undergo the
same retrieval-first spoiler boundary and rights checks as other sources. Server-owned
material approval, immutable version identity and revocation remain backend obligations.

`validatePreparedInputCapacity(modelId, inputTokens, maxOutputTokens)` centralizes
context admission with 1024-token headroom. Its returned ceiling is an application
admission rule; it is not a verified tokenizer, hidden-reasoning or billing bound.
