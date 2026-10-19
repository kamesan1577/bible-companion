import XCTest

final class ReadingBadgeUITests: XCTestCase {
    @MainActor private func launch(_ flags: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--simulator-qa", "--qa-screen=badges"] + flags; app.launch(); return app
    }
    @MainActor private func waitValue(_ element: XCUIElement, _ value: String, timeout: TimeInterval = 15) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout))
        expectation(for: NSPredicate(format: "label ENDSWITH %@", value), evaluatedWith: element); waitForExpectations(timeout: timeout)
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    @MainActor func testAllCountsArriveBeforeOpeningArtworkAndImageStartsOnlyOnSelection() {
        let app = launch()
        waitValue(app.buttons["絵画"], "1件")
        XCTAssertEqual(app.staticTexts["qa-artwork-load-count"].label, "画像取得 0")
        for name in ["解説", "地図", "人物"] { XCTAssertTrue((app.buttons[name].label).hasSuffix("件")) }
        capture(app, "badges-art-available-before-opening")
        app.buttons["絵画"].tap()
        XCTAssertTrue(app.staticTexts["ティントレット《聖パウロの回心》"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.images["ティントレット《聖パウロの回心》"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.staticTexts["qa-artwork-load-count"].label, "画像取得 1")
        capture(app, "badges-artwork-image-visible")
    }
    @MainActor func testLoadingAndFailureAreNotZero() {
        var app = launch(["--qa-public-held"])
        waitValue(app.buttons["絵画"], "件数を確認中", timeout: 2)
        capture(app, "badges-loading-not-zero")
        app.buttons["qa-release-public"].tap()
        waitValue(app.buttons["絵画"], "1件")
        app.terminate(); app = launch(["--qa-public-error"])
        waitValue(app.buttons["絵画"], "件数を確認できません")
        XCTAssertFalse(app.buttons["絵画"].label.hasSuffix("0件"))
        capture(app, "badges-failure-not-zero")
    }
    @MainActor func testPassageSwitchRejectsOldArtworkCount() {
        let app = launch(["--qa-public-slow"])
        XCTAssertTrue(app.buttons["QAレビ記へ"].waitForExistence(timeout: 10)); app.buttons["QAレビ記へ"].tap()
        waitValue(app.buttons["絵画"], "0件")
        XCTAssertEqual(app.staticTexts["qa-artwork-load-count"].label, "画像取得 0")
        app.buttons["絵画"].tap()
        XCTAssertTrue(app.staticTexts["この箇所に対応する確認済みの絵画資料はありません。"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["ティントレット《聖パウロの回心》"].exists)
        capture(app, "badges-new-passage-zero")
    }
    @MainActor func testShareExtensionUsesSameCountBadgesWithoutLoadingImages() {
        let app = XCUIApplication(); app.launchArguments = ["--simulator-qa", "--qa-handoff-owner"]; app.launch()
        XCTAssertTrue(app.buttons["質問する共有拡張を開く"].waitForExistence(timeout: 15)); app.buttons["質問する共有拡張を開く"].tap()
        let choices = app.cells.matching(identifier: "聖書コンパニオン"); XCTAssertTrue(choices.firstMatch.waitForExistence(timeout: 10)); choices.element(boundBy: choices.count-1).tap()
        waitValue(app.buttons["絵画"], "0件")
        for name in ["解説", "地図", "人物"] { XCTAssertTrue((app.buttons[name].label).hasSuffix("件")) }
        capture(app, "badges-real-share-counts")
        app.buttons["閉じる"].tap()
    }
    @MainActor func testDarkAppearanceKeepsFourTabsAndArtworkIndicator() {
        let app = launch(["--qa-dark"])
        waitValue(app.buttons["絵画"], "1件")
        for name in ["解説", "地図", "人物", "絵画"] { XCTAssertTrue(app.buttons[name].isHittable) }
        capture(app, "badges-dark-four-tabs")
    }
    @MainActor func testLargeAccessibilityTextKeepsCountsInMenu() {
        let app = launch(["--qa-accessibility-text"])
        let menu = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "解説")).firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 15)); menu.tap()
        let art = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "絵画", "1件")).firstMatch
        XCTAssertTrue(art.waitForExistence(timeout: 10))
        capture(app, "badges-accessibility-menu-counts")
    }

    @MainActor func testFutureTogglePersistsAcrossTabsAndResetsForNewPassage() {
        let app = launch()
        waitValue(app.buttons["絵画"], "1件")
        app.buttons["人物"].tap()
        let future = app.switches["先の登場箇所も見る"]
        for _ in 0..<12 { if future.exists && future.isHittable && future.frame.maxY < app.descendants(matching: .any).matching(identifier: "external-question-input").firstMatch.frame.minY - 60 { break }; app.swipeUp() }
        XCTAssertTrue(future.waitForExistence(timeout: 10))
        capture(app, "glass-future-native-switch-before")
        future.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        expectation(for: NSPredicate(format: "value == %@", "1"), evaluatedWith: future); waitForExpectations(timeout: 5)
        XCTAssertEqual(future.value as? String, "1")
        capture(app, "glass-future-native-switch-on")
        app.buttons["地図"].tap(); app.buttons["人物"].tap()
        for _ in 0..<12 { if future.exists && future.isHittable && future.frame.maxY < app.descendants(matching: .any).matching(identifier: "external-question-input").firstMatch.frame.minY - 60 { break }; app.swipeUp() }
        XCTAssertEqual(future.value as? String, "1")
        XCTAssertTrue((app.buttons["人物"].label).hasSuffix("件"))
        app.buttons["QAレビ記へ"].tap(); waitValue(app.buttons["絵画"], "0件")
        app.buttons["人物"].tap()
        for _ in 0..<12 { if future.exists && future.isHittable && future.frame.maxY < app.descendants(matching: .any).matching(identifier: "external-question-input").firstMatch.frame.minY - 60 { break }; app.swipeUp() }
        XCTAssertEqual(future.value as? String, "0")
        capture(app, "badges-future-reset-on-passage-change")
    }

}
