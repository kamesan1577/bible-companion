# Execution plan template

Use for a task that spans sessions; keep this document in the branch. No plan is required for a small obvious fix.

- Goal and observable acceptance: describe what a user can do after the change.
- Scope/invariants: affected files; reading boundary, identity, rights and privacy constraints.
- Baseline: exact commit, toolchain, relevant reproducer and current failing/passing result.
- Small steps: checkboxes with one independently testable behavior per step.
- Progress/decisions: timestamp, completed step, evidence path, design reason, unresolved questions.
- Recovery: exact checkout/branch, job root, failed step, inputs/hashes, safe rerun command; preserve accepted outputs.
- Acceptance evidence: actual commands and results, UI/source comparisons, remaining manual prerequisites.
- Handoff: next action without needing a conversation, and what must not be overwritten.
