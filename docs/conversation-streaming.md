# Question answering and native conversation streaming

The Share Extension opens locally, with a persistent question composer and no automatic AI generation. Explicit questions append chronological user/assistant turns. The app keeps its existing initial explanation. The shared SwiftUI screen is compiled into both targets, so the simulator fixture exercises the same view and model used by the extension. The extension controller still handles its existing share-item parsing and hosting.

## Findings

The three supplied screenshots show Acts 24:23–24 and the questions `誰やねんペリクスって` and `ペリクスってだれは`. Both received a description of Felix's actions rather than his identity. The saved conversation also exposed raw diagnostic warnings ahead of the answer.

The configured model is `@cf/google/gemma-4-26b-a4b-it`. Existing settings use `max_completion_tokens: 2048`, temperature 0.2, a 30-second deadline, JSON output, and `chat_template_kwargs.enable_thinking: false`. This change retains that model and reasoning setting. Debug preferences still determine the selected allowlisted model where previously supported.

The question route passes the latest question and server-owned conversation history. It never reads or writes the public standard-explanation cache. Only the fixed initial-explanation endpoint uses that cache, with empty history and public sources. There is no evidence in the inspected paths that these personal questions were answered from another user's cached explanation.

The old prompt required at most three citation-backed claims but did not spell out how to answer identity questions. Primary-text context was clipped to the selected reading's start, so selecting only verses 23–24 could omit earlier identification such as “Felix the governor.” That combination can encourage another summary of the available verses. Model quality alone is not an established diagnosis.

## Changes

- The prompt prioritizes the latest question. Identity questions ask for identity/office/role first; unrelated verse summaries must not replace an answer. Reasoned interpretations are encouraged; uncertainty is limited to the specific unknown rather than repeated as a generic disclaimer.
- Personal questions may retrieve up to 63 preceding verses, with a total background window limit of 64 verses for short selections and the same upper spoiler boundary. The original selection is retained. Initial explanations retain their original retrieval policy.
- History remains owner-scoped and bounded. Source-free general-knowledge replies enter history only when the server explicitly permits that mode. Narrative interpretation is no longer prefixed with a fixed “一般的な説明（出典未確認）” heading. Source-backed supporting claims retain citations and exact quotation checks; uncited narrative does not gain fabricated provenance. When that policy is enabled, the prompt removes the contradictory blanket instruction to refuse whenever cited evidence is absent; strict mode retains its evidence requirement.
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
- Swift package: 188 tests passed, including byte-fragmented SSE, EOF-before-completion rejection, real URLSession preview-before-EOF, request-ID mismatch, cancellation, late results after account switch, transcript ordering and deduplication. Explicit retries replace only the unanswered local attempt, keeping completed turns unchanged.
- App-state harness: 21 existing control-flow checks passed.
- Design contract and five design tests passed.
- Existing keyboard-send/follow-up UI regression passed. The actual Share Extension was opened, switched to local people metadata, and returned to its host three times successfully. The return test waits for a hittable host after the system share sheet, rather than merely an underlying element’s existence.
- Native simulator UI evidence: initial explanation retained, two conversational turns, keyboard-visible send, explicit keyboard dismissal, latest-message navigation, actual SSE preview, interrupted response recovery, shared-screen cancel/retry. Screenshots use deterministic fixtures, not generated live answers.

The screenshots under `verification/conversation/` are actual simulator captures of these fixture-driven views. They contain no real account, credential, or private user conversation.


## Follow-up: share-first questions (October 17)

The supplied IMG_4372 shows startup explanation generation hiding the composer. IMG_4373 shows a code-added general-knowledge heading and evasive wording about whether “Paul was stupid.” These are separate problems: automatic inference and input gating in the share screen; strict claim-centered instructions, fixed rendering labels, and missing earlier appeal context in the answer path.

- Share-item parsing, passage display and local people/place lookup do not call `/share/start` or any AI endpoint. Opening, switching tabs and selecting a passage never generate an explanation.
- The composer stays in a keyboard-safe bottom inset, including during setup failures and a running request. Sending captures the exact draft synchronously. Up to ten follow-ups queue and run serially after the previous response commits, preserving server history order. Failure/interruption pauses the queue; an uncertain request must be checked or cancelled before another dispatch. Nothing silently retries on reopening.
- The extension keeps a bounded, protected, backup-excluded local snapshot for 24 hours in its private container. Authenticated snapshots are keyed by owner, share-capability token and shared content. Signed-out/draft-only snapshots use a separate local-identity scope and cannot restore authenticated answers. Revocation/account changes clear the visible private state; old transport completions remain rejected.
- Prompt v7 asks for a direct answer, a short reason and useful preceding context. Casual questions are interpreted by intent. Facts, interpretations and genuinely unknown inner motives remain distinguished in natural language. Exact quotation, URL/citation allowlists, spoiler checks, consent and budget reservation remain enforced.
- The narrative (`generalText`) is the displayed answer when present; validated supporting claims remain available through source disclosure. It is not relabeled as source-verified. Streaming previews still only contain complete validated supporting claims, while narrative arrives in the terminal response.
- The older 24-verse retrieval window excluded Acts25:9–12 from Acts26:32. Personal questions now fetch selection separately from bounded earlier background, then prioritize evidence relevant to the question within the existing 16-source/20KB model-input cap. The selected range and upper spoiler end remain fixed.

### Quality evaluation limits

Offline regression cases include the consecutive questions “じゃあパウロは上訴しなければよかったの？”, “パウロってバカだったってこと？”, “結局なんで上訴したの？”, the short question “上訴って？”, and a genuinely unknown inner-motive question. Contract tests separately check question/history forwarding, instructions for natural direct answers and reasoned interpretation, retained factual provenance, rejection of invented quotations, and preceding appeal retrieval. They do not measure real Gemma answer quality.

A live evaluation must separately score: (1) directness—does the first sentence answer the question; (2) naturalness—no generic provenance preamble or repeated disclaimer; (3) factuality—facts match evidence, interpretation has reasons, uncertain motives are not invented. Existing application-session/budget-verification limitations still prevent a consent-preserving live Gemma run. No substitute fixture is presented as real inference.
