import XCTest

final class GlassRefinementUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor private func input(_ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any).matching(identifier: "external-question-input").firstMatch }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }
    @MainActor private func assertNativeTabs(_ app: XCUIApplication) {
        let tabs = app.segmentedControls["reading-section-tabs"]
        XCTAssertTrue(tabs.waitForExistence(timeout: 15), "Tabs must remain a platform SegmentedControl")
        XCTAssertLessThanOrEqual(tabs.frame.height, 40)
        for title in ["解説", "地図", "人物", "絵画"] { XCTAssertTrue(app.buttons[title].exists) }
        XCTAssertFalse(app.staticTexts["—"].exists)
    }
    @MainActor private func assertRoundSend(_ app: XCUIApplication) {
        let send = app.buttons["external-question-send"]
        XCTAssertTrue(send.isHittable)
        XCTAssertGreaterThanOrEqual(send.frame.width, 44)
        XCTAssertLessThanOrEqual(send.frame.width, 48)
        XCTAssertLessThanOrEqual(abs(send.frame.width-send.frame.height), 2)
        XCTAssertLessThanOrEqual(send.frame.maxY, app.keyboards.firstMatch.frame.minY)
    }
    // Run once with Simulator appearance light and once dark; both processes
    // inherit the actual system appearance, including the remote extension.
    @MainActor func testSystemAppearanceMainAndActualShare() {
        let app = XCUIApplication(); app.launchArguments = ["--simulator-qa", "--qa-screen=badges", "--qa-reset-provider"]; app.launch()
        XCTAssertTrue(input(app).waitForExistence(timeout: 15)); assertNativeTabs(app)
        capture(app, "glass-main-idle")
        app.buttons["地図"].tap(); XCTAssertTrue(app.buttons["地図"].isSelected)
        input(app).tap(); input(app).typeText("この場面は何を意味しますか？")
        assertRoundSend(app); capture(app, "glass-main-keyboard")
        app.terminate(); app.launchArguments = ["--simulator-qa", "--qa-handoff-owner", "--qa-reset-provider"]; app.launch()
        XCTAssertTrue(app.buttons["質問する共有拡張を開く"].waitForExistence(timeout: 15)); app.buttons["質問する共有拡張を開く"].tap()
        let choices = app.cells.matching(identifier: "聖書コンパニオン"); XCTAssertTrue(choices.firstMatch.waitForExistence(timeout: 10)); choices.element(boundBy: choices.count-1).tap()
        XCTAssertTrue(input(app).waitForExistence(timeout: 20)); assertNativeTabs(app)
        capture(app, "glass-share-idle")
        app.buttons["地図"].tap(); input(app).tap(); input(app).typeText("この箇所の背景を教えてください。")
        assertRoundSend(app); capture(app, "glass-share-keyboard")
        app.buttons["閉じる"].tap()
    }
    @MainActor func testLongDraftAndAccessibilityTextRemainEditable() {
        let app = XCUIApplication(); app.launchArguments = ["--simulator-qa", "--qa-screen=unified", "--qa-reset-provider", "--qa-accessibility-text"]; app.launch()
        let field = input(app); XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap(); field.typeText(String(repeating: "長文の質問です。\n", count: 12))
        XCTAssertTrue((field.value as? String ?? "").contains("長文の質問"))
        assertRoundSend(app); capture(app, "glass-accessibility-long-draft")
        app.buttons["キーボードを閉じる"].tap(); XCTAssertTrue(field.exists)
    }
}
