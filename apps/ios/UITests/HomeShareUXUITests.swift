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
        XCTAssertTrue(app.buttons["質問する設定を保存する"].waitForExistence(timeout: 10))
        app.buttons["質問する設定を保存する"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "処理を完了できませんでした")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["質問する設定を保存しました"].exists)
        capture(app, "setup-failure")
    }
    @MainActor func testSaveRelaunchAndExpiry() {
        var app = launch("setup", ["--qa-share-enabled", "--qa-clear-access", "--qa-share-success"])
        XCTAssertTrue(app.buttons["質問する設定を保存する"].waitForExistence(timeout: 10))
        app.buttons["質問する設定を保存する"].tap()
        XCTAssertTrue(app.staticTexts["質問する設定を保存しました"].waitForExistence(timeout: 10))
        capture(app, "setup-ready")
        app.terminate()
        app = launch("setup", ["--qa-share-enabled"])
        XCTAssertTrue(app.staticTexts["質問する設定を保存しました"].waitForExistence(timeout: 10))
        capture(app, "setup-ready-after-relaunch")
        app.terminate()
        app = launch("setup", ["--qa-share-enabled", "--qa-expiring-access"])
        XCTAssertTrue(app.staticTexts["質問する設定の期限が切れています"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["質問する設定を保存しました"].exists)
        capture(app, "setup-expired")
    }
    @MainActor func testCancelWhileSaving() {
        let app = launch("home", ["--qa-share-enabled", "--qa-clear-access", "--qa-share-success", "--qa-share-slow"])
        XCTAssertTrue(app.buttons["discovery-card"].waitForExistence(timeout: 10))
        app.swipeUp(); app.buttons["share-ai-settings"].tap()
        XCTAssertTrue(app.buttons["質問する設定を保存する"].waitForExistence(timeout: 10))
        app.buttons["質問する設定を保存する"].tap()
        XCTAssertTrue(app.staticTexts["質問する設定を保存しています"].waitForExistence(timeout: 3))
        capture(app, "setup-saving")
        app.buttons["閉じる"].tap()
        XCTAssertTrue(app.buttons["share-ai-settings"].waitForExistence(timeout: 5))
        app.buttons["share-ai-settings"].tap()
        XCTAssertTrue(app.buttons["質問する設定を保存する"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["質問する設定を保存しました"].exists)
        capture(app, "setup-cancelled")
    }
    @MainActor func testRootHomeWithNativeTabs() {
        let app = XCUIApplication()
        app.launchArguments = ["--simulator-qa", "--qa-screen=configured-home", "-hasSeenVisualShareGuideV2", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["discovery-card"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["アプリの接続設定に問題があります。最新版へ更新して、もう一度お試しください。"].exists)
        let prepare = app.buttons["share-ai-settings"]
        XCTAssertTrue(prepare.isHittable)
        XCTAssertTrue(app.tabBars.firstMatch.exists)
        XCTAssertLessThan(prepare.frame.maxY, app.tabBars.firstMatch.frame.minY)
        capture(app, "home-root-dark")
        app.swipeUp()
        app.buttons["browse-chapters"].tap()
        XCTAssertTrue(app.navigationBars["章から説明を探す"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        prepare.tap()
        XCTAssertTrue(app.buttons["ログインして準備を始める"].waitForExistence(timeout: 5))
        app.buttons["閉じる"].tap()
        XCTAssertTrue(prepare.waitForExistence(timeout: 5))
    }
    @MainActor func testUnconfiguredHomeShowsWarning() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasSeenVisualShareGuideV2", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["discovery-card"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["アプリの接続設定に問題があります。最新版へ更新して、もう一度お試しください。"].exists)
        capture(app, "home-unconfigured-error")
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
