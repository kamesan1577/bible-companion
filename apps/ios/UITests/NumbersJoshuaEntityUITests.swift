import XCTest

final class NumbersJoshuaEntityUITests: XCTestCase {
    @MainActor func testHosheaNameAndSource() {
        let app=launch("entity-num-hoshea")
        XCTAssertTrue(app.buttons["人物"].waitForExistence(timeout:15)); app.buttons["人物"].tap()
        let detail=app.buttons["entity-detail-person:joshua_1727"]; scrollTo(detail,in:app); XCTAssertTrue(detail.exists); detail.tap()
        XCTAssertTrue(app.staticTexts["ホセア"].firstMatch.waitForExistence(timeout:5))
        XCTAssertFalse(app.descendants(matching:.any).matching(identifier:"wikipedia-person:joshua_1727").firstMatch.exists)
        app.buttons["この説明の出典"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@","World English Bible")).firstMatch.waitForExistence(timeout:5))
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@","資料上の識別ID")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@","このcontext")).firstMatch.exists)
        attach(app,"num-hoshea-existing-id-source")
    }
    @MainActor func testGileadBothMeanings() {
        let app=launch("entity-num-gilead")
        XCTAssertTrue(app.buttons["人物"].waitForExistence(timeout:15));app.buttons["人物"].tap()
        let detail=app.buttons["entity-detail-person:gilead_1317"];scrollTo(detail,in:app);XCTAssertTrue(detail.exists);detail.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@","ギレアド人")).firstMatch.waitForExistence(timeout:5))
        attach(app,"num-gilead-dual-meaning")
    }
    @MainActor func testBohanFather() {
        let app=launch("entity-jos-bohan")
        XCTAssertTrue(app.buttons["人物"].waitForExistence(timeout:15));app.buttons["人物"].tap()
        let detail=app.buttons["entity-detail-person:reuben_2429"];scrollTo(detail,in:app);XCTAssertTrue(detail.exists);detail.tap()
        XCTAssertTrue(app.staticTexts["ルベン（ボハンの父）"].firstMatch.waitForExistence(timeout:5));attach(app,"jos-bohan-unidentified-father")
    }
    @MainActor func testDebirAliasSingleCardAndCandidateMap() {
        let app=launch("entity-jos-alias")
        XCTAssertTrue(app.buttons["地図"].waitForExistence(timeout:15));app.buttons["地図"].tap()
        let detail=app.buttons["entity-detail-place:debir_325"];scrollTo(detail,in:app);XCTAssertTrue(detail.exists)
        XCTAssertFalse(app.buttons["entity-detail-place:kiriath-sannah_702"].exists)
        let map=app.buttons["entity-candidate-map-place:debir_325"];scrollTo(map,in:app);XCTAssertTrue(map.exists);map.tap()
        XCTAssertTrue(app.staticTexts["従来資料の候補位置"].waitForExistence(timeout:5));attach(app,"jos-debir-single-alias-candidate-map")
    }

    @MainActor func testActualShareNumbersSameVerseBothMeanings() {
        let app=XCUIApplication();app.launchArguments=["--simulator-qa"];app.launch()
        let share=app.buttons["民数記26章を共有する"];XCTAssertTrue(share.waitForExistence(timeout:10));share.tap()
        let destination=app.staticTexts.matching(NSPredicate(format:"label == %@","聖書コンパニオン")).firstMatch
        XCTAssertTrue(destination.waitForExistence(timeout:10));destination.tap()
        XCTAssertTrue(app.buttons["人物"].waitForExistence(timeout:10));app.buttons["人物"].tap()
        let detail=app.descendants(matching:.any).matching(identifier:"entity-inline-detail-person:gilead_1317").firstMatch
        scrollTo(detail,in:app);XCTAssertTrue(detail.exists)
        let clan=app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@","ギレアド人")).firstMatch
        scrollTo(clan,in:app);XCTAssertTrue(clan.exists);attach(app,"actual-share-num-gilead-both-meanings")
    }
    @MainActor func testActualShareJoshuaSingleAliasAndMap() {
        let app=XCUIApplication();app.launchArguments=["--simulator-qa"];app.launch()
        let share=app.buttons["ヨシュア記15章を共有する"];XCTAssertTrue(share.waitForExistence(timeout:10));share.tap()
        let destination=app.staticTexts.matching(NSPredicate(format:"label == %@","聖書コンパニオン")).firstMatch
        XCTAssertTrue(destination.waitForExistence(timeout:10));destination.tap()
        XCTAssertTrue(app.buttons["地名"].waitForExistence(timeout:10));app.buttons["地名"].tap()
        let detail=app.descendants(matching:.any).matching(identifier:"entity-inline-detail-place:debir_325").firstMatch
        scrollTo(detail,in:app);XCTAssertTrue(detail.exists)
        XCTAssertFalse(app.descendants(matching:.any).matching(identifier:"entity-inline-detail-place:kiriath-sannah_702").firstMatch.exists)
        let map=app.descendants(matching:.any).matching(identifier:"entity-candidate-map-content-place:debir_325").firstMatch
        scrollTo(map,in:app);XCTAssertTrue(map.exists);attach(app,"actual-share-jos-debir-single-alias-map")
    }

    @MainActor private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--simulator-qa", "--qa-screen=" + screen]
        app.launch()
        return app
    }

    @MainActor private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<14 {
            if element.exists && element.isHittable && element.frame.minY < app.frame.height * 0.78 { return }
            app.swipeUp()
        }
    }

    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 1)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
