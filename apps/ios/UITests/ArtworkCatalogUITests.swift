import XCTest

final class ArtworkCatalogUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor private func verify(_ object: String, share: Bool) throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "artwork-catalog", withExtension: "json"))
        let cards = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        let card = try XCTUnwrap(cards.first { (($0["details"] as? [String: Any])?["objectUrl"] as? String)?.contains(object) == true })
        let title = try XCTUnwrap(card["title"] as? String)
        let id = try XCTUnwrap(card["id"] as? String)
        let app = XCUIApplication(); app.launchArguments = ["--simulator-qa", "--qa-screen=artwork-catalog", "--qa-handoff-owner"]
        app.launchEnvironment["BIBLE_QA_ARTWORK"] = try JSONSerialization.data(withJSONObject: card).base64EncodedString(); app.launch()
        defer { if app.buttons["閉じる"].exists { app.buttons["閉じる"].tap() }; app.terminate() }
        let art = app.buttons["絵画"]
        XCTAssertTrue(art.waitForExistence(timeout: 15))
        expectation(for: NSPredicate(format: "label CONTAINS %@", "1件"), evaluatedWith: art); waitForExpectations(timeout: 15)
        guard CurrentUI.selectSection("絵画",in:app) else { return }
        XCTAssertTrue(app.images["artwork-image-main-" + id].waitForExistence(timeout: 30), title)
        capture(app,"catalog-main-" + object.replacingOccurrences(of: "/", with: "-"))
        if share {
            app.buttons["qa-artwork-share"].tap()
            let choices = app.cells.matching(identifier: "聖書コンパニオン")
            guard choices.firstMatch.waitForExistence(timeout: 30) else {
                capture(app, "share-destination-unavailable")
                print("Missing cold share destination; visible cells: \(app.cells.allElementsBoundByIndex.map(\.label))\n\(app.debugDescription)")
                XCTFail("The system share sheet did not expose the installed extension"); return
            }
            choices.element(boundBy: choices.count-1).tap()
            XCTAssertTrue(app.buttons["閉じる"].waitForExistence(timeout: 15))
            capture(app,"catalog-share-before-select")
            let tree = XCTAttachment(string: app.debugDescription); tree.name = "catalog-share-tree"; tree.lifetime = .keepAlways; add(tree)
            let extensionApp = XCUIApplication(bundleIdentifier: "org.example.BibleCompanion.Share")
            guard CurrentUI.selectSection("絵画",in:extensionApp,shared:true) else { return }
            XCTAssertTrue(extensionApp.images["artwork-image-share-" + id].waitForExistence(timeout: 30), title)
            capture(app,"catalog-real-share-" + object.replacingOccurrences(of: "/", with: "-"))
            extensionApp.buttons["閉じる"].tap()
        }
        app.terminate()
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) { let item = XCTAttachment(screenshot: app.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item) }
    @MainActor func testNGAMainAndActualShareImage() throws { try verify("/45-finding",share:true) }
    @MainActor func testMetMainAndActualShareImage() throws { try verify("/459016",share:true) }
    @MainActor func testClevelandMainAndActualShareImage() throws { try verify("/1937.577",share:true) }
}
