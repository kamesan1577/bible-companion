import XCTest

/// The extension no longer owns an AI conversation/queue. These contracts test
/// the replacement external handoff, while Core/main fixtures retain stream tests.
final class ShareComposeUITests: XCTestCase {
    @MainActor private func open(flags: [String] = [], title: String = "質問する共有拡張を開く") -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--simulator-qa", "--qa-handoff-owner"] + flags; app.launch()
        CurrentUI.openShare(app, title: title); CurrentUI.replaceDraft("",in:app); return app
    }
    @MainActor func testQuestionURLFromShareOpensSafariAndPreservesDraft() {
        let app = open(); let field = CurrentUI.input(app)
        field.tap(); field.typeText(" URL direct? & # + %")
        CurrentUI.provider("ChatGPT", in: app); let draft = field.value as? String
        app.buttons["external-question-send"].tap()
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 15))
        app.activate(); XCTAssertTrue(field.waitForExistence(timeout: 10)); XCTAssertEqual(field.value as? String, draft)
        XCTAssertTrue(app.staticTexts["external-handoff-status"].exists)
        CurrentUI.capture(app,"share-url-return-keeps-draft",test:self); app.buttons["閉じる"].tap()
    }
    @MainActor func testLongSharedTextUsesExplicitCopyHandoff() {
        let app = open(flags:["--qa-chatgpt-long"]); let field = CurrentUI.input(app)
        field.tap(); field.typeText(" long-body-full-copy")
        CurrentUI.provider("ChatGPT", in:app)
        XCTAssertTrue(app.buttons["external-question-send"].label.contains("全文をコピー"))
        let draft = field.value as? String; app.buttons["external-question-send"].tap()
        let safari = XCUIApplication(bundleIdentifier:"com.apple.mobilesafari")
        XCTAssertTrue(safari.wait(for:.runningForeground,timeout:15)); app.activate()
        XCTAssertTrue(field.waitForExistence(timeout:10)); XCTAssertEqual(field.value as? String,draft)
        XCTAssertTrue(app.staticTexts["external-handoff-status"].label.contains("貼り付け"))
        CurrentUI.capture(app,"share-long-body-copy-not-truncated",test:self); app.buttons["閉じる"].tap()
    }
    @MainActor func testShareProviderPickerPreservesContextWithoutUnsupportedOpenProbe() {
        let app = open(); let field = CurrentUI.input(app)
        field.tap(); field.typeText(" provider-context-preserved")
        let draft = field.value as? String
        for provider in ["ChatGPT", "Claude", "Gemini"] {
            CurrentUI.provider(provider,in:app); XCTAssertEqual(field.value as? String,draft)
        }
        XCTAssertFalse(app.buttons["QA: ChatGPT open probe"].exists)
        XCTAssertFalse(app.buttons["質問を送る"].exists)
        CurrentUI.capture(app,"share-three-provider-contract",test:self); app.buttons["閉じる"].tap()
    }
    @MainActor func testProviderPreferencePersistsAcrossMainAndShareProcesses() {
        let app = open(); CurrentUI.provider("Claude",in:app)
        let field=CurrentUI.input(app); field.tap(); field.typeText(" saved-provider-draft")
        let draft=field.value as? String; app.buttons["閉じる"].tap(); app.terminate()
        app.launchArguments=["--simulator-qa","--qa-screen=settings","--qa-handoff-owner"];app.launch()
        XCTAssertTrue(app.buttons["external-provider-picker"].waitForExistence(timeout:15))
        XCTAssertTrue(app.buttons["external-provider-picker"].label.contains("Claude") || (app.buttons["external-provider-picker"].value as? String ?? "").contains("Claude"))
        app.terminate();app.launchArguments=["--simulator-qa","--qa-screen=unified-home","--qa-handoff-owner"];app.launch()
        let recent=app.buttons["recent-reading"];XCTAssertTrue(recent.waitForExistence(timeout:15));recent.tap()
        let restored=CurrentUI.input(app);XCTAssertTrue(restored.waitForExistence(timeout:10))
        expectation(for:NSPredicate(format:"value == %@",draft ?? ""),evaluatedWith:restored);waitForExpectations(timeout:5)
        XCTAssertTrue(app.buttons["external-question-send"].label.contains("Claude"))
        CurrentUI.capture(app,"same-context-draft-restored-in-main",test:self)
        app.terminate();app.launchArguments=["--simulator-qa","--qa-handoff-owner"];app.launch();CurrentUI.openShare(app)
        XCTAssertTrue(app.buttons["external-question-send"].label.contains("Claude"))
        // A new QA session URL is a different shared-original identity, even
        // when its passage matches. Do not leak the previous context's draft.
        let newDraft=CurrentUI.input(app).value as? String
        XCTAssertTrue(newDraft == nil || newDraft == "" || newDraft == "この箇所について質問")
        XCTAssertFalse((newDraft ?? "").contains("saved-provider-draft"))
        CurrentUI.capture(app,"new-original-does-not-inherit-old-draft",test:self);app.buttons["閉じる"].tap()
    }
    @MainActor func testActualExtensionImmediateComposerKeyboardDraftAndReopen() {
        let app=open();let field=CurrentUI.input(app)
        XCTAssertFalse(app.staticTexts["最初の解説"].exists)
        for tab in ["人物","地図","解説"] {app.buttons[tab].tap()}
        field.tap();field.typeText(" immediate-composer")
        CurrentUI.keyboardSend(app);let draft=field.value as? String
        XCTAssertFalse(app.buttons["回答の準備をやめる"].exists)
        CurrentUI.capture(app,"share-immediate-local-composer",test:self)
        app.buttons["閉じる"].tap()
        let dismiss=app.otherElements["PopoverDismissRegion"];if dismiss.waitForExistence(timeout:2){dismiss.tap()}
        CurrentUI.openShare(app);XCTAssertEqual(CurrentUI.input(app).value as? String,draft)
        XCTAssertFalse(app.staticTexts["最初の解説"].exists);app.buttons["閉じる"].tap()
    }
    @MainActor func testActualExtensionNeedsNoFirstPartyAISetup() {
        let app=open(flags:["--qa-clear-access"],title:"Crash Acts28:15");let field=CurrentUI.input(app)
        field.tap();field.typeText(" question-without-AI-setup")
        CurrentUI.keyboardSend(app)
        XCTAssertFalse(app.staticTexts["質問を送るには準備が必要です"].exists)
        XCTAssertFalse(app.staticTexts["送信待ち: question-without-AI-setup"].exists)
        XCTAssertTrue(app.staticTexts["聖句・原文・質問を外部へ"].exists)
        CurrentUI.capture(app,"share-no-first-party-setup",test:self);app.buttons["閉じる"].tap()
    }
    @MainActor func testLongDraftStaysEditableAndOverLimitDoesNotSend() {
        let app=open();let field=CurrentUI.input(app)
        field.tap();field.typeText(" long-editable "+String(repeating:"question ",count:24))
        CurrentUI.keyboardSend(app);let before=field.value as? String ?? ""
        field.typeText(String(repeating:"x",count:2100))
        XCTAssertTrue((field.value as? String ?? "").hasPrefix(before))
        XCTAssertGreaterThan((field.value as? String ?? "").utf16.count,2000)
        XCTAssertFalse(app.buttons["external-question-send"].isEnabled)
        XCTAssertTrue(app.staticTexts["質問は2000文字以内にしてください。入力は切り詰めず残しています。"].exists)
        XCTAssertFalse(app.staticTexts["送信済み・結果確認中: fail"].exists)
        CurrentUI.capture(app,"share-over-limit-keeps-complete-draft",test:self);CurrentUI.replaceDraft("",in:app);app.buttons["閉じる"].tap()
    }
}
