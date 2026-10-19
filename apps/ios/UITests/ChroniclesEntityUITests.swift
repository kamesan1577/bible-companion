import XCTest

final class ChroniclesEntityUITests: XCTestCase {
    @MainActor func testIsraelAncestorAndPrimarySourceRights() {
        let app = launch("entity-1ch-israel")
        app.buttons["人物"].waitForExistence(timeout: 15); app.buttons["人物"].tap()
        let detail = app.buttons["entity-detail-person:israel_682"]
        scrollTo(detail, in: app); XCTAssertTrue(detail.exists); detail.tap()
        app.swipeDown(); app.swipeDown()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "イサクの子")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "ヤコブ")).firstMatch.exists)
        attach(app, "chronicles-israel-ancestor")
        let source = app.buttons["この説明の出典"]
        scrollTo(source, in: app); source.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "World English Bible")).firstMatch.waitForExistence(timeout: 5))
        attach(app, "chronicles-primary-source-rights")
    }
    @MainActor func testEphraimFirstVerseDoesNotRevealMourning() {
        let app = launch("entity-1ch-ephraim")
        XCTAssertTrue(app.buttons["人物"].waitForExistence(timeout: 15)); app.buttons["人物"].tap()
        let detail = app.buttons["entity-detail-person:ephraim_1206"]
        scrollTo(detail, in: app); XCTAssertTrue(detail.exists); detail.tap()
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "嘆")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "殺")).firstMatch.exists)
        attach(app, "chronicles-ephraim-first-verse")
    }
    @MainActor func testUncoveredNamesAreExplainedAsUnfinishedCoverage() {
        let app = launch("entity-2ch-uncovered")
        XCTAssertTrue(app.buttons["人物"].waitForExistence(timeout: 15)); app.buttons["人物"].tap()
        let notice = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "人物や地名が登場しないという意味ではありません")).firstMatch
        scrollTo(notice, in: app); XCTAssertTrue(notice.exists)
        attach(app, "chronicles-unfinished-coverage")
    }
    @MainActor func testActualShareChroniclesUsesAncestorContext() {
        let app = XCUIApplication(); app.launchArguments = ["--simulator-qa"]; app.launch()
        let share = CurrentUI.menu("歴代誌上1章を共有する", in: app)
        scrollTo(share, in: app); XCTAssertTrue(share.waitForExistence(timeout: 10)); share.tap()
        let destination = app.cells.matching(identifier: "聖書コンパニオン").firstMatch
        XCTAssertTrue(destination.waitForExistence(timeout: 10)); destination.tap()
        XCTAssertTrue(app.buttons["人物"].waitForExistence(timeout: 10)); app.buttons["人物"].tap()
        let detail = app.descendants(matching: .any).matching(identifier: "entity-detail-person:israel_682").firstMatch
        scrollTo(detail, in: app); XCTAssertTrue(detail.exists)
        detail.tap(); CurrentUI.reveal(app.buttons["この説明の出典"],in:app); XCTAssertTrue(app.buttons["この説明の出典"].exists); attach(app, "actual-share-chronicles-ancestor")
    }
    @MainActor func testJabeshHasOneCanonicalPlaceAndGatedBurial() {
        let app = launch("entity-1ch-jabesh")
        XCTAssertTrue(app.buttons["地図"].waitForExistence(timeout: 15)); app.buttons["地図"].tap()
        let detail = app.buttons["entity-detail-place:jabesh-gilead_611"]
        scrollTo(detail, in: app); XCTAssertTrue(detail.exists)
        XCTAssertFalse(app.buttons["entity-detail-place:jabesh_610"].exists)
        detail.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "七日間断食")).firstMatch.waitForExistence(timeout: 5))
        attach(app, "chronicles-jabesh-single-place")
    }
    @MainActor func testBaalahResolvesToOneKiriathJearimCard() {
        let app = launch("entity-1ch-baalah")
        XCTAssertTrue(app.buttons["地図"].waitForExistence(timeout: 15)); app.buttons["地図"].tap()
        let detail = app.buttons["entity-detail-place:kiriath-jearim_701"]
        scrollTo(detail, in: app); XCTAssertTrue(detail.exists)
        XCTAssertFalse(app.buttons["entity-detail-place:baalah_135"].exists)
        detail.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "ユダに属する")).firstMatch.waitForExistence(timeout: 5))
        attach(app, "chronicles-baalah-canonical-place")
    }
    @MainActor func testJoashRescueDoesNotRevealLaterKingship() {
        let app = launch("entity-2ch-joash")
        XCTAssertTrue(app.buttons["人物"].waitForExistence(timeout: 15)); app.buttons["人物"].tap()
        let detail = app.buttons["entity-detail-person:joash_1632"]
        scrollTo(detail, in: app); XCTAssertTrue(detail.exists); detail.tap()
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "王として立てられ")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "その子ゼカリヤを殺し")).firstMatch.exists)
        attach(app, "chronicles-joash-rescue-first-verse")
    }
    @MainActor private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--simulator-qa", "--qa-screen=" + screen]; app.launch(); return app
    }
    @MainActor private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) { CurrentUI.reveal(element, in: app) }
    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let item = XCTAttachment(screenshot: app.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
    }
    @MainActor func testAzaziahFirstAppearanceShowsPrimaryCitationWithoutWikipedia() {
        let app = launch("entity-1ch-azaziah")
        XCTAssertTrue(app.buttons["人物"].waitForExistence(timeout: 15)); app.buttons["人物"].tap()
        let detail = app.buttons["entity-detail-person:azaziah_547"]
        scrollTo(detail, in: app); XCTAssertTrue(detail.exists); detail.tap()
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "wikipedia-person:azaziah_547").firstMatch.exists)

        let source = app.buttons["この説明の出典"]
        scrollTo(source, in: app); XCTAssertTrue(source.exists); source.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "聖書本文の出典")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "World English Bible", "1CH 15:21")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "wikipedia-person:azaziah_547").firstMatch.exists)
        attach(app, "chronicles-azaziah-first-primary-only")
    }

}
