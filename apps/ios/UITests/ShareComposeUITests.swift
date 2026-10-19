import XCTest

final class ShareComposeUITests: XCTestCase {
    @MainActor private func open(_ app: XCUIApplication, fixture: Bool = true) {
        let share = app.buttons[fixture ? "質問する共有拡張を開く" : "Crash Acts28:15"]
        XCTAssertTrue(app.navigationBars["描画確認"].waitForExistence(timeout: 15))
        for _ in 0..<8 { if share.exists && share.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(share.waitForExistence(timeout: 5)); share.tap()
        let candidates = app.cells.matching(identifier: "聖書コンパニオン")
        XCTAssertTrue(candidates.firstMatch.waitForExistence(timeout: 6))
        candidates.element(boundBy: candidates.count - 1).tap()
        let field = app.descendants(matching:.any).matching(identifier:"share-question-draft").firstMatch
        if !field.waitForExistence(timeout:2), candidates.count > 0 {
            let active = candidates.element(boundBy:candidates.count-1)
            if active.exists && active.isHittable { active.tap() }
        }
        XCTAssertTrue(field.waitForExistence(timeout:15))
    }
    @MainActor func testQuestionURLFromShareOpensSafari() {
        let app = XCUIApplication(); app.launchArguments = ["--simulator-qa", "--qa-handoff-owner"]; app.launch(); open(app)
        let field = app.descendants(matching: .any).matching(identifier: "share-question-draft").firstMatch
        field.tap(); field.typeText("URL direct? & # + %")
        app.buttons["chatgpt-open-external"].tap()
        XCTAssertFalse(app.navigationBars["ChatGPTへ渡す"].exists)
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 15))
        let wait = expectation(description: "Safari q render"); DispatchQueue.main.asyncAfter(deadline: .now()+5) { wait.fulfill() }; waitForExpectations(timeout: 7)
        attach(safari, "q-share-safari-result")
        app.activate()
    }
    @MainActor func testQuestionURLManualMainAppHandoff() {
        let app = XCUIApplication(); app.launchArguments = ["--simulator-qa", "--qa-handoff-owner", "--qa-chatgpt-long"]; app.launch(); open(app)
        let field = app.descendants(matching: .any).matching(identifier: "share-question-draft").firstMatch
        field.tap(); field.typeText("URL main? & # + %")
        app.buttons["chatgpt-open-external"].tap()
        let stage = app.buttons["chatgpt-stage-main"]
        for _ in 0..<8 { if stage.exists && stage.isHittable { break }; app.swipeUp() }
        stage.tap()
        let notice = app.staticTexts["chatgpt-handoff-notice"]
        expectation(for: NSPredicate(format: "label CONTAINS %@", "10分間"), evaluatedWith: notice); waitForExpectations(timeout: 5)
        attach(app, "q-link-staged-for-main")
        app.buttons["chatgpt-fallback-close"].tap()
        XCTAssertEqual(field.value as? String, "URL main? & # + %")
        app.buttons["閉じる"].tap()
        app.terminate(); app.launchArguments = ["--simulator-qa", "--qa-screen=settings", "--qa-handoff-owner"]; app.launch()
        let main = app.buttons["chatgpt-main-copy"]
        for _ in 0..<8 { if main.exists && main.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(main.waitForExistence(timeout: 10)); XCTAssertFalse(app.buttons["chatgpt-main-open"].exists)
        attach(app, "q-link-main-long-body-fallback")
        main.tap(); XCTAssertTrue(app.staticTexts["コピーしました。"].waitForExistence(timeout: 5))

    }
    @MainActor func testShareExtensionOfficialOpenAPIProbe() {
        let app = XCUIApplication(); app.launchArguments = ["--simulator-qa"]; app.launch(); open(app)
        let probe = app.buttons["QA: ChatGPT open probe"]
        XCTAssertTrue(probe.waitForExistence(timeout: 5)); probe.tap()
        let result = app.staticTexts["chatgpt-open-probe-result"]
        let completed = NSPredicate(format: "label == 'open=false' OR label == 'open=true'")
        expectation(for: completed, evaluatedWith: result); waitForExpectations(timeout: 15)
        attach(app, "chatgpt-official-extension-open-result")
        XCTAssertEqual(result.label, "open=false", "Record host result; if true, revisit the supported-route limitation before shipping")
        app.buttons["QA: browser control probe"].tap()
        expectation(for: NSPredicate(format: "label == 'browser-open=false'"), evaluatedWith: result); waitForExpectations(timeout: 10)
        attach(app, "share-browser-control-denied")
        app.buttons["閉じる"].tap()
        let dismiss = app.otherElements["PopoverDismissRegion"]; if dismiss.waitForExistence(timeout: 2) { dismiss.tap() }
        app.buttons["QA: main ChatGPT HTTPS"].tap()
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 15))
        app.activate()
        XCTAssertEqual(app.staticTexts["main-external-open-result"].label, "main-open=true")
        attach(app, "main-chatgpt-https-opens-without-chatgpt-app")
    }
    @MainActor func testChatGPTCopyAndPresentationPreferenceAcrossProcesses() {
        let app = XCUIApplication()
        func settings(_ visible: Bool) {
            app.terminate(); app.launchArguments = ["--simulator-qa", "--qa-screen=settings"]; app.launch()
            let toggle = app.switches["chatgpt-visibility"]
            for _ in 0..<8 { if toggle.exists && toggle.isHittable { break }; app.swipeUp() }
            XCTAssertTrue(toggle.waitForExistence(timeout: 15))
            if (toggle.value as? String == "1") != visible {
                toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
            }
            attach(app, visible ? "chatgpt-setting-on" : "chatgpt-setting-off")
            XCTAssertEqual(toggle.value as? String, visible ? "1" : "0")
        }
        settings(false)
        app.terminate(); app.launchArguments = ["--simulator-qa", "--qa-chatgpt-long"]; app.launch(); open(app)
        XCTAssertFalse(app.buttons["chatgpt-open-external"].exists)
        app.buttons["閉じる"].tap()
        settings(true)
        app.terminate(); app.launchArguments = ["--simulator-qa", "--qa-chatgpt-long"]; app.launch(); open(app)
        let field = app.descendants(matching: .any).matching(identifier: "share-question-draft").firstMatch
        field.tap(); field.typeText("ChatGPT draft preserved?")
        let alternative = app.buttons["chatgpt-open-external"]
        XCTAssertTrue(alternative.isHittable)
        XCTAssertLessThanOrEqual(alternative.frame.maxY, app.buttons["質問を送る"].frame.maxY + 2)
        attach(app, "chatgpt-alternative-keyboard")
        alternative.tap()
        for _ in 0..<8 { if app.buttons["chatgpt-copy-confirm"].exists && app.buttons["chatgpt-copy-confirm"].isHittable { break }; app.swipeUp() }
        XCTAssertTrue(app.buttons["chatgpt-copy-confirm"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["chatgpt-copy-content"].label.contains("ChatGPT draft preserved?"))
        attach(app, "chatgpt-explicit-copy-preview")
        app.buttons["chatgpt-copy-confirm"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "ChatGPT draft preserved?")
        XCTAssertTrue(app.staticTexts["AI requests: 0"].exists)
        app.buttons["閉じる"].tap()
    }
    @MainActor func testActualExtensionImmediateComposerKeyboardQueueAndReopen() {
        let app = XCUIApplication(); app.launchArguments = ["--simulator-qa"]; app.launch()
        open(app)
        XCTAssertTrue(app.staticTexts["AI requests: 0"].exists)
        XCTAssertFalse(app.staticTexts["最初の解説"].exists)
        attach(app, "share-compose-open-zero-ai")
        app.buttons["人物"].tap(); app.buttons["地名"].tap(); app.buttons["解説"].tap()
        XCTAssertTrue(app.staticTexts["AI requests: 0"].exists)
        let field = app.descendants(matching:.any).matching(identifier:"share-question-draft").firstMatch
        field.tap(); field.typeText("Appeal?")
        let send = app.buttons["質問を送る"]
        XCTAssertTrue(send.isEnabled); XCTAssertTrue(send.isHittable)
        XCTAssertLessThanOrEqual(send.frame.maxY, app.keyboards.firstMatch.frame.minY + 2)
        attach(app, "share-compose-keyboard-send")
        send.tap()
        // Enter and enqueue a follow-up while the first request is in flight.
        field.tap(); field.typeText("why?")
        XCTAssertTrue(send.isEnabled); send.tap()
        field.tap(); field.typeText("draft stays")
        XCTAssertTrue(app.staticTexts["エルサレムで裁かれる危険を避けるため、上訴したと考えられます。これは状況からの見立てです。"].waitForExistence(timeout: 15))
        XCTAssertEqual(field.value as? String, "draft stays")
        XCTAssertTrue(app.staticTexts["AI requests: 2"].exists)
        app.buttons["キーボードを閉じる"].tap()
        app.buttons["最新のメッセージへ"].tap()
        attach(app, "share-compose-two-turns")
        app.buttons["閉じる"].tap()
        let dismiss = app.otherElements["PopoverDismissRegion"]
        if dismiss.waitForExistence(timeout: 2) { dismiss.tap() }
        open(app)
        XCTAssertEqual(field.value as? String, "draft stays")
        XCTAssertTrue(app.staticTexts["AI requests: 0"].exists)
        XCTAssertTrue(app.staticTexts["why?"].exists)
        attach(app, "share-compose-reopened-draft")
        app.buttons["閉じる"].tap()
    }
    @MainActor func testActualExtensionWithoutSetupKeepsInput() {
        let app = XCUIApplication(); app.launchArguments = ["--simulator-qa"]; app.launch()
        open(app, fixture:false)
        let field = app.descendants(matching:.any).matching(identifier:"share-question-draft").firstMatch
        XCTAssertTrue(app.staticTexts["AI requests: 0"].exists)
        field.tap(); field.typeText("Question without setup")
        XCTAssertTrue(app.buttons["質問を送る"].isHittable)
        app.buttons["質問を送る"].tap()
        XCTAssertTrue(app.staticTexts["質問を送るには準備が必要です"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["送信待ち: Question without setup"].exists)
        field.tap(); field.typeText("still editable")
        XCTAssertEqual(field.value as? String, "still editable")
        XCTAssertTrue(app.staticTexts["AI requests: 0"].exists)
        attach(app,"share-compose-no-setup-draft")
        app.buttons["閉じる"].tap()
    }
    @MainActor func testLongDraftAndUncertainFailureKeepKeyboardSendAvailable() {
        let app = XCUIApplication(); app.launchArguments = ["--simulator-qa"]; app.launch(); open(app)
        let field = app.descendants(matching:.any).matching(identifier:"share-question-draft").firstMatch
        field.tap(); field.typeText("fail"); app.buttons["質問を送る"].tap()
        let draft = String(repeating:"a long question ", count:12)
        field.tap(); field.typeText(draft)
        XCTAssertTrue(app.buttons["送信した回答を確認"].waitForExistence(timeout:10))
        XCTAssertEqual(field.value as? String,draft)
        XCTAssertTrue(app.staticTexts["主がモーセを通して人々へ語りかけています。"].exists)
        XCTAssertTrue(app.staticTexts["未完了の部分回答です。全体の確認と保存は完了していません。"].exists)
        XCTAssertFalse(app.staticTexts["送信待ち: fail"].exists)
        XCTAssertTrue(app.staticTexts["送信済み・結果確認中: fail"].exists)
        XCTAssertTrue(app.buttons["質問を送る"].isEnabled)
        XCTAssertGreaterThanOrEqual(app.buttons["質問を送る"].frame.height,44)
        XCTAssertLessThanOrEqual(app.buttons["質問を送る"].frame.maxY,app.keyboards.firstMatch.frame.minY)
        attach(app,"share-long-draft-interrupted")
        app.buttons["質問を送る"].tap()
        XCTAssertTrue(app.staticTexts["AI requests: 1"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label == %@", "送信待ち: " + draft.trimmingCharacters(in:.whitespacesAndNewlines))).firstMatch.exists)
        app.buttons["キーボードを閉じる"].tap()
        app.buttons["閉じる"].tap()
    }
    private func attach(_ app: XCUIApplication, _ name: String) { let item = XCTAttachment(screenshot: app.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item) }
}
