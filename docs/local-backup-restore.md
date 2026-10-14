# Private local D1 backup and restore rehearsal

This tool makes private recovery snapshots of this checkout's **local** D1 database. It never connects to a Cloudflare account, provisions resources, deploys, or restores over an existing state directory. Node.js 24 and the installed, lockfile-selected Wrangler are required.

These snapshots contain **all accounts' private reading history, passkey public-key records, session/invitation verifiers and other authentication state**. They are not user exports, anonymized samples, or public-shareable artifacts. Do not attach them to issues, commit them, publish them, or upload them to a model or third-party service. Storage encryption, approved off-device backup, retention and deletion policies remain separate operational decisions. This diagnostic does not implement those policies or constitute production disaster recovery.

## Commands

Run from the repository root:

```sh
# Read-only diagnostic of the normal local development database.
node scripts/local-db.mjs inspect

# Use a meaningful, new label. It cannot overwrite another backup.
node scripts/local-db.mjs backup --name before-next-migration
node scripts/local-db.mjs verify --name before-next-migration

# Restore only into a NEW isolated local state directory.
node scripts/local-db.mjs restore --name before-next-migration --target rehearsal-1
```

The default source is `apps/api/.wrangler/state`, matching this checkout's Wrangler configuration. To select a previously created isolated local state, supply `--state .cache/STATE` to `inspect` or `backup`. Only simple in-repository `.cache` paths or the explicit default are accepted. Backup and target labels use 1–64 ASCII letters, digits, underscores or hyphens, starting with a letter or digit.

Backups live in `.cache/local-db/backups/LABEL/`; restored state lives in `.cache/local-db/restores/TARGET/`. `.cache/` is already Git-ignored. Artifact directories are created with mode `0700`, snapshots/manifests with `0600`, and restored Wrangler files inherit a restrictive umask. Existing artifact directories with loose permissions are refused. Symlinks, hardlinks and ambiguous local database selections are refused. Existing source file permissions are not changed. These POSIX mode checks do not replace device encryption or Windows ACL review.

There is deliberately no `--remote`, SQL-output, overwrite, replace-live-state, delete, production-config or authentication option. A failed backup may leave a private incomplete directory without a valid manifest; a failed restore may leave an isolated incomplete target without `restore-verified.json`. Neither is silently reused. Preserve it for local diagnosis and choose a new label after addressing the cause. The tool never automatically deletes local state.

## What is preserved and checked

1. Node's built-in SQLite online backup API takes a transactionally consistent snapshot, including committed data still in the WAL. It does not copy a database file while ignoring its WAL. The original database is opened read-only. A private copy is normalized to a standalone rollback-journal SQLite file; the original's journal mode is unchanged.
2. SQLite performs an integrity check and foreign-key check. The tool fingerprints the exact schema, including indexes and triggers, migration records, and every application table's complete content. Rows are read incrementally; BLOBs, integer values larger than JavaScript's safe integer range, real numbers and nulls are typed distinctly. Internal `_cf_` bookkeeping values are excluded from content equality because the local runtime may change them. Their schema is still included, and the binary snapshot retains them.
3. Migration files are discovered dynamically. Recorded D1 migration names must be an ordered prefix of the checked-in migration files. Their current checksums are recorded and rechecked. The application schema is also compared independently to a fresh in-memory replay of that applied prefix. **Migration names alone do not prove that historically edited migrations were applied.**
4. A historical or manually changed schema can still be backed up for preservation, but its summary reports `schemaMatchesMigrations: false`, and restore refuses it before creating a target. This requires investigation and reviewed matching migration history, never editing an already-applied migration merely to suppress the warning. A schema match checks structural identity; it does not prove that a historical data-only migration had identical contents. The snapshot preserves the actual data rather than reseeding or silently reapproving rights.
5. Restore first verifies the backup's binary checksum, complete fingerprint, migration checksums, binding identity and installed Wrangler version. It reserves a brand-new private target, uses the existing guarded Wrangler wrapper to initialize that local D1 database with `SELECT 1`, and restores only the newly created target file. No application migration is reapplied during restore. A backup from an older known prefix stays on that prefix.
6. Restore runs ordinary `SELECT COUNT(*)` queries through **actual local Wrangler D1** for every application table, then rechecks exact schema/content with SQLite after the runtime closes. It writes `restore-verified.json` only after all checks pass. It does not ask D1 to run unsupported integrity pragmas: integrity and foreign keys are checked through Node SQLite, while D1 checks actual local runtime readability.

The manifest contains hashes and counts, not plaintext private rows, but it is private metadata and must stay with its snapshot. Hashes detect accidental corruption or drift; an attacker able to replace both the snapshot and manifest can forge them. Only use trusted, locally generated snapshots. Raw database errors, SQL and row contents are not printed by this CLI; summaries contain only counts and verification status.

## Offline behavior and tests

The only restore subprocess goes through `scripts/wrangler.mjs`, with explicit `--local`, the reviewed development configuration, and an isolated `--persist-to` path. The shared local-wrapper environment sets:

```text
WRANGLER_HIDE_BANNER=true
WRANGLER_SEND_METRICS=false
WRANGLER_SEND_ERROR_REPORTS=false
CLOUDFLARE_CF_FETCH_ENABLED=false
```

The installed Wrangler's banner otherwise starts an npm update check even in CI. Hiding that banner prevents the update check on this local operation; metrics and error-report submission are disabled separately. Miniflare also fetches `https://workers.cloudflare.com/cf.json` when its request-metadata cache is absent; the installed runtime explicitly supports `CLOUDFLARE_CF_FETCH_ENABLED=false`, which selects its bundled synthetic fallback instead. This local-only option prevents fresh checkouts from depending on an external metadata request. There are no installs or downloads in the backup/restore test workflow. The tool is not an operating-system network sandbox; retain outbound network restrictions when running it on private data.

```sh
node --test scripts/local-db.test.mjs
```

The suite includes a real isolated local D1 round trip with freshly applied current migrations, two accounts, imports, conversations/messages, cancellation tombstones, settled and held budgets, a saved comparison/trial, authentication verifiers and revoked source/material rights. It verifies unchanged original state, exact round-trip schema/data, preserved owner/cascade and immutable-source triggers, and migration replay as a no-op. A test-only DNS/TCP/TLS guard rejects external Node connections before connection and asserts that Wrangler's update-check path was not entered; Miniflare's loopback traffic is allowed. Additional tests cover WAL data, BLOBs/large integers, corruption, historical schema drift, older migration prefixes, changed migrations/runtime, destination collisions, path/link attacks, foreign-key damage and restrictive permissions.

## Rehearsal and recovery decisions

Stop local Worker processes before restoring or examining a restored target. The snapshot API supports a live source, but a quiet source makes a human recovery review easier. Do not point another process at the new restore target during verification. Restoring creates an independent copy; it does not switch the running application.

After successful verification, an operator can explicitly start the disconnected local application against that target:

```sh
node scripts/wrangler.mjs dev --local --config apps/api/wrangler.jsonc \
  --persist-to .cache/local-db/restores/rehearsal-1
```

Do this only as a deliberate local rehearsal. Restored sessions and invitations may still be valid, source-rights status is historical, deleted records can reappear, and interrupted reservations/comparison leases require the application's normal conservative reconciliation. Do not promote a restored snapshot into a public or production service. Before any genuine recovery, establish authentication invalidation, current rights/policy reconciliation, deleted-data retention handling, the stable passkey RP domain and deployment authorization separately.

This uses Wrangler's current local Miniflare SQLite layout, not Cloudflare's remote D1 export/restore format. The manifest pins the installed Wrangler version and binding. Upgrading Wrangler or changing database identity requires a reviewed compatibility rehearsal; no automatic conversion is attempted. The installed local `d1 export` interface does not expose selection of arbitrary persisted state via `--persist-to`, so the native SQLite snapshot plus actual isolated D1 verification is used here. Remote backup, remote restore, cross-version portability and encrypted off-device retention remain unverified.

The local wrapper forwards interruption/termination signals to its child and waits for closure. The full integration test permits up to five minutes per fresh migration command and eleven minutes overall because cold CLI startup varies substantially in isolated checkouts; this allowance is not an API latency or Worker CPU claim. A timeout remains a failed verification, even when logs show successful SQL.
