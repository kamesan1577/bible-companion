# 履歴：契約証明ゲート撤去前の手順（現行運用には適用しない）

2026-10-15にFree運用の契約証明・Mac更新依存は撤去した。以下は過去の手順の保存であり、証明更新やスロット切替を通常利用のために実行しない。現行手順はdocs/operator-activation.mdを参照。

# Operator activation: local preparation, explicit future apply

Status: implementation and mocked tests only. No deployment, remote D1 mutation, real model inference, private GitHub creation, credential creation or new permissions have been performed by this workflow. An operator receipt is an attestation backed by retained evidence, not a provider-signed assertion or independently verified billing guarantee.

## 1. Reproduce the safe local baseline

Use Node 24+, the checked-in lockfile and existing repository checkout:

```sh
npm ci
npm run validate
node --test scripts/operator.test.mjs
npm run migrate
npm run infra -- invite-local --role owner
npm run dev
```

The existing local invitation route is for localhost and local D1 only. It does not register a production owner. Do not send that token to another service. The default config has no AI binding, no inference permission and no paid fallback. No R2, Queues or paid service is provisioned.

The new operator CLI does not log in, create credentials, accept terms, create a D1 database, buy a domain or change billing. A future authorized operator must have an existing account, existing `bible-companion` D1 database and a stable domain under that account. If those do not exist, stop for the corresponding setup/permission rather than substituting IDs. `prepare` itself needs none of those connections; it only validates entered identifiers.

## 2. Create a genuinely pending profile

```sh
node scripts/operator.mjs template --out .cache/operator/staging.json
```

This creates an exclusive, mode-0600 file under a mode-0700 directory. It contains 22 distinct model terms entries, all pending, and no receipt, connected models, accepted agreements or example credential. Placeholder account/domain/database values intentionally fail validation. Replace only those with the actual reviewed account ID, D1 ID, origin and RP ID. The profile is strict: arbitrary credential fields, unknown providers, arbitrary URLs, paid routes and unrecognized fields are rejected.

Use a stable HTTPS origin without a port, preferably exactly matching RP ID, for example an operator-controlled staging subdomain. Passkeys bind to RP ID. Changing it later may require new passkey registration. A production-profile test subdomain is a staging destination, not localhost. Deployment creates/updates the exact custom-domain route named by that origin. Domain ownership, DNS readiness, WebAuthn on-device operation and the actual callback must still be verified externally.

Leave `modelIds: []`, `freeReceipt: null`, the curated answer mode and pending terms as-is for an auth-only deployment. `defaultModelId` may remain the catalog default; it grants no inference authority.

```sh
node scripts/operator.mjs plan --profile .cache/operator/staging.json
node scripts/operator.mjs validate --profile .cache/operator/staging.json
node scripts/operator.mjs prepare --profile .cache/operator/staging.json
npm run deploy:dry-run
```

The first three operator commands make no network call or subprocess invocation. By default, prepare writes only `apps/api/wrangler.operator.json`, with private permissions, `workers_dev:false`, disabled preview URLs/observability, a 10ms CPU cap, exact account/D1/domain, no raw secrets and no extra services. It never overwrites an existing file or follows a symlink. The existing `deploy:dry-run` uses the default disconnected config; to inspect the operator bundle explicitly, use:

```sh
node scripts/wrangler.mjs deploy --dry-run --config apps/api/wrangler.operator.json
```

The wrapper forbids development-server execution of operator profiles to prevent accidental live binding calls. For a reviewed configuration change, preserve the previous private config outside tracked files, remove the old operator file yourself, and prepare again. There is deliberately no force-overwrite option. Do not commit the profile, receipt or generated operator config.

## Optional corpus, cleanup and application allowances

The profile makes each choice explicit; none silently enables AI or increases an allowance:

- `corpus: "none"` is the default curated starter dataset. Select `"webp-pinned-assets"` for the bundled, hash-pinned public-domain English WEB text. Prepare builds 1,257 exact public files locally (about 4.8 MB), adds the internal `SCRIPTURE_ASSETS` binding, and keeps Worker-first authenticated routing. Extra files, symlinks, changed bytes and incomplete builds fail before upload. There is no external corpus download in this workflow and no JCB redistribution or translation alignment claim.
- `cleanup: "none"` leaves scheduling unset. Select `"daily-utc"` to include the fixed `17 3 * * *` UTC cron in the future deployment. This runs the bounded lifecycle maintenance handler. Merely planning/preparing does not schedule anything remotely. Expiry access checks work without the cron, but stored expired rows need maintenance.
- `dailyAppBudget` defaults to 9,000 and `dailyUserBudget` to 2,000 estimated Neurons. Both must be positive integers, user ≤ application ≤ 10,000. These are application accounting allowances, not measured billing or a guarantee about other applications on the same account. Raising one requires an explicit reviewed profile and deployment; the CLI never does it automatically.

A comparison plan uses its prepared questions/context and output settings, reports the estimated total, and checks the current remaining allowance. If it cannot fit, reduce the number of trials or output limit and request a new plan, or explicitly review a different bounded application allowance. No paid upgrade or automatic settings substitution occurs. A synthetic local 10-question/two-model WEB comparison fits the default user allowance; this is an integration example, not a live cost measurement or guarantee for every model/question.

With pinned assets selected, the authorized apply order is `migrate`, `register-corpus`, then `deploy` (with `install-receipt` as needed before AI activation). Registration writes one exact immutable metadata record and zero verse rows. Readback checks the complete manifest identity, storage mode, approved active state and zero verse rows. Repeating an already matching registration is safe; a revoked, changed, incompatible D1-mode or conflicting corpus is never silently replaced/reapproved. Deploy rechecks registration and all upload files before proceeding. If content rights are revoked, deployment is refused until a separately reviewed content decision is implemented.

## 3. Record genuine Workers Free evidence before AI activation

The billing attestation must concern the account's **Workers Free billing plan**, not a domain's Free DNS/website plan. The [Workers AI pricing documentation](https://developers.cloudflare.com/workers-ai/platform/pricing/) describes the Free allocation and refusal at its limit; it does not prove this account's status. Workers Paid and prepaid AI Gateway routes are different and forbidden here.

In an already authorized provider session, the operator must review account identity, Workers billing plan, direct Workers AI binding route, absence of paid-model/Gateway-credit routing, and absence of cross-provider/paid fallback. Retain a dated provider screenshot/export and the human review record privately. Do not store tokens, passwords, payment details or API response credentials in this repository. The CLI accepts only a content-digest reference `sha256:<64 lowercase hex digits>` to the retained evidence; it does not read or upload that evidence. A digest records which evidence was reviewed; it cannot establish that the evidence is genuine. Never manufacture a receipt from test fixtures or by copying documentation alone.

Set `freeReceipt` to an object with a fresh operator-chosen `id` and `receipt` containing exactly:

- `schemaVersion`: 1
- `policyVersion`: `workers-ai-free-hard-stop.v1`
- `accountId`: the same 32-character lowercase hexadecimal account ID
- `verifiedAt` / `expiresAt`: real UTC ISO timestamps; at most 24 hours apart, not future verification, not expired
- `evidenceRef`: digest reference to the actual reviewed evidence
- `accountPlan`: `free`
- `providerRoute`: `direct-workers-binding`
- `gatewayCredits`, `paidModels`, `fallbacks`: all false

There is no ready-to-install receipt in the repository. The profile and account/database/action/fingerprint must be approved for future application. Existing Wrangler authentication is referenced, never copied into JSON. The CLI only checks that this authentication sees the intended account and D1 ID; it does **not** independently inspect billing. Account upgrades after the snapshot cannot be detected continuously. Revoke before changing the Workers plan, Gateway routing, payment status or evidence assumptions. Do not upgrade the account while the Free-only profile is active.

Application reservations use conservative estimates, not proven token bounds. Hidden reasoning usage and other applications' account usage remain uncertain. The runtime labels `budgetBoundVerified:false`, uses a bounded input estimate plus margin, and relies on the provider Free cutoff as the final monetary stop. Expiry/revocation fails closed. No calibration inference or real test call is issued by this CLI.

## 4. Review each selected model's terms separately

All 22 entries remain visible, including seven paid-required models which cannot activate in this profile. Published links in the template are discovery evidence only. For each selected free-allocation candidate, obtain the required legal/terms review and any required agreement acceptance separately, then set its own row to `reviewed`, with actual `reviewedAt`, a digest evidence reference and relevant HTTPS `termsUrls`. The policy version must exactly match the repository. An empty or unknown license is not unrestricted use. Do not mark a whole provider or all 22 models reviewed from one unchecked default.

The CLI records review, never accepts agreements. If terms require explicit acceptance and that has not been authorized/performed, leave the row pending and stop. Supported URL hosts are narrowly restricted to current official discovery sources. A future change in source requires code review, not arbitrary URL entry. Select `modelIds` and an included `defaultModelId` only after those reviews. Plan exposes the catalog's token parameter, temperature ceiling, streaming capability, reasoning-control uncertainty and billing classification. Unknown models/providers, paid-required models, stale terms policy and incomplete review evidence are refused.

## 5. Choose answer mode honestly

The default `reviewed-claim-selection` selects from existing reviewed claims. Corpus coverage does not turn this into general explanatory Bible Q&A.

To stage experimental generated prose, explicitly include `grounded-generation` in `answerModes`, set `experimentalGroundedReviewed:true`, and choose an allowed `defaultAnswerMode`. This records the operator's mode review; it does not bypass current per-user quality consent. Structural citations do not prove semantic truth, spoiler safety or Japanese quality. Real model/device evaluations remain required. Modes remain separate in runtime execution identity and UI disclosures.

## 6. Future remote apply, one approved action at a time

Do not run these commands as part of offline preparation or tests. Each `apply` requires all of:

1. An already authenticated Wrangler session with appropriate existing permissions. No login/setup/token creation is attempted.
2. An exact prepared config matching the current profile.
3. Explicit user authorization for the chosen action, account, database and profile (including custom-domain changes for deployment).
4. `--execute --allow-remote` and `--confirm ACTION:ACCOUNT_ID:DATABASE_ID:PROFILE_FINGERPRINT`, using the fingerprint returned by `plan`.

The two flags are an operator acknowledgement, not a replacement for user authorization. Before mutation, the CLI runs read-only `whoami --json` and `d1 info --json`, checks exact IDs, and rechecks evidence expiry. It captures provider output without printing it. Failures suppress raw output because it could contain sensitive details. Check actual provider state before retrying any uncertain mutation; do not assume failure means nothing happened.

Use the same profile path in each command:

```sh
node scripts/operator.mjs apply --profile .cache/operator/staging.json --action ACTION --execute --allow-remote --confirm ACTION:ACCOUNT_ID:DATABASE_ID:PROFILE_FINGERPRINT
```

Actions, in normal initial order:

- `migrate`: applies checked-in migrations to the exact existing remote D1.
- `register-corpus`: only when `corpus` is `webp-pinned-assets`; registers the exact bundled corpus metadata, verifies readback, and refuses conflicting/revoked data. No verse-row import or remote resource creation.
- `install-receipt`: active profiles only; installs the immutable receipt. An existing exact-byte/account, nonrevoked receipt is a verified no-op. Different bytes or revoked IDs fail, never reapprove. Use a fresh ID for renewed evidence.
- `deploy`: deploys the Worker and creates/updates the specified custom-domain route. An active config may still fail closed until its receipt is installed; deployment does not perform inference.
- `invite-owner`: inserts a one-hour, single-use invitation only if no owner or unexpired owner invitation already exists. Raw token appears once in the private invoking terminal after successful insert verification; only its hash goes to D1/process arguments. Do not redirect terminal output into logs. Register a passkey on the exact configured domain.
- `invite-member`: creates a separate one-hour member invitation after the owner is registered. Member role never comes from client input.
- `rotate-receipt-slot`: optional explicit slot initialization/compare-and-swap rotation, separate from evidence installation. Requires the exact old generation and receipt ID in the profile, then verifies the changed pointer and its current nonrevoked evidence. Never auto-retries an uncertain result.
- `revoke-receipt`: account/ID-bound, idempotent revocation; never deletes or un-revokes. This action remains available after receipt expiry. `plan` can display an expired receipt fingerprint (`receiptCurrent:false`), but validate/prepare/install/deploy still reject expired evidence.

No manual SQL editing is required. Invitation creation can fail after a lost acknowledgement; do not regenerate indiscriminately. An unexpired pending owner invitation intentionally blocks another; wait for expiry or inspect authorized provider state. Losing the invitation token is not recoverable from its stored hash.

## Daily use and receipt renewal

**Free-mode AI requires renewed human-reviewed account evidence at least every 24 hours while it is used.** A shorter receipt lifetime requires earlier renewal. This is a deliberate safety boundary and a daily operating burden, not an unattended free-service guarantee. There is no automatic renewal, billing inspection or paid fallback. If daily review is too much work, leave AI disconnected and use available reading/material features. Do not lengthen receipts or copy yesterday's timestamps to avoid the review.

The local `plan` command reports `receiptCurrent` and `receiptMaintenance.expiresAt` without any provider call. It describes the selected local profile, not the currently deployed Worker or live receipt revocation state. An expired receipt stops new AI dispatch even when today's application allowance is unused. The daily allowance reset does not restore an expired receipt.

### Renew a pinned-ID deployment through the CLI

This is the unchanged default when the profile has no `freeReceiptSlot`.

1. Before changing a profile, retain the old profile and matching prepared config privately outside tracked files. They identify the exact old receipt if revocation is needed. If evidence assumptions changed, revoke the old receipt using that matching profile/config before preparing its replacement; never keep AI active while upgrading the account or enabling a paid route.
2. Review current genuine provider evidence again as in section 3. Use a fresh receipt ID, real new verification/expiry times no more than 24 hours apart, and the digest of the newly retained evidence. Keep already reviewed model terms only if still applicable. Do not edit an installed receipt or reuse a revoked ID.
3. Run `plan` and `validate` for the new private profile. Preserve and remove the previous `apps/api/wrangler.operator.json` yourself, then run `prepare` with the new profile. Inspect the generated config and its dry-run bundle. The new ID changes the profile fingerprint; old confirmation strings no longer authorize the new profile.
4. With explicit authorization for each action, run `apply --action install-receipt` and then `apply --action deploy`, using the new profile and its new fingerprint as described in section 6. **Installing alone does not renew the running app:** the deployed `AI_FREE_RECEIPT_ID` still points to the old receipt until deployment. Renewal on an unchanged schema/corpus needs no new migration, corpus registration or invitation.
5. After a confirmed deployment, reopen the owner's “モデルと比較” screen to reload its catalog. Check the configured models' readiness; a successful deploy by itself is not proof of live AI or Free billing status. Any actual inference remains a separately authorized test. A comparison planned before renewal may have stale execution identity; obtain a new plan rather than retrying the old plan blindly. For an unfinished question/comparison, use its existing status-check/recovery controls first to avoid duplicate inference.

If an install/deploy acknowledgement is lost, inspect the actual provider state through the already authorized CLI session before retrying. Exact existing nonrevoked receipt installation is a verified no-op, but neither that nor a local `plan` proves which config is deployed. Do not infer success from an error or silently redeploy. Keep the old profile/config until any required account/ID-bound revocation is complete; the single prepared-config path must match the profile used for that action.

### Optional stable deployment slot: renew without daily redeployment

For a future deployment that needs lower daily maintenance, explicitly add `freeReceiptSlot` to its private active profile:

```json
"freeReceiptSlot": {
  "id": "main",
  "expectedGeneration": 0,
  "expectedReceiptId": null
}
```

The slot ID identifies this deployment within this account/database. Use separate IDs for independently operated deployments. Initial activation requires generation `0` and a null old receipt; no existing pointer may be overwritten. The profile still needs the exact newly reviewed `freeReceipt` and model reviews. `prepare` emits `AI_FREE_RECEIPT_MODE: "slot"` and `AI_FREE_RECEIPT_SLOT`, without a pinned receipt ID. These modes are exclusive; missing slot state never falls back to another receipt. Existing pinned deployments keep their behavior until an explicitly authorized deployment selects slot mode.

1. For first activation, apply current migrations (including `0022_free_receipt_slots.sql`), install the genuine receipt, and separately authorize `rotate-receipt-slot` using the same exact `action:account:database:profileFingerprint` confirmation format. The CLI checks account/database identity before mutation. The initial pointer receives generation 1. Then explicitly deploy the prepared slot-mode Worker; deployment rechecks the exact pointer and nonrevoked current receipt.
2. For later renewal, review fresh genuine evidence and choose a new receipt ID. Set `expectedGeneration` and `expectedReceiptId` to the exact currently installed pointer obtained through an authorized read. Keep the same slot ID, account, database and deployment settings. A wrong/stale value produces zero changes; the CLI does not fetch a new value and retry automatically.
3. Run `plan` and `validate`; the new fingerprint covers the new evidence and exact previous pointer. If all deployment settings are unchanged, the existing prepared config is byte-for-byte identical and can stay in place. If settings changed, preserve it and prepare a new config as usual; those deployment changes still require deployment.
4. Separately authorize `install-receipt` and `rotate-receipt-slot` with the new profile fingerprint. Installation alone never activates the new receipt. Rotation atomically changes the old pointer to the new receipt at generation +1 and verifies readback. A running Worker already configured for this same slot now uses the new evidence without redeployment. Review is still required at least every 24 hours; there is no unattended renewal or automatic authority fallback.
5. Reload model readiness and create new comparison plans. Rotation invalidates old authority fingerprints and prevents any not-yet-dispatched request using the old generation from reaching AI. Old plans are never rebound. Proven-undispatched reservations may be refunded; a dispatch that happened or cannot be disproven remains charged and must use existing status/recovery controls.

If the CAS response or readback is lost, stop and inspect the exact pointer and receipt through the authorized provider CLI before making a new decision. Replaying the same rotation does not count as a success. Do not create a new generation just to clear an uncertain acknowledgement. Already used receipt IDs cannot be restored to the same slot, even if still valid; generation cannot reset or decrease, and slot/history identities cannot be replaced or deleted. Receipt revocation remains account/ID-bound and does not require rotating a pointer. The runtime checks revocation and expiry again atomically at dispatch. Another account's same-named slot cannot authorize this deployment.

### Recognize an unavailable state

- AI disabled or an unconnected model: the default installation intentionally has no AI. The owner must finish reviewed activation; signing in again or waiting for midnight cannot connect it.
- `BUDGET_UNVERIFIED` / `budget_unverified`: authority is missing, expired, revoked or otherwise invalid; it is not evidence that the daily allowance ran out. Check the operator profile/expiry and the exact deployed pinned receipt ID or slot/account/generation pointer, retained evidence and remote receipt state. Fix only the verified cause through the reviewed workflow. The iOS message explains that evidence cannot be verified and explicitly does not infer expiry or allowance exhaustion; owner catalog guidance points to the operator CLI, while members are directed to the owner and can use “資料のみ” meanwhile. The app does not identify receipt expiry separately from other invalid authority causes.
- `comparison_budget_exceeded`: check remaining user and application allowances, then reduce question count or output limit and make a new plan. A plan larger than the full daily allowance still fails after reset. Ordinary members share the application allowance even though each has a separate user allowance; a member's low usage does not imply enough application budget remains.
- An expired receipt is different from a missing consent or disabled answer mode. Use Settings for current per-user consent; neither consent nor selecting another model renews the operator's evidence.

All 22 catalog entries are visible for inspection; visibility is not permission or connectivity. The seven paid-required entries cannot activate in this Free-only profile. Model readiness is checked before selection, while the exact prepared question/context and remaining allowances are checked again for each request. The catalog is not a live billing dashboard or a promise that a comparison will fit.

## 7. Prepare private GitHub publication

```sh
node scripts/operator.mjs github-plan --owner EXACT_PERSONAL_OWNER
```

This is local preparation only, always for `EXACT_PERSONAL_OWNER/bible-companion`, private visibility. The current session has not established authenticated GitHub access. Do not run login or grant scopes automatically.

Future separately authorized actions use existing `gh` authentication:

```sh
node scripts/operator.mjs github-apply --owner EXACT_PERSONAL_OWNER --action create --execute --allow-remote --confirm create:EXACT_PERSONAL_OWNER/bible-companion:private
node scripts/operator.mjs github-apply --owner EXACT_PERSONAL_OWNER --action push --execute --allow-remote --confirm push:EXACT_PERSONAL_OWNER/bible-companion:private
```

Creation checks the authenticated personal owner, creates a private repository without a push, then verifies exact name and private visibility. Push rechecks owner and private visibility, then checks that `origin` has exactly one allowed push URL and pushes local HEAD to `main` using that verified URL directly. Git URL rewrite configuration is rejected before push; no forced update or public fallback exists. Creation and push are separate approvals. Do not change a conflicting origin automatically. Inspect tracked contents and the commit for secrets before authorizing push. A successful push command is not CI/device acceptance; independently verify the remote commit and CI afterward.

## Verification boundary

`node --test scripts/operator.test.mjs` uses local temporary files, an isolated real SQLite database, checked-in public corpus artifacts and injected process mocks. It checks pending templates, all 22 terms slots, no-overwrite/private permissions, traversal/symlink rejection, invalid/malicious receipt and key injection, unknown/paid provider refusal, account/expiry/route/terms/mode gates, exact authorization, provider identity mismatch, immutable duplicate receipt handling, revocation, owner invitation exclusion, private-repository visibility and push target checks. None of these tests proves real provider access, billing status, live inference, successful deployment, passkeys on iPhone, GitHub publication or legal acceptance.
