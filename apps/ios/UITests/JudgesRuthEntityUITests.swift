import XCTest

final class JudgesRuthEntityUITests: XCTestCase {
    @MainActor func testDanBothMeaningsAndSource() {
        let app=launch("entity-jdg-dan")
        XCTAssertTrue(app.buttons["人物"].waitForExistence(timeout:15));guard CurrentUI.selectSection("人物", in: app) else { return }
        let detail=app.buttons["entity-detail-person:dan_973"];scrollTo(detail,in:app);XCTAssertTrue(detail.exists);detail.tap()
        let ancestor=app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@","彼らの父" )).firstMatch
        scrollTo(ancestor,in:app);XCTAssertTrue(ancestor.exists);attach(app,"jdg-dan-collective-and-ancestor")
        app.buttons["この説明の出典"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@","World English Bible")).firstMatch.waitForExistence(timeout:5))
        attach(app,"jdg-dan-source-rights")
    }
    @MainActor func testSecondLuzRemainsASeparatePlace() {
        let app=launch("entity-jdg-luz")
        XCTAssertTrue(app.buttons["地図"].waitForExistence(timeout:15));guard CurrentUI.selectSection("地図", in: app) else { return }
        let detail=app.buttons["entity-detail-place:luz_738"];scrollTo(detail,in:app);XCTAssertTrue(detail.exists)
        XCTAssertFalse(app.buttons["entity-detail-place:bethel_202"].exists);detail.tap();attach(app,"jdg-second-luz-distinct-place")
    }
    @MainActor func testActualShareRuthBeginningShowsReviewedPlaces() {
        let app=XCUIApplication();app.launchArguments=["--simulator-qa"];app.launch()
        let share = CurrentUI.menu("ルツ記1章を共有する", in: app);XCTAssertTrue(share.waitForExistence(timeout:10));share.tap()
        let destination = app.cells.matching(identifier: "聖書コンパニオン").firstMatch
        XCTAssertTrue(destination.waitForExistence(timeout:10));destination.tap()
        XCTAssertTrue(app.buttons["地図"].waitForExistence(timeout:10));guard CurrentUI.selectSection("地図", in: app) else { return }
        let detail=app.descendants(matching:.any).matching(identifier:"entity-detail-place:bethlehem_218").firstMatch
        scrollTo(detail,in:app);XCTAssertTrue(detail.exists)
        XCTAssertFalse(app.descendants(matching:.any).matching(identifier:"entity-detail-place:ephrathah_404").firstMatch.exists)
        detail.tap(); CurrentUI.reveal(app.buttons["この説明の出典"],in:app); XCTAssertTrue(app.buttons["この説明の出典"].exists); attach(app,"actual-share-ruth-first-places")
    }
    @MainActor private func launch(_ screen:String)->XCUIApplication {let app=XCUIApplication();app.launchArguments=["--simulator-qa","--qa-screen="+screen];app.launch();return app}
    @MainActor private func scrollTo(_ element:XCUIElement,in app:XCUIApplication) { CurrentUI.reveal(element, in: app) }
    @MainActor private func attach(_ app:XCUIApplication,_ name:String) {let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
}
