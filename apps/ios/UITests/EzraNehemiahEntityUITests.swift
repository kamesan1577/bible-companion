import XCTest

final class EzraNehemiahEntityUITests: XCTestCase {
    @MainActor func testAdaiah75ShowsItsOwnVerseAndPrimarySource() {
        let app = launch("entity-ezr-adaiah")
        XCTAssertTrue(app.buttons["人物"].waitForExistence(timeout: 15)); app.buttons["人物"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "原文と照合したものから順に収録")).firstMatch.waitForExistence(timeout: 5))
        let detail = app.buttons["entity-detail-person:adaiah_75"]
        scrollTo(detail, in: app); XCTAssertTrue(detail.exists); detail.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "エズラ記10:39")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "wikipedia-person:adaiah_75").firstMatch.exists)
        attach(app, "ezr-adaiah75-primary-description")
        let sources = app.buttons["この説明の出典"]
        scrollTo(sources, in: app); XCTAssertTrue(sources.exists); sources.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "World English Bible")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Public Domain")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "fixed witness")).firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "webp-usfx-")).firstMatch.exists)
        attach(app, "ezr-adaiah75-public-domain-source")
    }

    @MainActor func testNehemiahAthaiahShowsReviewedDescriptionAndOwnSource() {
        let app = launch("entity-neh-athaiah")
        XCTAssertTrue(app.buttons["人物"].waitForExistence(timeout: 15)); app.buttons["人物"].tap()
        let detail = app.buttons["entity-detail-person:athaiah_358"]
        scrollTo(detail, in: app); XCTAssertTrue(detail.exists); detail.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "エルサレムに住んだユダ族")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "wikipedia-person:athaiah_358").firstMatch.exists)
        attach(app, "neh-athaiah358-primary-description")
        let sources = app.buttons["この説明の出典"]
        scrollTo(sources, in: app); XCTAssertTrue(sources.exists); sources.tap()
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "NEH 11:4")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Public Domain")).firstMatch.waitForExistence(timeout: 5))
        attach(app, "neh-athaiah358-public-domain-source")
    }

    @MainActor func testHeldBeerothAndPartialCoverageRemainExplicit() {
        let app = launch("entity-neh-beeroth")
        XCTAssertTrue(app.buttons["地図"].waitForExistence(timeout: 15)); app.buttons["地図"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "説明が出ない名前も、未収録の場合があります")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["entity-detail-place:beeroth_168"].exists)
        attach(app, "neh-held-beeroth-partial-coverage")
    }

    @MainActor func testHeldElnathanIDIsNotRenderedAsAResolvedPerson() {
        let app = launch("entity-ezr-held-elnathan")
        XCTAssertTrue(app.buttons["人物"].waitForExistence(timeout: 15)); app.buttons["人物"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "説明が出ない名前も、未収録の場合があります")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["entity-detail-person:elnathan_1180"].exists)
        attach(app, "ezr-ambiguous-elnathan-held-absent")
    }

    @MainActor func testAijaShowsScopedLocationAndPrimarySource() {
        let app = launch("entity-neh-aija")
        XCTAssertTrue(app.buttons["地図"].waitForExistence(timeout: 15)); app.buttons["地図"].tap()
        let detail = app.buttons["entity-detail-place:aija_39"]
        scrollTo(detail, in: app); XCTAssertTrue(detail.exists); detail.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "11:31")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "wikipedia-place:aija_39").firstMatch.exists)
        attach(app, "neh-aija39-scoped-location-description")
        let sources = app.buttons["この説明の出典"]
        scrollTo(sources, in: app); XCTAssertTrue(sources.exists); sources.tap()
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "NEH 11:31")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Public Domain")).firstMatch.waitForExistence(timeout: 5))
        attach(app, "neh-aija39-public-domain-source")
    }

    @MainActor func testHezekiahShowsUnidentifiedNameWithoutKingIdentity() {
        let app = launch("entity-ezr-hezekiah")
        XCTAssertTrue(app.buttons["人物"].waitForExistence(timeout: 15)); app.buttons["人物"].tap()
        let detail = app.buttons["entity-detail-person:hezekiah_1514"]
        scrollTo(detail, in: app); XCTAssertTrue(detail.exists); detail.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "特定できません")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "wikipedia-person:hezekiah_1514").firstMatch.exists)
        attach(app, "ezr-hezekiah1514-unidentified-list-name")
        let sources = app.buttons["この説明の出典"]
        scrollTo(sources, in: app); XCTAssertTrue(sources.exists); sources.tap()
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "2:16")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Public Domain")).firstMatch.waitForExistence(timeout: 5))
        attach(app, "ezr-hezekiah1514-primary-source")
    }

    @MainActor func testHanunFirstDescriptionDoesNotRevealLaterNamesake() {
        let app = launch("entity-neh-hanun-early")
        XCTAssertTrue(app.buttons["人物"].waitForExistence(timeout: 15)); app.buttons["人物"].tap()
        let detail = app.buttons["entity-detail-person:hanun_1405"]
        scrollTo(detail, in: app); XCTAssertTrue(detail.exists); detail.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "谷の門")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "3:30")).firstMatch.exists)
        attach(app, "neh-hanun-first-appearance-no-later-namesake")
    }

    @MainActor func testHananFirstDescriptionKeepsLaterSourceHidden() {
        let app = launch("entity-neh-hanan-early")
        XCTAssertTrue(app.buttons["人物"].waitForExistence(timeout: 15)); app.buttons["人物"].tap()
        let detail = app.buttons["entity-detail-person:hanan_1374"]
        scrollTo(detail, in: app)
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        XCTAssertTrue(detail.isHittable)
        attach(app, "neh-hanan-detail-link-before-navigation")
        detail.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
        let detailTitle = app.navigationBars["ハナン"]
        if !detailTitle.waitForExistence(timeout: 3) {
            // Confirm the first tap actually changed navigation state; retry once from a clear hit area.
            scrollTo(detail, in: app)
            XCTAssertTrue(detail.isHittable)
            detail.tap()
        }
        guard detailTitle.waitForExistence(timeout: 5) else {
            XCTFail("Hanan detail navigation did not open"); return
        }
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "律法理解を助けた人々")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "後のレビ人名簿")).firstMatch.exists)
        attach(app, "neh-hanan-first-appearance-scoped-description")
        let sources = app.buttons["この説明の出典"]
        scrollTo(sources, in: app)
        XCTAssertTrue(sources.waitForExistence(timeout: 5))
        sources.tap()
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "NEH 8:7")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "NEH 10:10")).firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "fixed witness")).firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "webp-usfx-")).firstMatch.exists)
        attach(app, "neh-hanan-first-source-with-later-source-hidden")
    }

    @MainActor func testHarhurFamilyLabelUsesNameDetail() {
        let app = launch("entity-neh-harhur")
        XCTAssertTrue(app.buttons["人物"].waitForExistence(timeout: 15)); app.buttons["人物"].tap()
        let detail = app.buttons["entity-detail-person:harhur_1415"]
        scrollTo(detail, in: app); XCTAssertTrue(detail.exists)
        XCTAssertTrue(detail.label.contains("この名前について")); detail.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "集団名")).firstMatch.waitForExistence(timeout: 5))
        attach(app, "neh-harhur-family-label-name-detail")
    }

    @MainActor func testHodevahFamilyNameDetailUsesScopedTextAndPrimaryCitation() {
        let app = launch("entity-neh-hodevah")
        XCTAssertTrue(app.buttons["人物"].waitForExistence(timeout: 15)); app.buttons["人物"].tap()
        let detail = app.buttons["entity-detail-person:hodevah_1542"]
        scrollTo(detail, in: app); XCTAssertTrue(detail.exists)
        XCTAssertTrue(detail.label.contains("この名前について")); detail.tap()
        let summary = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "家系名の範囲")).firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertFalse(summary.label.contains("74"))
        XCTAssertFalse(summary.label.localizedCaseInsensitiveContains("seventy-four"))
        attach(app, "neh-hodevah1542-family-name-description")
        let sources = app.buttons["この説明の出典"]
        scrollTo(sources, in: app); XCTAssertTrue(sources.exists); sources.tap()
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "NEH 7:43")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Public Domain")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "fixed witness")).firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "webp-usfx-")).firstMatch.exists)
        attach(app, "neh-hodevah1542-primary-source-public-domain")
    }

    @MainActor func testJoiada1680EarlyDetailShowsFirstOccurrenceRoleAndSourceOnly() {
        let app = launch("entity-neh-joiada-early")
        XCTAssertTrue(app.buttons["人物"].waitForExistence(timeout: 15)); app.buttons["人物"].tap()
        let detail = app.buttons["entity-detail-person:joiada_1680"]
        scrollTo(detail, in: app); XCTAssertTrue(detail.exists); detail.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "ヨヤダをエリアシブの子として系譜に記します")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "系譜に記されるエリアシブの子。")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "祭司エリアシブ")).firstMatch.exists)
        attach(app, "neh-joiada1680-first-occurrence-role")
        let sources = app.buttons["この説明の出典"]
        scrollTo(sources, in: app); XCTAssertTrue(sources.exists); sources.tap()
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "NEH 12:10")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "NEH 13:28")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "World English Bible")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Public Domain")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "fixed witness")).firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "webp-usfx-")).firstMatch.exists)
        attach(app, "neh-joiada1680-first-source-public-domain")
    }

    @MainActor func testSanballat2470EarlyDetailShowsFirstOccurrenceAndPrimarySourceOnly() {
        let app = launch("entity-neh-sanballat-early")
        XCTAssertTrue(app.buttons["人物"].waitForExistence(timeout: 15)); app.buttons["人物"].tap()
        let detail = app.buttons["entity-detail-person:sanballat_2470"]
        scrollTo(detail, in: app); XCTAssertTrue(detail.exists); detail.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "ホロナイ人サンバラテは、トビヤとともに")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "ゲシェム")).firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "2:19")).firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "13:28")).firstMatch.exists)
        attach(app, "neh-sanballat2470-first-occurrence-description")
        let sources = app.buttons["この説明の出典"]
        scrollTo(sources, in: app); XCTAssertTrue(sources.exists); sources.tap()
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Nehemiah 2:10")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Nehemiah 2:19")).firstMatch.exists)
        XCTAssertFalse(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Nehemiah 13:28")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "World English Bible")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Public Domain")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "AIによる日本語編集")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "fixed witness")).firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "webp-usfx-")).firstMatch.exists)
        attach(app, "neh-sanballat2470-first-source-public-domain-ai-attribution")
    }

    @MainActor func testMeremoth2006EarlyDetailShowsCorrectLineageAndFirstSourceOnly() {
        let app = launch("entity-neh-meremoth-early")
        XCTAssertTrue(app.buttons["人物"].waitForExistence(timeout: 15)); app.buttons["人物"].tap()
        let detail = app.buttons["entity-detail-person:meremoth_2006"]
        scrollTo(detail, in: app); XCTAssertTrue(detail.exists); detail.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "ウリヤの子、ハッコツの孫")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "3:21")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "複数箇所")).firstMatch.exists)
        attach(app, "neh-meremoth2006-correct-lineage-description")
        let sources = app.buttons["この説明の出典"]
        scrollTo(sources, in: app); XCTAssertTrue(sources.exists); sources.tap()
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "NEH 3:4")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "NEH 3:21")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "World English Bible")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Public Domain")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "fixed witness")).firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "webp-usfx-")).firstMatch.exists)
        attach(app, "neh-meremoth2006-first-source-public-domain")
    }

    @MainActor private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--simulator-qa", "--qa-screen=" + screen]; app.launch(); return app
    }

    @MainActor private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        // Keep controls below the pinned reading header and above the floating AI button.
        let safeTop = app.frame.height * 0.32
        let safeBottom = app.frame.height * 0.70
        let lower = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.68))
        let upper = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.48))
        for _ in 0..<24 {
            if element.exists && element.isHittable && element.frame.minY >= safeTop && element.frame.maxY <= safeBottom { return }
            if element.exists && element.frame.height > 0 && element.frame.minY < safeTop {
                upper.press(forDuration: 0.05, thenDragTo: lower)
            } else {
                lower.press(forDuration: 0.05, thenDragTo: upper)
            }
        }
    }

    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let item = XCTAttachment(screenshot: app.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
    }
}
