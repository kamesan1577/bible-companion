import XCTest
final class ShareCrashUITests: XCTestCase {
    @MainActor func testRepeatedActs2815AndOtherPlaceMapsWithKeyboard() {
        let app=XCUIApplication();app.launchArguments=["--simulator-qa"];app.launch()
        for (title,id) in [("Crash Acts28:15","place:forum-of-appius_22"),("Crash Acts28:15","place:forum-of-appius_22"),("Crash Acts27:2","place:adramyttium_109")] {
            CurrentUI.openShare(app,title:title)
            app.buttons["地図"].tap()
            let map=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@ OR identifier BEGINSWITH %@","entity-map-","entity-candidate-map-")).firstMatch
            CurrentUI.reveal(map,in:app);XCTAssertTrue(map.exists)
            let candidate=map.identifier.hasPrefix("entity-candidate-map-");map.tap()
            let provenance=app.staticTexts[candidate ? "従来資料の候補位置" : "位置情報の出典と権利"];CurrentUI.reveal(provenance,in:app);XCTAssertTrue(provenance.exists)
            CurrentUI.capture(app,"repeated-share-map-"+id,test:self)
            app.navigationBars.buttons.firstMatch.tap()
            let field=CurrentUI.input(app);XCTAssertTrue(field.waitForExistence(timeout:5))
            let dismissKeyboard=app.buttons["キーボードを閉じる"];if dismissKeyboard.exists { dismissKeyboard.tap() }
            field.tap();field.typeText(" map question")
            CurrentUI.keyboardSend(app)
            XCTAssertTrue((field.value as? String ?? "").contains("map question"))
            app.buttons["キーボードを閉じる"].tap()
            app.buttons["解説"].tap();app.buttons["地図"].tap()
            XCTAssertTrue(app.buttons["閉じる"].exists);app.buttons["閉じる"].tap()
            let dismiss=app.otherElements["PopoverDismissRegion"];if dismiss.waitForExistence(timeout:2){dismiss.tap()}
        }
    }
}
