import XCTest

final class KingsEntityUITests: XCTestCase {
    @MainActor func testJacobIndividualAndSourceRights() {
        let app = launch("entity-2ki-jacob")
        XCTAssertTrue(app.buttons["人物"].waitForExistence(timeout: 15)); app.buttons["人物"].tap()
        let detail = app.buttons["entity-detail-person:israel_682"]
        scrollTo(detail, in: app); XCTAssertTrue(detail.exists); detail.tap()
        let jacob = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "ヤコブ")).firstMatch
        scrollTo(jacob, in: app); XCTAssertTrue(jacob.exists); attach(app, "kings-jacob-individual")
        app.buttons["この説明の出典"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "World English Bible")).firstMatch.waitForExistence(timeout: 5))
        attach(app, "kings-source-rights")
    }
    @MainActor func testRoyalAdrammelechDoesNotBecomeTheDeity() {
        let app = launch("entity-2ki-adrammelech")
        XCTAssertTrue(app.buttons["人物"].waitForExistence(timeout: 15)); app.buttons["人物"].tap()
        let detail = app.buttons["entity-detail-person:adrammelech_104"]
        scrollTo(detail, in: app); XCTAssertTrue(detail.exists)
        XCTAssertFalse(app.buttons["entity-detail-person:adrammelech_103"].exists)
        detail.tap(); attach(app, "kings-adrammelech-homonym")
    }
    @MainActor func testActualShareKingsBeginningShowsIsraelRegion() {
        let app = XCUIApplication(); app.launchArguments = ["--simulator-qa"]; app.launch()
        let share = app.buttons["列王記上1章を共有する"]
        scrollTo(share, in: app); XCTAssertTrue(share.waitForExistence(timeout: 10)); share.tap()
        let destination = app.staticTexts.matching(NSPredicate(format: "label == %@", "聖書コンパニオン")).firstMatch
        XCTAssertTrue(destination.waitForExistence(timeout: 10)); destination.tap()
        XCTAssertTrue(app.buttons["地名"].waitForExistence(timeout: 10)); app.buttons["地名"].tap()
        let detail = app.descendants(matching: .any).matching(identifier: "entity-inline-detail-place:united-kingdom-of-israel_1301").firstMatch
        scrollTo(detail, in: app); XCTAssertTrue(detail.exists); attach(app, "actual-share-kings-first-region")
    }
    @MainActor private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--simulator-qa", "--qa-screen=" + screen]; app.launch(); return app
    }
    @MainActor private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<14 { if element.exists && element.isHittable && element.frame.minY < app.frame.height * 0.78 { return }; app.swipeUp() }
    }
    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let item = XCTAttachment(screenshot: app.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
    }
}
