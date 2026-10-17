import XCTest

final class HomeShareUXUITests: XCTestCase {
    @MainActor private func launch(_ screen: String, _ flags: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--simulator-qa", "--qa-screen=\(screen)"] + flags
        app.launch()
        return app
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways
        add(shot)
    }
    @MainActor func testHomeDiscoveryAndSetup() {
        let app = launch("initial")
        XCTAssertTrue(app.buttons["discovery-card"].waitForExistence(timeout: 15))
        capture(app, "home-dark")
        app.buttons["discovery-card"].tap()
        XCTAssertTrue(app.staticTexts["アポロとエペソの人々"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["アポロ"].firstMatch.waitForExistence(timeout: 10))
        capture(app, "discovery-open")
        app.navigationBars.buttons.firstMatch.tap()
        app.swipeUp()
        app.buttons["share-ai-settings"].tap()
        XCTAssertTrue(app.buttons["ログインして準備を始める"].waitForExistence(timeout: 10))
        capture(app, "setup-signed-out")
        app.buttons["閉じる"].tap()
        XCTAssertTrue(app.buttons["share-ai-settings"].waitForExistence(timeout: 5))
    }
    @MainActor func testFailureDoesNotClaimReady() {
        let app = launch("setup", ["--qa-share-enabled", "--qa-clear-access"])
        XCTAssertTrue(app.buttons["共有AIを有効にする"].waitForExistence(timeout: 10))
        app.buttons["共有AIを有効にする"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "処理を完了できませんでした")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["共有AIを使えます"].exists)
        capture(app, "setup-failure")
    }
    @MainActor func testSaveRelaunchAndExpiry() {
        var app = launch("setup", ["--qa-share-enabled", "--qa-clear-access", "--qa-share-success"])
        XCTAssertTrue(app.buttons["共有AIを有効にする"].waitForExistence(timeout: 10))
        app.buttons["共有AIを有効にする"].tap()
        XCTAssertTrue(app.staticTexts["共有AIを使えます"].waitForExistence(timeout: 10))
        capture(app, "setup-ready")
        app.terminate()
        app = launch("setup", ["--qa-share-enabled"])
        XCTAssertTrue(app.staticTexts["共有AIを使えます"].waitForExistence(timeout: 10))
        capture(app, "setup-ready-after-relaunch")
        app.terminate()
        app = launch("setup", ["--qa-share-enabled", "--qa-expiring-access"])
        XCTAssertTrue(app.staticTexts["共有AIの期限が切れています"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["共有AIを使えます"].exists)
        capture(app, "setup-expired")
    }
    @MainActor func testCancelWhileSaving() {
        let app = launch("home", ["--qa-share-enabled", "--qa-clear-access", "--qa-share-success", "--qa-share-slow"])
        XCTAssertTrue(app.buttons["discovery-card"].waitForExistence(timeout: 10))
        app.swipeUp(); app.buttons["share-ai-settings"].tap()
        XCTAssertTrue(app.buttons["共有AIを有効にする"].waitForExistence(timeout: 10))
        app.buttons["共有AIを有効にする"].tap()
        XCTAssertTrue(app.staticTexts["共有AIの設定を保存しています"].waitForExistence(timeout: 3))
        capture(app, "setup-saving")
        app.buttons["閉じる"].tap()
        XCTAssertTrue(app.buttons["share-ai-settings"].waitForExistence(timeout: 5))
        app.buttons["share-ai-settings"].tap()
        XCTAssertTrue(app.buttons["共有AIを有効にする"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["共有AIを使えます"].exists)
        capture(app, "setup-cancelled")
    }
    @MainActor func testAccessibilityType() {
        let app = XCUIApplication()
        app.launchArguments = ["--simulator-qa", "--qa-screen=initial", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["discovery-card"].waitForExistence(timeout: 10))
        capture(app, "home-accessibility-xxxl")
        app.swipeUp(); app.swipeUp()
        XCTAssertTrue(app.buttons["share-ai-settings"].waitForExistence(timeout: 5))
        app.buttons["share-ai-settings"].tap()
        capture(app, "setup-accessibility-xxxl-top")
        for _ in 0..<12 {
            if app.buttons["ログインして準備を始める"].isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.buttons["ログインして準備を始める"].isHittable)
        capture(app, "setup-accessibility-xxxl-action")
    }
}
