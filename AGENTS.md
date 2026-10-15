# Bible Companion development map

This repository is the source of truth. No dots account, conversation memory, or live AI is needed to build and test.

1. Read [the harness guide](docs/harness/README.md), [architecture](docs/ARCHITECTURE.md), and [handoff](docs/harness/HANDOFF.md).
2. Read the relevant [design contracts](docs/design/README.md), [acceptance map](docs/acceptance-status.md), or [data evaluation guide](docs/harness/DATA.md).
3. Use `make doctor`, `make setup`, `make check`; on a Mac also `make swift`, `make build`, `make ios-ui`. See the guide for toolchains and evidence.
4. Work on a separate branch/checkout. Keep changes small; reproduce bugs before fixing them. Do not hide failures with skips, retries, or snapshot replacement.
5. Preserve reading boundaries, same-name identity distinctions, source/license attribution, account isolation, and offline operation. Use existing native UI and tests.
6. Keep drafts/checkpoints in ignored `.cache/`; reviewed bundled resources are a separate publication step. Never run data generators merely to validate a harness change.
7. Do not commit secrets, private configs, accounts, personal text, signing assets, device exports, logs, or local job databases. Examples contain names only. Check staged diffs and `make source-audit` before publishing.
8. Record exact commands, results, unresolved limitations, and next steps in the handoff. Complex tasks use [the plan template](docs/harness/PLAN.md); small fixes need no new process.
9. Do not deploy, change billing/permissions, invoke paid models, or alter release versions/feeds as a side effect of verification. Existing subscription tools are optional generation adapters, never a test dependency.
