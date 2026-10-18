# Shared settings readback investigation (2026-10-18)

The supplied IMG_4683.png shows the 0.1.19 preparation screen: both status and a save attempt report that saved settings cannot be read. That text combined `corrupted` and `readFailed`; it did not identify a lock, signing failure, or a specific failed operation. The screenshot alone cannot establish why saving failed.

## Confirmed defect and repair

On real Foundation, opening an absent file with `FileHandle(forReadingFrom:)` returns `NSCocoaErrorDomain` code **4**, with underlying POSIX ENOENT. The previous helper recognized Cocoa260 and POSIX2 only at the outer level. It therefore reported an ordinary missing capability as a read failure and instructed the user to unlock the phone. The new classifier recognizes Cocoa4/260 and bounded underlying ENOENT. Directory/coordination failures remain failures, rather than being mistaken for absent credentials.

Permission denial is now distinct from proven protected-data unavailability. Generic read, corrupted data, full disk, coordination and write failures have separate guidance. Fixed operation stages plus allowlisted numeric codes are preserved for readback, owner and capability operations. Underlying descriptions, userInfo, URLs, group/team IDs, owner IDs and credentials are never rendered or retained by this diagnostic error type.

A user-triggered preparation-screen diagnostic inspects existing profile metadata, the OS-provided shared container and existing capability bytes. It does not call AI/auth endpoints, write settings, change accounts, remove files or loosen protection. A profile candidate match does not claim that the extension's effective signature or its actual container read has been verified. Only a later extension read receipt proves that separate process received the saved credential.

## Signing and storage findings

- Shared credentials/owner/receipt live in App Group files, using atomic writes and complete file protection. The ordinary session remains in the main app's own Keychain. No shared Keychain entitlement is needed for this design; general-session access is not added to the extension.
- Both distributed targets declare the same `group.org.kamesan1577.BibleCompanion` group and corresponding Info setting. Release0.1.19 IPA's app and extension were checked when packaged. This does not prove the entitlements of the user's SideStore-re-signed installation.
- [Apple's App Group documentation](https://developer.apple.com/documentation/xcode/configuring-app-groups) requires the app and extension to belong to a common group; containerURL is the OS gate. Profile metadata cannot grant access by itself.
- SideStore's current [profile assignment](https://github.com/SideStore/SideStore/blob/develop/SideStore/Core/Operations/PipelineOperations/FetchProvisioningProfilesOperation.swift) processes main and extension profiles and adjusts group IDs with a team suffix (and special bundle-ID/customization rules). Its [resigning operation](https://github.com/SideStore/SideStore/blob/develop/SideStore/Core/Operations/PipelineOperations/ResignAppOperation.swift) uses those profiles. Our existing resolver accepts only the exact configured group or one unique supported team suffix; it never chooses an unrelated group.

## Safe immediate guidance and limits

Close the preparation screen and continue reading in the main app. Avoid repeatedly saving, deleting local data, signing out or reinstalling just to follow the old lock message. The shared-question path should remain unavailable until owner-bound save/readback succeeds. A one-time ordinary close/reopen is safe; continued failure needs the diagnostic result, not another claim that unlocking must fix it. No app-data deletion, reinstall, new entitlement, OAuth scope, signing identity or deployment is performed by this change.

The actual physical-device **save failure is not yet reproduced or identified**. The missing-file bug is established, but may explain only the initial status. Simulator storage/readback and classification tests are regression evidence, not proof of SideStore permissions or a fix on this device. No release/version/feed/backend update is included.

## ChatGPT handoff duplicate reported in the same follow-up

The actual LEV19:1–2/JCB prompt repeated one complete quotation twice, with U+202D/U+202C directional controls embedded in the second reference. Exact whole-block equality missed it. The handoff now segments only blocks terminated by recognised references, compares canonical passage plus translation plus body, and retains the first original representation. Comparison removes direction controls, normalises reference width/dash/parenthesis presentation through the existing parser and ignores balanced outer quotation wrappers/blank padding. CRLF is treated as one newline. Body wording, internal punctuation and word spacing stay significant. Unrecognised references, different passages/translations/bodies and trailing notes are kept. Ambiguous reflow/translation descriptions are conservatively retained rather than guessed.

The user's actual pasted quotation and question `何？これ` are regression inputs. Tests also check decoded ChatGPT q URL equality, presentation variants and non-removal of different passages, translations, notes and meaningful spacing. Both URL handoff and clipboard use the same prompt builder.

Validation: 278 Swift tests passed; real Simulator storage cases passed for absent settings, read-only diagnostics, saved-state persistence/relaunch and expiry. The two diagnostic cases are rechecked against the final native code. These are fixture/no-provider checks. Main after PR4 passed Linux run39093548183 and iOS run39093550009 at0c7db81. This follow-up changes no release metadata, corpus, feed or server.
