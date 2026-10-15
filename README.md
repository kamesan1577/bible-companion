# 聖書読書コンパニオン

Private, native-iOS companion. The app receives a YouVersion passage, preserves the reader’s context, isolates accounts, and filters reviewed source material to the confirmed reading boundary. Experimental generated prose is not claimed to have a proven semantic spoiler guarantee.

## Independent development harness

Start with [AGENTS.md](AGENTS.md) and the [harness guide](docs/harness/README.md). `make doctor && make setup && make check` validates a clean checkout without production credentials or live AI. On a Mac, `make swift`, `make build`, and `make ios-ui` cover core tests, unsigned app/Share Extension builds and actual native UI regressions. See the [handoff](docs/harness/HANDOFF.md) for verified results and remaining gates.

## Local development

Node.js 24+ is required. No external credentials are required for tests or local data work.

```sh
npm ci
npm run validate
npm run migrate
npm run infra -- invite-local --role owner
npm run dev
```

`npm run infra -- plan` prints the setup plan. `npm run deploy:dry-run` builds the Worker without publishing. `npm run infra -- validate-config` checks the selected local configuration. The repository does not create accounts, provision paid resources, or deploy itself.

## Layout

- `apps/ios`: native SwiftUI client, Share Extension, protected local storage and portable core tests
- `apps/api`: Cloudflare Workers/Hono API, D1 migrations, browser passkey entry page
- `packages/core`: canonical passages, import parsing, spoiler boundary and cache identity
- `packages/ai-harness`: server-only model registry, provider adapter and grounded answer evaluation
- `docs`: API, architecture, operations, provenance, acceptance evidence
- `scripts/infra.mjs`: explicit local infrastructure and private repository commands

## Safety defaults

AI is disabled and has no remote binding by default. Every candidate starts unconnected; paid/unknown models are never silently enabled. All personal API routes require a hashed bearer session and owner-scoped queries. Shared Bible text is parsed transiently; the server persists canonical references and source metadata, not the shared text. No JCB text is bundled. Developer mode is server-enforced owner-only. The iOS app never asks for provider API keys or account passwords; it uses browser passkeys and receives its own app session.

The browser passkey flow uses a stable configured RP ID/origin, invitation-based registration as the initial abuse/cost-control default, user verification, short-lived one-use challenges, and a 60-second one-use native return code bound to PKCE S256. Production requires a stable HTTPS domain; changing RP ID later can strand existing passkeys.

## Current verification boundaries

SQLite-based tests verify real migrations and account isolation. Local Workers dry-run is separate from deployment. Physical iPhone signing, SideStore, share-extension delivery, browser passkeys on device, live AI quality/latency and operational cost are not established by unit tests. See the [specification acceptance map](docs/acceptance-status.md), [architecture](docs/ARCHITECTURE.md), [export protocol](docs/export-protocol.md), and [operations guide](docs/OPERATIONS.md) for evidence and go-live gates.

No public service has been deployed. The ordinary GitHub source tree is sufficient for development; see the harness source audit and commit-bound source export. Backend deployment and signed-device distribution are separate steps.

The initial data set has nine reviewed WEB grounding excerpts and sixteen primary-source material cards. This is deliberately partial coverage, not a complete biblical encyclopedia. No live AI call has been made. The grounded-generation mode remains experimental and is not claimed to prove semantic spoiler safety.

Invitation-only registration is an implementation default proposed for the initial launch, not a user-requested permanent restriction. Supporting open self-registration requires an explicit registration mode and abuse/cost controls; see the future-mode design in `docs/OPERATIONS.md`. It is not enabled by this repository.

## Private local recovery rehearsal

`npm run db:local -- inspect` checks the local database. `npm run db:local:test` verifies isolated backup/restore without remote credentials. Backups contain private data and authentication verifiers, remain Git-ignored, and cannot overwrite an existing target. Read [local backup/restore](docs/local-backup-restore.md) before using snapshots. This is not production recovery or a public export format.

## Optional public-domain English text

The [primary-text corpus workflow](docs/scripture-corpus.md) prepares a byte-pinned 66-book World English Bible selection locally. It preserves empty/missing/unsupported source references instead of silently renumbering them. Runtime retrieval distinguishes literal English scripture from reviewed Japanese commentary; it does not claim JCB alignment. Corpus download/import is explicit and optional, and no corpus is deployed by the checked-in configuration.

### Explicit AI modes and operator activation

The API supports reviewed-claim selection and experimental grounded generation. The latter can use verified public-domain primary text beyond the curated Acts examples, but requires an operator allowlist and a separate current user acknowledgment of semantic/spoiler limitations. Changing modes changes the frozen request/comparison identity. Revoking consent blocks dispatch and publication; it does not claim that an already-running provider can be cancelled.

Budget activation is closed by default. The alternative Free-provider-hard-stop mode requires a current, account-bound operator receipt for the **Workers billing Free plan**, direct Workers AI binding and no Gateway credits, Paid models or fallback. Its reservations are estimates, not proven token bounds or measured billing. Account-plan changes require revoking the receipt first; a receipt is a time-limited human-reviewed snapshot, not continuous provider attestation. No real receipt, terms acceptance or model connection has been installed. See the [operator activation guide](docs/operator-activation.md) for the future authorized workflow, including optional pinned corpus assets, cleanup scheduling and explicit allowances.
