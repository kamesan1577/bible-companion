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
    @MainActor func testShareConversationKeyboardCancelAndRetry() {
        let app=XCUIApplication(); app.launchArguments=["--simulator-qa","--qa-screen=share-conversation"];app.launch()
        XCTAssertTrue(app.staticTexts["最初の解説"].waitForExistence(timeout:10))
        let field=app.descendants(matching:.any).matching(identifier:"share-question-draft").firstMatch
        field.tap();field.typeText("Who is Felix?")
        let send=app.buttons["質問を送る"]
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout:3));XCTAssertTrue(send.isEnabled)
        XCTAssertLessThanOrEqual(send.frame.maxY,app.keyboards.firstMatch.frame.minY+2)
        attach(app,"share-keyboard-send")
        send.tap()
        XCTAssertTrue(app.staticTexts["受信中の回答です。全体の確認が終わるまで確定しません。"].waitForExistence(timeout:3))
        attach(app,"share-stream-preview")
        app.buttons["回答の準備をやめる"].tap()
        XCTAssertTrue(app.buttons["同じ質問をもう一度送る"].waitForExistence(timeout:5))
        XCTAssertFalse(app.staticTexts["受信中の回答です。全体の確認が終わるまで確定しません。"].exists)
        app.buttons["同じ質問をもう一度送る"].tap()
        expectation(for:NSPredicate(format:"exists == false"),evaluatedWith:app.buttons["回答の準備をやめる"]);waitForExpectations(timeout:12)
        XCTAssertTrue(app.staticTexts["フェリクスはローマの総督で、パウロの訴えを審理した人物です。"].exists)
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "Who is Felix?")).count, 1)
        field.tap();field.typeText("His wife?");send.tap()
        expectation(for:NSPredicate(format:"exists == false"),evaluatedWith:app.buttons["回答の準備をやめる"]);waitForExpectations(timeout:12)
        XCTAssertTrue(app.staticTexts["ドルシラはフェリクスの妻です。"].exists)
        app.buttons["キーボードを閉じる"].tap();app.buttons["最新のメッセージへ"].tap();XCTAssertTrue(app.staticTexts["ドルシラはフェリクスの妻です。"].exists)
        attach(app,"share-conversation-two-turns")
    }
    private func attach(_ app:XCUIApplication,_ name:String){let item=XCTAttachment(screenshot:app.screenshot());item.name=name;item.lifetime = .keepAlways;add(item)}
}
