# Operation, recovery and distribution

## Local recovery

Stop the failed step and retain its log/result/job root. Use `make doctor`; inspect `git status`, tool versions and the failing assertion. Re-run the smallest failing test before the complete relevant gate. `make setup` re-creates Node dependencies from the lockfile. Build caches under `.cache/harness` may be removed when no build is using them; generation checkpoints are not disposable caches. Keep them under a separate named root.

Use [local backup/restore](../local-backup-restore.md) for database backup rehearsals and [OPERATIONS](../OPERATIONS.md) for remote recovery. Existing tests restore into a separate target; never overwrite the only copy of user data. The harness does not back up production or grant account recovery. Secrets, recovery exports and private job outputs stay outside Git and public CI artifacts.

CLI member invitation tokens currently expire **one hour** after creation (`scripts/infra.mjs` and `scripts/operator.mjs`, `seconds + 3600`). They are hashed, user-role invitations, and consumed transactionally only after successful registration; the recipient registers their own passkey. Do not issue real invitations during verification. Tests validate the local generation/role/expiry and registration isolation paths.

## Source and candidate provenance

`make source-audit` inspects tracked Git objects, including iOS, Share Extension, API, packages, bundled data and generation tools. Use `python3 scripts/harness/run.py audit-source --ref origin/main` after fetching to audit the published branch, rather than assuming an untracked local checkout or Release ZIP is complete. It is a targeted source/path gate, not a comprehensive secret scanner; also inspect staged diff and `SECURITY.md`.

The existing `npm run source:export -- --commit COMMIT_SHA --output /tmp/new-source-export` exports an exact Git commit with deterministic manifest/checksums; the output directory must be new and outside the repository. `source:export:test` checks completeness and private-path rejection. Verify the manifest/hash before handing an archive to another developer. A Release asset is supplementary; ordinary repository checkout must remain sufficient. Do not check in user backups or binary caches to make a build work.

`python3 scripts/harness/verify-ios-artifact.py PATH_TO_APP_OR_IPA` validates the version/build against this checkout, main/extension bundle identity, Mach-O executables, Share Extension point, privacy manifests and hashes of every bundled data/license resource. `make build` runs this automatically on its simulator app. Run it on an existing IPA before distribution; it reads ZIP entries without extraction. It does not sign or publish anything and does not establish entitlement/signature correctness.

`make ios-device` builds Release for the physical-device SDK without signing and packages `Payload/BibleCompanion.app` with `ditto` into a timestamped unsigned IPA under `.cache/harness/`. It runs the same artifact verifier and prints the artifact SHA256. The default candidate has the safe unconfigured API endpoint and supports bundled offline content; it is not a configured production service. An existing signing/SideStore workflow must re-sign it before installation. The command neither increments versions nor uploads a release/feed, and creates no signing identity.

For a signed IPA, use the established [Mac acceptance](../../apps/ios/MAC-ACCEPTANCE.md) and the existing release notes, with an existing signing identity. Inspect app and extension bundle IDs, matching App Group entitlements, embedded extension, supported OS, privacy manifests, bundled data/license notices and exact commit/build result. Match the release/source manifest and final artifact SHA256 to the intended commit; signatures/attestations record provenance, not correctness. Preserve build/installation evidence. Simulator `.app` packages are not installable iPhone IPAs.

Version/build counters, release notes and update feeds change only in a dedicated release task after relevant checks. Never publish an untested archive, mutate an existing release in place, claim unsigned simulator output is device-tested, or use automatic deployment as a side effect of PR CI. Keep artifact upload optional and privacy-reviewed; CI logs must use fixtures only. This harness adds no deployment credentials or remote migrations.

## Handoff/restart

Read `AGENTS.md` and `HANDOFF.md`, check the latest main and competing branches, reproduce the recorded command, then take the next small step. A finished PR includes what changed, exact validation and unresolved machine/device/semantic gates. A later release worker must rerun gates on its combined commit, especially after concurrent data changes; successful harness-branch tests do not cover data merged afterward.
