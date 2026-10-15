# Independent development and verification

This checkout is sufficient for development by a person or another AI. Start with `AGENTS.md`; the code, tests and linked documents define behavior. Prior conversations and a particular AI application are not dependencies.

## Clean setup

Clone `https://github.com/kamesan1577/bible-companion`, create your own branch, then run from its root:

```sh
make doctor
make setup
make check
make source-audit
```

Use Node **24 LTS** (`.node-version` / `.nvmrc`), its bundled npm, Python 3.9+, Git, and Make. `make setup` runs `npm ci` against the committed lockfile; it needs registry access once. It does not install global tools, configure credentials, migrate remote databases, or contact an AI. On a managed machine put these tools on PATH first. `make doctor` fails with an actionable message when prerequisites are absent. Normal tests require no environment variables; `.env.example` lists optional configuration names without values.

`make check` runs the existing full API/core validation, deterministic data and checkpoint tests, generated OpenAPI drift check, two local migration applications (idempotence), configuration validation and Worker dry-run build. The existing SQLite/Workers runtime tests execute actual migrations and worker behavior. No Cloudflare testing framework migration is needed to keep these working. `npm audit --audit-level=high` is a separate network-dependent dependency check, also retained in CI.

On macOS use full Xcode 26+ with the iOS 26+ SDK and an already-installed runtime, Swift 6+, and XcodeGen 2.42+. Select the existing installation with `DEVELOPER_DIR` if necessary. Xcode first-launch/license/toolchain installation is a machine setup prerequisite, not part of the harness. On Linux, `make swift` needs a compatible Swift 6 toolchain; the native app/UI commands need macOS.

```sh
make swift       # all Foundation core tests, including identity/spoiler/coordinate tests
make build       # unsigned simulator app including BibleShare.appex
make ios-ui      # core simulator tests AND all actual UI regression tests
# Optional: choose an existing simulator; does not erase/create a device
python3 scripts/harness/run.py ios-ui --device SIMULATOR_UUID
```

A fresh clone needs **no private xcconfig** for unsigned testing. The safe checked-in `.invalid` endpoint and existing QA fixtures are intentional. `make build` / `make ios-ui` reject a private override to avoid silently testing someone else's server. Signed-device development instead follows [Mac acceptance](../../apps/ios/MAC-ACCEPTANCE.md) using an existing identity and private xcconfig. Never commit it.

The harness uses ignored `.cache/harness/` for build products, timestamped `.xcresult` bundles and simulator inventory. XCTest screenshots use `keepAlways` and remain in the UI result bundle, including successful assertions. Vitest and native builds cap worker concurrency at two to keep clean local runs within a laptop’s resource budget; test timeouts and assertions are unchanged. A failure stops the command; rerun only after inspecting the failed test/result. The UI command runs all `ReadingInteractionUI` tests, including real share-sheet extension presentation, repeated dismiss/return, recovery, people/place tabs, MapKit, Wikipedia/provenance, reading pages, keyboard and spoiler consent. These use existing local fixtures; they do not invoke a model. See [UI evidence and acceptance](UI.md) for the remaining visual/device checks.

## Parallel work and acceptance

Create a distinct clone or Git worktree per task. Do not reuse another worker's branch, `.cache`, simulator run or data job root. Keep data generation and app/harness changes in separate PRs. Fetch the latest main before publishing, inspect conflicts, and integrate deliberately; never force-push main. Harness-only changes must not regenerate `data/`, bundled resources, marketing/build versions or distribution feeds.

A small fix needs a reproducer, implementation and relevant tests. A longer task copies [PLAN.md](PLAN.md), keeps progress and recovery instructions current, and records actual evidence in [HANDOFF.md](HANDOFF.md). Passing deterministic tests is necessary but does not prove prose truth or pixel quality. Use [DATA.md](DATA.md) for semantic evaluation and [OPERATIONS.md](OPERATIONS.md) for recovery/distribution. Report failures and unexecuted gates explicitly.

## CI and cost

The existing Linux and macOS workflows remain **manual dispatch**: do not silently enable hosted runner or artifact costs. They have read-only repository permissions and pinned action commits. Linux uses `make check` and source audit. macOS builds both targets and runs core plus `ReadingInteractionUI` tests. Artifact upload remains opt-in with one-day retention. Dispatch only under an existing allowed Actions quota; local commands are the same verification path. A submitted PR does not imply that hosted CI ran.

## Sources and design decisions

Read-only reference: [kamelog](https://github.com/kamesan1577/kamelog/tree/0b2cb4d53c8ffa11131be859776cf8c2487e7ae6), especially AGENTS.md, Makefile, CI and HANDOFF.md. Reused the concise entrypoint, one check command, actual UI evidence, public-data hygiene, and honest verification status; did not import its web/FFmpeg/container dependencies or modify that repository.

Official guidance reviewed 2026-10-16: [OpenAI harness engineering](https://openai.com/index/harness-engineering/) supports a short repository map and executable constraints; [ExecPlans](https://developers.openai.com/cookbook/articles/codex_exec_plans) supports self-contained progress and recovery notes; [Anthropic long-running harnesses](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) supports small tasks with persistent progress; [Apple XCTest attachments](https://developer.apple.com/documentation/xctest/adding-attachments-to-tests-activities-and-issues) supports preserved evidence; [GitHub secure use](https://docs.github.com/en/actions/reference/security/secure-use) supports minimal permissions and pinned dependencies. These inform this small harness, not a new framework or claim of automatic correctness.
