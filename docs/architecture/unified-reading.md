# One reader in the app and Share Extension

The shipped 0.1.19 app and extension contained identical copies of all 168 Core resource files. The UI divergence came from two separate reading trees: the app exposed static commentary and public material cards, while the share sheet exposed generated explanation/chat and an offline entity pane. Counts alone do not establish factual accuracy. The unified reader retains the app's static commentary, original English commentary/dictionary, public material cards, offline entity profiles and artwork/map details in both targets.

`UnifiedReadingView` and `ExternalQuestionComposer` now compile into both targets. The four sections are 解説 / 地図 / 人物 / 絵画. A segmented picker and horizontal gestures select them; accessibility text sizes use a menu. Both surfaces retain the shared original above the content and place the composer in a bottom safe-area inset. The existing home discovery artwork remains, alongside the most recent opened passage. A local history lists the latest 100 records without deleting older files.

`POST /public/reading` accepts only a validated passage and optional translation. It calls the same public projection builder as authenticated import reading, including source-policy epochs, rights validation and public cache dependencies. It accepts no shared original, question, messages or account fields, writes no private reading history and invokes no model. The bundled corpus remains available if public materials fail to load. Existing private/cloud conversations remain readable; their UI cannot start another first-party question. Legacy server endpoints remain for compatibility with already distributed clients.

## Questions continue in one selected external service

The setting is shared through the existing App Group. Sending deliberately includes only the displayed passage, available shared original and current question, built through `ChatGPTCopyPrompt`. No previous conversation, app session/capability or backend prompt is included. The complete prompt is copied locally with a 10-minute expiry. No text is silently truncated.

- ChatGPT uses the existing HTTPS `q` handoff within the conservative URL length limit. The UI says an answer may start when opened. A long prompt falls back to full copy plus the base URL.
- Claude and Gemini use full copy plus their base HTTPS pages. The user must paste and send. The UI does not claim URL opening is prompt delivery.
- A native SwiftUI `Link` delegates opening to the system. There are no responder-chain hacks, private APIs, new credentials or new AI charges. Missing native apps can use the browser. Opening failures and provider login/app behavior cannot be fully observed by this app, so input remains available for retry.

Official references checked on 2026-10-18:

- [Claude desktop links](https://support.claude.com/en/articles/14729294-open-claude-desktop-with-a-link) document desktop prompt prefilling; this is not an iOS consumer-chat guarantee.
- [Claude mobile links](https://support.claude.com/en/articles/14898120-open-the-claude-mobile-app-with-a-link) document Claude Code routes and access requirements; arbitrary normal-chat prefilling was not established.
- [Gemini on iOS](https://support.google.com/gemini/answer/13275745?co=GENIE.Platform%3DiOS&hl=en) describes entering/submitting a prompt; an arbitrary-prompt URL contract was not established.
- [SwiftUI Link](https://developer.apple.com/documentation/swiftui/link) is the public link-opening surface used by both targets.

## Local records and account boundaries

New records are independent of legacy share AI configuration and cloud history. The App Group stores the selected provider, an active-reading owner marker, hashed per-owner `ReadingVisits` records and per-owner/context `ExternalDrafts`. Payload files use atomic writes and complete file protection, excluded from backup through the containing folder. No external AI answer is saved by this app. A context identity includes passage, translation and exact shared original; it cannot mix two originals or translations.

Reads/writes check the owner marker inside coordinated storage access. The composer rechecks the marker immediately before copying/opening and when returning to the foreground; another owner revokes the open draft. Account transitions replace the root view and read only the new owner's records. Provider choice is device-wide; originals and drafts are not. Anonymous activity stays anonymous rather than being silently assigned to a later account. Expiry/401 invalidates the visible authenticated session without deleting prior stored records. Existing explicit logout/data-deletion controls retain their separate confirmed lifecycle. New local visit/draft folders are retained behind their owner boundary; the settings label explicitly identifies the legacy cloud-data deletion scope. A separate local deletion UX is not introduced by this change.

This change does not migrate/delete old cloud histories, change corpus files, add database migrations, grant new service permissions, or claim external provider answers stream back into the app. It does not call the old first-party model from the normal reading UI.
