# Durable owner comparison protocol

Comparison is opt-in, owner-only, and sequential. No remote AI binding, model terms approval, or genuine budget proof is configured by this repository.

1. POST `/v1/developer/comparisons/plan` with the frozen plan. At most two distinct model+answer-mode combinations and ten questions are accepted. Strict-proof mode reserves against each model's verified full bound and checks actual prepared input again before dispatch. Free-provider-hard-stop mode prepares each question/model/mode input, uses its conservative input estimate and output cap with an explicit estimate margin, and binds that exact reservation to the plan. The same prepared estimate must match at dispatch. Source policy, prompt/catalog/consent policy and receipt identities are bound; changes require a new plan. Neither path claims measured provider Neurons. Plans exceeding configured or remaining daily allowance are rejected before a job is created; choose fewer trials or lower output, or obtain an explicitly reviewed operator allowance change.
2. Persist the owner ID, request UUID, exact plan and confirmation hash privately before POST `/v1/developer/comparisons`. A new job returns 202 and performs no inference. Identical start replay returns 200 with its state.
3. POST `/v1/developer/comparisons/{id}/steps` with the original plan, confirmation hash and the current `trialIndex`. A request claims at most one trial. Only the first queued trial after completed predecessors can be claimed. The provider timeout is at most 30 seconds; its durable lease is 90 seconds.
4. Advance only after an acknowledged step. On uncertain transport, stop and reconcile by GET. A delayed request can still arrive after a GET reports ready or404. Resume only the same frozen index; an atomic claim prevents two invocations. Do not substitute a new UUID to conceal an uncertain outcome.
5. DELETE records an owner-scoped durable cancellation even before start. GET then returns a terminal zero-trial state with `errorCode: cancelled_before_start`. GET `/active` can locate an active server job if the local plan was lost; without that plan the client can cancel, not reconstruct private unsaved questions.

## Response state

`ComparisonState` contains requestId, status, phase, saved, trialCount, completedCount, nextTrialIndex, activeTrialIndex, expiresAt, trials, results and errorCode. Terminal statuses are complete, cancelled, failed and expired. Active phases are preparing, ready and executing.

Each trial contains index, questionIndex, modelIndex, modelId, status, reservedBudgetUnits, modelInvoked (nullable), usageUnknown and leaseExpiresAt. Queued/running/complete/failed/cancelled are trial states. A step response contains state, trialIndex, result, replayed and resultAvailability.

Saved results have `{questions, results:[{questionIndex,modelIndex,result}], sourcePolicyVersion}` and are projected through current citation rights/version policy on every read. Unsaved answers are returned only in the successful step response. An acknowledged completed trial is never invoked again just to reconstruct its unsaved body; replay returns null with `resultAvailability: not_saved`. No unsaved question or answer text is persisted in the server ledger. Local frozen recovery plans remain private user data and are cleared with their account context.

## Accounting and interruption

The entire confirmed allowance is reserved once. Each trial has an independent dispatch marker. Completion, cancellation, deletion and expiry settle only marked trials; never-started trials release their allowance. A marked trial interrupted before a trustworthy provider result retains its full bound, because usage cannot be measured reliably. Actual Neurons remain unknown, not zero.

An idle job expires after 15 minutes or at the next UTC budget boundary, whichever comes first. An expired running lease becomes failed and is never retried automatically. Lazy cleanup runs during comparison requests, so correctness does not depend on enabling a cron trigger. Scheduled cleanup can reclaim abandoned jobs after deployment configuration is explicitly approved.

Every dispatch checks current consent, source-policy epoch, exact stored proof identity and expiry, request cancellation, lease ownership and model authorization. Queued trials also bind the registry, prompt and model-terms policy versions; a changed deployment fails the old plan before another invocation. Completed-trial replay remains readable under current source rights without re-inference. Current model terms approvals are version-bound request configuration; replacing a deployment does not retroactively revoke already-running older isolates. Immediate fleet-wide terms revocation would require a durable policy epoch before live service is enabled.

Trial responses are bounded to40,000bytes. At most20 stored trial bodies plus the64KiB bounded plan fit within the1MB export-entity bound and below D1's2MB row limit. A larger result fails explicitly without truncation and retains any dispatched allowance. No Queues, automatic retries, indefinite `waitUntil` job, or paid background infrastructure is used.
