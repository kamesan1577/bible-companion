# Implementation architecture and boundaries

## Components

The native client lives in `apps/ios`. SwiftUI renders reader/import/chat/developer flows; the Share Extension queues an explicit selection for the app. The API uses Cloudflare Workers, Hono and D1. Public-domain source excerpts and reviewed original Japanese commentary are checked-in, versioned seed data. Public reference cards retain primary-source attribution and a content spoiler endpoint separate from their applicability ranges.

R2, Queues, Durable Objects and an external vector database are not required or provisioned for this initial text-and-reference implementation. Approved artwork is loaded directly from one allowlisted museum image host; no untrusted URL is fetched by the Worker. An image proxy, full-text corpus ingestion and durable asynchronous inference would require separate resource/rights reviews.

## Authentication boundary

The app opens the configured HTTPS browser origin using ASWebAuthenticationSession, with random state and PKCE S256. The browser performs a discoverable, user-verified passkey ceremony. SimpleWebAuthn verifies the actual signature, authenticator data, exact expected origin and RP ID. Registration requires a hashed expiring invitation; registration and invitation consumption are transactional. A native callback carries only a short-lived hashed one-use code and state. The app exchanges the code plus verifier for a bearer session, which is stored hashed in D1 and privately in Keychain on iOS.

No API key or model credential is provided to the iPhone. Existing owner status is server data. Browser cookies are HttpOnly/SameSite/HTTPS-Secure, while native requests use bearer authorization. Lost-passkey recovery, additional passkey management, physical device ceremonies and stable production domain setup remain launch gates.

## Private data ownership

All private route lookups bind the authenticated user ID. Child message/generation rows use composite owner-parent foreign keys. Conversation/import ownership is additionally enforced with SQL triggers without rebuilding a parent table and destroying its children. Private request UUIDs and cancellation tombstones are owner-scoped at access boundaries. Account deletion removes live sessions and private rows; comparison reservations are reconciled conservatively before dependent rows disappear.

Deletion epochs prevent an earlier authenticated import/conversation/comparison claim from recreating bulk-deleted reading data. Export has its own mutation epoch so it can fail and restart after any concurrent private change. Exports are user-readable projections with revoked/stale assistant bodies replaced by explicit markers; they are not an implemented backup restore mechanism.

## Passage and content policy

The parser validates all 66 canonical books using 1,189 chapter counts. Ambiguous distinct references are returned for confirmation rather than silently keeping the first URL or line. A conversation stores the question target and the full user-confirmed reading boundary separately. A narrowed target cannot expand the available reading range or cross a disjoint gap.

Sources must have reviewed rights, valid canonical bounds and trusted provenance. Selection favors target-overlapping evidence before applying bounded context limits. Material cards are filtered by their content spoiler endpoint, and later applicability references are trimmed before delivery. Missing coordinates and unrelated artwork are left absent. Initial coverage is nine excerpt sources and sixteen cards, not complete coverage.

The global source-policy epoch is checked atomically at answer publication to close in-flight revocation races. Historical reads check the actual cited source IDs, immutable versions, rights and spoiler policy. An unrelated source update does not hide a still-valid historical citation. Reusing the same ID/version for different semantic content is rejected even after deletion/reinsertion.

## Answer modes and accounting

Source-only mode returns reviewed source material with an explicit no-AI notice and invokes no model. Reviewed-claim selection permits a model to choose eligible claim IDs, while the server renders trusted text. The optional grounded-generation mode validates structured references and quotations but cannot prove that arbitrary generated prose is free of semantic hallucination or future-event leakage. It remains experimental.

All model candidates start unconnected. Real inference requires provider consent, current model terms review, an approved connected free model and a current budget authority. The default strict mode requires an independently verified token-bound proof. The explicit alternative uses an account-bound, at most24-hour Workers Free billing receipt and direct-binding/no-Gateway/no-Paid policy. Its prepared-input reservations are conservative estimates, not proved hidden-token bounds; account-wide provider refusal is the final stop. No genuine production proof or receipt is configured. Synthetic records/providers exist only in tests. Connection, terms, budget mode/readiness and experimental grounded-generation consent are separate gates, rechecked before dispatch and publication.

Reservation and settlement are atomic SQL operations against global and per-user daily allowance. Proven no-dispatch work settles to zero. Started inference with unknown actual usage retains the conservative reserved amount. Cancellation does not prove upstream computation or billing stopped. Comparisons are client-driven durable jobs, capped at two models and ten questions, with no automatic retries and at most one active job per owner. Starting reserves allowance without inference; each explicit HTTP step atomically claims one trial. Per-trial dispatch markers settle only started work, and expired leases never rerun. See [comparison protocol](comparison-protocol.md).

## Request lifecycle and caching

Cancellation persists even when it arrives before the original question/comparison claim. A transport timeout or GET 404 is not evidence that an original request cannot still execute. Clients preserve the frozen UUID and payload, reconcile that same request, and never mint a replacement UUID as an automatic retry.

Public reading caches contain only fixed reviewed public-data overviews, never private question/history/model preference. Offline eligibility is a server-issued, 24-hour grant for the overview field only when all actual citations are eligible reviewed public-domain sources. Material arrays, images and source text are excluded from this initial offline grant. Manifest changes require revalidation or removal; offline copies cannot discover rights revocation until reconnection.

Reading cache lookup uses the durable source-policy epoch before querying or parsing source/material bodies. Every hit still authenticates the owner-scoped import and rechecks the epoch after reading the cached payload. The key binds passage, translation, spoiler policy, default model, registry/prompt versions, explicit reading-response schema version and pinned primary-corpus manifest/index identity. Source/material publication changes and corpus sealing/revocation advance the epoch; sealed scripture bytes and semantic source/material versions are immutable. Rendering, attribution or offline-grant changes that do not otherwise change those inputs must bump `READING_RESPONSE_SCHEMA_VERSION`. This makes a hit cheaper without treating TTL as a rights guarantee.

The current question endpoint returns one final JSON result. It is not a streaming endpoint. Harness timings measure server validation/readiness; actual iPhone first-visible latency must be measured on the client. Idempotent request replay is supported, but no claim is made of a fully calibrated cross-request AI answer cache.

## Verification and release boundary

Tests run against actual SQLite migrations/triggers and unmocked SimpleWebAuthn cryptographic verification with synthetic local credentials. Wrangler local D1 migrations and Worker dry-run are separate checks. A fresh archived checkout has installed dependencies using the lockfile and passed type, API, design, configuration and bundling checks without preexisting node_modules or ignored files.

Linux Swift core tests and source parsing do not establish Xcode SDK typechecking, signing, rendering, Share Extension delivery or physical iPhone passkeys. Live model quality, actual neuron usage, latency and provider billing behavior remain unverified. No remote deployment, paid plan, persistent provider credential or private GitHub repository has been created by these local checks.
