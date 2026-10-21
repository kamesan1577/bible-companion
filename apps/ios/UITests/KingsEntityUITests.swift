import XCTest

final class KingsEntityUITests: XCTestCase {
    @MainActor func testJacobIndividualAndSourceRights() {
        let app = launch("entity-2ki-jacob")
        XCTAssertTrue(app.buttons["人物"].waitForExistence(timeout: 15)); guard CurrentUI.selectSection("人物", in: app) else { return }
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
        XCTAssertTrue(app.buttons["人物"].waitForExistence(timeout: 15)); guard CurrentUI.selectSection("人物", in: app) else { return }
        let detail = app.buttons["entity-detail-person:adrammelech_104"]
        scrollTo(detail, in: app); XCTAssertTrue(detail.exists)
        XCTAssertFalse(app.buttons["entity-detail-person:adrammelech_103"].exists)
        detail.tap(); attach(app, "kings-adrammelech-homonym")
    }
    @MainActor func testActualShareKingsBeginningShowsIsraelRegion() {
        let app = XCUIApplication(); app.launchArguments = ["--simulator-qa"]; app.launch()
        let share = CurrentUI.menu("列王記上1章を共有する", in: app)
        scrollTo(share, in: app); XCTAssertTrue(share.waitForExistence(timeout: 10)); share.tap()
        let destination = app.cells.matching(identifier: "聖書コンパニオン").firstMatch
        XCTAssertTrue(destination.waitForExistence(timeout: 10)); destination.tap()
        XCTAssertTrue(app.buttons["地図"].waitForExistence(timeout: 10)); guard CurrentUI.selectSection("地図", in: app) else { return }
        let detail = app.descendants(matching: .any).matching(identifier: "entity-detail-place:united-kingdom-of-israel_1301").firstMatch
        scrollTo(detail, in: app); XCTAssertTrue(detail.exists); detail.tap(); CurrentUI.reveal(app.buttons["この説明の出典"],in:app); XCTAssertTrue(app.buttons["この説明の出典"].exists); attach(app, "actual-share-kings-first-region")
    }
    @MainActor private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--simulator-qa", "--qa-screen=" + screen]; app.launch(); return app
    }
    @MainActor private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) { CurrentUI.reveal(element, in: app) }
    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let item = XCTAttachment(screenshot: app.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
    }
}
