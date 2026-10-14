# Independent product acceptance audit

Reviewed 2026-10-13 19:34 UTC against the original HTML specification v1.1, README, acceptance map and actual TypeScript/Swift source. Baseline HEAD was `bb6c95c`; the working tree was actively changing. This is a product-path audit, not another unit-test total or a device acceptance result.

## Decision

**Not yet a usable end-to-end iPhone AI companion.** The honest local deliverable is substantial native/API source, conservative reference browsing, account-isolation and request-recovery machinery, and local verification. No Apple SDK build, device Share Extension/passkey round trip, genuine AI answer, deployment or private GitHub publication has been established. Those missing external checks are different from the implementation gaps below: some gaps remain even after credentials become available.

## Prioritized findings

### P1 — First live activation has no supported operator path

- Evidence: `scripts/config.mjs` accepts only `AI_ENABLED: false`, empty connected/terms model lists and the disconnected resource schema. `scripts/infra.mjs` provides only `invite-local`. `apps/api/src/budget.ts` requires a D1 proof record, with no operator installation workflow. `docs/OPERATIONS.md` acknowledges this.
- Reproduction: start with an authorized Cloudflare account and a stable HTTPS domain; follow the documented CLI. There is no complete route to first production owner registration, reviewed model activation and first question without replacing policy code or writing SQL manually. `init-production-config` is a disconnected profile, not a ready AI deployment.
- Impact: missing credentials are not the only blocker. The handoff currently leaves an engineering bootstrap job for the user.
- Resolution requested from backend owner: explicit prepare/plan/validate and authorized operator execution, stable RP/domain, owner/member invitation, terms review and account/model gates. Default stays disconnected. No remote calls or new authorization were made in this review.
- Fixable without credentials: **yes, implement and test the workflow**. Genuine activation evidence remains external.

### P1 — “Verified budget proof” must not require impossible empirical certainty

- Evidence: `packages/ai-harness/src/budget.ts` requires `inputTokenUpperBound`, `outputTokenUpperBound`, `includesHiddenReasoning: true` and an evidence reference before any inference. Merely measuring a few calls does not prove a universal hidden-token bound.
- Impact: model calibration needs an explicitly authorized first call, but product inference requires prior proof. Treating a sampled maximum as a hard cap would be misleading; refusing every practical activation forever also misses the product.
- Practical resolution: separate an operator-verified Free-only account/provider cutoff from conservative application reservations. Bind the reviewed account/model/price/config identity and expiry; reject Paid plans, paid-only models and prepaid Gateway routing in this profile; never silently upgrade or retry across providers. Show estimates as estimates, including uncertain usage. If true contractual bounds exist, preserve their distinct evidence type.
- Official basis checked during audit: [Cloudflare pricing](https://developers.cloudflare.com/workers-ai/platform/pricing/) says Free includes 10,000 Neurons/day, exceeding free allocation requires upgrade, and further operations fail at the limit. It separately permits certain paid models via prepaid AI Gateway credits. This does **not** prove that the user's account is Free or provide a per-request token bound.
- Fixable without credentials: **yes, the policy and workflow**; actual account verification cannot be fabricated.

### P1 — Broad contextual AI is unreachable through the app/API

- Evidence: `apps/api/src/ai.ts` and `comparisons.ts` call `createCompanionAnswer` without `answerMode`. `packages/ai-harness/src/index.ts` defaults to `reviewed-claim-selection`; `prompts.ts` requires selection of at most three existing claim keys and explicitly forbids generated prose. Imported primary-text verses have `claims: []`. `grounded-generation` exists in the harness but is not selectable by either route.
- Reproduced locally with a trusted-manifest-shaped Genesis 1:1 source, synthetic test authorization and a mock provider: default mode returned `insufficient-evidence`, `modelInvoked: false`, and **zero provider calls**. No live provider or permission was used.
- Impact: importing all 66 books does not make them answerable. The reachable AI can select from nine prewritten Acts excerpts; it cannot create the general Japanese contextual explanation implied by the product. A model comparison would mostly compare claim selection, not Japanese explanatory writing.
- Resolution: explicitly expose a server-controlled, reviewed experimental generation mode if the intended product requires it, with mode included in execution identity, plans, results and UX. Keep structural grounding distinct from semantic truth/spoiler guarantees. Alternatively clearly scope the release to reviewed-claim selection and do not describe it as broad Bible Q&A.
- Fixable without credentials: **yes, mode wiring and tests**. Japanese quality, model usefulness and semantic review still require authorized real runs.

### P1 — Geography acceptance is unimplemented, not merely unverified

- Evidence: `ReadingView.swift` has a tab named 地図, but `MaterialCardView.swift` renders textual fields only. Three place cards intentionally have no verified coordinates; no plotted map, geographic layout or map renderer exists. `docs/acceptance-status.md` correctly discloses this.
- Reproduction: open Acts 18:18 and choose 地図. Available place descriptions cannot show where Cenchreae is relative to Corinth. The explicit spec evaluation “地理の説明と地図が一致” cannot pass.
- Scope: missing maps need a small reviewed, licensed geographic dataset and renderer, not broad new services. An unavailable state is safer than invented coordinates but is not map completion.
- Fixable without credentials: **partly**; source research and local implementation are possible. Device display and any network map service require separate verification. Do not auto-provision a paid map provider.

### P2 — Offline “history” currently means imported references, not saved conversations

- Evidence: `PrivateHistoryStore` persists account-scoped imported passage metadata. `ConversationHistoryModel` and `SavedComparisonModel` fetch bodies over the network and do not keep durable offline answer history. Offline grants in `reading.ts` allow only eligible reviewed public-domain overview/citations for 24 hours, not cards, artwork, corpus text or AI answers.
- Reproduction: read a conversation online, background/restart, go offline, open the conversation history. Imported references may remain available, but the saved conversation body cannot be reopened offline.
- Impact: the spec's saved-material/history offline path is narrower than its ordinary reading. This is an implementation tradeoff, not a tested completion of the full requirement.
- Native owner confirms this boundary and that full material/art offline expansion is deliberately deferred. Acceptance documentation should distinguish imported-reference history from conversation history. Do not expand offline rights/storage scope silently.
- Fixable without credentials: **documentation now; feature later within an agreed bounded offline policy**.

### P2 — Source-only question screen implies responsiveness that does not exist

- Evidence: `QuestionView.swift` requires nonempty question text even when `sourceOnly` defaults true; `createSourceOnlyAnswer` ignores the question for answer selection and renders the first three overlapping curated claims.
- Reproduced: “髪を切ったのはなぜ？” and “この場面を描いた絵はある？” at Acts 18:18 return identical hair/vow/geography summary text. The no-AI notice is honest, but a user who typed the art question has not received a response to that question.
- Resolution: make selected-range reference browsing clearly separate from question-responsive AI, or supply an explicit notice that the question does not change source-only results. Do not label a fixed excerpt as an answered question. Keep the user's draft when switching modes.
- Fixable without credentials: **yes, UX/contract clarification**. Sent to native owner.

### P2 — A privacy sentence can be read as “AI answers are never persisted”

- Evidence: `HistorySettings.swift` originally said “共有本文・資料原文・AI回答は永続保存しません” without specifying local-device storage. The API persists assistant answers in private messages/generation request results; saved comparisons also contain bodies.
- Impact: users can reasonably understand the setting as a service-wide retention promise, despite the intended device-only meaning.
- Resolution: explicitly say “端末には” for the local restriction, describe server-side private conversation storage separately, and retain the honest pending backup retention decision.
- Fixable without credentials: **yes**. Sent to native owner for correction; verify final text.

### P2 — Existing public cache does not avoid source retrieval, and latency instrumentation is incomplete

- Evidence: `reading.ts` loads sources and materials, checks policy and hashes their complete content before consulting `public_cache`. `AppStore.loadReading` does manifest request then reading request sequentially after local overview display. `QuestionView` displays server harness timing only; no client-visible completion measurement is established.
- Impact: a `public-hit` is not evidence of a fast CDN/native path and does not remove the main retrieval work. Cache-heavy/0.5-second/2-second goals remain unmeasured, as the acceptance map correctly says.
- Resolution: instrument end-user screen-ready and request-to-visible timings first. Consider revision/epoch-based public cache lookup that avoids repeated full payload retrieval while preserving rights revocation and private isolation. Do not trade correctness for speculative optimization.
- Fixable without credentials: **yes, instrumentation and local query/logic tests**. Real p50/p95 and free-worker CPU need deployment/device measurements.

## Other checked boundaries

- Source-only answers do filter target overlap after retrieval; I did not find evidence that arbitrary older Acts excerpts are presented as the selected-range overview.
- The shared JCB text is not sent as AI context: it is parsed transiently and the API uses canonical references plus WEB/reviewed sources. The native disclosure and translation-alignment notice are essential. A question about exact JCB wording remains unsupported unless that wording is included through an authorized path; full WEB corpus coverage is not JCB equivalence.
- Reviewed source chunks can span several verses. A single earlier verse may have no eligible Japanese claim because a chunk ends past the reading boundary. Splitting reviewed claims into smaller bounded pieces would improve pinpoint support without relaxing spoiler checks.
- One existing NGA artwork is genuinely episode-specific to Acts 9:3–7; empty art at Acts 18:18 is correct and preferable to substituting an unrelated painting. Device image loading is unverified.
- Invite-only registration still allows multiple isolated member accounts. It is a proposed rollout default, not a user-approved permanent closed-membership requirement.
- SwiftUI/Liquid Glass source and styling evidence do not establish Apple SDK compilation, actual light/dark appearance, VoiceOver, large type or SideStore viability.

## Smallest meaningful acceptance sequence after authorized setup

1. Bootstrap one owner and one member through the documented operator workflow; no manual code/SQL patching and no role claims from the client.
2. Install app and share extension using the intended signing route. Register/login/cancel and return to app on the actual iPhone.
3. Share actual JCB single verse, range and disjoint ranges, including offline/unlogged-in and repeated send. Confirm imported verses/translation and account association.
4. In a covered Acts passage, display a short reference and ask two related questions with a real selected model; distinguish generated vs selected-claim mode and verify history context.
5. In an uncovered book, verify the precise limitation or real grounded generation rather than claiming the corpus itself supplies explanations.
6. Open map/person/art tabs and test concrete useful content, including the correctly empty art case. Confirm provenance and boundary behavior.
7. Reopen imported references and a conversation offline; document exactly what remains available. Check failed-question recovery and account switching without data mixing.
8. Run two-model comparison with confirmed plan, cancellation and provider Free-only account gate. Record Japanese quality plus device-visible latency and actual/estimated usage separately.
9. Verify private GitHub visibility and exact pushed commit once existing authorization is available. No repository or deployment was created by this audit.

The checklist stops at unavailable authorization/device evidence. It does not turn missing acceptance into a unit-test success claim.

## Follow-up verification at 19:36 UTC

- Native owner corrected both copy findings. Independently re-read `QuestionView.swift`: source-only now explicitly says typed questions are saved but do not change the displayed selected-range materials. This closes the misleading-response wording issue; the feature remains fixed reference browsing.
- Independently re-read `HistorySettings.swift`: it now specifies no durable device storage for shared/source/AI bodies, separately states server question/answer/saved-comparison retention, and mentions unresolved provider-backup erasure. This closes the service-wide non-persistence implication.
- Operator activation and generation-mode changes are still owned by the backend team and were not yet present/reverified in this audit snapshot. The remaining findings above should be reconciled against their final patch, not counted as fixed solely from intent.

## Re-audit at 20:00 UTC: original P1 implementation closure and new integration findings

Backend confirmed a stable read-only checkpoint for this pass. Changes are in the working tree, not yet a final committed/released build. Independently ran:

- `node --test scripts/operator.test.mjs scripts/operator-security-review.test.mjs`: 43 passing, all injected process mocks/local files.
- `npm exec vitest run apps/api/test/answer-mode.test.ts apps/api/test/free-hard-stop-budget.test.ts apps/api/test/security-budget-modes.test.ts packages/core/test/geography-data.test.ts`: 25 passing across four files. These exercise API/SQLite/real pinned corpus bytes with **mock inference**, not live model quality.

### Original P1 findings now substantially addressed in source

1. **Operator bootstrap:** `scripts/operator.mjs` now implements pending templates, plan/validation/private exclusive config preparation, exact account/database/profile/action confirmation, existing-auth account and D1 identity checks, migration/deploy, receipt installation/revocation, first-owner/member invitations and separate private GitHub creation/push. It does not create credentials or accept agreements. This closes the original “no supported owner/model activation commands” implementation finding for the curated-data service. The corpus and maintenance omissions below prevent calling the overall production path complete.
2. **Budget proof practicality:** `budget.ts`, `budget-dispatch.ts` and migration 0020 add an explicit `free-provider-hard-stop` mode with an immutable account-bound receipt, maximum 24-hour validity and atomic expiry/revocation checking at dispatch. It reports `budgetBoundVerified:false` and separates conservative reservations from provider cutoff. There is no claim of continuous billing verification. This closes the mathematical-proof bootstrap deadlock in source. Real billing account status is still unverified, and renewal is a daily operator dependency requiring genuine fresh evidence and an updated profile/config, not automatic permanent approval.
3. **Generated answers reachable:** `answer-mode.ts`, API question/comparison routes, native policy/quality consent and frozen `PendingQuestion` mode now carry explicit reviewed-claim vs experimental generation. Independently reran the API test that installs the pinned Genesis primary-text fixture, sends a real API question and reaches a mock provider once; its result declares unverified semantic grounding. Also verified tests for stale/revoked consent, same-model/different-mode comparisons, and narrowed late-range retrieval. This closes the original unreachable-mode finding. It does not prove Japanese quality or semantic spoiler protection.
4. **Actual maps implemented in source:** `MaterialCardView` now links to `PlaceMapView`, which uses MapKit with an approximate marker, pan/zoom, 50 km initial camera, coordinate explanation, provenance and modern-basemap limitation. It rederives the card from current reading state rather than trusting a stale snapshot. `PlaceLocation` validates bounded coordinates, passage applicability and licensed attribution. Three reviewed Pleiades-derived representative points are present, with CC BY/OSM attribution. This closes the “no renderer/coordinates” implementation finding. No Apple SDK typecheck or tile rendering/device interaction was run; no full travel reconstruction or all-Bible geography is claimed.

### Remaining locally fixable integration gap A — production corpus activation absent

- `profileToConfig` always reads default `wrangler.jsonc` and adds the AI binding, but never adds `SCRIPTURE_ASSETS`.
- Operator profile schema has no optional corpus choice; action list has no corpus registration.
- `scripts/scripture-assets-config.mjs` supports only `plan`, `generate`, `register-local`, with remote operation explicitly rejected.
- The now-passing Genesis route test must manually `seedAssetCorpus` and attach `realAssetBinding`. That is test setup, not something the operator deployment currently does.
- Consequently the documented authorized prepare → migrate → receipt → deploy path remains a nine-excerpt deployment. The 66-book primary-text path still needs configuration/SQL engineering outside the supported operator workflow.
- Backend notified: integrate an **optional explicitly selected pinned corpus** build/binding and bounded immutable registration action, preserving no-overwrite/no-reapproval/source-rights protections; or clearly state the operator workflow deploys curated excerpts only. No new paid service is needed.

### Remaining locally fixable integration gap B — production maintenance never scheduled

- `apps/api/src/index.ts` contains the scheduled cleanup and stale-request/reservation settlement handler.
- Prepared operator config has no cron trigger, and profile/actions offer no maintenance setup or execution choice.
- The operations guide says to schedule cleanup at launch, but following the actual operator path never does. Auth/rate/export/cache rows keep accumulating and interrupted state is not cleaned by that handler.
- Backend notified: provide an explicit disclosed bounded schedule or authorized maintenance action and a test proving the prepared deployment activates it. Do not claim a handler's existence proves a scheduler is configured.

### Remaining locally fixable integration gap C — default comparison reservation cannot support 2×10

- Free mode reserves against `min(64000, model context ceiling)` input tokens for **every** trial, irrespective of actual short prepared input, then adds 25% margin. It is honestly called an estimate.
- Operator config inherits `DAILY_USER_BUDGET=2000`, `DAILY_APP_BUDGET=9000`; current profile schema cannot select reviewed budget values.
- Independently calculated at the normal 512 output setting: Granite (cheapest candidate) reserves 130/trial, making even two Granite modes × ten questions cost 2,600 reserved units; Llama 1B reserves 192 (3,840 total); default Gemma reserves 745 (14,900 total). Therefore **no** two-model ten-question plan can pass the default user budget, and many catalog models cannot pass even one trial. These are calculated reservations, not measured usage or bills.
- Backend notified: support explicit reviewed budget inputs and/or a consistent plan/dispatch request-specific conservative estimate. Never silently raise the allowed budget. Explain the predicted total before confirmation and test a realistically bounded two-model ten-question plan. Provider Free cutoff remains the monetary backstop; an estimate is still not a proven hidden-token bound.

### Unchanged launch boundary

No real credentials, terms acceptance, Free-account receipt, external inference, deployment, private GitHub publication or Apple SDK/device run occurred in this audit. The remaining broad offline-conversation-history and device-visible latency limitations above still stand. A finite set of real setup/device/model checks remains necessary after the locally fixable integration issues are addressed.

## Re-audit of checkpoint b6a407e at 20:34 UTC

Backend confirmed the checkpoint was committed with a clean working tree before this review. I inspected the operator sequence, actual config generation/registration/deployment guards, prepared comparison input calculation and the associated tests. Independently reran 49 operator/security tests and 23 focused API answer-mode/Free-budget/security tests; all passed. Remote process calls and AI responses remained mocked.

### The three residual integration holes are closed in implementation

- **Corpus:** an explicit `webp-pinned-assets` profile choice builds the pinned public files, adds `SCRIPTURE_ASSETS` and Worker-first routing, and exposes `register-corpus`. The practical order is prepare → authorized migrate → authorized register-corpus → receipt installation if AI is selected → authorized deploy → owner invitation/registration. Deploy checks exact approved metadata and upload contents. The real-SQLite operator test verifies deployment fails before registration, repeated matching registration stays one metadata row/zero verse rows, and revoked content cannot be reapproved or deployed. The service no longer requires ad hoc production SQL/config changes to use the corpus.
- **Maintenance:** `cleanup: daily-utc` generates the exact `17 3 * * *` cron, disclosed in the fingerprinted plan. `none` remains explicit and warns that maintenance is not configured. The intended initial daily-use profile should select the scheduled option before the deployment approval; merely preparing it creates no real schedule.
- **Comparisons:** explicit capped profile budgets are now supported. Per-trial reservation uses the prepared question/source bytes, mode and output setting, with the estimate inputs/amount included in execution identity; plan and dispatch recalculate the same context. This removes the unconditional 64k-input reservation for real plans. The 25% margin remains an estimate and is not promoted to a token/billing proof.

### Two small local follow-ups were returned to backend

1. **Make the 20-trial evidence match its wording.** The checked-in `security-budget-modes` test at this checkpoint sets `DAILY_USER_BUDGET='9000'`, despite the report that its 816-unit plan fits the normal 2000 allowance. It plans/starts 20 trials but dispatches only trial 0. The arithmetic can support “this plan estimate is below 2000”; it does not establish a completed 20-trial default-budget journey. Requested a test with actual 2000 allowance, all twenty sequential mock trials, terminal completion and replay without extra provider invocation. No live benchmarking is requested.
2. **Catalog readiness still uses the removed worst-case reservation.** `modelBudgetReadiness` calls `estimateModelReservation` with zero prepared input, selecting the 64k/context ceiling and rejecting the model if that exceeds the user allowance. The native catalog and preference route use this result, so some Free models remain unavailable for even a short question that would pass the actual prepared-input reservation. For example Qwen3.8's 64k/512 estimate exceeds 2000 while a 4096/512 estimate is far lower. Requested policy readiness separate from per-request capacity in Free-cutoff mode, or an explicit conservative-catalog limitation. Paid/terms/account/expiry gates must remain unchanged; exact budget checks must still occur at planning/dispatch.

### Initial daily-use limitations remain explicit

- The Free-account evidence expires within 24 hours. A fresh genuine review, new immutable receipt, updated prepared profile/config and authorized application remain an operator responsibility. This is practical for a staged evaluation but is not an unattended daily-use maintenance solution. No silent perpetual approval, fabricated billing evidence or automatic paid change should be introduced to hide the burden.
- Passkey recovery/additional credentials, actual signing/Share Extension behavior, Apple SDK build and runtime appearance remain external acceptance gaps. Losing the sole passkey is not solved by local database backup.
- Native offline imported-reference history is available; durable offline conversation/AI-answer bodies are not. Device-visible latency goals remain unmeasured.
- Broader history/culture coverage and real Japanese explanation quality still need human/model evaluation. A reachable grounded mode, WEB corpus and map renderer are implemented capabilities, not guarantees of semantic correctness.

No external account, service, credential or deployment was activated. The remaining local follow-ups are bounded consistency/evidence improvements; the prior corpus/cron/plan bootstrap blockers should no longer be presented as unimplemented.

### Final bounded follow-up verification at 20:37 UTC

Both follow-ups above are now fixed in the working tree and independently rechecked:

- Free-mode catalog readiness validates current account authority, model tier/settings and context capacity, marks `readinessScope: provider-policy-only` and `preparedRequestBudgetRequired: true`, and leaves actual reservation/remaining-allowance checks to the prepared question or comparison plan. Strict-proof mode is unchanged. The regression successfully selects a Free model whose former worst-case estimate exceeded the allowance, then verifies receipt revocation disables it. This closes the catalog usability inconsistency without claiming all selected questions will fit.
- The twenty-trial test now asserts the actual 2000 user allowance, executes all twenty sequential mocked provider calls against ten distinct pinned-asset passages, reaches `complete` with `completedCount:20` and no next trial, then replays trial zero with no twenty-first provider call. It verifies `reserved:0` and consumed estimated units equal the confirmed reservation. This establishes the local full-ledger journey, not live model quality or cost.
- Independently reran `free-hard-stop-budget.test.ts` and `security-budget-modes.test.ts`: 17 checks passed across both files.

No additional locally reproducible blocking defect was found in this bounded re-audit. Initial daily-use acceptance remains conditional on the explicit 24-hour receipt maintenance, credential/recovery decisions, real deployment/resource measurement and actual iPhone/model validation listed above. These are not silently converted into completion by the local results.
