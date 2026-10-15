# Harness handoff

## Scope and baseline

Baseline: Bible Companion `d0888b4f3b484967a193b31f6a8158ca9f26a323` (v0.1.10-preview.1). Audit of fetched `origin/main` found the full source in its ordinary Git tree, including native app/extension, API, packages, tests, data witnesses and checkpoint tools; Release ZIPs are not the only source. The generated Xcode project is intentionally replaced by tracked `project.yml` plus XcodeGen. No node_modules, signing identity, private configuration or conversation memory is required as source.

Reference inspected read-only: kamelog `0b2cb4d53c8ffa11131be859776cf8c2487e7ae6` (AGENTS, Makefile, CI, HANDOFF). No files in kamelog were changed.

This branch adds a concise shared AGENTS/CLAUDE entrypoint, stdlib-only common runner/Make commands, Node 24 selection, data mutation checks, native artifact verification, detailed setup/data/UI/recovery guides and manual CI integration. Existing generation checkpoints are reused; JSON saves now use flush/fsync + atomic replace with an interruption regression test. Member invitation documentation matches the one-hour implementation and has an explicit role/expiry regression.

## Concurrent work

Use `codex/portable-development-harness` separately from data work. No bundled JSON, data generation output, release version/build number or feed is changed. Do not overwrite Romans/Leviticus work or force-push main. Re-run all relevant gates after those data changes merge; current Acts evidence cannot certify another book.

## Verification

Results are recorded for draft PR #1 and refined before final handoff. Local outputs live under ignored `.cache/harness/`; no private logs or device exports are committed. A fresh independent Git clone received dependencies with `npm ci`, not copied node_modules. Node 24.22.0 / npm 11.19.1, Python 3.14.3, Xcode 26.0.1 / iOS SDK 26.0, XcodeGen 2.44.1 were used. The Python structural/checkpoint gate also ran with the system Python 3.9.

- Setup/doctor: passed; no credentials or live AI.
- Data structural gate: 225 profiles / 1,506 sources / 1,921 occurrences passed. This is not a new semantic review.
- `make check`: passed after reconnection, including 628 API/package tests, 123 Node integration/contract tests, data/checkpoint suites, OpenAPI drift, two local migrations, configuration validation and Worker dry-run. No live AI or remote D1 was used.
- `make data` (included in check): 50 tests passed (12 jobs, 5 contexts, 5 reviews, 5 primary alignment, 14 harness mutation/artifact/checkpoint, 9 simulator selection/ownership).
- `make swift`: 180 tests passed, zero failures on macOS.
- iOS Simulator core scheme: 180 tests passed, zero failures on iOS 26.0.
- `make build`: passed after reconnection (generic Simulator build, including arm64/x86_64); Share Extension present and all 142 bundled resource/license files match this checkout.
- `npm audit --audit-level=high`: zero vulnerabilities.
- Source export at implementation commit `40a249eae91a07eb1c788cc9b7320d31f906fa39`: 941 files, archive SHA256 `ab6a53930aa5b9c7ba6149f6464d4cc274475ed822cd93413dea251aa49a1dae`; archive and every member hash independently matched the manifest. Later harness refinements are in the Git branch, not that earlier export.
- `make ios-device`: passed; unsigned Release iPhoneOS IPA generated, Share Extension and all 142 data/license resources verified, version 0.1.10/build 11 unchanged. IPA SHA256: `5d0688f17dc0a5736e31fe33ae9124001f420007b816b0bde89c7f44a1f6f298`. Local candidate: `.cache/harness/ios-device-20261015T195315549261Z/BibleCompanion-unsigned.ipa`. No signing/installation acceptance is implied.
- Linux CI: [run 38797426027](https://github.com/kamesan1577/bible-companion/actions/runs/38797426027) passed on implementation commit `0c1c85e3cb7214e3eeeb000e69fceb45f82b4bc5`.
- `make ios-ui`: passed after reconnection: iOS Simulator core 180/180 and UI 18/18, zero failures/skips. UI result: `.cache/harness/ios-ui-20261015T195258763030Z/ReadingInteractionUI.xcresult` (iPhone 17 Pro, iOS 26.0). Exported 51 preserved screenshot attachments under `.cache/harness/ui-attachments/`.
- Inspected five representative screenshots: actual shared Apollos details, shared Alexandria MapKit, Corinth MapKit, keyboard/send visibility, and Wikipedia/primary-source disclosure. Text, loaded map tiles, uncertainty/source notices and controls were visible in these captured viewports; this is not complete accessibility, dark-mode or physical-device acceptance.
- First macOS CI [38797430496](https://github.com/kamesan1577/bible-companion/actions/runs/38797430496): build/resource checks and core 180 passed; UI ran all 18, with two failing initial-share cases (six assertions) and 16 passing cases. This is a failed run, not acceptance. The initial destination was absent and the next extension view did not become available. Dedicated-device provisioning and explicit boot/install setup are being verified; assertions and timeouts are unchanged.

Initial attempts exposed environment limits: sandboxed local socket denial, unbounded Vitest worker contention, macOS symlinked system temp ancestors rejected by operator safety checks, and a 60-second D1 migration timeout while several clean builds/export processes ran concurrently. The harness now caps Vitest/native build concurrency at two, uses resolved checkout-local test scratch space and preserves assertions/timeouts. Failed attempts are not counted as successful checks; the final full run determines acceptance.

## Remaining manual prerequisites

Hosted CI remains manual. The existing public-repository standard-runner workflows were dispatched on the PR branch with artifact upload disabled; final run links/results are recorded below. No runner billing or storage setting is changed. Real signed-iPhone YouVersion sharing, App Group delivery after re-signing, browser passkeys, accessibility/light/dark visual acceptance, production backup restoration and final SideStore installation remain separate evidence gates. No release or deployment is performed. A different AI can operate the local job CLI; actual generation still requires an already-authorized subscription assistant and independent source comparison.

## Next action

Read the harness guide, `make doctor`, then reproduce the relevant gate. For a new feature use a new branch; for new book data follow DATA.md and preserve per-item evidence/checkpoints. For a release verify its exact combined commit and artifact with OPERATIONS.md rather than reusing this branch's results.

## Follow-up isolation validation

The first hosted macOS run failed two initial-share cases despite 18/18 passing on the retained local device. A separate empty local device passed the two cases; the CI-only difference was not declared reproduced locally. The harness now creates its own device, waits for boot/migration completion and explicitly installs the containing app before XCTest. It retains the original assertions/timeouts and logs the accessibility hierarchy on share failure.

A subsequent local run caught that lowercasing simctl’s UUID breaks Xcode destination matching. The regression test failed before the fix and passed afterward; `aa9918b` preserves the emitted UUID spelling. The known-bad hosted run was cancelled, not counted as passing. Linux CI [38802043786](https://github.com/kamesan1577/bible-companion/actions/runs/38802043786) passed on this corrected implementation. Hosted macOS [38802047517](https://github.com/kamesan1577/bible-companion/actions/runs/38802047517) and the fully owned local run are being confirmed.

The next hosted attempt remained in its separate generic build beyond the 12-minute step bound without reaching Simulator creation; it was not counted as passing. macOS CI now invokes the exact locally verified `make ios-ui` path instead of duplicating build/boot/install/test steps. This boots the owned device before building, caps build concurrency at two and preserves the 5/12/10/20-minute boot/build/core/UI bounds. Native doctor no longer requires unrelated Node/npm tools. No XCTest wait or assertion was relaxed.
