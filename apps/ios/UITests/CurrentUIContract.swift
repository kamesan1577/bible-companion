import XCTest

/// Shared interaction mechanics, never an alternative success condition.
@MainActor enum CurrentUI {
    static func input(_ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any).matching(identifier: "external-question-input").firstMatch }
    private static func geometry(_ app: XCUIApplication) -> (ceiling: CGFloat, maps: [CGRect]) {
        var ceiling = app.frame.maxY - 45
        var maps: [CGRect] = []
        guard let root = try? app.snapshot() else { return (ceiling, maps) }
        func visit(_ node: any XCUIElementSnapshot) {
            if node.identifier == "external-question-input", !node.frame.isEmpty { ceiling = node.frame.minY - 14 }
            if node.elementType == .map { maps.append(node.frame) }
            for child in node.children { visit(child) }
        }
        visit(root)
        return (ceiling, maps)
    }
    static func reveal(_ element: XCUIElement, in app: XCUIApplication, up: Bool = true) {
        for _ in 0..<24 {
            var down = !up
            let layout = geometry(app)
            if element.exists {
                let frame=element.frame
                if element.isHittable && frame.minY > 75 && frame.maxY < layout.ceiling { return }
                if frame.maxY < 75 { down = true }
            }
            // A single immutable AX snapshot supplies composer bounds after navigation. A bounded
            // short drag in the page margin also avoids panning an embedded map.
            var x = CGFloat(0.95)
            let bounds = app.frame
            let point = CGPoint(x: bounds.minX + bounds.width * x, y: bounds.minY + bounds.height * (down ? 0.40 : 0.70))
            if let map = layout.maps.first(where: { $0.contains(point) }), map.maxX + 4 < bounds.maxX - 8 {
                x = (map.maxX + 4 - bounds.minX) / bounds.width
            }
            let start=app.coordinate(withNormalizedOffset:CGVector(dx:x,dy:down ? 0.40 : 0.70))
            let end=app.coordinate(withNormalizedOffset:CGVector(dx:x,dy:down ? 0.70 : 0.40))
            start.press(forDuration:0.05,thenDragTo:end)
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
        let value=app.buttons["external-provider-picker"].staticTexts.firstMatch
        XCTAssertTrue(value.waitForExistence(timeout:5)); value.tap()
        XCTContext.runActivity(named:"provider-options-"+name) { activity in
            let shot=XCTAttachment(screenshot:app.screenshot());shot.lifetime = .keepAlways;activity.add(shot)
            let tree=XCTAttachment(string:app.debugDescription);tree.lifetime = .keepAlways;activity.add(tree)
        }
        app.buttons[name].tap(); app.buttons["完了"].tap()
        XCTAssertTrue(app.buttons["external-question-send"].label.contains(name))
    }
    static func keyboardSend(_ app: XCUIApplication) {
        let send = app.buttons["external-question-send"]
        let keyboard = app.keyboards.firstMatch
        guard keyboard.waitForExistence(timeout: 5) else {
            XCTContext.runActivity(named: "missing-keyboard") { activity in
                let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; activity.add(shot)
                let tree = XCTAttachment(string: app.debugDescription); tree.lifetime = .keepAlways; activity.add(tree)
            }
            XCTFail("Keyboard AX node unavailable; inspect screenshot before diagnosing visibility"); return
        }
        XCTAssertTrue(send.isEnabled); XCTAssertTrue(send.isHittable)
        XCTAssertGreaterThanOrEqual(send.frame.height, 44)
        XCTAssertLessThanOrEqual(send.frame.maxY, keyboard.frame.minY + 2)
    }
    static func capture(_ app: XCUIApplication, _ name: String, test: XCTestCase) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; test.add(shot)
    }
}
