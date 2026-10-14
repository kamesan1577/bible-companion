# Specification acceptance status

Checked against specification 1.1 on 2026-10-13. This is an implementation/evidence map, not a launch approval. The project has no deployed service, connected inference provider or signed iPhone build. A passing local test is not evidence that YouVersion, SideStore, browser passkeys or Cloudflare billing work on the intended device/account.

## Product and reading flow

| Confirmed capability | Current implementation and evidence | Remaining acceptance work |
| --- | --- | --- |
| Native iOS companion, reader/import/chat | SwiftUI app, Share Extension, explicit pending import queue and API client; `apps/ios/VERIFICATION.md` and independent source review | Apple SDK typecheck/build, signing, SideStore installation/update/expiry, physical Share Extension and ASWebAuthenticationSession |
| JCB/YouVersion single verse, range, several ranges and cross-chapter import | Canonical66-book parser, URL/text parsing and ambiguity confirmation; core/API tests, idempotent owner-scoped import; native fixture decoding | Actual current YouVersion payloads/device share behavior; translation-specific numbering alignment remains unverified |
| Read selected range and choose a narrower question target | Backend validates target inside one confirmed imported range, keeps independent readingBoundary; native arbitrary verse-subset editor with canonical validation | Device editor interaction remains unverified; disconnected imported ranges are chosen explicitly, not falsely merged |
| Resume private reading and conversation | Owner-scoped import list, conversation detail with bounded message pages; paginated conversation metadata and native saved-chat browsing/resume with scope/policy fencing | Verify history UX and pagination on device |
| Offline and expired-login import safety | Private queue/frozen request identity, account association confirmation, idempotent replay and cancellation tombstones; Foundation/API race tests | Real process termination, storage protection, device logout/login and low-connectivity behavior |
| Failed/slow question preserves input and allows explicit stop | Bounded harness timeout, native frozen request recovery, no automatic replacement UUID, private result lookup | Live provider cancellation is not guaranteed; actual latency and interruption behavior remain unmeasured |

## Evidence, spoilers and media

| Confirmed capability | Current implementation and evidence | Remaining acceptance work |
| --- | --- | --- |
| Short explanations with sources | Nine reviewed WEB excerpt sources, bounded approved original Japanese card-summary commentary with full citation attribution, plus pinned 66-book English primary text via bounded D1 or immutable Assets retrieval. Explicit experimental grounded-generation reaches non-Acts primary text in API integration tests; reviewed-claim selection remains available | The English corpus preserves measured source omissions/numbering differences and does not provide Japanese/JCB equivalence or broad commentary. Actual local D1 ingestion and zero-write replay pass; deployment remains pending. Source-only is explicitly non-AI |
| Facts, inference and faith interpretations separated | Structured claim kinds, exact evidence validation, traditions where supplied; harness grounding/adversarial tests | Human Japanese quality and faith-sensitive interpretation review with real models |
| Avoid information beyond confirmed reading | Retrieval, titles/claims, material applicability, history scope, citations and cached visibility share canonical boundary checks | Experimental generated prose can imply pretrained spoilers. Its semantic truth/spoiler safety is not proved by structural validation |
| People and relationships | Twelve episode-bounded person cards with primary verse provenance and uncertainty labels | Broad biography/relationship coverage and visual relationship browsing remain partial |
| Geography and maps | Three approximate Pleiades representative points with CC BY/OSM attribution, scoped place cards and native MapKit detail source | Device map rendering/network behavior remains unverified; points do not establish exact event sites or reconstruct journeys |
| Existing artwork matching the passage | One verified public-domain NGA Tintoretto work forActs9:3–7, exact provenance and bounded image loader | More passage-specific art is absent; no unrelated cover art or invented artwork is substituted. Device image rendering/rights refresh unverified |
| Licensed content and attribution | Public-domain WEB attribution, original commentary, source/card provenance docs, source version immutability, rights revocation filtering | JCB full-text redistribution/context retrieval permissions are unresolved; imported raw text is not a licensed corpus and is not persisted server-side |

## Authentication, privacy and recovery

| Confirmed capability | Current implementation and evidence | Remaining acceptance work |
| --- | --- | --- |
| Passkey login with native callback | SimpleWebAuthn actual signed ES256/CBOR tests, exact RP/origin/UV, one-use challenge/code, PKCES256 exchange, hashed sessions | Stable production HTTPS domain, real browser ceremony, free-signing/native callback, physical passkey registration/login/cancel/replay |
| Other readers can have separate accounts | Member/owner separation, owner-only developer routes and multi-account SQL/API isolation tests | Invite-only is the initial operational default, not a permanent product restriction. Open registration is design-only and requires abuse/storage/cost review |
| No model keys on the phone | Server Workers AI binding interface; native stores only its app session in Keychain source | No binding or provider authorization is configured; physical Keychain behavior remains untested |
| Delete private history/account | Explicit fresh-auth confirmation API, data epochs, cascading private rows, revoked sessions, cancellation and budget reconciliation tests | Native typed confirmation and fresh-auth deletion controls are implemented with uncertain-outcome cleanup; device behavior and backup retention/erasure policy remain unverified |
| Export private data | Snapshot-bound paginated API, explicit size limits, rights-safe projections; incremental protected native export/share source and tests | Actual share-sheet/temp-file lifecycle on iOS; export is not an account recovery or restore format |
| Lost passkey / device change | Failure states and release-gate documentation | Additional passkey management, verified account recovery and device migration are not implemented |
| Backup/restore | Isolated local D1 backup/restore is implemented and tested with schema/content verification and no-overwrite targets; no remote backup is configured | Production retention, encryption, recovery authority and provider restore drill require explicit operational decisions |

## AI model choice, comparison and cost

| Confirmed capability | Current implementation and evidence | Remaining acceptance work |
| --- | --- | --- |
| Owner-only22-model catalog with per-model settings | Exact allowlist, capability intersection, paid/connection/terms/budget readiness, native full catalog; unknown provider/ID/settings rejected | All live connections are unverified. Model terms metadata is not legal acceptance; all production review flags remain empty |
| Model switch affects new answers only | Server model preference, exact answer model identity, immutable historical answer metadata | Genuine provider output and Japanese response behavior across selected candidates |
| At most2 models ×10 questions, sequential and cancellable | Durable one-trial-per-request ledger, confirmed plan hash, exactly-once claim, replay without re-inference, expiry and budget tests | Real model comparison/evaluation. Offline scripted evaluation is not a quality benchmark |
| Free-first, no silent paid fallback | Published-rate estimates, separate measured/estimated fields, global/user atomic reservation, strict proof or explicit Free-account receipt gate, atomic evidence/consent rechecks, no automatic retries or provider fallback | No genuine token/hidden-reasoning proof or production account receipt exists. Strict proof remains default; an explicit alternative uses an expiring account-bound Workers Free hard-stop receipt and estimated reservations, excludes Gateway credits/Paid models/fallbacks, and requires actual operator account review, terms and user consent before activation |
| Honest usage/cache/timing attribution | Unknown actual Neurons remain null; source-only/model invocation explicit; private/public cache separation and server timing scope | Provider prompt-cache use is unknown unless not invoked, reasoning-token counts remain null, and model revisions are provider-managed/unpinned; real billing, TTFT and iPhone-visible metrics are unmeasured |
| Ten realistic acceptance questions | All ten spec questions plus two regression questions, expected/prohibited claims and source links; human evaluation rubric | Real provider runs and human scoring, detailed craft context and broader reviewed commentary. The Cenchreae eastern-harbor question now has a fixture-provider API acceptance case with cited archaeological provenance |

## Speed, cache and operational evidence

- Public cache contains reviewed reference content only. Private questions, shared text, sessions and histories never become public cache keys or bodies.
- Native offline grant covers reviewed public-domain overview/citations only, with source dependencies,24-hour body lifetime, recent manifest checks and persisted revocation markers. Full material/image/AI-answer offline storage is not granted.
- The0.5-second cached-screen and2-second median/5-second p95 first-answer targets are unmeasured product goals. Node harness completion and SQLite wall time do not establish them.
- Current independent D1 profiling stays below the Free50-query ceiling, with a measured worst path of37 prepared statements. See [resource verification](reviews/backend-resource-verification.md) for methods, CPU diagnostics and limits.
- Local TypeScript/SQLite tests, native Foundation tests, source/syntax checks, XcodeGen generation, fresh npm-ci checkout, local D1 migrations and Worker dry-run have evidence. Apple SDK/runtime, deployed cache/CPU/memory, provider quota and network measurements do not.
- GitHub publication is blocked by missing existing authorization. No private repository has been created remotely, no public service deployed, and no paid resource provisioned.

## Prepared operator handoff

The local-only operator workflow now supports explicit optional pinned corpus assets, exact metadata registration/readback, a fixed daily cleanup schedule and reviewed user/application allowances. It builds only allowlisted public files, rejects extra upload files, and verifies account/database/action/profile identity before any future authorized apply. Real SQLite and mocked process tests cover idempotence, revocation, no paid fallback and private GitHub destinations. No actual remote setup, scheduling, invitation, deployment or push was performed. See [operator activation](operator-activation.md).

## Release decision

The implemented adapters and safeguards are suitable for further local verification. They are not ready-to-use live AI. Deployment approval must cover the stable authentication origin, provider/model terms and authorization, independently justified budget limits, actual Free Worker measurements, signed device acceptance, source rights and recovery/retention decisions. Passing local tests must not silently enable any of those gates.
