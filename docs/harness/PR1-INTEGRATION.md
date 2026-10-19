# PR #1 integration plan

- Goal: merge the portable harness after verifying current main, without changing the app, data, distribution versions or feeds.
- Baseline: PR d52eeeed9b8538bb5fe063347cc63205a1699cbb; main 844005c93ba7d89acd2a47a9a34f852d364ccacd (0.1.23/build 24). Worktree `harness-pr1-local`, branch `review/pr1-integration`.
- [x] Merge main and review the complete 32-file harness diff.
- [x] Reproduce missing per-target resource detection (two failing mutation tests); require resources in both app and Share Extension.
- [x] Verify Node 24/API/core, all Swift tests, unsigned build and current native UI; record full hosted UI failure.
- [x] Resolve only observed integration defects; preserve all product assertions and all 43 artwork records.
- [x] Run exact-head hosted Linux/macOS CI: Linux passed; macOS completed with 32 of 98 UI cases failing.
- [ ] BLOCKED: merge only after current UI contracts and CI share-artwork selection are repaired and both exact-head gates pass; then run both workflows on the merge commit.
- [x] Record results in HANDOFF; no release/deploy/feed writes.

Recovery: retain ignored `.cache/harness` results and adjacent `harness-pr1-evidence`. Inspect the failed assertion before rerunning. Use only the task-owned Simulator recorded there; never erase another device. No private xcconfig or signing account is needed.

2026-10-19: common checks and Swift 289/289 passed; unsigned build and all 168 resource pairs passed. Reproduced unsigned account restoration failure; UI-only ad-hoc signing is under native regression verification. Full hosted UI checks remain required before merge.

Final checkpoint: macOS completed all cases (66 passed / 32 failed; 62 assertion failures), not a hang or timeout. Local iPhone Air repeated all three artwork tests successfully and reproduced the obsolete home-title/settings expectations. Tests were not skipped or weakened. See HANDOFF for exact CI links and the remaining merge gate.

## Authorized contract migration continuation

All 32 failures are being reviewed against current main. Preserve all 98 cases and production source/data; replace retired first-party share/AI-setup assertions with current external handoff, full draft retention, provider persistence, and no false streaming/readiness. Main/Core legacy stream coverage stays. Update entity profile navigation/source/map assertions without changing canonical IDs or aliases. Fix lazy-menu/composer visibility mechanics. Pin the screenshot fixture model and log model/runtime; diagnose artwork selection on CI separately before the full gate. No failure exclusions or automatic retry.

## Resume checkpoint

The native formal gate has now been run again: build/resource verification passed; Core 289/290 passed with URL-only missingBody as the single failure. All 98 UI methods remain, but the fail-fast formal command correctly never started them. No full-suite success or merge is claimed. Current production trees and releases/assets are unchanged. See HANDOFF for the exact product blocker, verified diagnostics and required scope decision.
