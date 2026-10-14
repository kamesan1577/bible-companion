# Linux XcodeGen validation

Validated 2026-10-13 17:30 UTC; regenerated at 20:28 UTC against the reviewed source and 24 synchronized fixtures. **Project generation passed. Apple SDK compilation did not run.**

## Source provenance

- Official repository: https://github.com/yonaskolb/XcodeGen
- Pinned release: `2.46.0`
- Tag/checked-out commit: `8445e778451c7e44237b90281bde622d764b0084` (verified with official remote `ls-remote` and local `rev-parse`).
- Source working tree remained clean.
- `Package.swift` SHA-256: `27613a3df5c35e8a0886bbf962f54a30e2ec31e7d7bf9109a27ec12c0f50ba78`
- `Package.resolved` SHA-256: `2f0b0265e33ab55bbc6cab8ad209afa85821064a2cb6fe4a1df07b642f7cebcd`
- Dependencies resolved using the release's pinned lockfile and `--disable-automatic-resolution`.
- Built locally using official Swift 6.4.1 Linux toolchain; no third-party precompiled XcodeGen binary was used.
- Resulting Linux `xcodegen` reported `Version: 2.46.0`.
- Built executable SHA-256: `2cfbae680f1adacfd9aef333a8640043f0c18ebebb3482101e95d9f20198adfb`

These hashes record the reviewed source/build provenance, not an independent code-signature or reproducible-build attestation.

## Generation and inspection

Ran the generated CLI against `apps/ios/project.yml` in its normal source location. Generated `apps/ios/BibleCompanion.xcodeproj`, confirmed ignored by Git. The executor needed `USER=agent LOGNAME=agent` because those environment variables were absent; no source patch was necessary.

Inspected generated project and scheme:

- `BibleCompanion`: application product.
- `BibleShare`: app-extension product, embedded in the application.
- `CompanionCoreTests`: unit-test bundle product.
- iOS deployment target 26.0, SDKROOT iphoneos, Swift language mode 6.0, complete strict concurrency.
- App and extension refer to their intended Info.plist and entitlement files; both App Group entitlement templates match.
- Extension uses `APPLICATION_EXTENSION_API_ONLY=YES` and `SKIP_INSTALL=YES`.
- Local CompanionCore package resolves to the app directory containing Package.swift.
- Privacy manifests appear in app/extension resource phases.
- Twenty-four fixture JSON files appear in the test target's resource phase: account-deleted, ai-policy, comparison-cancelled-before-start, comparison-expired, comparison-list, comparison-start, comparison-step, content-manifest, conversation-detail, conversation-list, conversation, export-page, export-snapshot, import, material-answer, materials, me, model-catalog, question-result, reading-data-deleted, reading-primary-text, reading, scripture-page, scripture-unavailable.
- Shared BibleCompanion scheme builds the app and includes CompanionCoreTests. Test parallelization is disabled in the generated scheme.
- Debug/Release use the checked-in Local.xcconfig (which optionally includes private local configuration). No real signing team, credentials or live API endpoint were introduced.

The initial test-fixture issue was corrected before this run: target-level `resources` was replaced with a `sources` entry using `buildPhase: resources`, as required by XcodeGen.

## Environment notes

The first source-build attempt exhausted the small `/tmp` tmpfs while the Swift toolchain archive and extracted toolchain coexisted. Independent build/cache directories were moved to the writable task workspace and TMPDIR/Clang caches redirected. The toolchain owner removed its no-longer-needed downloaded archive. The subsequent build passed. Moving already-compiled Clang caches changes their embedded absolute path; a fresh cache was required after relocation.

An exploratory generation into an alternate output directory was used only for inspection. The final verified generation used the normal app directory so relative entitlement, Info.plist and local package paths were correct.

## Remaining native gate

No Xcode, Apple SDK, simulator, physical device, code signing or IPA packaging ran. Generated settings were inspected; this is not `xcodebuild -showBuildSettings`, a native compile/link result, or proof that SwiftUI/UIKit/AuthenticationServices signatures and actor annotations typecheck on the intended Apple SDK.
