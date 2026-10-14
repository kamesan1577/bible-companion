import XCTest

final class ReadingInteractionUITests: XCTestCase {
    @MainActor func testQuestionKeyboardSpoilersAndOrdinaryDebugVisibility() {
        let app = XCUIApplication(); app.launchArguments = ["--simulator-qa"]; app.launch()
        XCTAssertTrue(app.buttons["質問画面"].waitForExistence(timeout: 10)); app.buttons["質問画面"].tap()
        let field = app.descendants(matching: .any).matching(identifier: "question-draft").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("background")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let send = app.buttons["質問を送る"]
        XCTAssertTrue(send.exists); XCTAssertTrue(send.waitForExistence(timeout: 5)); XCTAssertTrue(send.isEnabled)
        XCTAssertLessThanOrEqual(send.frame.maxY, app.keyboards.firstMatch.frame.minY + 2)
        XCTAssertTrue(app.buttons["質問を送る"].exists)
        XCTAssertFalse(app.staticTexts["開発者用デバッグ"].exists)
        attach(app, "keyboard-send-visible")
        app.swipeDown()
        let toggle = app.switches["ネタバレ防止"]
        XCTAssertTrue(toggle.exists); toggle.tap()
        XCTAssertTrue(app.buttons["オフにする"].waitForExistence(timeout: 3)); app.otherElements["PopoverDismissRegion"].tap()
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.tap(); XCTAssertTrue(app.buttons["オフにする"].waitForExistence(timeout: 3)); app.buttons["オフにする"].tap(); expectation(for: NSPredicate(format: "value == %@", "0"), evaluatedWith: toggle); waitForExpectations(timeout: 3)
        toggle.tap(); XCTAssertEqual(toggle.value as? String, "1")
        attach(app, "spoiler-prevention-restored")
    }
    @MainActor func testBundledPeopleAndRepeatedShareDismissal() {
        let app = XCUIApplication(); app.launchArguments = ["--simulator-qa"]; app.launch()
        XCTAssertTrue(app.buttons["使徒23:1の人物"].waitForExistence(timeout: 10)); app.buttons["使徒23:1の人物"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "パウロ")).firstMatch.waitForExistence(timeout: 5))
        attach(app, "bundled-people")
        app.navigationBars.buttons.firstMatch.tap()
        for _ in 0..<3 {
            let share = app.buttons["実際の共有拡張を開く"]
            XCTAssertTrue(share.waitForExistence(timeout: 3)); share.tap()
            XCTAssertTrue(app.otherElements["PopoverDismissRegion"].waitForExistence(timeout: 3))
            app.otherElements["PopoverDismissRegion"].tap()
            XCTAssertTrue(share.waitForExistence(timeout: 3))
        }
        attach(app, "repeated-share-return")
    }
    @MainActor func testShareExtensionLocalMetadataAndRepeatedReturn() {
        let app = XCUIApplication(); app.launchArguments = ["--simulator-qa"]; app.launch()
        for _ in 0..<3 {
            let share = app.buttons["実際の共有拡張を開く"]
            XCTAssertTrue(share.waitForExistence(timeout: 10)); share.tap()
            let candidates = app.cells.matching(identifier: "聖書コンパニオン")
            let companion = candidates.element(boundBy: candidates.count - 1)
            XCTAssertTrue(companion.waitForExistence(timeout: 5)); companion.tap()
            XCTAssertTrue(app.staticTexts["使徒の働き 23:1"].waitForExistence(timeout: 5))
            let people = app.buttons["人物"]
            XCTAssertTrue(people.exists); people.tap()
            XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "パウロ")).firstMatch.waitForExistence(timeout: 5))
            attach(app, "share-extension-local-people")
            XCTAssertTrue(app.buttons["閉じる"].exists); app.buttons["閉じる"].tap()
            XCTAssertTrue(share.waitForExistence(timeout: 5))
        }
    }
    @MainActor func testKeyboardSendAndFollowupReachOnlyLocalFixture() {
        let app = XCUIApplication(); app.launchArguments = ["--simulator-qa"]; app.launch()
        XCTAssertTrue(app.buttons["質問画面"].waitForExistence(timeout: 10)); app.buttons["質問画面"].tap()
        let field = app.descendants(matching: .any).matching(identifier: "question-draft").firstMatch; XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("background")
        let send = app.buttons["質問を送る"]; expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: send); waitForExpectations(timeout: 5); send.tap()
        XCTAssertTrue(app.staticTexts["固定データ: background"].waitForExistence(timeout: 5))
        field.tap(); field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10) + "followup")
        XCTAssertTrue(send.isEnabled); send.tap()
        XCTAssertTrue(app.staticTexts["固定データ: followup"].waitForExistence(timeout: 5))
        attach(app, "keyboard-send-and-followup-complete")
    }
    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
