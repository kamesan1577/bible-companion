# Backend resource verification

Measured locally on 2026-10-13 with Node 24.19.0. These checks use synthetic users, ephemeral generated keys, in-memory SQLite, and mocked provider responses. They make no external inference calls or production performance claims.

## Reproduce

- `npm test -- --run apps/api/test/security-query-profile.test.ts`
- `node scripts/diagnostics/profile-cpu.mjs` (prints its temporary raw-report location)
- `npm test -- --run apps/api/test/security-review.test.ts packages/ai-harness/test/security-review.test.ts`

The CPU script uses installed SimpleWebAuthn and esbuild dependencies. It generates credentials solely in memory; the report contains timings, no private keys. A disposable Node-target API bundle is left alongside its report in the OS temporary directory.

## D1 statement and payload bounds

Official [D1 limits](https://developers.cloudflare.com/d1/platform/limits/) checked October 13: Free 50 queries per invocation, 2,000,000-byte row/string/BLOB limit, 100 bound parameters, six concurrent D1 connections. Recheck these before launch.

The test counts prepared statements, including each member of a batch. This is a conservative application-level proxy; database trigger internals are not counted. It asserts at most 50 statements, at most 100 bound parameters, and bounded response and fixture row sizes. It exercises failures, abort/refund, policy revocation, completed-step replay, partial cancellation, expired leases, maximum 20-trial plans, and the 22-model catalog. The largest observed fixture row serialization was 68,346 bytes; this is not a storage-size measurement or proof over every possible production row. Source/result bounds and export preflight must remain enforced independently.

| Route fixture | Maximum prepared statements |
| --- | ---: |
| parse-short | 2 |
| parse-near-input-limit | 2 |
| reading-public-miss | 11 |
| reading-public-hit | 6 |
| source-only-question-save | 21 |
| history-latest-50-of-220 | 8 |
| whole-export-220-messages | 16 |
| export-page-25 | 22 |
| source-policy-conflict | 5 |
| export-page-25-assistants | 37 |
| export-page-25-saved-comparisons | 12 |
| invalid-parse-input | 2 |
| provider-fixture-success | 28 |
| provider-fixture-failure-retain | 22 |
| provider-fixture-revocation-retain | 26 |
| client-aborted-before-dispatch-refund | 21 |
| comparison-plan-max20 | 5 |
| comparison-start-max20 | 16 |
| comparison-single-step-max20-ledger | 19 |
| comparison-completed-step-replay | 9 |
| model-catalog22 | 3 |
| comparison-start-unsaved | 16 |
| comparison-single-step-unsaved | 16 |
| comparison-cancel-partial | 5 |
| comparison-expiry-reconcile | 5 |
| scripture-populated-bounded-page | 7 |
| scripture-populated-reading | 11 |
| scripture-populated-source-only | 21 |

After optional primary-text retrieval was wired, reading/provider/step paths added one query; the profile reflects that wiring. Three additional paths use 176 synthetic primary-text rows of approximately 1.2 KB each: bounded scripture pagination, uncached reading, and literal source-only output. These measure representative payload bounds without asserting authentic corpus content or exhaustive maximum-volume behavior.

Worst measured route is 37 statements, leaving 13 below the published Free ceiling. The comparison plan previously reached 83; batched proof lookup and one-trial-per-request execution removed that overrun. Export candidate metadata is measured before loading body rows; responses stay below 1 MiB. Query profiling includes Node/SQLite wall samples and observed heap deltas, but neither is Worker CPU or peak isolate memory.

## Separate CPU diagnostics

Unmocked SimpleWebAuthn verifies locally signed ES256 packed self-attestation registration and ES256 assertions. Signing, fixture generation, SQLite, route logic, and module import are excluded from warmed verifier measurements. After one separately recorded first call and three warmups, 25 samples are captured using process.cpuUsage (user plus system) and performance.now separately.

| Diagnostic | CPU median | CPU p95 |
| --- | ---: | ---: |
| Registration verification | 1.374 ms | 4.090 ms |
| Assertion verification | 0.816 ms | 2.567 ms |
| Cold Node bundled API initialization, 8 fresh processes | 180.308 ms | 745.333 ms |

A second reproduction of the tracked script gave registration CPU median/p95 2.792/5.970 ms, assertion 1.150/3.246 ms, and cold initialization 229.161/245.105 ms. This variation reinforces that these are diagnostics, not stable runtime guarantees.

Cold initialization requires a Node-target esbuild bundle in fresh child processes. It includes module file read, parsing and evaluation; excludes bundling and Node process startup. OS file caches may already be warm. Whole-process CPU includes runtime activity and is sensitive to JIT, background work and platform crypto; it is not Cloudflare isolate-billed CPU. The cold result must not be compared directly to a per-request Worker allowance.

## Hard launch gates

- Measure actual deployed Free Worker CPU, memory and D1 use for authentication, cold/warm requests, bounded large exports, and every inference/error/refund path before enabling access.
- Do not infer compliance with the Free 10 ms CPU allowance from local timings. If deployed limits fail, optimize or pause launch; do not automatically upgrade billing.
- Real browser WebAuthn, Apple ASWebAuthenticationSession and native signed builds remain separate unverified integration gates.
- Real inference remains disabled until terms, explicit consent and provider authorization are satisfied, together with either the default independently justified strict budget proof or the explicitly selected, expiring account-bound Workers Free hard-stop receipt. The receipt alternative uses estimated reservations and does not establish verified token bounds or continuously verified account status.

## Conservative deletion accounting

Observed abort after dispatch-marker creation but before provider invocation now credits the trial allowance, including when concurrent cancellation already settled the reservation. A narrower deletion race intentionally retains conservative allowance: if private job/trial records are deleted before that correction, the evidence for an idempotent credit no longer exists. Deletion releases every trial still known to be undispatched at deletion. Retained allowance is a safety reserve, not measured provider usage or a monetary charge claim; no extra private lease history is retained solely for this rare refund edge.

## Real pinned asset-route diagnostic (19:38 UTC)

Reproduce with `npm test -- --run apps/api/test/security-assets-profile.test.ts`. The checked-in compressed official corpus supplies real content; an in-memory binding supplies verified asset bytes. Preparing that fixture is outside measurement. Each variant has ten request samples; `process.cpuUsage` and wall time are separate. Fresh-binding resets application asset caches but does not reset Node/JIT/OS caches or model a cold Worker isolate. Request CPU includes local SQLite and JSON/hash work.

| Page | Cache | D1 statements | Asset fetches / bytes | CPU median / p95 |
| --- | --- | ---: | ---: | ---: |
| Genesis 1:1–3 | Fresh binding | 6 | 2 / 14,797 | 6.173 / 30.662 ms |
| Genesis 1:1–3 | Warm binding | 6 | 0 / 0 | 2.211 / 2.649 ms |
| Psalm 119, first 100 | Fresh binding | 6 | 2 / 45,496 | 8.315 / 16.055 ms |
| Psalm 119, first 100 | Warm binding | 6 | 0 / 0 | 3.145 / 16.406 ms |
| Full Genesis selection, first 100 | Fresh binding | 6 | 5 / 24,909 | 6.813 / 12.380 ms |
| Full Genesis selection, first 100 | Warm binding | 6 | 0 / 0 | 2.647 / 6.978 ms |

Response payloads were 1,205–19,121 bytes. The test asserts query/fetch/payload bounds, not timing thresholds. These local spikes reinforce the need for actual deployed CPU measurement; they prove neither failure nor compliance with Worker CPU limits. Direct unauthenticated internal asset routes return404 without calling the asset binding; rights and policy are rechecked independently of immutable byte caches.

## Optional Free-receipt complete20-trial rehearsal (20:35 UTC)

The ninth test in `apps/api/test/security-budget-modes.test.ts` uses ten distinct Genesis passages, two models, real pinned assets, the actual default2000-unit user allowance, a clearly synthetic Free-account receipt, and a mocked provider. Each mocked response quotes eligible text from that trial’s prepared prompt; this is a structural/lifecycle test, not evidence of model quality. Exact prepared-input estimate fingerprints match between plan and every dispatch.

All20 sequential trials complete with exactly20 provider-mock calls. Completed-step replay makes no21st call. The full plan reserves847 estimated units and ends with reserved0/consumed847. Those units are conservative application accounting, not measured provider usage.

| Request | Prepared statements | Local CPU diagnostic |
| --- | ---: | ---: |
| Plan20 trials | 26 | 69.514 ms, one sample |
| Start20-trial ledger | 37 | 25.961 ms, one sample |
| Each of20 saved steps | 20 | 5.530–11.052 ms |
| Completed-step replay | 9 | 4.595 ms, one sample |

The largest step response was70260 bytes. All requests remain below50 D1 statements. Planning CPU varies substantially across local runs; these samples reinforce the outstanding deployed Free CPU gate rather than proving platform-limit compliance. No account verification, real inference or billing was performed.

## Early public reading-cache diagnostic (20:47 UTC)

The real-asset profile now also measures the ordinary `/reading` response with ten samples per variant. Each miss clears only the public response cache and creates a fresh in-memory asset binding before measurement; each hit reuses a validated public response. Fixture preparation and explicit cache-clearing are outside timing. Rights/policy and owned-import checks remain inside every request.

| Selection | Cache | Queries | Asset fetches / bytes | Response bytes | CPU median / p95 | Wall median / p95 |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Genesis 1:1–3 | Miss | 11 | 2 / 14,797 | 5,960 | 5.294 / 8.946 ms | 4.846 / 8.599 ms |
| Genesis 1:1–3 | Hit | 6 | 0 / 0 | 5,959 | 1.488 / 2.440 ms | 1.265 / 2.170 ms |
| Psalm 119 selection | Miss | 11 | 2 / 45,496 | 40,171 | 10.081 / 26.561 ms | 9.964 / 15.878 ms |
| Psalm 119 selection | Hit | 6 | 0 / 0 | 40,170 | 1.974 / 2.600 ms | 2.470 / 3.178 ms |

A separate10-case security suite (`security-reading-cache.test.ts`) verifies source/material/corpus epoch completeness, staged-versus-sealed corpus behavior, in-flight revocation rejection, runtime/schema-pin invalidation, projection-key separation, owned-import authorization and absence of tenant data in shared cache bodies. A hit test deliberately throws if any source/material/corpus body-loading query is attempted and asserts no asset binding call.

The same run’s20-trial comparison diagnostic measured31.661 ms planning and33.029 ms starting, with all steps at most10.722 ms local CPU. This is descriptive variation, not a causal optimization guarantee or a Cloudflare compliance measurement.

## Actual local Worker runtime smoke (2026-10-13)

`npm run worker:runtime:test` bundles the actual API entrypoint and runs it in the locked
Miniflare/workerd runtime with an isolated temporary D1 store. It verifies authenticated
import, cross-owner refusal, reading cache miss/hit, source-only answer persistence,
rights revocation and historical assistant redaction (preserving the user question),
closed AI refusal, and session logout. A real ES256-signed assertion exercises server-created
WebAuthn options, exact-origin refusal, challenge replay refusal, and concurrent PKCE
exchange with exactly one successful session. The pinned real WEB artifact also runs through
a local service binding: actual Worker digest/JSON validation, Genesis pagination, no
verse rows in D1, unauthenticated internal-path refusal, and corpus revocation all pass.
The service binding supplies checked-in public bytes; it is not a deployed Assets test. All migrations are applied to the isolated
SQLite file while workerd is stopped; subsequent route SQL runs through actual D1 bindings.

The Node deny-external-network preload remains enabled, request metadata fetching is
disabled (`cf:false` and `CLOUDFLARE_CF_FETCH_ENABLED=false`), and a Worker outbound
handler rejects all external fetches. The test asserts zero outbound requests.
Only loopback runtime plumbing and synthetic short-lived local sessions are used;
temporary state is removed after disposal. This is runtime integration coverage,
not a deployed CPU limit, browser passkey, native-device, or live AI verification.

## Independent offline checkout verification (2026-10-13, 22:49 UTC)

An independent clean checkout of `03909c127f95b0563c964b666e0a8596da66cb41`, using
Node 24.19.0 and npm 11.9.0, installed 110 packages from an existing local npm cache.
The complete `npm run validate` passed: 49 Vitest files / 609 tests, 118 Node test
cases across the remaining suites, typechecking, generated seed checks, and the
design contract including 24 contrast pairs. The two actual local workerd/D1 tests
covered authenticated reading/source-only routes and frozen receipt-slot dispatch,
concurrent rotation and revocation. Provider/operator remote actions in other tests
were mocked; no real authentication, deployment or inference was performed.

For a clean checkout with an already populated compatible npm cache, set
`NPM_CACHE` to that cache's absolute path, then run from the repository root:

```sh
export npm_config_offline=true npm_config_update_notifier=false
export WRANGLER_HIDE_BANNER=true WRANGLER_SEND_METRICS=false
export WRANGLER_SEND_ERROR_REPORTS=false CLOUDFLARE_CF_FETCH_ENABLED=false
export NODE_OPTIONS="--require=$PWD/scripts/diagnostics/no-external-network.cjs"
mkdir -p .cache/verification-tmp
export TMPDIR="$PWD/.cache/verification-tmp"
export BIBLE_NETWORK_DIAGNOSTIC="$PWD/.cache/verification-network.jsonl"
npm ci --offline --cache="${NPM_CACHE:?Set an existing local npm cache}" --no-audit --no-fund
npm run validate
npm run deploy:dry-run
```

Stop if the cache is incomplete, local runtime sockets are denied, or an external
request is refused. Do not fetch missing packages or remove the network guard.
Inspect any existing diagnostic file separately before attributing its entries to
a new run. The fixture's Worker outbound rejection and `cf:false` remain enabled
in addition to the inherited Node preload and environment settings above.

The first validation invocation omitted npm's offline/update-notifier settings
and was rejected by execution review for a reported `registry.npmjs.org` attempt
while typechecking was in progress. Its log did not establish completion of any
validation stage or produce a Node network diagnostic. Installed npm source showed
an asynchronous registry update check and a supported `update-notifier=false`
early return; this was a possible cause, not proven attribution. The corrected
invocation above retained the same guards, passed all stages, and produced no
denied-external-request diagnostic.

The guarded Worker dry-run also passed (1767.39 KiB, gzip 322.00 KiB). Two
`npm run openapi` executions produced bytes identical to the committed contract;
two clean-HEAD source exports using `scripts/export-source.mjs` produced identical
archives and manifests, as described in [the source export protocol](../source-export.md).
Archive SHA-256: `6467d447d92c26d7e0814abd5d45e9c7276d8020b18eb980b5e5aa2c64475c5e`.
Both checkout and original repository remained clean. These results apply to the
exact commit above; they do not establish deployed Free-tier CPU/memory limits,
live provider quality, browser passkey behavior, or Apple SDK/device acceptance.
