> Historical result at 3200fd6. Superseded by the q-URL/SwiftUI route verification in docs/releases/v0.1.18-preview.1.md. NSExtensionContext and SwiftUI openURL are different paths; the latter subsequently succeeded.

# ChatGPT handoff verification — local only, 2026-10-17

The verified production candidate remains explicit preview-and-copy. Direct Share Extension opening, question prefill, and an adopted official button icon remain incomplete. No guessed URL query, private API, responder chain, account token, full conversation or model system prompt is used. Publication remains unapproved. Physical-device crash diagnosis and real Gemma answer quality remain unverified.

## Public opening API: controlled result

Dedicated iOS26.0.1 Simulator 08333859-7E6B-4ED6-9C1D-262DF429F812 has Safari installed and no ChatGPT app. The signed actual Share Extension and containing app were tested, with explicit taps and public HTTPS roots only:

| Caller and destination | Public API | Result |
| --- | --- | --- |
| Actual Share Extension, ChatGPT root | NSExtensionContext.open | false |
| Same Share Extension, Apple developer HTTPS root | NSExtensionContext.open | false |
| Containing app, ChatGPT root | UIApplication.open | true; Safari reached foreground |

`testShareExtensionOfficialOpenAPIProbe` passed all controls, 34.7 seconds, in `Test-ReadingInteractionUI-2026.10.17_10-38-56-+0900.xcresult`. Screenshots show the callbacks and the return from Safari. HTTPS opening therefore does not require the ChatGPT app in this environment; its absence alone cannot explain the extension's failure. The same extension rejects an unrelated browser destination. These are Simulator/host observations, not physical-device measurements.

The [current Apple NSExtensionContext.open documentation](https://developer.apple.com/documentation/foundation/nsextensioncontext/open(_:completionhandler:)) assigns support to each extension point and identifies Today and iMessage support on iOS; Share is not identified as supported. Its current conditions refine the older [Extension Programming Guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionOverview.html). The [UIApplication.open documentation](https://developer.apple.com/documentation/uikit/uiapplication/open(_:options:completionhandler:)) supports ordinary HTTPS and reports handler success. UIApplication is used only in the DEBUG host, never from the Share Extension. All probes are DEBUG fixtures; extension probes are Simulator-only. No inference was sent.

## ChatGPT entry and prefill status

OpenAI's [official site](https://openai.com/brand/) links to the public ChatGPT web root. Its [iOS download guidance](https://help.openai.com/en/articles/7908378-where-can-i-download-the-openai-chatgpt-ios-app-on-the-apple-app-store) identifies the official App Store app. A normal app/browser can open that web root, as verified above. This does not prove that an installed native ChatGPT app will launch instead of the browser.

The [iOS FAQ](https://help.openai.com/en/articles/7885016-chatgpt-ios-app-faq) and [Search guidance](https://help.openai.com/en/articles/9237897-searching-the-web-with-chatgpt) inspected here do not establish a supported third-party iOS prompt-prefill contract. No official commitment for a custom scheme or question query parameter was established. This is an evidence boundary, not proof that no undocumented behavior exists. Such behavior is not adopted as a supported feature.

The minimal supported fallback is: inspect the composed text, explicitly copy it, dismiss the share screen, open the official ChatGPT app or web root manually, paste and review, then choose whether to send. Only the current question, actual original shared text, selected book/chapter/verse and provided translation are copied. The draft remains intact. Clipboard contents are local-only and expire after ten minutes. The device-level visibility preference remains independent of account/AI consent. The final copy/preference native test passed in 58.8 seconds; Swift core has 260 passing tests including prompt bounds/Unicode/context checks.

## Official artwork: reference obtained, button adoption incomplete

The official brand page exposes a download button disabled until its Marks usage checkbox is accepted. The checkbox was not checked and the gated package was not downloaded or bypassed. Its [public brand guidelines and usage terms](https://openai.com/brand/) require a direct service relationship, exact supplied artwork, ownership acknowledgment, appropriate prominence, and no implication of endorsement. The public help article's app-identification image was downloaded unchanged with source URL and SHA256 retained as a reference. That reference image is not treated as an approved developer button package, and is not adopted in the app.

The current button therefore remains plain ChatGPT text, explicitly labeled as preview/copy. Formal icon adoption remains incomplete pending the official download/usage decision. No logo was drawn, recolored, cropped or substituted. No new credentials, fees, backend deployment, remote push, release numbering or feeds were introduced.

## Local deliverables

Branch: integration/local-home-share-content-20261017. Base copy/settings implementation: 3b94ca85d446d0a42183c1da7cf4972cff71b9ff. Follow-up adds only controlled DEBUG probes and this verification record; the production fallback is unchanged. Completed logs, screenshots, installation-control booleans, reference-image source/hash, patch and final source commit are retained in the accompanying local evidence bundle. Raw official documentation is not redistributed in that bundle; the links above are authoritative.
