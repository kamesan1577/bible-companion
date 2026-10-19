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
        XCTAssertTrue(app.buttons["discovery-card"].waitForExistence(timeout: 15)); capture(app, "home-current")
        app.buttons["discovery-card"].tap()
        XCTAssertTrue(app.staticTexts["アポロと夫妻の個別指導"].waitForExistence(timeout: 10))
        for title in ["解説", "地図", "人物", "絵画"] { XCTAssertTrue(app.buttons[title].exists) }
        XCTAssertTrue(CurrentUI.input(app).exists); capture(app, "discovery-current-reader")
        app.buttons["external-provider-settings"].tap()
        XCTAssertTrue(app.buttons["external-provider-picker"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["ログインして準備を始める"].exists)
        app.buttons["完了"].tap(); XCTAssertTrue(CurrentUI.input(app).exists)
    }
    @MainActor func testMissingSettingsAndReadOnlyDiagnostics() {
        let app = launch("setup", ["--qa-share-enabled", "--qa-clear-access"])
        XCTAssertTrue(app.staticTexts["共有画面で質問するには準備が必要です"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["質問する設定を確認できません"].exists)
        app.buttons["share-storage-diagnostics"].tap()
        let report = app.staticTexts["share-storage-diagnostic-result"]
        XCTAssertTrue(report.waitForExistence(timeout: 5))
        XCTAssertTrue(report.label.contains("missing"))
        XCTAssertTrue(report.label.contains("読み取りのみ"))
        XCTAssertFalse(report.label.contains("bcs1_"))
        capture(app, "missing-settings-diagnostic")
    }
    @MainActor func testDiagnosticsPreserveVerifiedSavedSettings() {
        let app = launch("setup", ["--qa-share-enabled", "--qa-clear-access", "--qa-share-success"])
        XCTAssertTrue(app.buttons["質問する設定を保存する"].waitForExistence(timeout: 15))
        app.buttons["質問する設定を保存する"].tap()
        XCTAssertTrue(app.staticTexts["質問する設定を保存しました"].waitForExistence(timeout: 10))
        app.buttons["share-storage-diagnostics"].tap()
        let report = app.staticTexts["share-storage-diagnostic-result"]
        XCTAssertTrue(report.waitForExistence(timeout: 5))
        XCTAssertTrue(report.label.contains("共有設定の読み取り：成功"))
        XCTAssertFalse(report.label.contains("bcs1_"))
        capture(app, "saved-settings-diagnostic")
        app.terminate()
        let restored = launch("setup", ["--qa-share-enabled"])
        XCTAssertTrue(restored.staticTexts["質問する設定を保存しました"].waitForExistence(timeout: 10))
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
    @MainActor func testProviderSheetDismissAndChangePreserveDraft() {
        let app = launch("unified", ["--qa-reset-provider"])
        let field = CurrentUI.input(app); XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap(); field.typeText(" provider-sheet-dismiss-keeps-draft")
        let draft = field.value as? String
        app.buttons["external-provider-settings"].tap()
        XCTAssertTrue(app.buttons["external-provider-picker"].exists)
        XCTAssertFalse(app.staticTexts["質問する設定を保存しています"].exists)
        app.buttons["完了"].tap(); XCTAssertEqual(field.value as? String, draft)
        CurrentUI.provider("Claude", in: app)
        XCTAssertEqual(field.value as? String, draft); capture(app, "provider-sheet-dismiss-keeps-draft")
    }
    @MainActor func testRootHomeWithNativeTabs() {
        let app = launch("configured-home", ["-hasSeenVisualShareGuideV2", "YES"])
        XCTAssertTrue(app.buttons["discovery-card"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.tabBars.firstMatch.exists)
        XCTAssertTrue(CurrentUI.input(app).exists); capture(app, "home-current-native-tabs")
        CurrentUI.reveal(app.buttons["browse-chapters"], in: app); app.buttons["browse-chapters"].tap()
        XCTAssertTrue(app.navigationBars["章から説明を探す"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        app.tabBars.buttons["設定"].tap()
        XCTAssertTrue(app.buttons["external-provider-picker"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["質問の送信先"].exists)
    }
    @MainActor func testUnconfiguredHomeRetainsOfflineReaderWithoutBlockingWarning() {
        let app = XCUIApplication(); app.launchArguments = ["-hasSeenVisualShareGuideV2", "YES"]; app.launch()
        XCTAssertTrue(app.buttons["discovery-card"].waitForExistence(timeout: 15))
        app.buttons["discovery-card"].tap()
        XCTAssertTrue(app.staticTexts["アポロと夫妻の個別指導"].waitForExistence(timeout: 10))
        XCTAssertTrue(CurrentUI.input(app).exists)
        XCTAssertFalse(app.staticTexts["アプリの接続設定に問題があります。最新版へ更新して、もう一度お試しください。"].exists)
        capture(app, "unconfigured-offline-reader-available")
    }
    @MainActor func testAccessibilityType() {
        let app = launch("initial", ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(app.buttons["discovery-card"].waitForExistence(timeout: 15)); capture(app,"home-accessibility-xxxl")
        let settings = app.buttons["external-provider-settings"]
        XCTAssertTrue(settings.isHittable); settings.tap()
        XCTAssertTrue(app.buttons["external-provider-picker"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["完了"].isHittable); capture(app,"provider-accessibility-xxxl")
        app.buttons["完了"].tap(); XCTAssertTrue(CurrentUI.input(app).exists)
    }
}
