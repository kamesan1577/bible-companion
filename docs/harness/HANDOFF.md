# Harness handoff

## Scope and baseline

Baseline: Bible Companion `d0888b4f3b484967a193b31f6a8158ca9f26a323` (v0.1.10-preview.1). Audit of fetched `origin/main` found the full source in its ordinary Git tree, including native app/extension, API, packages, tests, data witnesses and checkpoint tools; Release ZIPs are not the only source. The generated Xcode project is intentionally replaced by tracked `project.yml` plus XcodeGen. No node_modules, signing identity, private configuration or conversation memory is required as source.

Reference inspected read-only: kamelog `0b2cb4d53c8ffa11131be859776cf8c2487e7ae6` (AGENTS, Makefile, CI, HANDOFF). No files in kamelog were changed.

This branch adds a concise shared AGENTS/CLAUDE entrypoint, stdlib-only common runner/Make commands, Node 24 selection, data mutation checks, native artifact verification, detailed setup/data/UI/recovery guides and manual CI integration. Existing generation checkpoints are reused; JSON saves now use flush/fsync + atomic replace with an interruption regression test. Member invitation documentation matches the one-hour implementation and has an explicit role/expiry regression.

## Concurrent work

Use `codex/portable-development-harness` separately from data work. No bundled JSON, data generation output, release version/build number or feed is changed. Do not overwrite Romans/Leviticus work or force-push main. Re-run all relevant gates after those data changes merge; current Acts evidence cannot certify another book.

## Verification

Results are recorded here before PR publication. Local outputs live under ignored `.cache/harness/`; no private logs or device exports are committed. A fresh independent Git clone received dependencies with `npm ci`, not copied node_modules. Node 24.22.0 / npm 11.19.1, Python 3.14.3, Xcode 26.0.1 / iOS SDK 26.0, XcodeGen 2.44.1 were used. The Python structural/checkpoint gate also ran with the system Python 3.9.

- Setup/doctor: passed; no credentials or live AI.
- Data structural gate: 225 profiles / 1,506 sources / 1,921 occurrences passed. This is not a new semantic review.
- Checkpoint/context/review/primary-alignment suites: 12 + 5 + 5 + 5 passed before the atomic-write addition; final combined results follow below.
- Full portable check, Swift, app/UI and artifact checks: running; replace this status with exact final results before publishing.

## Remaining manual prerequisites

Hosted CI remains manual and is not dispatched by this task; use existing allowed quota if chosen. No runner billing or storage setting is changed. Real signed-iPhone YouVersion sharing, App Group delivery after re-signing, browser passkeys, accessibility/light/dark visual acceptance, production backup restoration and final SideStore installation remain separate evidence gates. No release or deployment is performed. A different AI can operate the local job CLI; actual generation still requires an already-authorized subscription assistant and independent source comparison.

## Next action

Read the harness guide, `make doctor`, then reproduce the relevant gate. For a new feature use a new branch; for new book data follow DATA.md and preserve per-item evidence/checkpoints. For a release verify its exact combined commit and artifact with OPERATIONS.md rather than reusing this branch's results.
