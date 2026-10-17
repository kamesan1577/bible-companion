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
        XCTAssertTrue(app.descendants(matching:.any).matching(identifier:"share-question-draft").firstMatch.waitForExistence(timeout: 15))
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
        XCTAssertTrue(app.buttons["質問を送る"].isEnabled)
        XCTAssertLessThanOrEqual(app.buttons["質問を送る"].frame.maxY,app.keyboards.firstMatch.frame.minY+2)
        attach(app,"share-long-draft-interrupted")
        app.buttons["質問を送る"].tap()
        XCTAssertTrue(app.staticTexts["AI requests: 1"].exists)
        XCTAssertTrue(app.staticTexts["送信待ち: " + draft.trimmingCharacters(in:.whitespacesAndNewlines)].exists)
        app.buttons["キーボードを閉じる"].tap()
        app.buttons["閉じる"].tap()
    }
    private func attach(_ app: XCUIApplication, _ name: String) { let item = XCTAttachment(screenshot: app.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item) }
}
