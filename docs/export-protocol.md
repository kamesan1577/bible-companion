# Private export protocol

## Availability and scope

The API supports a small-account JSON download and a bounded paginated export. The native protected-file export/share flow is implemented in source and covered by Foundation tests; its Apple SDK and device share-sheet lifecycle remain unverified. The API exports the authenticated account’s imports, conversations, messages, saved comparison results, settings and model preference. It never exports passkeys, bearer/session tokens, authentication challenges, invitation tokens, request hashes or another account’s data.

User-authored questions are preserved. Assistant bodies whose cited sources are no longer approved/current, or which violate the conversation’s current spoiler setting, are replaced with `{ "hidden": true, "reason": "source_or_spoiler_policy_changed" }`. The message ID, role, timestamp and user question remain. An unrelated source update does not by itself erase a valid historical citation. Public citation `(id, version)` content is immutable; semantic corrections require a new version. This is a filtered user-readable export, not a full database backup or an implemented restore format.

## Small-account endpoint

`GET /v1/me/export` returns the normalized account document when the account contains at most 1,000 export entities and 1 MiB of raw import/message/comparison JSON. The server checks these limits before loading the account bodies. Larger accounts receive HTTP 413 with `export_requires_pagination`. No partial success or silent truncation is returned. Concurrent private writes or source-policy changes return HTTP 409 `export_changed`.

## Bounded snapshot flow

1. `POST /v1/me/export/snapshots` with `{}` and the bearer session.
2. Save the returned metadata privately: `version`, `snapshotId`, `createdAt`, `expiresAt`, `user`, `settings`, `modelPreference`, and `sections`.
3. For each section (`imports`, `conversations`, `messages`, `comparisons`), request `GET /v1/me/export/pages?snapshotId=…&section=…`.
4. Write each returned item incrementally to the protected output file. Follow the opaque, URL-encoded `nextCursor` in the same section until it is null. Do not construct cursors or reuse one in a different section/snapshot.
5. Only after every section completes, finalize the JSON file and expose it for explicit user sharing.

Every page contains at most 25 items and at most 1 MiB of encoded JSON. A single entity larger than 1,000,000 bytes receives HTTP 413 `export_entity_too_large`; no fields are truncated. The initial supported export does not split an individual message/comparison across pages.

A snapshot lasts 15 minutes. Starting a new one replaces the previous snapshot for that account. Snapshot records contain ownership, epochs, upper row bounds and expiry, not private message bodies. Every request still requires the same authenticated owner. Another account receives 404 even with a valid snapshot ID.

## Consistency and concurrent changes

This is an optimistic, restartable snapshot, not a long-held database transaction. Initial per-section upper row IDs exclude later inserts. A separate monotonically increasing private export epoch changes on import, conversation, message, comparison, model-preference or account-settings mutations. The server checks that epoch, the bulk-deletion epoch and the public source-policy epoch before and after each page projection.

Any intervening private write, delete or public source-policy change invalidates the snapshot with HTTP 409 `export_changed`. Expiry returns `export_expired`; replacement/deletion returns 404. Discard the incomplete output and restart. A successfully received earlier page is not sufficient to call the whole export complete. Source revocation during projection cannot be silently mixed into later pages.

The client should avoid starting an export while a comparison or chat is running. It must not automatically retry forever against an actively changing account. Show the reason and let the user restart once activity has settled.

## Native implementation requirements

Assemble pages on disk, not as one growing in-memory array. Use an app-private temporary directory with complete file protection, exclude it from backup, and never put exports in the shared public-reading cache or App Group import queue. Keep authentication material out of the file name and contents. Close and remove incomplete temporary files on cancellation, decoding failure, 401/404/409/413, or share-sheet cancellation. Remove the completed temporary export after the explicit sharing operation finishes. Sharing the file with any destination must remain a deliberate user action.

The native implementation follows these requirements with bounded incremental assembly and cleanup tests. This is not a claim that its file/share lifecycle has been tested on iOS.

## Backup and recovery boundaries

No remote backups or restore jobs have been configured. Production backup retention and deletion timing remain launch decisions. Account deletion removes live private rows and sessions; it cannot promise immediate erasure from a provider backup that has not yet been configured or audited. Lost-passkey recovery and importing an export back into an account are also not implemented. Do not present export as an authenticated account-recovery bypass.

Page retrieval first reads only row identities and byte lengths, then loads at most1MB of raw bodies. Oversized individual entities fail explicitly before loading; user content is never silently truncated.
