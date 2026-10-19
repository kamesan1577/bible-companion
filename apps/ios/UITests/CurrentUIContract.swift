import XCTest

/// Shared interaction mechanics, never an alternative success condition.
@MainActor enum CurrentUI {
    static func input(_ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any).matching(identifier: "external-question-input").firstMatch }
    static func reveal(_ element: XCUIElement, in app: XCUIApplication, up: Bool = true) {
        for _ in 0..<18 {
            let ceiling = input(app).exists ? input(app).frame.minY - 12 : app.frame.maxY - 45
            if element.exists && element.isHittable && element.frame.minY > 70 && element.frame.maxY < ceiling { return }
            if up { app.swipeUp() } else { app.swipeDown() }
        }
    }
    static func menu(_ title: String, in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons[title]
        // The QA menu is a lazy List; existence alone does not bring rows on screen.
        if button.exists && button.isHittable { return button }
        reveal(button, in: app)
        if !button.exists || !button.isHittable { reveal(button, in: app, up: false) }
        XCTAssertTrue(button.exists, "QA menu item missing: \(title)")
        XCTAssertTrue(button.isHittable, "QA menu item not visible: \(title)")
        return button
    }
    static func openShare(_ app: XCUIApplication, title: String = "質問する共有拡張を開く") {
        menu(title, in: app).tap()
        let choices = app.cells.matching(identifier: "聖書コンパニオン")
        XCTAssertTrue(choices.firstMatch.waitForExistence(timeout: 10))
        choices.element(boundBy: choices.count - 1).tap()
        XCTAssertTrue(input(app).waitForExistence(timeout: 20))
    }
    static func replaceDraft(_ value: String, in app: XCUIApplication) {
        let field=input(app); XCTAssertTrue(field.waitForExistence(timeout:15)); field.tap()
        // Select all through UIKit's standard hardware-keyboard command; deleting
        // a character count from a tapped caret can leave an unseen suffix.
        field.typeKey("a", modifierFlags: .command)
        field.typeText(XCUIKeyboardKey.delete.rawValue)
        let cleared=field.value as? String ?? ""
        XCTAssertTrue(["", "この箇所について質問", "箇所を開くと質問できます"].contains(cleared))
        if !value.isEmpty { field.typeText(value) }
    }
    static func provider(_ name: String, in app: XCUIApplication) {
        app.buttons["external-provider-settings"].tap()
        app.buttons["external-provider-picker"].tap(); app.buttons[name].tap(); app.buttons["完了"].tap()
        XCTAssertTrue(app.buttons["external-question-send"].label.contains(name))
    }
    static func keyboardSend(_ app: XCUIApplication) {
        let send = app.buttons["external-question-send"]
        XCTAssertTrue(send.isEnabled); XCTAssertTrue(send.isHittable)
        XCTAssertGreaterThanOrEqual(send.frame.height, 44)
        XCTAssertLessThanOrEqual(send.frame.maxY, app.keyboards.firstMatch.frame.minY + 2)
    }
    static func capture(_ app: XCUIApplication, _ name: String, test: XCTestCase) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; test.add(shot)
    }
}
