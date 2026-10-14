# Independent iOS source review

Final checkpoint: **2026-10-13 20:28 UTC**. Review covers the native app, share extension, Foundation core, API contracts and generated project. No remaining definite source-level blocker was identified in this pass. Native release readiness still depends on the Apple-platform gates below.

## Independently executed validation

- Official Swift 6.4.1 Linux: **134 XCTest cases passed, zero failures** in a separate reviewer build directory.
- Structural/source verifier: **105 checks passed**, including synchronized backend fixtures and tree-sitter parsing of **66 Swift files**.
- Fourteen app-model fault-injection checks independently passed with the actual AppStore, QuestionModel and ComparisonModel implementations and substituted observation/storage/authentication boundaries; these are control-flow checks, not Apple framework validation.
- Real Swift frontend parsing of app/service/feature/design-system/share-extension files: **passed; syntax only**.
- Design source guard: **24 contrast pairs passed**. This is not a rendered accessibility test.
- Official pinned XcodeGen 2.46.0 built from source and freshly generated the app project. App, embedded extension, test target, scheme, entitlements, package path and 24 test fixtures were inspected. See [XcodeGen validation](xcodegen-linux-validation.md) for provenance and boundaries.

Linux core compilation and source parsing do not establish SwiftUI, UIKit, AuthenticationServices or Apple-specific concurrency type correctness.

## Findings remediated and re-reviewed

### Authentication and account privacy

- Web-login callbacks and token exchange now carry an attempt identity; cancellation cannot complete a replacement login attempt.
- Logout immediately clears visible private state and fences old tasks, independently attempts cleanup, and preserves a retry path. A durable explicit-login marker prevents failed Keychain deletion from restoring the old session.
- A separate session epoch protects same-account logout/relogin as well as account switches. Usage, history, import, consent and private view completions check that epoch. Retained recovery/developer views use captured clients rather than a replacement account's mutable bearer client.
- App Group unavailability permits manual import; actual protected-file/I/O failures remain visible rather than being mistaken for absent data.

### Durable imports and uncertain questions

- Share submissions use a deterministic owner/share/confirmed-payload identity across interruption. App and extension coordinate ownership, enqueue, read and purge operations. Reads are bounded to 256 KB and preserve unreadable protected files.
- Pending questions persist a frozen owner-scoped request identity/body before POST. Recovery checks status, explicitly replays that same request, or cancels it. GET 404 does not prove a timed-out POST cannot still execute. Backend cancellation tombstones cover cancellation before a request claim exists.
- The Foundation ledger codec has a bounded 32 KB versioned envelope, validated legacy migration, exact owner/UUID checks, UTF-16 limits and date validation. Unknown future formats permit cancellation-only ID recovery without replaying an unknown body or silently discarding uncertain work.
- Preflight rejection is distinguished from uncertain submission, and complete/null filtered answers display an unavailable state.

### Public offline cache and policy changes

- Typed public-domain source-only overviews/citations are separated from account history and the private pending ledger. JCB/shared excerpts, private questions, AI answer bodies and material-card bodies are not stored in this public cache.
- Eligibility requires explicit server policy and exact dependency versions. Revalidation checks approved, active, reviewed, public, public-domain and generation-allowed metadata, including changes that retain the same content version.
- Cache lifetime is bounded to 24 hours and anchored to the earlier server/local fetch time. Offline reads and manifest checks do not renew the stored body's lifetime. Manifest freshness and foreground expiry are enforced.
- Post-await selection fences prevent stale cache/network work from replacing the current reading. Response passage/translation/spoiler settings and citation boundaries are validated.
- A durable non-content validation marker blocks cache reuse after unresolved reconciliation or purge failure. It is set before manifest retrieval and token-scoped so stale attempts cannot clear newer policy work. Regression tests cover rapid A-to-B selection with both attempts offline, observed policy information followed by offline failure, and retained markers across cache instances after simulated purge failure.
- The production marker uses stable namespace `publicReadingOverviews.v1`, rather than an absolute sandbox path. Apple documents that container paths can change on update: [Technical Note TN2285](https://developer.apple.com/library/archive/technotes/tn2285/).
- Reference-system notices now make the standard-KJV/protestant-66 numbering assumptions and unverified JCB alignment visible, including a fallback for older cached records.

### Input, request and image robustness

- Overflowing integer coordinates are rejected rather than defaulted. Multiple references are handled explicitly. Range indices and UTF-16 request lengths are validated.
- Import parsing has generation/cancellation checks, captured session/client state and save-while-parsing prevention. Developer estimates freeze the confirmed plan and fence stale results.
- API transport incrementally limits its retained response-body buffer to 4 MB, rejects oversized declared lengths and refuses redirects. Tests include declared 10 MB and unknown-length 11 MB responses, exact cap/cap-plus-one, cancellation before/during transfer, and late duplicate completion. This is not a claim that total process memory stays below 4 MB.
- Artwork uses a separate ephemeral HTTPS transport restricted to api.nga.gov, rejects redirects, validates image MIME, caps streamed data at 8 MB and downsamples to a 1600-pixel thumbnail. Apple runtime behavior remains unverified.

### Protected export and sequential comparison

- Export assembles bounded pages directly into a protected, backup-excluded private file. It validates owner/snapshot/section, expiry, page size/count and opaque-cursor loops, and exposes sharing only after all sections finish.
- Review found and corrected partial files left by a throwing initializer, missing orphan-cleanup retry state, and a stale cancelled export's directory-wide cleanup that could delete a newer export. Initial-write failure now rolls back; stale attempts clean only their own files. Startup cleanup failure is visible and retryable.
- Comparison recovery preserves the frozen owner/plan/hash and attempted trial index before dispatch. It advances only from validated acknowledged state, supports pre-start cancellation tombstones, and recognizes expired jobs as terminal.
- Review corrected a transient storage failure that permanently blocked comparison planning, and an old estimate that could be displayed under a newly selected passage. Successful re-read clears the blocked state; passage changes/disappearance invalidate planning, and confirmation displays the frozen passage.
- Real backend export and comparison start/step/expired/pre-start-cancelled fixtures decode and pass core checks. Model settings derive from the intersection of enabled server-catalog ranges; missing/invalid schemas do not enable parameters.
- Actual protected-file transitions, share-sheet completion/cancellation and delayed view-model lifecycle sequences still need Apple-platform runtime tests. Core fault injection establishes initializer cleanup behavior, not device-level file-protection semantics.

### Verse subsets, saved history and private deletion

- Verse-subset selection validates the original reading boundary and permits cross-chapter subsets without widening the spoiler boundary. Saved-conversation resume requires the exact original import/range and preserves the conversation's scope/spoiler setting.
- Conversation messages load in bounded pages and maintain a 200-message display window. Policy-version/scope changes invalidate merged pages. Saved comparisons are reloaded through the server's current source-policy projection.
- Review found and corrected a resumed-question task that could write its pending ledger after cancellation/logout. Task-entry, pre-ledger and pre-dispatch checks now use cancellation/generation fences and frozen payloads.
- Review corrected history error-code handling: source_policy_changed, conversation_policy_changed and conversation_changed all clear retained messages; authentication and missing-record failures clear private detail too.
- Account/bulk-reading deletion requires owner/session-bound typed confirmation plus a destructive native confirmation. A recent-authentication rejection requires login renewal and a fresh confirmation; uncertain delivery is not automatically retried.
- Review found and corrected the concurrent GET401/DELETE-success race. The deletion transition now owns account cleanup, cancels reading work, suppresses unrelated error-driven session invalidation and blocks competing state mutations. The epoch stays stable on recent-authentication rejection so the reauthentication UI remains available.
- Actual route fixtures cover history lists/detail and both deletion acknowledgments. Core checks and transport tests pass; destructive backend calls against genuine user data were not performed.

## Security and configuration checks

- PKCE uses 32 cryptographically random bytes, a 43-character unpadded URL-safe Base64 verifier, and SHA-256 of the UTF-8 verifier followed by the same Base64URL transform. Randomness failure throws; no weak fallback was found.
- Authentication validates the exact callback scheme/host/path and a single matching state/code. The verifier is not put in the callback URL.
- Keychain uses WhenUnlockedThisDeviceOnly; bearer tokens are not stored in the App Group. Default API sessions disable cookies/cache and require HTTPS.
- App and extension plist/entitlement files parse, and App Group templates match. Authentication code using UIApplication.shared is not part of the extension target.
- The test fixture resource-membership bug was corrected and verified in the generated project.

## Required Apple-platform release gates

1. Unsigned app/share-extension compile and link with the intended iOS 26 SDK; Swift 6 complete-concurrency checking and the iOS test target. Inspect effective Xcode build settings.
2. Simulator/device checks for Dynamic Type, VoiceOver, landscape/iPad, Reduce Motion, Reduce Transparency, native glass controls and sheet dismissal.
3. Delayed callback/transport tests for cancelled login A/new login B, signout during restore/import/usage/consent, and same-account relogin.
4. Real Keychain and protected-file failure recovery; simultaneous app/extension enqueue versus logout; app updates and process interruption around cache-marker persistence and accepted-but-unacknowledged requests.
5. Request reconciliation/cancellation tests against the integrated backend, including cancellation before reservation and policy-filtered answers. Exercise deletion success concurrent with GET401, recent-authentication rejection/reconfirmation, interrupted deletion and local cleanup failure using test accounts.
6. Signing, capabilities and any real device authentication require the intended authorized development setup.

No Apple SDK build, simulator/device rendering, signed package, deployment, live inference, credential creation or new access grant was performed by this review.

## Official API references checked

- [Apple GlassButtonStyle](https://developer.apple.com/documentation/swiftui/glassbuttonstyle)
- [Apple iOS 26 SwiftUI design session](https://developer.apple.com/videos/play/wwdc2025/323/)
- [ASWebAuthenticationSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession)
- [Authentication-session cancellation](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/cancel())


## Apple declaration and first-run follow-up, 19:00 UTC

Official Apple documentation/declaration metadata was checked for the concrete APIs used: GlassButtonStyle (iOS 26), Tab (iOS 18), UIViewControllerRepresentable (MainActor/preconcurrency), Social compose overrides and authentication presentation anchors. No definite signature/availability mismatch was identified for the iOS 26 target. This is documentary/source review, not Apple SDK compilation.

- Authentication now uses the documented `init(url:callback:completionHandler:)` with `.customScheme`, both available from iOS 17.4, replacing the deprecated callbackURLScheme initializer. [Apple initializer](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/init(url:callback:completionhandler:)-6nut7), [custom-scheme callback](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/callback/customscheme(_:)).
- Apple requires activity-controller popover presentation on iPad. The revised export host waits until attached, presents once, anchors to its presenting host view, and guards duplicate completion. File cleanup remains tied to outer-sheet dismissal. Nested-sheet/popover rendering, rotation, interactive dismissal and activity completion still require iPad/iPhone runtime checks. [Activity controller](https://developer.apple.com/documentation/uikit/uiactivityviewcontroller), [anchor view](https://developer.apple.com/documentation/uikit/uipopoverpresentationcontroller/sourceview), [anchor coordinates](https://developer.apple.com/documentation/uikit/uipopoverpresentationcontroller/sourcerect).
- History now distinguishes successful empty results from unchecked/loading/error states and offers explicit retry. Manual import no longer claims a pending share exists when none does. Initial endpoint setup, unchecked usage and unavailable passkey-management/recovery features are disclosed.
- Independent rerun after these edits: **101 core XCTest cases, 84 source checks, 52 grammar files, 24 contrast pairs and real frontend syntax parsing passed**. The last generated-project resource inspection remains 18:49 UTC with 19 fixtures; these edits did not add resources.


## Corpus-native follow-up, 19:13 UTC

Independent rerun with SwiftPM `--jobs 2`: **107 core XCTest cases passed**, **91 source checks / 56 grammar files**, **24 contrast pairs**, real frontend syntax parsing and fresh XcodeGen generation all passed. All **22 fixture JSON resources**, including reading-primary-text, scripture-page and scripture-unavailable, appear in the generated test resource phase.

Source review confirms exact requested-passage validation, bounded page count/encoded size, verified corpus metadata, fixed verse identifiers, duplicate/omission-conflict checks, forward ordering, cursor-cycle checks and corpus/policy identity checks across pages. The pager retains cursor history rather than accumulating primary text pages. A forward/back/forward navigation regression and policy change while paging backward were recommended as additional coverage.

Primary text is explicitly labeled English World English Bible, not JCB/Japanese text or editorially reviewed Japanese commentary. Missing Japanese commentary is stated and English excerpts are initially collapsed. Unavailable corpus and missing source coordinates are distinct states. Both newly received and loaded offline snapshots reject literal-primary-text; no new primary-text offline grant was introduced. No definite source blocker was found in this pass. Apple SDK compilation, paging interactions and device lifecycle behavior remain unverified.


### Pager regression closure, 19:19 UTC

The author extracted opaque-only ScriptureCursorHistory into Foundation Core. Independent **109-test** rerun passes, including three-page forward/back/forward navigation, cursor-cycle rejection/reset and corpus-version rejection during backward navigation. **91 source checks, 56 grammar files, 24 contrast pairs and real frontend parsing** still pass. Source review confirms the app model uses the tested helper. Cached-only material tabs now say a connection is needed instead of implying unqueried material is absent. No new resources were added; the last XcodeGen inspection still has 22 fixtures. No additional definite source blocker was identified.


## Protected-storage and accessibility-copy pass, 19:30 UTC

Independent results: **111 Foundation XCTest cases passed**; **six AppStore fault-injection control-flow checks passed**; **91 source checks / 56 grammar files, 24 contrast pairs and frontend syntax parsing passed**.

The AppStore harness compiles the actual AppStore implementation with only its SwiftUI import replaced, links real CompanionCore, and substitutes observation, storage and authentication boundaries. It checks signed-out launch preserving an unbound share, unreadable history withholding authenticated state, explicit restore recovery with failed cleanup, durable 401 cleanup failure across store instances, owner-marker I/O failure, and missing-App-Group manual-input fallback. These checks do not exercise Keychain, file protection, NSFileCoordinator, UIKit, SwiftUI or iOS runtime behavior.

- Review identified premature authenticated-state publication before protected history/token restoration. Restore now validates local data before publication and offers retry or explicitly confirmed local clearing if storage remains unreadable.
- Silent owner-marker writes were replaced by throwing updates. Only genuinely unavailable App Group access allows the stated manual-input fallback; protected/I/O failures remain blocking and retryable. Logout and 401 now share synchronous full local cleanup with durable cleanup intent, avoiding later cleanup tasks erasing a replacement account.
- Re-review caught an intermediate regression where ordinary signed-out startup purged pending unbound shares. The final path preserves those shares; authenticated expiry/logout/401 keep the full purge.
- The actual cross-module Swift compiler identified actor isolation of APIClient.baseURL; the endpoint is now an explicitly nonisolated immutable Sendable URL. Credentials remain actor-private.
- Japanese copy distinguishes request-burst limits from daily budgets, translates comparison states and explains unavailable versus unreadable shared storage. Queue wording distinguishes 24-hour eligibility expiry from deletion at the next cleanup opportunity. Scripture verse labels explicitly name the book/chapter/verse for accessibility.
- The Mac acceptance checklist provides unsigned build/test and signature-inspection commands, with real signing, authentication, deletion and SideStore operation held behind their stated authorization/device gates. Static accessibility labels and semantic headings are present; VoiceOver focus, reading order and rendered layout remain unverified.


Final owner-marker hardening re-reviewed at 19:31 UTC: the read is capped at 65 bytes and the Core decoder accepts only an empty unbound marker or a valid UTF-8 UUID within 64 bytes. Corruption no longer becomes an unbound share; missing coordination results no longer masquerade as an unavailable App Group. Independent full suite: **112 XCTest cases passed**, with the added malformed/oversized marker regression. Source/design checks and LocalStorage frontend parsing also pass; real cross-process/protected-file behavior remains a device gate.

## Focused native map review, 19:50 UTC

Five PlaceLocationTests independently pass, including the added malformed-source-URL regression; PlaceMapView frontend syntax parsing also passes. Source provenance URLs now require a nonempty HTTPS host, preventing an opaque URL from authorizing a pin.

The map requires reviewed/approved, scope-compatible material, finite approximate coordinates, a named provenance source, supported source licensing and attribution/license links. It looks up the card in current reading state and excludes cached-only overview state. Text explains representative ancient-site coordinates versus modern map features; coordinates, explanation and provenance remain outside the map. No user-location request or routing API is present.

Apple's documented [Map initializer](https://developer.apple.com/documentation/mapkit/map/init(initialposition:bounds:interactionmodes:scope:content:)), [standard style](https://developer.apple.com/documentation/mapkit/mapstyle/standard(elevation:emphasis:pointsofinterest:showstraffic:)), [camera initializer](https://developer.apple.com/documentation/mapkit/mapcamera/init(centercoordinate:distance:heading:pitch:)) and [scale control](https://developer.apple.com/documentation/mapkit/mapscaleview) match the reviewed call forms. Map rendering, annotation focus, scrolling/gestures, attribution visibility and MapKit network behavior remain Apple-platform runtime gates. This focused run does not replace the next full integration test run.


## Answer-mode consent and integration closure, 20:00 UTC

Independent full rerun: **125 Foundation XCTest cases passed with zero failures; eight AppStore harness cases passed; 100 source checks, 62 grammar files, 24 contrast pairs and real frontend syntax parsing passed**. Fresh official-source XcodeGen generation includes all **23 JSON fixtures**, including ai-policy. No additional definite source-level blocker was identified.

- Reviewed-claim selection and grounded generation have explicit server policy/consent gates and separate Japanese risk disclosures. Consent acceptance is tied to the frozen owner, session epoch and policy version. Source-only behavior remains separately identified.
- Review found that grounded-mode revocation could resubmit stale provider consent and re-enable a revoked provider. Native revocation now omits the provider field; the backend applies partial consent updates atomically and prevents grounded revocation from granting provider consent. Native mutations serialize, invalidate cached policy at dispatch and fence stale completions. Policy refresh cannot start or publish during mutation.
- Two additional harness cases use a fake URLProtocol to hold consent delivery, verify serialization and suppressed refresh, and inspect the partial-revocation body. They make no live request and do not substitute for backend concurrency or Apple networking tests.
- Pending-question schema 2 freezes answer mode with the request body. Valid legacy records migrate to reviewed selection; unknown future records retain cancellation-only recovery. Comparison identity accepts the same model under distinct modes while rejecting duplicate model/mode configurations; legacy frozen plans remain unchanged.
- Explicit answer-mode-disabled and grounded-consent-required preflight errors clear pending state only after backend confirmation that they precede provider inference. Uncertain delivery still retains the frozen identity. Developer estimates invalidate when mode/policy/consent changes, and confirmations disclose frozen modes and estimated rather than guaranteed budget reservations.
- Generated-answer warnings appear in new, recovered and saved answers and comparison results. The synchronized policy and result fixtures decode in the independently compiled core suite.

This closes the source/testing checkpoint, including the preceding map review. Apple SDK compile/link, real file protection, authentication callbacks, map rendering, VoiceOver, iPad sharing and device lifecycle acceptance remain outstanding.


## Daily-use regression closure, 20:19 UTC

Independent repair validation: **130 XCTest cases, 14 app-model control-flow cases, 102 source checks, 64 grammar files, 24 contrast pairs and real frontend parsing passed**. The project was regenerated again with the same 23 fixtures. This supersedes the 20:00 aggregate for the repaired source.

- Concurrent question-status checks could publish older running or answer data after a newer terminal/policy-filtered result. Status requests now serialize under a fresh generation, block overlapping sends and reject late completion after closing. Authentication and source-policy rejections clear an earlier answer while preserving the request identity.
- A rejected recent-authentication deletion cancelled the cached-reading expiry task while retaining its body. Cancellation now clears cached-only presentation before removing the expiry guard; offline cache reopening remains available and is covered by fault injection.
- Comparison policy failures and explicit status refresh now clear separate transient answer bodies, preventing those bodies from bypassing current saved-result projection. Reading-scope changes clear presentation without deleting unresolved recovery identity. The frozen presentation plan survives terminal ledger removal, including resuming an old range after selecting another; each live trial labels its original scope.
- Failed re-planning formerly left an older estimate available for confirmation. The tested ComparisonPlanDraft clears previous state before a new attempt and rejects stale responses. Developer-operation completions additionally check owner, session, view and operation identity.
- Oversized comparison plans now advise reducing questions/output and explicitly re-planning, rather than implying a daily reset necessarily fixes the plan. Source-only loading states identify reference retrieval without claiming AI generation.

The harness uses the exact three model implementations with substituted storage/authentication/observation boundaries and fake URLProtocol responses. It does not exercise Apple frameworks or real accounts. No additional definite source-level blocker was identified in the repaired pass; the Apple-platform acceptance gates above remain unchanged.


## Material-summary citation review, 20:28 UTC

Independent aggregate: **134 XCTest cases, 14 exact-model harness cases, 105 source checks, 66 grammar files, 24 contrast pairs and frontend syntax parsing passed**. Fresh XcodeGen generation contains exactly **24 fixture resources**, including material-answer.

Additive optional sourceKind/materialProvenance fields preserve legacy citation decoding. Material-summary citations are explicitly distinguished from scripture quotations; missing/unknown legacy kinds are not presented as verified scripture. The native disclosure iterates every provenance reference and displays its title, publisher, license, available attribution and checked date, plus safe source/license links. HTTPS links require a nonempty host and reject embedded credentials. The real material-answer fixture preserves all four references, including the Pleiades attribution, across decoding/encoding.

Both new offline snapshot creation and loaded-snapshot reuse reject material provenance, including a forged public-domain cache grant. This does not expand the existing offline content license policy. No definite source-level blocker was identified; disclosure rendering, accessibility and Apple SDK compatibility remain subject to the existing platform acceptance gates.

### Catalog-readiness copy follow-up, 20:36 UTC

Reviewed the text-only DeveloperView update against backend budget metadata. Selectable models and provider-policy readiness are now distinguished from per-question/comparison budget approval; the optional preparedRequestBudgetRequired flag and EXACT_REQUEST_BUDGET_CHECK_REQUIRED warning match server keys. Independent frontend parsing, 105 source checks / 66 grammar files and 24 contrast pairs pass. No request or recovery control flow changed. The last full 134-test / 14-harness aggregate remains the 20:28 checkpoint.
