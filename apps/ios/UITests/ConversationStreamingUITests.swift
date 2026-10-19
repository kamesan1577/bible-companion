import XCTest

final class ConversationStreamingUITests: XCTestCase {
    @MainActor func testInitialExplanationConversationKeyboardAndStream() {
        let app = XCUIApplication(); app.launchArguments = ["--simulator-qa", "--qa-screen=conversation"]; app.launch()
        XCTAssertTrue(app.staticTexts["最初の解説"].waitForExistence(timeout: 10))
        let field = app.descendants(matching:.any).matching(identifier:"question-draft").firstMatch
        field.tap(); field.typeText("Who is Felix?")
        let send = app.buttons["質問を送る"]
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3)); XCTAssertTrue(send.isEnabled)
        XCTAssertLessThanOrEqual(send.frame.maxY, app.keyboards.firstMatch.frame.minY + 2)
        attach(app,"conversation-keyboard")
        send.tap()
        XCTAssertTrue(app.staticTexts["Who is Felix?"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["受信中の回答です。全体の確認が終わるまで確定しません。"].waitForExistence(timeout: 3))
        XCTAssertFalse(send.isEnabled); attach(app,"conversation-stream-preview")
        expectation(for:NSPredicate(format:"exists == false"),evaluatedWith:app.buttons["回答の準備をやめる"]);waitForExpectations(timeout:12)
        XCTAssertTrue(app.staticTexts["フェリクスはローマの総督で、パウロの訴えを審理した人物です。"].exists)
        field.tap(); field.typeText("His wife?"); send.tap()
        expectation(for:NSPredicate(format:"exists == false"),evaluatedWith:app.buttons["回答の準備をやめる"]);waitForExpectations(timeout:12)
        XCTAssertTrue(app.staticTexts["ドルシラはフェリクスの妻です。"].exists)
        app.buttons["キーボードを閉じる"].tap(); app.buttons["最新のメッセージへ"].tap(); XCTAssertTrue(app.staticTexts["ドルシラはフェリクスの妻です。"].exists)
        XCTAssertTrue(app.staticTexts["Who is Felix?"].exists); attach(app,"conversation-two-turns")
    }
    @MainActor func testInterruptedResponseRequiresStatusBeforeResend() {
        let app=XCUIApplication();app.launchArguments=["--simulator-qa","--qa-screen=conversation"];app.launch()
        let field=app.descendants(matching:.any).matching(identifier:"question-draft").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout:10));field.tap();field.typeText("fail");app.buttons["質問を送る"].tap()
        XCTAssertTrue(app.buttons["質問の状況を確認"].waitForExistence(timeout:12))
        XCTAssertFalse(app.buttons["質問を送る"].isEnabled)
        XCTAssertFalse(app.staticTexts["受信中の回答です。全体の確認が終わるまで確定しません。"].exists)
        attach(app,"conversation-interrupted")
    }
    @MainActor func testShareExternalDraftKeyboardCloseReopenAndEdit() {
        let app = XCUIApplication(); app.launchArguments = ["--simulator-qa", "--qa-handoff-owner"]; app.launch()
        CurrentUI.openShare(app)
        let field = CurrentUI.input(app); field.tap(); field.typeText(" share-handoff-draft")
        CurrentUI.keyboardSend(app)
        let draft = field.value as? String
        XCTAssertFalse(app.staticTexts["受信中の回答です。全体の確認が終わるまで確定しません。"].exists)
        XCTAssertFalse(app.buttons["同じ質問をもう一度送る"].exists)
        app.buttons["閉じる"].tap()
        let dismiss = app.otherElements["PopoverDismissRegion"]; if dismiss.waitForExistence(timeout: 2) { dismiss.tap() }
        CurrentUI.openShare(app)
        XCTAssertEqual(CurrentUI.input(app).value as? String, draft)
        CurrentUI.input(app).tap(); CurrentUI.input(app).typeText(" follow-up")
        XCTAssertTrue((CurrentUI.input(app).value as? String ?? "").contains("follow-up"))
        CurrentUI.keyboardSend(app); attach(app,"share-handoff-close-reopen-edit")
        app.buttons["閉じる"].tap()
    }
    private func attach(_ app:XCUIApplication,_ name:String){let item=XCTAttachment(screenshot:app.screenshot());item.name=name;item.lifetime = .keepAlways;add(item)}
}
