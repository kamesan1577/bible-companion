# ADR: immutable primary scripture storage

Date:2026-10-13. Status: optional static-assets adapter implemented and locally verified; no remote resource created.

## Decision and reason

Keep the verified local D1 corpus importer as a tested fallback. Prefer immutable per-chapter Worker Assets for an eventual free-first public primary-text deployment, with the pinned manifest and mutable rights/activation policy in D1. Neither choice is enabled remotely by this decision.

The corpus is immutable public-domain English text, not private reading state. SQL per-verse mutation/search is unnecessary for the current range lookup. Full text must stay outside the Worker JavaScript bundle so every request does not parse the entire Bible at cold start. A chapter asset can be bounded, hash checked and filtered to the confirmed range before it enters any answer context.

## Alternatives

- **Indexed D1 verses:** implemented and actually imported locally.31,103 rows plus several indexes make initial writes materially larger than31,103. Free D1 allows100,000 written rows/day; index writes count. Multiple-day staged remote import is possible but adds operational complexity and competes with private-app writes. SQL indexes provide fast range and exact citation lookup; immutable row triggers and corpus rights guards are already tested.
- **Worker Assets chapters:**1,189 small immutable files. Asset storage and asset-only requests are free; Worker-invoked authenticated API requests still consume the normal Worker request/CPU allowance. Use an internal asset binding and `run_worker_first:true`, never direct asset fallback for a protected path. Keep rights checks in D1 on each relevant request and include the policy epoch in publication/cache guards. This avoids bulk verse-row writes, but deployed cache/CPU behavior still needs measurement.
- **R2:** can store the same immutable chunks, but introduces a separate bucket/access setup, operation allowances and provider terms/billing gate. No current requirement justifies that extra service over Worker Assets.
- **Bundled JSON in code:** rejected because full-corpus parse/memory and startup costs would affect unrelated auth/private routes. Compressed archival artifacts in the repository are not runtime module imports.

## Required adapter safeguards

1. Derive chapters only from the already pinned, hash-verified prepared corpus. Preserve original source coordinates and explicitly exclude unsupported/empty text from displayed passages.
2. Pin an asset index digest and each chapter digest. Reject oversized, redirected, malformed, wrong-version or hash-mismatched responses. No user-supplied URLs, paths or asset binding overrides.
3. Bound chapter fetch count and response bytes per request. Page long ranges instead of loading all chapters into memory.
4. Require approved active manifest policy even on cache hits; revocation invalidates new publication, history and replay. No silent fallback to an older active dataset after revocation.
5. Maintain the same authenticated import scope, cursor, omission, English/source-language and unreviewed-editorial contract as the D1 adapter.
6. Keep asset upload/deployment and provider activation separate from local build/dry-run. No automatic paid fallback.

## Official evidence

- [D1 pricing](https://developers.cloudflare.com/d1/platform/pricing/):5million read rows/day and100,000 written rows/day on Free; index and CLI/import writes count.
- [Worker Assets billing](https://developers.cloudflare.com/workers/static-assets/billing-and-limitations/):asset requests are free/unlimited and storage has no additional charge; Worker-first requests use Worker allowance and fail429 at the free limit rather than bypassing the Worker.
- [Worker Assets binding](https://developers.cloudflare.com/workers/static-assets/binding/) and [Worker-first routing](https://developers.cloudflare.com/workers/static-assets/routing/worker-script/):configuration and internal fetch interface.

These published limits are not measurements of this application. Physical deployment, account quota and free CPU acceptance remain open gates.

## Implemented local workflow

Run from the repository root with Node 24:

```sh
npm run corpus:assets:config -- plan
npm run corpus:assets:config -- generate
node scripts/wrangler.mjs d1 migrations apply bible-companion --local --config apps/api/wrangler.assets.json --persist-to .cache/scripture-assets-state
npm run corpus:assets:config -- register-local --execute
node scripts/wrangler.mjs deploy --dry-run --config apps/api/wrangler.assets.json
```

The generated profile is ignored by Git and stays local. Registration targets an isolated state directory, requires all migrations, and inserts one corpus metadata record with zero verse rows. Repeating registration is a no-write operation; a revoked/inactive corpus cannot be silently reapproved. The original full-D1 local state remains separate. These exact commands completed locally, including the deployment dry-run; no asset was uploaded.

The deterministic build emits 1,257 files totaling 4,798,545 bytes: 1,189 chapter files, 66 per-book indexes, a global audit index and a pin map. The runtime reads only a requested book index (at most 31,472 bytes) and bounded chapters (largest actual chapter 14,024 bytes). It retains at most three book indexes and six chapters per binding, with at most eight chapter loads per request. The whole global index is never parsed on the request path. All 31,095 present canonical coordinates are checked against the source corpus; seven empty/missing coordinates remain explicit omissions.

Local tests cover exact artifact membership and hashes, stream/body cleanup, late binding responses, direct internal-path denial, tenant and rights checks, pagination, and metadata-only activation. Real bundled-asset profiles used six D1 statements per scripture page. Node CPU samples are diagnostics, not evidence that deployed Workers meet the Free CPU limit; see the resource verification report.
