import XCTest

final class RomLeviticusEntityUITests: XCTestCase {
    @MainActor func testRomansOpeningShowsStoredProfileSourceAndWikipedia() {
        let app = launch("entity-rom-early")
        XCTAssertTrue(app.buttons["人物"].waitForExistence(timeout: 15))
        app.buttons["人物"].tap()

        let paul = app.buttons["entity-detail-person:paul_2479"]
        scrollTo(paul, in: app)
        XCTAssertTrue(paul.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "召された使徒")).firstMatch.exists)
        attach(app, "rom-early-people-stored-profile")

        paul.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "wikipedia-person:paul_2479").firstMatch.waitForExistence(timeout: 5))
        CurrentUI.reveal(app.buttons["この説明の出典"], in: app); app.buttons["この説明の出典"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "World English Bible")).firstMatch.waitForExistence(timeout: 5))
        attach(app, "rom-early-profile-source-and-wikipedia")
    }

    @MainActor func testRomansJacobVariantIsNotDisplayedAsIsraeliteCollective() {
        let app = launch("entity-rom-jacob")
        XCTAssertTrue(app.buttons["人物"].waitForExistence(timeout: 15))
        app.buttons["人物"].tap()

        let jacob = app.staticTexts["ヤコブ"].firstMatch
        scrollTo(jacob, in: app)
        XCTAssertTrue(jacob.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["イスラエルの民"].exists)
        attach(app, "rom-jacob-personal-name")
    }

    @MainActor func testRomansLateShowsCenchreaeCandidateMap() {
        let app = launch("entity-rom-late")
        XCTAssertTrue(app.buttons["人物"].waitForExistence(timeout: 15))
        app.buttons["人物"].tap()
        XCTAssertTrue(app.staticTexts["プリスカ"].waitForExistence(timeout: 5))
        attach(app, "rom-late-people")

        app.buttons["地図"].tap()
        let candidateMap = app.buttons["entity-candidate-map-place:cenchreae_281"]
        scrollTo(candidateMap, in: app)
        XCTAssertTrue(candidateMap.waitForExistence(timeout: 5))
        candidateMap.tap()
        XCTAssertTrue(app.staticTexts["従来資料の候補位置"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "entity-candidate-map-content-place:cenchreae_281").firstMatch.exists)
        attach(app, "rom-late-cenchreae-candidate-map")
    }

    @MainActor func testLeviticusOpeningShowsStoredProfileSourceAndWikipedia() {
        let app = launch("entity-lev-early")
        XCTAssertTrue(app.buttons["人物"].waitForExistence(timeout: 15))
        let people=app.buttons["人物"]
        expectation(for:NSPredicate(format:"label ENDSWITH %@","件"),evaluatedWith:people);waitForExpectations(timeout:15)
        people.tap();XCTAssertTrue(people.isSelected)

        let moses = app.buttons["entity-detail-person:moses_2108"]
        CurrentUI.reveal(moses, in: app)
        XCTAssertTrue(people.isSelected, "Vertical scrolling must not change the reading tab")
        XCTAssertTrue(moses.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "会見の天幕")).firstMatch.exists)
        attach(app, "lev-early-people-stored-profile")

        moses.tap()
        let wiki = app.descendants(matching: .any).matching(identifier: "wikipedia-person:moses_2108").firstMatch
        CurrentUI.reveal(wiki, in: app); XCTAssertTrue(wiki.exists)
        CurrentUI.reveal(app.buttons["この説明の出典"], in: app); app.buttons["この説明の出典"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "World English Bible")).firstMatch.waitForExistence(timeout: 5))
        attach(app, "lev-early-profile-source-and-wikipedia")
    }

    @MainActor func testLeviticusSinaiMountainAndWildernessRemainSeparate() {
        let app = launch("entity-lev-sinai")
        XCTAssertTrue(app.buttons["地図"].waitForExistence(timeout: 15))
        app.buttons["地図"].tap()

        let mountain = app.staticTexts["シナイ山"].firstMatch
        let wilderness = app.staticTexts["シナイの荒野"].firstMatch
        scrollTo(mountain, in: app)
        XCTAssertTrue(mountain.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["entity-detail-place:mount_sinai_855"].exists)
        scrollTo(wilderness, in: app)
        XCTAssertTrue(wilderness.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["entity-detail-place:sinai_1098"].exists)
        attach(app, "lev-sinai-mountain-and-wilderness")
    }

    @MainActor func testLeviticusJacobVariantIsNotDisplayedAsIsraeliteCollective() {
        let app = launch("entity-lev-jacob")
        XCTAssertTrue(app.buttons["人物"].waitForExistence(timeout: 15))
        app.buttons["人物"].tap()

        let jacob = app.staticTexts["ヤコブ"].firstMatch
        scrollTo(jacob, in: app)
        XCTAssertTrue(jacob.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["イスラエルの民"].exists)
        attach(app, "lev-jacob-personal-name")
    }

    @MainActor private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--simulator-qa", "--qa-screen=" + screen]
        app.launch()
        return app
    }

    @MainActor private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) { CurrentUI.reveal(element, in: app) }

    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 1)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
