# Question answering and native conversation streaming

The Share Extension and app now keep the initial explanation and append subsequent user/assistant turns. The shared SwiftUI screen is compiled into both targets, so the simulator fixture exercises the same view and model used by the extension. The extension controller still handles its existing share-item parsing and hosting.

## Findings

The three supplied screenshots show Acts 24:23–24 and the questions `誰やねんペリクスって` and `ペリクスってだれは`. Both received a description of Felix's actions rather than his identity. The saved conversation also exposed raw diagnostic warnings ahead of the answer.

The configured model is `@cf/google/gemma-4-26b-a4b-it`. Existing settings use `max_completion_tokens: 2048`, temperature 0.2, a 30-second deadline, JSON output, and `chat_template_kwargs.enable_thinking: false`. This change retains that model and reasoning setting. Debug preferences still determine the selected allowlisted model where previously supported.

The question route passes the latest question and server-owned conversation history. It never reads or writes the public standard-explanation cache. Only the fixed initial-explanation endpoint uses that cache, with empty history and public sources. There is no evidence in the inspected paths that these personal questions were answered from another user's cached explanation.

The old prompt required at most three citation-backed claims but did not spell out how to answer identity questions. Primary-text context was clipped to the selected reading's start, so selecting only verses 23–24 could omit earlier identification such as “Felix the governor.” That combination can encourage another summary of the available verses. Model quality alone is not an established diagnosis.

## Changes

- The prompt prioritizes the latest question. Identity questions ask for identity/office/role first; unrelated verse summaries must not replace an answer. Missing evidence remains an explicit limitation.
- Personal questions may retrieve up to 24 preceding verses, with a total primary-text context limit of 32 verses for short selections and the same upper spoiler boundary. The original selection is retained. Initial explanations retain their original retrieval policy.
- History remains owner-scoped and bounded. Source-free general-knowledge replies enter history only when the server explicitly permits that mode. General knowledge remains labeled and never gains fabricated citations.
- Initial explanations and private chat remain separate. Transport negotiation is excluded from the fixed explanation cache key. Personal chat is not published to the shared cache.
- Native clients explicitly request SSE. JSON clients and old JSON responses remain compatible. No automatic generation retries are introduced.
- Both native views use chronological chat rows, a keyboard-safe composer, a visible stop control, and a latest-message button. Returning to a conversation reloads saved messages; older pages are available. Developer warnings and budget details are behind the existing developer disclosure.

## Streaming contract and limits

Cloudflare's [current Gemma 4 model specification](https://developers.cloudflare.com/workers-ai/models/gemma-4-26b-a4b-it/) documents `stream: true` and SSE message deltas. The Worker consumes that real provider stream. It emits:

| Event | Meaning |
| --- | --- |
| `progress` | An observed phase: request preparation, generation dispatch, provider text receipt, validation, persistence, or cache retrieval. |
| `preview` | A complete claim received from the provider, checked with the existing citation/reference validator. It is provisional until the full document and current policy pass. |
| `complete` | The existing `RequestResult`, after full validation and persistence. |
| `failure` | A bounded status/code envelope. The client discards provisional text and retains the request identity for status recovery. |

This is claim-level streaming, not a character-by-character type animation. Raw JSON, incomplete quotations, internal reasoning, and unverified general-knowledge text are never forwarded as previews. A model that uses a different JSON key order, returns only general knowledge, or has not completed a claim will show truthful progress until final validation. Cache hits return the saved result directly without simulated token output.

Client sessions are ephemeral with no URL cache or cookie storage. Transfers and frame parsing are bounded, UTF-8/CRLF fragmentation is supported, redirects are rejected, and a terminal event is required. Canceling discards provisional text. The existing request ledger and cancellation/status endpoints prevent blind retries. Share cancellation is restricted to the exact share capability; an unknown pre-claim request remains uncertain and must be checked rather than treated as safely unprocessed. Cloudflare's binding does not document an AbortSignal for AI.run, so stopping the UI cannot promise to reverse provider work or usage already incurred.

## Validation

No live AI request, production deployment, distribution update, new credentials, or billing change was made. Deterministic provider fixtures verify the request contract and streaming behavior; they do **not** establish live Gemma answer quality or speed. A budget-authorized live acceptance check of the two screenshot questions remains for rollout coordination.

- TypeScript typecheck and Vitest: 636 tests passed.
- Swift package: 187 tests passed, including byte-fragmented SSE, EOF-before-completion rejection, real URLSession preview-before-EOF, request-ID mismatch, cancellation, late results after account switch, transcript ordering and deduplication.
- App-state harness: 21 existing control-flow checks passed.
- Design contract and five design tests passed.
- Native simulator UI evidence: initial explanation retained, two conversational turns, keyboard-visible send, actual SSE preview, interrupted response recovery, shared-screen cancel/retry. Screenshots use deterministic fixtures, not generated live answers.

The screenshots under `verification/conversation/` are actual simulator captures of these fixture-driven views. They contain no real account, credential, or private user conversation.
