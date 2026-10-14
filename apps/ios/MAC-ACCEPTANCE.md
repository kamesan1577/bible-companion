# Mac acceptance checklist

This source has passed Linux Foundation tests and source review. It has **not** passed an Apple SDK build, Simulator/device interaction, signing or SideStore installation. Complete the checks below before calling the iOS app ready.

## 1. Confirm the tools, without changing accounts

Run from the repository root:

```sh
git rev-parse --short HEAD
xcodebuild -version
xcrun --sdk iphonesimulator --show-sdk-version
xcodegen --version
swift --version
node --version
```

Expected: Xcode/iOS SDK 26 or later, Swift 6, XcodeGen 2.42+ (2.46.0 was used for project generation), Node 24+. If a tool or SDK is absent, stop and install it from its official source with the user's approval. Xcode license acceptance, developer-account login, provisioning and new credentials require the user's action/authorization. No service administration website is needed for the source checks.

## 2. Reproduce local checks

```sh
npm ci
npm run typecheck
npm test
node scripts/design/check-design.mjs
swift test --package-path apps/ios --jobs 2
python3 apps/ios/Scripts/verify-source.py
```

Expected: no failing tests; at least the documented 134 Foundation tests pass; design guard reports 24 contrast pairs. The Python check may explicitly skip optional tree-sitter syntax parsing if those packages are absent. That does not substitute for the Apple build below. Never paste session tokens, private exports or credential values into a bug report.

## 3. Generate and build an unsigned Simulator app

```sh
cd apps/ios
test -e Config/Local.private.xcconfig || cp Config/Local.example.xcconfig Config/Local.private.xcconfig
./Scripts/generate-project.sh
xcodebuild -project BibleCompanion.xcodeproj -scheme BibleCompanion \
  -sdk iphonesimulator -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project BibleCompanion.xcodeproj -scheme BibleCompanion -showdestinations
xcrun simctl list devices available
```

Expected: `BUILD SUCCEEDED`, including the embedded Share Extension, with no Swift6 isolation/type errors. The checked-in `.invalid` server is intentional: first launch should clearly say the connection is unconfigured and disable login. Do not enter an API key into this app or its xcconfig.

Choose an available iOS26+ Simulator UUID from the output, then:

```sh
SIMULATOR_ID='PASTE_THE_LISTED_SIMULATOR_UUID'
xcodebuild -project BibleCompanion.xcodeproj -scheme BibleCompanion \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO test
```

Expected: `TEST SUCCEEDED`. Stop and fix any Apple-specific diagnostic; the previous Linux test count is not evidence that this step passes.

## 4. Launch and inspect first-run/accessibility states

Boot the chosen simulator if it is not already booted, then install/launch:

```sh
xcrun simctl boot "$SIMULATOR_ID"
open -a Simulator
xcrun simctl install "$SIMULATOR_ID" DerivedData/Build/Products/Debug-iphonesimulator/BibleCompanion.app
xcrun simctl launch "$SIMULATOR_ID" org.example.BibleCompanion
```

Use the configured bundle ID instead of `org.example.BibleCompanion` if changed. A boot command reporting an already-booted device is harmless; do not erase the Simulator to work around another error.

Check:

- Unconfigured server, signed-out, loading, failed request and genuinely empty history have distinct copy. Unchecked usage does not claim zero.
- Light/dark; the largest accessibility text size; VoiceOver reading order and actionable labels; Reduce Motion/Transparency; increased contrast; landscape and iPad.
- Reading surfaces remain opaque. Toolbars and system controls use native glass. Nothing overlaps the bottom question action or keyboard.
- VoiceOver can read a full book/chapter/verse range, source notices, question scope, errors and retry controls without relying on icons or color.
- English WEB text is labeled English; missing Japanese commentary and unverified JCB alignment are explicit. Missing/empty source coordinates are never replaced with another verse.

Record screenshots and failing steps only after checking they do not contain private questions or account data.

## 5. Connect only to an approved HTTPS environment

This step waits for an already approved, deployed API/RP hostname. A local HTTP Worker is not an iPhone passkey environment. The backend deployment runbook is separate; do not create Cloudflare/AI credentials or deploy merely to satisfy this checklist.

Set `BIBLE_API_URL` in the ignored `Config/Local.private.xcconfig` using xcconfig-safe syntax:

```text
BIBLE_API_URL = https:/$()/YOUR_APPROVED_HOST
```

Rebuild. The user completes real passkey authentication in the system browser. Confirm the callback is `biblecompanion://auth/callback`; never copy tokens into chat. Additional passkey management and lost-passkey recovery are currently unavailable and must remain disclosed.

With an authorized test account, verify:

- Login cancellation during browser and token exchange; retry; locked-device/session restore; logout while offline; cleanup retry after protected-data failure.
- Import one/cross-chapter/multiple ranges; unknown translation confirmation; repeat the same share after termination without duplicate imports.
- Arbitrary subset selection preserves the original reading end. Saved conversation continuation preserves its original scope/spoiler policy.
- Offline overview displays its timestamp and expiry; material tabs ask to reconnect. English scripture/answers are not silently persisted into that public cache.
- Saved-message older pages and English text forward/back pages fail closed on a source-policy change. Backgrounding clears retained private/reference-page bodies.
- AI-disconnected/terms-unreviewed/budget-unavailable models remain unavailable. Do not enable paid inference or transmit a real question just to test a disabled-state screen.
- A material-grounded answer labels commentary separately from scripture. Expand its source disclosure and verify every original reference, attribution and license link remains readable at the largest text size; these summaries must not appear in the offline public overview cache.
- Map detail for the three reviewed sites shows approximate ancient-site placement on a modern map, all source/license credits and textual fallback while offline; no location permission is requested.
- Experimental generation requires the current warning sheet and explicit consent; changing account/policy invalidates a stale sheet. Provider revocation stays revoked after generation revocation. Reviewed selection remains a separate mode; there is no automatic fallback. Test actual inference only after the separate provider/data/budget authorization.
- Estimated free-tier reservations are not labeled verified bounds or actual charges; unknown connection/terms/budget state never becomes “available.”
- Repeated status taps do not replace a newer terminal/hidden answer with an older response. Changing reading scope clears old comparison bodies; resuming a pending comparison keeps its original passage label after completion. A failed new budget plan cannot reuse the previous confirmation.
- Reject a deletion for expired recent authentication while an offline overview is visible; the cancelled display must not survive without expiry, and explicitly reopening the reading must still reuse a valid cache.
- Export cancel/share/dismiss on iPhone and iPad, including rotation; only a complete file is shareable and temporary files are removed afterward.

Destructive deletion tests require a disposable test account and explicit approval for the actual deletion. Confirm both typed confirmation and final destructive dialog; expired recent auth must require a fresh login and a new confirmation. Do not run this against the user's real history by default.

## 6. Physical signing and SideStore gate

Wait for the user to choose their existing signing team, bundle IDs and supported installation method. Do not create signing credentials, grant persistent access, accept account agreements, change permissions or use automatic provisioning on their behalf without the required authorization.

The app and `.Share` extension must retain the same real App Group. A signing/sideloading method that removes that entitlement cannot be described as supporting the Share Extension. Manual chapter/text import must still work, while the app explains the unavailable share queue.

After the authorized signer produces an `.app`, inspect it locally:

```sh
APP_PATH='/absolute/path/to/BibleCompanion.app'
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign -d --entitlements :- "$APP_PATH"
codesign -d --entitlements :- "$APP_PATH/PlugIns/BibleShare.appex"
```

Expected: valid signatures and matching `com.apple.security.application-groups` values on both targets. Inspection alone does not prove App Group operation after SideStore re-signing. On the installed iPhone, actually share from YouVersion, close/reopen the app, lock/unlock, and verify queue ownership/expiry. Do not bypass iOS security warnings or add a VPN/trust profile to work around an unsupported signing setup.

## Completion record

Record the commit, Xcode/iOS/device versions, build/test result, and each failed/manual gate. A signed IPA, passkey success, App Group delivery, accessibility quality or SideStore compatibility is established only after that exact step succeeds on the target environment.
