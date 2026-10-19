import XCTest

final class SamuelEntityUITests: XCTestCase {
    @MainActor func testJacobAndIsraelMeaningsAndSources() {
        let app=launch("entity-2sa-dual")
        XCTAssertTrue(app.buttons["人物"].waitForExistence(timeout:15));app.buttons["人物"].tap()
        let detail=app.buttons["entity-detail-person:israel_682"];scrollTo(detail,in:app);XCTAssertTrue(detail.exists);detail.tap()
        let jacob=app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@","ヤコブ")).firstMatch
        scrollTo(jacob,in:app);XCTAssertTrue(jacob.exists);attach(app,"samuel-israel-jacob-dual-context")
        app.buttons["この説明の出典"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@","World English Bible")).firstMatch.waitForExistence(timeout:5));attach(app,"samuel-source-rights")
    }
    @MainActor func testHittiteAhimelechIsSeparateFromPriest() {
        let app=launch("entity-1sa-ahimelech")
        XCTAssertTrue(app.buttons["人物"].waitForExistence(timeout:15));app.buttons["人物"].tap()
        let detail=app.buttons["entity-detail-person:ahimelech_148"];scrollTo(detail,in:app);XCTAssertTrue(detail.exists)
        XCTAssertFalse(app.buttons["entity-detail-person:ahimelech_126"].exists);detail.tap();attach(app,"samuel-ahimelech-homonym")
    }
    @MainActor func testActualShareSamuelBeginningShowsReviewedPlaces() {
        let app=XCUIApplication();app.launchArguments=["--simulator-qa"];app.launch()
        let share = CurrentUI.menu("サムエル記上1章を共有する", in: app);scrollTo(share,in:app);XCTAssertTrue(share.waitForExistence(timeout:10));share.tap()
        let destination = app.cells.matching(identifier: "聖書コンパニオン").firstMatch
        XCTAssertTrue(destination.waitForExistence(timeout:10));destination.tap()
        XCTAssertTrue(app.buttons["地図"].waitForExistence(timeout:10));app.buttons["地図"].tap()
        let detail=app.descendants(matching:.any).matching(identifier:"entity-detail-place:ephraim-territory_1292").firstMatch
        scrollTo(detail,in:app);XCTAssertTrue(detail.exists);detail.tap(); CurrentUI.reveal(app.buttons["この説明の出典"],in:app); XCTAssertTrue(app.buttons["この説明の出典"].exists); attach(app,"actual-share-samuel-first-places")
    }
    @MainActor private func launch(_ screen:String)->XCUIApplication {let app=XCUIApplication();app.launchArguments=["--simulator-qa","--qa-screen="+screen];app.launch();return app}
    @MainActor private func scrollTo(_ element:XCUIElement,in app:XCUIApplication) { CurrentUI.reveal(element, in: app) }
    @MainActor private func attach(_ app:XCUIApplication,_ name:String) {let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
}
