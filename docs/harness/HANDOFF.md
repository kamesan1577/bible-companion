# Harness handoff

## Restart here

PR: https://github.com/kamesan1577/bible-companion/pull/1
Branch: `codex/portable-development-harness`. Read AGENTS.md, then README.md in this directory. Use `make doctor`, `make setup`, `make check`; on an existing Apple toolchain use `make swift`, `make build`, `make ios-ui`, `make ios-device`. No dots account, chat history, AI provider credential or production service is required. Generation remains optional and uses existing subscription tools plus recorded independent review.

Baseline is `d0888b4f3b484967a193b31f6a8158ca9f26a323` / v0.1.10-preview.1. The ordinary Git tree contains the app, extension, API, packages, data witnesses, tests and job tools; source is not confined to Release ZIPs. XcodeGen regenerates the project from tracked project.yml. Read-only kamelog reference: `0b2cb4d53c8ffa11131be859776cf8c2487e7ae6` (AGENTS, Makefile, CI, HANDOFF); kamelog was not changed.

## Scope and concurrent work

This PR adds a small shared instruction map, common stdlib runner/Make commands, Node 24 selection, data mutation gates, artifact verification, atomic checkpoint saves, owned Simulator provisioning, CI and setup/data/UI/recovery guides. Existing tests and job/review formats are reused. No new dependency, model API, deployment, credential, release version/build or feed change is introduced.

Main advanced to `80733e72ecd418ac49db4a58d0c115d5ffadcb09` with Romans/Leviticus. A read-only source audit also passed on that main tree (1,174 tracked files). Those data/product changes are not included in this branch. Its upstream UI selector/scroll corrections are preserved; harness diagnostics are additive. A local virtual merge has no conflicts. Re-run gates on the eventual combined commit: Acts-only harness evidence does not certify newly merged books. A proposed local merge of main was rejected by automatic approval review because it included parallel data/version changes; it was removed before push. No data/resource/release/project-version paths differ from the original baseline in this branch.

## Verified evidence

A fresh independent clone used `npm ci`, without copied dependencies/private configuration. Tools: Node 24.22.0 / npm 11.19.1, Python 3.14.3 (structural tests also passed with system Python 3.9), Xcode 26.0.1 / iOS SDK 26.0, XcodeGen 2.44.1. Outputs below are ignored local evidence, not committed private logs.

- `make check`: passed on `544da98`; 628 API/package tests, 123 Node integration/contract tests, local database backup/restore/import/runtime checks, OpenAPI drift, migrations twice, configuration validation and Worker dry-run. No live AI/remote D1.
- `make data`: 50 tests passed: jobs 12, contexts 5, reviews 5, primary alignment 5, mutation/artifact/checkpoint 14, simulator helpers 9. Structural Acts check: 225 profiles, 1,506 sources, 1,921 occurrences. These are structural checks, not new semantic review.
- `make swift`: 180 passed. Simulator core: 180 passed. `make build`: generic arm64/x86_64 build passed with Share Extension and all 142 bundled data/license resource hashes matching.
- Owned fresh-device `make ios-ui` on `aa9918b`: core 180/180 and UI 18/18, zero failures/skips. Result `.cache/harness/ios-ui-20261015T202652771830Z/ReadingInteractionUI.xcresult`; device `5DD88513-BE9E-4122-A6FE-9CD829E6FBEE` was deleted afterward. No peer device is targeted by the default harness.
- Earlier successful UI run exported 51 screenshot attachments under `.cache/harness/ui-attachments/`. Five representative views were inspected: actual shared Apollos detail, Alexandria and Corinth MapKit, keyboard/send, Wikipedia/primary-source disclosure. Text, map tiles, uncertainty/rights notices and controls were visible in those viewports; this is bounded visual evidence.
- `make ios-device`: unsigned Release iPhoneOS IPA `.cache/harness/ios-device-20261015T203843703079Z/BibleCompanion-unsigned.ipa`; SHA256 `c551e8600edc550ea83f82daab7fe41052ebcd7c6683954f5ccc7b86fdf4e570`. Version 0.1.10/build 11 unchanged; embedded Share Extension and 142 resources verified. Signing/device installation is not established.
- `make source-audit` on `00989f0b501741ae6e5fbdfc8f917f7bc95d21d9`: 943 tracked files, source present in Git. Exact export `/tmp/bible-harness-source-final/`; archive SHA256 `e393cb644796a276bea546fd6478e5e4c21eb34c0b2e9a70aa9f55595f5b8942`. Archive and all 943 member hashes independently matched its manifest.
- Linux CI [38804364352](https://github.com/kamesan1577/bible-companion/actions/runs/38804364352) passed on `544da98`, including dependency audit (zero vulnerabilities).

## Final UI follow-up

The first hosted macOS run built and passed core 180, but failed two initial-share cases (16/18 passed). A separate cold local device passed those cases; the hosted failure was not claimed reproduced locally. Dedicated boot/install provisioning then reduced hosted failures to one: the initial share destination selector used a display name as a cell identifier. On iOS 26.3 the cell is `shareCell`; upstream main already corrects it to the visible extension label. This branch preserves that exact correction and its screenshot attachment. No case is skipped or automatically retried.

A local UUID-case regression was caught and fixed with a failing-then-passing test; Xcode destination matching requires simctl's original spelling. The known-bad run was cancelled. Another hosted build stalled and was cancelled; its logs were unavailable, so no compiler root cause is asserted. CI now runs the exact locally verified `make ios-ui`, with bounded boot/build/core/UI commands and its own device cleanup, instead of duplicated setup. Public standard runners are used; artifact upload is optional and was disabled. No billing/storage setting changed.

Latest selector-aligned local UI passed on `00989f0`: core 180/180, UI 18/18, zero skipped/failed; `.cache/harness/ios-ui-20261015T211703511805Z/ReadingInteractionUI.xcresult`. All 54 attachments were exported under `.cache/harness/ui-final-attachments/`; the actual share destination, Apollos disclosure and Alexandria map were inspected again. Only owned device `3CC70549-F520-4E78-8543-DEEB2A33AD10` was deleted; its absence was verified. Hosted runs both passed: Linux [38808705921](https://github.com/kamesan1577/bible-companion/actions/runs/38808705921), macOS [38808663838](https://github.com/kamesan1577/bible-companion/actions/runs/38808663838) on `6284469`. `00989f0` only removes a failure diagnostic adjacent to the upstream block to avoid a merge conflict; expectations and behavior are identical.

## Remaining manual prerequisites

Signed real-iPhone YouVersion sharing, App Group delivery after re-signing, browser passkeys, final SideStore installation, full text-size/accessibility/light/dark inspection and production backup restoration remain manual gates with existing authorized accounts/devices. No release/deployment was performed. Newly generated data needs independent source/identity/verse/rights/Wikipedia/spoiler/coordinate evaluation under DATA.md; structural success alone is insufficient. A release worker must validate the exact combined commit and final signed artifact rather than reuse these branch-only results.

The final documentation smoke check exposed a direct-script UTF-8 decoding failure in macOS system Python 3.9 despite imported tests passing. `70e89c9` adds an explicit UTF-8 declaration and a direct `--help` regression. System Python 3.9 passed all 15 harness tests and 12 job tests; Python 3.14 also passed the 15 harness tests. No job schema, model, source packet or generation output changed. The data/test gate now totals 51 tests. Linux CI [38809800147](https://github.com/kamesan1577/bible-companion/actions/runs/38809800147) passed on `70e89c9`, including the complete common check, source audit and dependency audit.

Final hosted macOS acceptance: [38808663838](https://github.com/kamesan1577/bible-companion/actions/runs/38808663838) succeeded on `6284469` with Xcode 26.3: build, embedded extension and 142 resource checks passed; core 180/180 and UI 18/18 passed, zero failures. Both previously failing share cases passed. Artifact upload was intentionally skipped, not any test. Later executable differences are the failure-diagnostic removal (locally tested native suite) and UTF-8 startup fix (latest successful Linux full gate); remaining edits are documentation/comments. PR is reviewable, not merged or released. Re-run on the eventual combined main commit before publishing.
