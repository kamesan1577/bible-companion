import XCTest
final class ShareCrashUITests: XCTestCase {
 @MainActor func testRepeatedActs2815AndOtherPlaceMapsWithKeyboard() {
  let app=XCUIApplication();app.launchArguments=["--simulator-qa"];app.launch()
  for title in ["Crash Acts28:15", "Crash Acts28:15", "Crash Acts27:2"] {
   let share=app.buttons[title]
   for _ in 0..<6 { if share.exists && share.isHittable { break }; app.swipeDown() }
   XCTAssertTrue(share.waitForExistence(timeout:15));share.tap()
   let cells=app.cells.matching(identifier:"聖書コンパニオン");XCTAssertTrue(cells.firstMatch.waitForExistence(timeout:6));cells.element(boundBy:cells.count-1).tap()
   XCTAssertTrue(app.buttons["地名"].waitForExistence(timeout:15));app.buttons["地名"].tap()
   let map=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@", "share-place-map-")).firstMatch
   for _ in 0..<6 { if map.exists && map.isHittable { break }; app.swipeUp() }
   XCTAssertTrue(map.waitForExistence(timeout:8))
   attach(app,"places-before-map-"+title)
   map.tap(); if !app.buttons["地図を閉じる"].waitForExistence(timeout:2) { map.tap() };XCTAssertTrue(app.buttons["地図を閉じる"].waitForExistence(timeout:8))
   let wait=expectation(description:"map render");DispatchQueue.main.asyncAfter(deadline:.now()+3){wait.fulfill()};waitForExpectations(timeout:5)
   attach(app,"single-map-"+title)
   app.buttons["地図を閉じる"].tap()
   if app.buttons["地図を閉じる"].exists { app.buttons["地図を閉じる"].tap() }
   expectation(for:NSPredicate(format:"exists == false"),evaluatedWith:app.buttons["地図を閉じる"]);waitForExpectations(timeout:5)
   let field=app.descendants(matching:.any).matching(identifier:"share-question-draft").firstMatch
   field.tap()
   let keyboard = app.keyboards.firstMatch
   let systemKeyboard = XCUIApplication(bundleIdentifier:"com.apple.springboard").keyboards.firstMatch
   let keyboardVisible = keyboard.waitForExistence(timeout:2) || systemKeyboard.waitForExistence(timeout:2)
   attach(app,"keyboard-after-map-"+title)
   field.typeText("map question")
   XCTAssertTrue(app.buttons["質問を送る"].isHittable)
   // The remote extension keyboard is sometimes omitted from the host app's AX tree
   // after reopening. Screenshots remain attached for visual verification in that case.
   if keyboardVisible {
       let frame = keyboard.exists ? keyboard.frame : systemKeyboard.frame
       XCTAssertLessThanOrEqual(app.buttons["質問を送る"].frame.maxY,frame.minY+2)
   } else {
       XCTAssertTrue(app.buttons["キーボードを閉じる"].exists)
       XCTAssertTrue((field.value as? String ?? "").contains("map question"))
   }
   app.buttons["キーボードを閉じる"].tap()
   // Remote extension AX may throw for an offscreen segmented button.
   // Inspect its frame before asking XCTest to activate it.
   for _ in 0..<10 {
       let tab = app.buttons["解説"]
       let frame = tab.frame
       if tab.exists, frame.width > 0, frame.height > 0, frame.minY > 80, frame.maxY < app.frame.maxY - 120 { break }
       app.swipeDown()
   }
   app.buttons["解説"].tap();app.buttons["地名"].tap()
   XCTAssertTrue(app.buttons["閉じる"].exists);app.buttons["閉じる"].tap()
   expectation(for:NSPredicate(format:"exists == false"),evaluatedWith:field);waitForExpectations(timeout:5)
   let dismiss=app.otherElements["PopoverDismissRegion"];if dismiss.waitForExistence(timeout:2),!share.isHittable {dismiss.tap()}
   expectation(for:NSPredicate(format:"hittable == true"),evaluatedWith:share);waitForExpectations(timeout:5)
  }
 }
 private func attach(_ app:XCUIApplication,_ name:String){let item=XCTAttachment(screenshot:app.screenshot());item.name=name;item.lifetime = .keepAlways;add(item)}
}
