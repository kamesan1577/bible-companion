# Native iOS application

SwiftUI application and Share Extension for the private Bible companion. iOS 26 / Xcode 26 are required. This is native source, not a WebView wrapper. The design system in `Sources/DesignSystem` is governed by `../../docs/design/README.md`; feature views must consume it rather than invent new colors, typography, radii, or translucent reading cards.

Start with the concise [Mac acceptance checklist](MAC-ACCEPTANCE.md): exact unsigned build/test commands, expected results, signing/App Group inspection, and steps that must wait for the user.

## Build on a Mac

Prerequisites: Xcode 26 with the iOS 26 SDK and an installed iOS simulator; XcodeGen 2.42+ from its official release/Homebrew. No Xcode/signing tools are available in the implementation's Linux environment. The Foundation package was compiled and its 134 XCTest tests passed using an official Swift 6.4.1 Linux toolchain; see `VERIFICATION.md`.

```sh
cd apps/ios
cp Config/Local.example.xcconfig Config/Local.private.xcconfig
# Edit the private configuration: your own bundle ID, App Group, and stable HTTPS API URL.
# Set DEVELOPMENT_TEAM only when you choose an existing signing identity.
./Scripts/generate-project.sh
xcodebuild -project BibleCompanion.xcodeproj -scheme BibleCompanion \
  -sdk iphonesimulator -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project BibleCompanion.xcodeproj -scheme BibleCompanion -showdestinations
# Replace SIMULATOR_ID with an available iOS26 simulator from the previous command.
xcodebuild -project BibleCompanion.xcodeproj -scheme BibleCompanion \
  -destination 'platform=iOS Simulator,id=SIMULATOR_ID' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO test
swift test
```

The generated `.xcodeproj`, private config, archives, provisioning profiles and signing keys are ignored. XcodeGen is the reproducible source of project configuration. The Swift package contains Foundation-only models/parser/transport/state helpers and is testable separately on a compatible Swift 6 toolchain. The app and Share Extension still require Apple SDK compilation.

`BIBLE_API_URL` uses `https:/$()/host` because ordinary `//` starts an xcconfig comment. The checked-in endpoint is deliberately `.invalid`; the app fails closed with a setup message. Do not put service API keys in configuration. The Worker must use the matching `biblecompanion://auth/callback` callback and a stable HTTPS WebAuthn RP/origin.

## Implemented flows

- Native `TabView`, `NavigationStack`, toolbar, segmented/menu picker, sheet, and `.buttonStyle(.glass)`; iOS26 supplies actual Liquid Glass. The reading layer stays opaque and uses the shared light/dark palette.
- Whole/single/multiple/cross-chapter labels, clear end-of-reading boundary, separate selected imported ranges, and question targets narrowed to any valid verse subset or chapter segment without moving the spoiler cutoff.
- Source-only overview/citations and reviewed map/person/art cards with provenance, episode boundaries and explicit empty states. Public-domain artwork images use ephemeral unauthenticated loading. No invented artworks, maps, licensed Bible text, scene divisions, AI results, or streaming animation.
- Answer citations distinguish scripture from commentary and reviewed material summaries. Material citations preserve every underlying source, publisher, license, attribution, license link and review date in a native disclosure. Legacy unspecified kinds remain explicitly unverified. Material-summary provenance cannot enter the public offline overview store.
- Native MapKit detail shows only the three reviewed approximate Pleiades ancient-site points (Corinth, Kenchreai, Ephesus), with source attribution/license links and a modern-map uncertainty legend. It never requests user location or constructs historical routes. Text/source details remain readable when map tiles are unavailable. Apple rendering remains a device gate.
- Optional paged World English Bible reference text is explicitly English, source-coordinate preserving, and separate from Japanese commentary/JCB alignment. The view shows missing/empty coordinates without remapping, keeps only the current page in memory, and rechecks corpus/policy identity across pages. Literal-primary-text overview excerpts are collapsed and disclose that Japanese commentary is unavailable. Primary text is not granted offline storage.
- Shared URL/text intake, local conservative parser, server fallback parser, manual canonical range correction, and explicit unknown-translation confirmation. The share sheet saves to a protected App Group queue; the user opens the main app. It never attempts unsupported automatic app launch.
- Share queue entries expire after 24 hours. Cross-process file coordination serializes writes/owner changes/clear. Owner-unbound shares require confirmation, other owners' entries remain hidden, and deterministic owner+share+confirmed-payload IDs prevent duplicate imports after interrupted saves.
- First-run setup, loading, failed history requests, genuinely empty history, and unchecked usage have distinct labels. Unsupported passkey management/lost-key recovery is disclosed in account settings.
- Passkeys through `ASWebAuthenticationSession`; random state, PKCE S256, exact callback path/state/code validation, one-use code exchange, attempt fencing, and Keychain session storage. No bearer token in callback URLs, logs, App Group storage, or ordinary preferences.
- Protected-storage restore publishes a logged-in state only after local history and owner markers are readable. A signed-out first launch preserves unbound shares; expired/401/logout paths use durable synchronous cleanup and block a new login while cleanup remains incomplete. Missing App Group support has an explicit manual-import fallback; other I/O failures are not mistaken for missing entitlements.
- Account-scoped offline history metadata, immediate logout privacy clearing, retryable cleanup, and a persisted explicit-login marker if Keychain deletion fails. Private responses use ephemeral networking with no cookies/URL cache; redirects are rejected and response bytes are capped incrementally at 4 MB before JSON decoding.
- Answer mode is explicitly selected between reviewed-claim selection and experimental grounded generation. Generation requires current, version-bound semantic/spoiler-limit consent plus provider consent and server/model/budget gates. Consent mutations serialize; revoking generation cannot grant provider consent. New pending-question schema2 freezes mode; legacy missing-mode records migrate only to reviewed selection. Comparisons can use the same model in two different modes, with both configurations frozen. Budget warnings distinguish estimated free-tier reservations from verified bounds.
- AI question loading/cancel/status recovery, explicit source-only mode, AI consent, quota/offline/error text. Answers arrive as complete JSON; no fake streaming. A protected account-scoped, versioned pending-question ledger freezes request ID/body before POST. Legacy records migrate after validation; unknown schema records are retained and offer cancellation-only recovery where their owner/request identity can be validated. Unknown delivery never silently sends a new ID. Settings can check, replay the same ID, or cancel even after relaunch.
- Paged saved conversation browsing, current-policy-filtered message detail, and fixed-scope continuation of an existing conversation. Up to 200 messages remain in memory while paging; private answer bodies are cleared on background/navigation and never added to the public cache. Owner-only saved comparison browsing shows only current server-projected results.
- Explicit bulk reading-data/account deletion requires a typed confirmation and destructive confirmation dialog. Expired recent authentication requires a fresh login and a new confirmation; uncertain delivery never automatically repeats deletion. Successful or uncertain outcomes clear local private state and log out, with retryable local cleanup and an honest backup-erasure notice.
- History, usage/reset display, consent revocation, owner-only server-driven model catalog/preference and two-model comparison planning/confirmation. All registry candidates are listed with capability, connection, terms-review and budget gates. Parameter controls use the selected models’ common valid bounds. Unconnected/unapproved models are disabled. Comparison confirmation uses a protected frozen plan; each acknowledged request executes at most one trial, and uncertain delivery waits for explicit same-plan status/recovery. Unsaved answer bodies stay in memory.

- Private paginated export assembles JSON directly on protected disk, validates snapshot/section/cursor/size/expiry, and exposes sharing only after every section completes. Cancellation/errors discard incomplete files; sharing completion, startup and logout clean temporary outputs. Local unresolved questions/comparisons block export. The activity presenter explicitly anchors an iPad popover to its attached host view; the native share lifecycle still needs device verification.

## Deliberate boundaries

- Device public caching stores only server-granted public-domain source-only overviews and their citations, up to 64 entries/256 KB each. The hard body TTL is at most 24 hours from the earlier of fetch/server check; foreground expiry removes displayed cached content. Each connection revalidates dependency IDs, versions, rights, public visibility and reviewed status against a fresh manifest. Offline hits do not renew the TTL. A non-content validation-intent marker is written before online manifest checks; interrupted or failed disk reconciliation requires a successful online check before cached bodies can reopen. Ordinary transport failure clears only its own newly created marker. A visible badge states fetch/revalidation times. Source text, including the optional English primary-text view, material cards/images, shared text and AI answers are excluded. Public overviews can survive logout, but the cache is never exposed as another account’s reading history.
- Private history is saved locally only as canonical chapter/verse metadata. Pending question text is retained solely for explicit delivery recovery and removed at terminal status/logout. The app does not bundle JCB or another restricted translation.
- Maps/people/artworks render only reviewed, rights-approved, boundary-safe server material; otherwise they show an explicit unavailable state. Unverified coordinates never become map pins. The UI does not manufacture substitute content.
- Question scope selects the whole current import range, chapter segments, or an arbitrary valid verse subset. Multiple disjoint imported ranges are individually selectable; cross-range question aggregation is not implemented. Resumed conversations retain their original question scope and spoiler policy.
- Locally cached full public source bodies, artwork downloads, private answer caching, export restoration, and lost-passkey account recovery are not implemented.
- Xcode signing/entitlement provisioning, real-device Share Extension delivery, actual Liquid Glass visuals, VoiceOver layout, and SideStore packaging remain device-verification gates. No signed IPA is produced in Linux. No identity or persistent signing permission is created.

## Signing / SideStore handoff

After the unsigned simulator build and tests pass, open the generated project in Xcode. Choose the user's existing signing team, make application and extension bundle IDs unique, and ensure both targets share the exact App Group entitlement. Archive for a physical iOS device only after those choices are authorized. App Group support must be preserved by any later re-signing workflow; do not assume a sideloading/signing method supports it. If it does not, use manual import in the app and mark Share Extension unavailable until verified. Apple IDs, private keys and provisioning credentials are entered by the user in the signing tool, never in chat/source.

## Verification

```sh
python3 Scripts/verify-source.py
# Optional syntax grammar check (still not compilation):
# python3 -m pip install --target /tmp/swift-parser tree-sitter tree-sitter-swift
# PYTHONPATH=/tmp/swift-parser python3 Scripts/verify-source.py
```

This script checks canonical metadata, real backend fixtures, plist/entitlements, source privacy invariants and the design guard. It explicitly labels iOS build/rendering as not run. XCTest source covers range rendering/counts, invalid ranges, scope boundaries, parser adversarial inputs/overflow, queued-owner/expiry rules, stale-request gates, endpoint security, and actual response fixtures. Do not treat grammar checks as Swift compiler or runtime test passes.

## Device acceptance before calling this ready

1. Build/test both targets with Swift 6 strict concurrency and Xcode26. Test fresh install and upgrade with the same App Group.
2. Capture light/dark, large accessibility type, increased contrast, Reduce Transparency and Reduce Motion; compare with the canonical screenshot and design catalog. Inspect 17pt semantic body text, target sizes and landscape/iPad.
3. Verify unconfigured-server onboarding, failed/empty history distinctions, unchecked usage, and unavailable passkey recovery disclosure. Cancel login during browser presentation and during token exchange, immediately restart, reject stale callbacks, test wrong/missing/duplicate state and device lock.
4. Import the same share twice, terminate after server acceptance but before queue cleanup, retry with the same payload, edit translation, share while logged out, and switch accounts.
5. Lose network before/after a question POST, close/reopen, inspect/replay the same pending ID, cancel before server reservation, change range/spoiler mode, and confirm late answers cannot enter a new scope/account.
6. Test quota, unconnected/disabled models, required consent, revoked source versions, empty citations and unavailable materials. Never label source-only content as generated AI.
7. Browse more than 200 saved messages, revoke a source while loading an older page, background/foreground, and resume the same conversation without changing its original spoiler boundary. Test arbitrary start/end verse choices across chapters and rejected reversed/outside ranges.
8. Confirm bulk/account deletion, reject incorrect confirmation, receive recent-auth 403, reauthenticate and reconfirm. Race a GET401 against DELETE success; verify all private ledgers/export files are cleared or show a cleanup retry. Lose the deletion acknowledgment and confirm no automatic destructive retry.
9. Export on iPhone and iPad, dismiss both activity and outer sheet, rotate the device, cancel sharing and complete sharing; verify exactly-once completion and protected-file cleanup.
10. Open English reference text with and without a server corpus, page forward/back, revoke/change the corpus between pages, and background/foreground. Confirm omissions remain explicit and no JCB/Japanese alignment or editorial-review claim appears.
11. Change comparison fields while planning, verify frozen plan confirmation, cancellation/status recovery, no automatic retry or model fallback, and owner-only server rejection for members.

## API/design references checked

- Apple: [Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/), [glass button style](https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glass(_:)), [web authentication session](https://developer.apple.com/documentation/authenticationservices/authenticating-a-user-through-a-web-service), [required-reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api).
- Apple API declaration review: [modern web-auth callback initializer](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/init(url:callback:completionhandler:)-6nut7), [custom callback scheme](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/callback/customscheme(_:)), [activity presentation](https://developer.apple.com/documentation/uikit/uiactivityviewcontroller), and [popover anchor](https://developer.apple.com/documentation/uikit/uipopoverpresentationcontroller/sourceview). These are source-level API checks; they do not replace SDK compilation or device tests.
- User-requested [Apple-design reference](https://github.com/emilkowalski/skills/blob/main/skills/apple-design/SKILL.md), applied to native controls without copying web motion/blur approximations.
- Backend contract: `../../docs/openapi.json`; test fixtures are synthetic responses generated by the backend contract tests, not live user data.
