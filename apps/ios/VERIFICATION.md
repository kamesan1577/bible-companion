# Native source verification — 2026-10-13

## Passed

- **Foundation core compiled with Swift 6.4.1 on Debian 13.** `swift test` completed with **134 XCTest tests, 0 failures**. This covers actual DTO decoding from server fixtures, canonical ranges/verse counts, spoiler-scope separation, adversarial parsing, overflow, multi-reference non-truncation, queued-share ownership/expiry, stale-response gate, endpoint restrictions, and stubbed HTTP authentication/error behavior. Network tests use a local `URLProtocol`; no live service or credentials are involved.
- **All authored app and extension Swift source passed `swiftc -frontend -parse`.** This is compiler syntax parsing, not Apple-framework type checking.
- **105 source/configuration checks passed**, including optional grammar parsing of 66 authored Swift files, canonical metadata/fixture synchronization, callback scheme, share activation, minimal entitlements, privacy manifests, native-only UI, absence of credential logging, and iOS26 project target.
- **Material-citation tests:** real route fixture retains all four WEB/ASCSA/Pleiades references and CC-BY attribution through decoding/encoding; legacy and unknown kinds are not mislabeled scripture; opaque/credential-bearing/non-HTTPS source links are rejected; forged material-summary grants fail both offline snapshot creation and disk-cache reuse.
- **Map and answer-mode tests:** five source-bound approximate-coordinate/attribution tests; explicit consent/allowlist/version/account fences; schema2 frozen-mode replay and legacy migration; same-model/different-mode comparison validation.
- **Bounded transport/offline/ledger tests:** unknown-length responses over 10 MB, early Content-Length rejection, exact limits, cancellation/late completion, approved overview projection, TTL/clock skew, same-version license revocation, manifest freshness, account-independent cache keys, and legacy/current/future/corrupt pending-request schemas.
- **XcodeGen project generation passed on Linux** using official 2.46.0 source. Target types, package/entitlement paths, extension embedding and test resources were inspected; see `../../docs/reviews/xcodegen-linux-validation.md`. This does not compile Apple frameworks.
- **Export/comparison state tests:** incremental valid JSON, complete-only finalization, owner isolation, page/cursor/expiry rejection, parameter-range intersections, frozen comparison roundtrips, ready/executing/terminal transitions, and pre-start cancellation tombstones.
- **Saved-history/subset/deletion tests:** actual paged conversation/comparison and deletion fixtures, exact original reading-boundary matching for resume, policy-change invalidation, hidden-answer suppression, bounded message windows, arbitrary cross-chapter subset constraints, and account/session-bound typed deletion confirmation.
- **Extracted app model checking:** history, question, comparison and export model code passed Swift6 complete-concurrency type checking against the real Foundation core with minimal observation/storage stubs. This does not establish SwiftUI/UIKit compatibility.
- **Design contract passed:** 24 contrast pairs, generated token consistency, and source guards against feature-local colors/fonts/radii/materials/navigation backgrounds.
- **English primary-text contract tests:** available versus unavailable fixtures, exact passage, corpus/language/license/reference metadata, source-policy changes, cursor loops, duplicate/oversized bodies, explicit omissions and rejection of literal primary text from the offline overview cache.
- **AppStore control-flow fault injection:** fourteen cases compile the actual AppStore, QuestionModel and ComparisonModel implementations with fake observation/storage/auth boundaries and link the real Foundation core. They cover signed-out share preservation, unreadable-history admission, explicit cleanup recovery,401 cleanup failure across restart, failed owner-marker writes, missing-App-Group fallback, serialized consent mutations, grant-free partial revocation, overlapping/late question status, policy/scope result clearing, terminal result scope retention and cache expiry after rejected deletion. These are not Keychain/App Group/SwiftUI runtime tests. The harness found and fixed a real cross-module actor-isolation error by marking the immutable API endpoint `nonisolated`; bearer state remains actor-private.
- **Apple declaration/first-run review:** modern custom-scheme authentication initializer matches documented iOS17.4+ availability; iPad export uses an explicit host-anchored popover. Unconfigured endpoints, failed versus empty history, unchecked usage and absent passkey recovery are disclosed distinctly. UIKit presentation and first-run rendering remain untested on a device.
- **Independent source review completed in parallel.** Its separate Linux scratch build/test run also passed. Review findings led to corrected login attempt fencing, early local logout, persisted logout intent, protected queue I/O handling, deterministic import replay IDs, private pending-question recovery, frozen comparison confirmation, generation-fenced import parsing, and Xcode fixture membership.

The initial Swift test run caught a malformed-range parsing error: a trailing `-10` was accepted as a translation suffix. The parser now requires a letter-led translation suffix and the regression test passes.

## Post-checkpoint repair evidence (after the 20:00 UTC checkpoint)

The daily-use audit found and repaired overlapping question-status responses, stale comparison bodies after policy/scope changes, loss of a completed comparison's original scope, cached display retaining no expiry after rejected recent-auth deletion, stale budget confirmation after a failed re-plan, and reset-only copy for an oversized comparison. `ComparisonPlanDraft` has three executable stale-response/failure regressions. The expanded fault-injection script runs unchanged app-model implementations against fake persistence/auth/HTTP boundaries and real Core; its tests do not establish Apple framework compatibility or actual wall-clock UI latency. Source-only loading copy now says it is fetching range materials without AI.

## Not run / not established

- App/Share Extension compilation and linking against the iOS26 SDK; Apple-specific Swift6 isolation diagnostics.
- XcodeGen generation on macOS, `xcodebuild test`, Simulator rendering or interaction, VoiceOver/Dynamic Type/Reduce Motion/Reduce Transparency device inspection.
- MapKit rendering, map-tile offline behavior, attribution readability and VoiceOver navigation; actual consent-sheet presentation and server-policy changes during native interaction.
- Physical iPhone passkeys, App Group delivery, iOS background/locked-device behavior, signing, archiving, IPA packaging, or SideStore re-signing.
- Live AI inference, provider budget/consent behavior, billed cost, end-to-end latency, or production service deployment.

A passing Foundation build or syntax parser must not be reported as a passing iOS build. The exact Mac commands and device acceptance matrix are in `README.md`.

## Reproduce the checks

```sh
cd apps/ios
swift test
# Optional Linux-only app-state fault injection, with the same Swift toolchain:
bash Scripts/test-app-state-linux.sh
python3 Scripts/verify-source.py
# Optional grammar checker dependencies are separate from app dependencies.
# The implementation used PYTHONPATH=/tmp/bible-swift-parser.
find Sources ShareExtension -name '*.swift' -print0 | xargs -0 swiftc -frontend -parse
```

Linux compilation used the official Swift.org Debian13 Swift6.4.1 archive in a temporary directory, with Clang/SwiftPM caches redirected into writable temporary directories. It did not install signing identities, modify accounts, or deploy anything.
