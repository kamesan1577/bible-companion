# Reading home and shared AI setup

Scope: public main 1944c6f (0.1.17), branch codex/reading-home-share-ux.

The October 17 request replaces the empty reading landing state with a large, working content entrance. The featured card opens the bundled Acts 18:24–28 people and places, without authentication, an API request, a new import, or invented progress. A title, reference, and explicit Open action establish the hierarchy. Chapter browsing remains a separate native action. Shared AI status and its settings live together below the content. Existing opaque reading surfaces, semantic typography, black/white palette and restrained accent are retained. Native glass is used for actions; there is no custom translucent reading layer or copied YouVersion content.

Shared AI setup distinguishes signed out/unconfigured, checking, saving, saved/usable, expired, and failure. Usability requires both current policy and validated account-scoped App Group access; a known policy fetch failure never produces a ready label. The expiration is displayed from the saved access value. Extension read acknowledgment remains a separate fact. Ready means the local setup is valid, not a promise that network/provider requests will succeed. The detail explicitly says a network connection is required.

The primary action names its next effect: review AI terms or enable shared AI. Terms and provider consent are still collected by the existing consent view. Enabling saves the existing limited share capability; no question is sent. Closing while saving cancels the task, with a cancellation check before capability persistence. Closing after successful persistence does not revoke consent or capability. Opening setup again rechecks saved state. Existing automatic refresh, maximum lifetime, owner validation and consent semantics are unchanged.

DEBUG-only simulator fixtures provide successful capability issuance, a delayed response, forced failure, persisted relaunch and a 3-second expiry. They use an ephemeral URLProtocol at fixture.example.org and no production services. Release builds exclude the fixture entry point.

The shared-conversation follow-up changes only onboarding/setup copy here: opening a share leads to question entry, and sending a question triggers AI. Setup checking/saving is explicitly distinguished from inference. Runtime conversation behavior is owned by the separate PR 2 work and is not implemented or merged in this branch.
