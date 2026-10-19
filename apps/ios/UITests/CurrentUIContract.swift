import XCTest

/// Shared interaction mechanics, never an alternative success condition.
@MainActor enum CurrentUI {
    static func input(_ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any).matching(identifier: "external-question-input").firstMatch }
    @discardableResult static func selectSection(_ title: String, in app: XCUIApplication, shared: Bool? = nil) -> Bool {
        func failed(_ message: String) -> Bool {
            XCTContext.runActivity(named: "section-selection-failure") { activity in
                let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; activity.add(shot)
                let tree = XCTAttachment(string: app.debugDescription); tree.lifetime = .keepAlways; activity.add(tree)
            }
            XCTFail(message); return false
        }
        let sharedRoot = app.descendants(matching: .any).matching(identifier: "qa-reading-share").firstMatch
        let isShared = shared ?? sharedRoot.exists
        let root = isShared ? sharedRoot : app.descendants(matching: .any).matching(identifier: "qa-reading-main").firstMatch
        guard root.waitForExistence(timeout: 15) else { return failed("Expected reading surface unavailable") }
        let control = root.segmentedControls["reading-section-tabs"]
        guard control.waitForExistence(timeout: 5) else { return failed("Native reading segmented control unavailable") }
        let ready = ["解説", "地図", "人物", "絵画"].map { name in
            XCTNSPredicateExpectation(predicate: NSPredicate(format: "label MATCHES %@", ".*、([0-9]+件|件数を確認できません)"), object: control.buttons[name])
        }
        guard XCTWaiter.wait(for: ready, timeout: 15) == .completed else { return failed("Reading inventory labels have not settled") }
        let tab = control.buttons[title]
        guard tab.exists, tab.isHittable else { return failed("Native section target is not hittable: \(title)") }
        let frame = tab.frame
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let anchor = origin.screenPoint
        origin.withOffset(CGVector(dx: frame.midX - anchor.x, dy: frame.midY - anchor.y)).press(forDuration: 0.12)
        guard root.scrollViews["reading-page-" + title].waitForExistence(timeout: 5), tab.isSelected else {
            return failed("Native section selection did not reach its page: \(title)")
        }
        return true
    }
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
        let frame: CGRect
        if keyboard.waitForExistence(timeout: 1) {
            frame = keyboard.frame
        } else {
            // Remote extension keyboards can be visible without a host Keyboard AX node.
            // UIKit's DEBUG-Simulator probe observes actual notification coordinates.
            let probe = app.descendants(matching: .any).matching(identifier: "qa-keyboard-frame").firstMatch
            func observedFrame() -> CGRect? {
                guard probe.exists, let value = probe.value as? String else { return nil }
                let values = value.split(separator: ",").compactMap { Double($0) }
                guard values.count == 4, values.allSatisfy({ $0.isFinite }) else { return nil }
                let result = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
                guard result.width > 0, result.height > 0, result.intersection(app.frame).height > 0,
                      result.minY > app.frame.minY, result.minY < app.frame.maxY else { return nil }
                return result
            }
            let observed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in observedFrame() != nil }, object: probe)
            let status = XCTWaiter.wait(for: [observed], timeout: 5)
            guard status == .completed, let measured = observedFrame() else {
                XCTContext.runActivity(named: "missing-keyboard") { activity in
                    let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; activity.add(shot)
                    let tree = XCTAttachment(string: app.debugDescription); tree.lifetime = .keepAlways; activity.add(tree)
                }
                XCTFail("No visible keyboard AX node or UIKit-observed screen frame"); return
            }
            frame = measured
            XCTContext.runActivity(named: "UIKit-observed keyboard geometry") { activity in
                let value = XCTAttachment(string: "Keyboard notification frame: \(measured); send target: \(send.frame)")
                value.lifetime = .keepAlways; activity.add(value)
            }
        }
        XCTAssertTrue(send.isEnabled); XCTAssertTrue(send.isHittable)
        XCTAssertGreaterThanOrEqual(send.frame.height, 44)
        XCTAssertGreaterThan(frame.height, 0)
        XCTAssertLessThanOrEqual(send.frame.maxY, frame.minY + 2)
    }
    static func capture(_ app: XCUIApplication, _ name: String, test: XCTestCase) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; test.add(shot)
    }
}
