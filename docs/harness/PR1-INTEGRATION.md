# PR #1 integration plan

- Goal: merge the portable harness after verifying current main, without changing the app, data, distribution versions or feeds.
- Baseline: PR d52eeeed9b8538bb5fe063347cc63205a1699cbb; main 844005c93ba7d89acd2a47a9a34f852d364ccacd (0.1.23/build 24). Worktree `harness-pr1-local`, branch `review/pr1-integration`.
- [x] Merge main and review the complete 32-file harness diff.
- [x] Reproduce missing per-target resource detection (two failing mutation tests); require resources in both app and Share Extension.
- [ ] Verify Node 24/API/core, all Swift tests, unsigned build and current native UI.
- [x] Resolve only observed integration defects; preserve all product assertions and all 43 artwork records.
- [ ] Run exact-head hosted Linux/macOS CI, merge if successful, then run both workflows on the merge commit.
- [ ] Record results in HANDOFF; no release/deploy/feed writes.

Recovery: retain ignored `.cache/harness` results and adjacent `harness-pr1-evidence`. Inspect the failed assertion before rerunning. Use only the task-owned Simulator recorded there; never erase another device. No private xcconfig or signing account is needed.

2026-10-19: common checks and Swift 289/289 passed; unsigned build and all 168 resource pairs passed. Reproduced unsigned account restoration failure; UI-only ad-hoc signing is under native regression verification. Full hosted UI checks remain required before merge.
