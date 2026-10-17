# Share renewal and interrupted answers

This change follows the 0.1.18 release. The reported screens showed no clear save confirmation, a user turn labelled both sent and waiting, a disappeared streaming preview, and a confirmation sheet before every ChatGPT handoff.

## Confirmed causes and limits

SharedPreviewModel and QuestionModel cleared `preview` in their completion cleanup on both success and failure. The only received text was outside the transcript, so a failed request removed it. Queued submissions also remained in the pending array until a complete response; the UI labelled the active submission as unsent. The screenshot's generic server error does not identify whether the upstream failure was a timeout, provider failure or final answer validation. This patch does not claim that underlying production failure has been reproduced or fixed. It retains individually validated previews as incomplete entries and surfaces a safe status/code. Transport-level interruption carries the latest preview with its error, avoiding a race with queued MainActor display updates. Authentication and policy revocation never retain that provisional text.

The preparation screen already wrote and read back capability bytes, but its success branch also depended on a separately refreshed policy snapshot. Transient policy loads can clear that snapshot, and errors were nested inside the not-ready section. Save results now have their own visible section; success is set only after owner-bound file readback. Local save success and extension read acknowledgement are distinguished.

## Renewable share access

Migration 0025 adds hashed refresh credentials and a short-lived access-token mapping. It is additive. A refresh credential remains share-only, expires with its original parent login (currently at most 30 days), and cannot call the general API. Access tokens remain bounded to 24 hours. Refresh checks the current parent session, account epoch, provider consent, grounded policy consent and share consent; it never creates consent, performs inference, or changes budgets. Renewal is rate-limited. Retrying a lost renewal response is safe: the same refresh credential issues another short-lived token within the same scope, and an earlier still-valid token remains valid only until its own expiry.

The stable scope remains the original share_ai_access primary key, preserving conversation ownership, request status, cancellation and idempotent start. A refresh token cannot cross into another share scope or account. On consent withdrawal, existing share credentials are invalidated permanently, so re-consenting cannot revive a leaked old refresh token. Logout removes the parent session; account epoch changes and server policy changes also stop access. No automatic account login renewal is introduced.

The extension renews on the first question and before subsequent send/status/cancel operations when needed, without opening the containing app. The app also renews on foreground. Credentials are stored atomically with complete file protection in the existing backup-excluded App Group directory. Compare-and-save rejects late network results after account change, logout, or another scope replacing the credential. The normal account session is never given to the extension. Existing non-renewable installations require one app-side preparation to obtain the new credential format; this is not an indefinite credential.

## ChatGPT handoff

The normal composer action opens the existing q URL directly. The fallback sheet appears only when opening is rejected or the URL exceeds the explicit interoperability size policy. Drafts remain unchanged, presentation visibility settings remain separate, and the accessibility label describes an external destination. Shared representations are deduplicated without deduplicating repeated phrases inside scripture; an exact repeated whole block is collapsed in the outgoing prompt. No history, account identifier, session credential or system prompt is exported.

The owner approved the OpenAI Marks usage terms. The official consent checkbox was then accepted at https://openai.com/ja-JP/brand/ and the supplied black/white Blossom PNGs are included unchanged. The external-link symbol is an adjacent separate element. See [asset provenance](assets/openai-marks.md).

## Verification and rollout

API tests cover expired-access renewal, continuation in the same conversation, zero inference during refresh, general-API rejection, separate share scopes, lost refresh responses, logout, consent withdrawal/regrant, account epoch, parent expiry and refresh expiry. Swift tests cover owner-bound expired credential reading, split streams, missing terminal frames, partial error transport and persistence. Native UI tests use fixture transport; they do not establish physical-device crash resolution or real Gemma answer quality.

Apply migration 0025 to the existing D1 database before deploying this Worker, then release the matching client. No new database, plan, model or general credential is needed. The current restricted deployment OAuth did not include D1 write, so the production migration application path must be resolved without silently expanding access. After normal Wrangler credential refresh, Worker settings are readable but a read-only D1 metadata probe still returns HTTP 401 (10000). The current granted scopes are user/read, account/read, workers/write, workers_scripts/write and offline access. No new login or D1 scope has been requested. Do not deploy the Worker before the schema exists. Keep the existing 0.1.18 release and feed intact until this change is ready for its own release.

### Local acceptance evidence

- TypeScript typecheck, 648 API/harness tests and the design contract passed.
- Swift package: 270 tests passed. App-model harness: 21 control-flow checks passed, including simultaneous share-save coalescing and rejection of late writes after account/session or consent changes. Storage boundaries in that harness are fakes.
- Native simulator acceptance: save/readback/relaunch/expiry, failed save, retained interrupted answer with keyboard input, direct external q handoff, long-body fallback/main copy, and cross-process visibility preference all passed. One earlier visibility test attempted to close a sheet already dismissed by its copy action; the corrected focused retest passed. These are case-level results, not a claim that the earlier combined run was entirely green.
- Actual simulator screenshots were inspected for the saved/readback state, retained partial answer and adjacent unmodified official logo/external symbol.
- No live Gemma request, new inference budget, release build, source archive copy, production schema change, production deployment or new release was performed during this follow-up. Existing build directories were reused and no local cleanup was performed.

### Production access checkpoint

Account: `kamesan1577` (`caa16bf3ff27f1e044c12a02af8dda1b`). Existing database: `bible-companion`, binding `DB`, UUID `0c0f9384-2f2d-415f-84ba-50fa6fc77bdd`.

The official D1 dashboard link https://dash.cloudflare.com/?to=/:account/workers/d1 redirected to this account's `/workers/d1` page, but the page's UI reads timed out while the Mac was locked. No D1 console permission decision or SQL result was observed; do not describe this as an account-level denial. No browser cookies or private dashboard API were extracted and no Worker endpoint was added to bypass restricted D1 API access.

Preferred continuation: unlock the Mac, open the existing D1 dashboard, select the exact database UUID, and inspect its Console and migration history through the normal UI before applying migration 0025. Verify columns, index and token table after application. If normal dashboard access is unavailable, the additional official Wrangler scope needed is `d1:write`. This is not included in the currently granted restricted CLI scopes. A fresh standard OAuth flow must be separately approved and its final grant performed by the owner; no such flow has been started for D1. The existing 0.1.18 release and stable feed remain public and unchanged.

A follow-up identity guard also covers drafts opened without AI access: account changes, sign-in from a signed-out scope, or an unreadable local identity clear the draft and block both AI submission and external handoff. Same-owner ChatGPT handoff does not require an AI capability. `Scripts/StateHarness/ShareDraft.swift` was compiled with the exact model declaration preceding SharedPreviewView, DEBUG and the fake storage boundary; these isolation cases passed without network or filesystem persistence. Native layout acceptance above predates this final model-only isolation guard; the previous UI rendering and logo assets are unchanged.
