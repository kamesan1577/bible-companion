# Operations and launch gates

## No automatic spending

The checked-in configuration contains a placeholder D1 ID and no AI binding. All commands default to local execution or dry-run. Enable Workers AI only after account access, free-plan behavior, current model availability, per-model parameter schemas and reservation estimates are verified. An application neuron budget is an estimate and cannot independently guarantee the provider’s invoice; the provider account’s free-only plan is the final spending guard. Never switch plan or enable a paid model automatically.

Required decisions before deployment: permanent RP domain, intended owner invitation, data retention and backup erasure timetable, account-recovery procedure, text/image license scope, enabled models and per-call conservative reservation. No third-party logging of private bodies is configured. Cloudflare platform logs/retention must be reviewed at account setup.

## Passkeys and recovery

`/auth/authorize` is opened in ASWebAuthenticationSession with a cryptographically random state and PKCE S256 challenge. The app must retain verifier/state in protected storage for the in-flight session, compare returned state exactly, exchange code once, and keep the bearer session in Keychain. Never trust callback parameters before checking state. Never place a bearer token in a URL.

Registration is invitation-only. Owner role comes from a server-created invitation, not a request parameter or first-user shortcut. Local invitations are created by `npm run infra -- invite-local --role owner`. Remote invitations must be created by an authenticated operator only after account authorization. Tokens are shown once, hashed in D1, expire after 24 hours and are transactionally consumed at successful registration.

Lost all passkeys: no email bypass is implemented. Administrative recovery policy remains a launch blocker. Do not reset ownership based only on an email address. A verified recovery process and multiple passkey registration are required before relying on this as the sole copy of history.

## Maintenance

The Worker’s scheduled handler removes expired authentication data, sessions, rate windows and public cache records. Schedule configuration is intentionally absent until deployment is approved. At launch, schedule daily cleanup and establish budget-reservation recovery: interrupted unknown-use calls remain conservatively charged, not refunded. UTC daily budgets are separate from the user’s local calendar day.

D1 migrations must be applied before Worker deployment. Rehearse against a local database and a backup before any production migration. Do not delete production databases or backups as part of setup. User export includes only the authenticated account’s data. A retention policy for deleted data in backups remains required.

## Validation ladder

1. `npm run validate`: static type checks and actual SQLite invariant tests.
2. `npm run migrate`: local Wrangler D1 migration compatibility.
3. `npm run deploy:dry-run`: Worker bundling, without upload.
4. Local browser WebAuthn test with virtual authenticator, origin and replay tests.
5. Physical iPhone/SideStore registration, cancelled flow, callback, replay, and offline import recovery.
6. Only after explicit connection approval: one selected free-tier model’s connectivity, Japanese grounded-answer quality, TTFT, consumption and cutoff.

Do not treat passing steps 1–3 as proof of 4–6.

## Request reconciliation and private deletion

Keep a frozen request UUID and payload until its outcome is reconciled. A transport timeout or GET 404 does not prove the original request stopped. Retry with the same UUID. Cancelling a valid UUID records a durable owner-scoped tombstone even before generation claims it; the tombstone remains until account deletion. A completed request cannot be cancelled retroactively. Provider dispatch already in progress may still incur usage.

Private reading-data and account deletion require authentication within the last five minutes and the exact documented confirmation string. Reading-data deletion increments an account epoch so previously authenticated, delayed import/conversation/comparison claims cannot recreate deleted data. In-flight publications require the original conversation and current source-policy epoch. Deleted account reservations with uncertain usage are settled conservatively before dependent rows disappear. Backup erasure is explicitly pending a deployment retention decision.

## Reviewed material cards and offline refresh

Sixteen primary-source cards are seeded with explicit provenance, content spoiler bounds and episode-specific applicability. Place coordinates are unknown rather than fabricated. The sole initial artwork is tied to Acts 9:3–7 and its public-domain museum record; it is not shown as an Acts 18 illustration. Automatic image loads permit only the reviewed api.nga.gov HTTPS host without credentials or nondefault ports. The native client must also reject redirects and limit streamed bytes.

Recheck the authenticated content manifest before showing previously downloaded reference material online. Any manifest version change invalidates cached materials, including same-version content corrections. Reading responses and AI publication check a database policy epoch; rights revocation invalidates both public cache identities and saved answer visibility. Historical answer display checks its actual cited source versions and current rights; an unrelated source update does not hide a still-valid answer. Export retains user-authored text and questions, replacing unavailable assistant/comparison bodies with explicit markers rather than silently removing history. Offline copies cannot learn about a revocation until reconnection, which remains a visible offline limitation.

The checked-in scaffold validator accepts the disconnected profile. The separate prepared operator profile supports explicitly reviewed Free-only AI, a stable custom domain, pinned scripture Assets and an optional fixed daily cleanup schedule; its plan/prepare steps do not authorize or execute deployment. Actual remote apply requires exact target/action confirmation and existing account authorization. Logging remains disabled, and setting an environment string is not proof of account/model review. API and CLI share the same authentication origin/callback validation. Node 24 is required for native TypeScript imports used by code-generation and validation scripts.

See [private export protocol](export-protocol.md) for bounded snapshots, concurrent-write restarts, explicit per-page/entity limits and source-implemented native protected-file handling with device validation pending. Public source revision records retain only reviewed public semantic identities so a deleted identifier/version cannot later be reused for different evidence. They are not private reading history.

Seed generators are check-only for existing migrations (`npm run seed:check`). They refuse to rewrite migration history. Reviewed source/card changes require an explicitly new later-numbered output via `--output`, a new content version where semantics change, and updating the generator's declared current target for subsequent checks. Review rights revocations before applying a new seed: a regenerated approved seed is not permission to silently reapprove a revoked source.

The checked-in Wrangler wrapper accepts only local development/local D1 operations and deploy dry-run, with a validated in-repository config. It rejects remote deployment, login, remote D1 and resource provisioning. Actual production operation remains a separately authorized operator step.

## Future open registration mode (design, not enabled)

Invitation-only registration is the initial operational default to limit abuse and cost during unverified deployment. It is not a claim that the product must remain closed to other readers. A future explicit `registrationMode: open` would still create member accounts only, require a valid user-verified passkey, bind browser challenges to the configured origin, and atomically create the account/credential. Owner promotion would remain a separate authenticated administrative action, never a first-user or client-role shortcut. Opening registration requires per-IP/per-device challenge limits, account-creation quotas, abuse monitoring that avoids logging religious/private content, storage limits and a provider-free-only cost gate. No mode switch, signup advertisement or remote enrollment is enabled here.

## Free-plan platform limits and launch measurement

Checked against current official documentation on2026-10-13: Workers Free allows10ms CPU per HTTP invocation,128MB per isolate,50 external subrequests and six simultaneous outgoing connections. Network/database waiting is excluded from CPU time. `waitUntil` extends work only up to30seconds after response/disconnection. These are launch constraints, not performance results. [Workers limits](https://developers.cloudflare.com/workers/platform/limits/)

D1 Free permits50queries per Worker invocation,100bound parameters per statement, six simultaneous connections,100KB SQL statements and2,000,000-byte rows/strings/BLOBs. Local tests count prepared statements conservatively, but cannot certify deployed CPU or memory. [D1 limits](https://developers.cloudflare.com/d1/platform/limits/)

Workers AI's free allocation is10,000Neurons/day, resetting at00:00UTC. Local Wrangler inference also consumes allocation. No live inference was used in these tests. Pricing and quota do not establish verified per-request hard bounds; all real models remain gated. [AI pricing](https://developers.cloudflare.com/workers-ai/platform/pricing/) and [AI limits](https://developers.cloudflare.com/workers-ai/platform/limits/)

The [comparison protocol](comparison-protocol.md) spreads evaluation across one durable trial per explicit request. Catalog and plan proof reads are batched. Public retrieval excludes individual serialized records above64KiB, bounds source/card collections to1MiB each, and skips cache storage above1.8MB. The native transport remains independently bounded. Zod4.6.7 is currently locked. Physical deployment CPU/memory measurement, genuine provider bounds and actual quota behavior remain release gates; no paid-plan switch is implied by passing local tests.

## Optional corpus bootstrap and write allowance

The real local WEB import has31,103 immutable verse rows, including unsupported/empty source markers. It is not a remote bootstrap result. D1 Free currently includes100,000 written rows/day; indexed-column writes add index entries and DDL can also count. Consequently, importing the complete indexed corpus can exceed a single day's free write allowance. Account-wide existing usage matters too. Do not infer free remote import from the small archive size or from local success. A future remote D1 procedure must measure and pace staged work across resets, or use the separately reviewed immutable static-asset adapter, without upgrading plans automatically. [Official D1 pricing and row accounting](https://developers.cloudflare.com/d1/platform/pricing/)
