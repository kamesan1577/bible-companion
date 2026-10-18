import XCTest

final class UnifiedReadingUITests: XCTestCase {
    @MainActor private func launch(_ screen: String = "unified", flags: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--simulator-qa", "--qa-screen=\(screen)"] + flags; app.launch(); return app
    }
    @MainActor private func input(_ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any).matching(identifier: "external-question-input").firstMatch }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) { let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot) }
    @MainActor func testCommonFourTabsKeyboardDraftAndProviderRelaunch() {
        var app = launch(flags: ["--qa-reset-provider"])
        let field = input(app); XCTAssertTrue(field.waitForExistence(timeout: 15))
        for title in ["解説", "地図", "人物", "絵画"] { XCTAssertTrue(app.buttons[title].exists) }
        app.buttons["人物"].tap(); XCTAssertTrue(app.staticTexts["モーセ"].firstMatch.waitForExistence(timeout: 10))
        capture(app, "unified-lev-people")
        app.buttons["絵画"].tap(); XCTAssertTrue(app.staticTexts["この箇所に対応する確認済みの絵画資料はありません。"].waitForExistence(timeout: 10))
        field.tap(); field.typeText("Why holy? & + # %\nPlease answer directly.")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertTrue(app.buttons["external-question-send"].isHittable)
        capture(app, "unified-keyboard-send")
        app.buttons["external-provider-settings"].tap()
        app.buttons["external-provider-picker"].tap(); app.buttons["Claude"].tap(); app.buttons["完了"].tap()
        XCTAssertTrue(app.buttons["external-question-send"].label.contains("全文をコピーしてClaude"))
        XCTAssertTrue((field.value as? String ?? "").contains("Why holy?"))
        app.terminate(); app = launch()
        XCTAssertTrue(input(app).waitForExistence(timeout: 15))
        XCTAssertTrue((input(app).value as? String ?? "").contains("Why holy?"))
        XCTAssertTrue(app.buttons["external-question-send"].label.contains("Claude"))
        capture(app, "unified-draft-provider-restored")
    }
    @MainActor func testDifferentAccountCannotReadDraftAndOriginalAccountCanRestore() {
        var app = launch(); XCTAssertTrue(input(app).waitForExistence(timeout: 15))
        input(app).tap(); input(app).typeText(" owner-specific-20261018")
        app.terminate(); app = launch(flags: ["--qa-second-owner"])
        XCTAssertTrue(input(app).waitForExistence(timeout: 15)); XCTAssertFalse((input(app).value as? String ?? "").contains("owner-specific-20261018"))
        capture(app, "unified-other-account-empty-draft")
        app.terminate(); app = launch(); XCTAssertTrue(input(app).waitForExistence(timeout: 15)); XCTAssertTrue((input(app).value as? String ?? "").contains("owner-specific-20261018"))
    }
    @MainActor func testPublicFailureRetainsOfflineReaderAndComposer() {
        let app = launch(flags: ["--qa-public-error"])
        XCTAssertTrue(input(app).waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["公開資料を読み直す"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "この箇所の説明")).firstMatch.exists)
        app.buttons["公開資料を読み直す"].tap(); XCTAssertTrue(input(app).exists)
        capture(app, "unified-public-error-offline")
    }
    @MainActor func testActualShareExtensionUsesSameTabsAndWritesRecentAcrossProcesses() {
        let app = XCUIApplication(); app.launchArguments = ["--simulator-qa", "--qa-handoff-owner"]; app.launch()
        XCTAssertTrue(app.buttons["質問する共有拡張を開く"].waitForExistence(timeout: 15)); app.buttons["質問する共有拡張を開く"].tap()
        let choices = app.cells.matching(identifier: "聖書コンパニオン"); XCTAssertTrue(choices.firstMatch.waitForExistence(timeout: 10)); choices.element(boundBy: choices.count - 1).tap()
        XCTAssertTrue(input(app).waitForExistence(timeout: 20))
        for title in ["解説", "地図", "人物", "絵画"] { XCTAssertTrue(app.buttons[title].exists) }
        input(app).tap(); input(app).typeText("share keyboard question")
        XCTAssertTrue(app.buttons["external-question-send"].isHittable)
        capture(app, "unified-real-share-keyboard")
        app.buttons["閉じる"].tap(); app.terminate()
        app.launchArguments = ["--simulator-qa", "--qa-screen=unified-home"]; app.launch()
        XCTAssertTrue(app.buttons["recent-reading"].waitForExistence(timeout: 15)); XCTAssertTrue(app.buttons["recent-reading"].label.contains("26"))
        XCTAssertTrue(app.buttons["discovery-card"].exists)
        capture(app, "unified-share-to-main-recent")
    }
    @MainActor func testCopyProviderOpensBrowserWithoutNativeAppAndRetainsQuestion() {
        let app = launch()
        XCTAssertTrue(input(app).waitForExistence(timeout: 15))
        input(app).tap(); input(app).typeText(" provider-copy-public-fixture")
        app.buttons["external-provider-settings"].tap(); app.buttons["external-provider-picker"].tap(); app.buttons["Gemini"].tap(); app.buttons["完了"].tap()
        let send = app.buttons["external-question-send"]
        XCTAssertTrue(send.label.contains("全文をコピーしてGemini")); send.tap()
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 15))
        app.activate(); XCTAssertTrue(input(app).waitForExistence(timeout: 10))
        XCTAssertTrue((input(app).value as? String ?? "").contains("provider-copy-public-fixture"))
        XCTAssertTrue(app.staticTexts["external-handoff-status"].label.contains("貼り付け"))
        capture(app, "unified-provider-open-return-keeps-input")
    }

    @MainActor func testHorizontalSwipeAndKeyboardDismissalStayClearOfSend() {
        let app = launch()
        XCTAssertTrue(input(app).waitForExistence(timeout: 15))
        app.buttons["地図"].tap(); app.swipeLeft()
        XCTAssertTrue(app.buttons["人物"].isSelected)
        app.swipeRight(); XCTAssertTrue(app.buttons["地図"].isSelected)
        input(app).tap(); input(app).typeText(" keyboard-layout-check")
        let send = app.buttons["external-question-send"], close = app.buttons["キーボードを閉じる"]
        XCTAssertTrue(send.isHittable); XCTAssertTrue(close.isHittable)
        XCTAssertLessThanOrEqual(close.frame.maxY, app.keyboards.firstMatch.frame.minY)
        XCTAssertLessThanOrEqual(send.frame.width, 52)
        XCTAssertLessThanOrEqual(abs(send.frame.width - send.frame.height), 2)
        XCTAssertLessThanOrEqual(send.frame.maxY, app.keyboards.firstMatch.frame.minY)
        capture(app, "unified-keyboard-dismissal-no-overlap")
        close.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.keyboards.firstMatch)
        waitForExpectations(timeout: 5)
        XCTAssertTrue((input(app).value as? String ?? "").contains("keyboard-layout-check"))
    }

}
