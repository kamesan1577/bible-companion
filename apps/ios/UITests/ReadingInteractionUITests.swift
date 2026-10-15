import XCTest

final class ReadingInteractionUITests: XCTestCase {
    @MainActor func testQuestionKeyboardSpoilersAndOrdinaryDebugVisibility() {
        let app = XCUIApplication(); app.launchArguments = ["--simulator-qa"]; app.launch()
        XCTAssertTrue(app.buttons["質問画面"].waitForExistence(timeout: 10)); app.buttons["質問画面"].tap()
        let field = app.descendants(matching: .any).matching(identifier: "question-draft").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("background")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let send = app.buttons["質問を送る"]
        XCTAssertTrue(send.exists); XCTAssertTrue(send.waitForExistence(timeout: 5)); XCTAssertTrue(send.isEnabled)
        XCTAssertLessThanOrEqual(send.frame.maxY, app.keyboards.firstMatch.frame.minY + 2)
        XCTAssertTrue(app.buttons["質問を送る"].exists)
        XCTAssertFalse(app.staticTexts["開発者用デバッグ"].exists)
        attach(app, "keyboard-send-visible")
        app.swipeDown()
        let toggle = app.switches["ネタバレ防止"]
        XCTAssertTrue(toggle.exists); toggle.tap()
        XCTAssertTrue(app.buttons["オフにする"].waitForExistence(timeout: 3)); app.otherElements["PopoverDismissRegion"].tap()
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.tap(); XCTAssertTrue(app.buttons["オフにする"].waitForExistence(timeout: 3)); app.buttons["オフにする"].tap(); expectation(for: NSPredicate(format: "value == %@", "0"), evaluatedWith: toggle); waitForExpectations(timeout: 3)
        toggle.tap(); XCTAssertEqual(toggle.value as? String, "1")
        attach(app, "spoiler-prevention-restored")
    }
    @MainActor func testBundledPeopleAndRepeatedShareDismissal() {
        let app = XCUIApplication(); app.launchArguments = ["--simulator-qa"]; app.launch()
        XCTAssertTrue(app.buttons["使徒23:1の人物"].waitForExistence(timeout: 10)); app.buttons["使徒23:1の人物"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "パウロ")).firstMatch.waitForExistence(timeout: 5))
        attach(app, "bundled-people")
        app.navigationBars.buttons.firstMatch.tap()
        for _ in 0..<3 {
            let share = app.buttons["実際の共有拡張を開く"]
            XCTAssertTrue(share.waitForExistence(timeout: 3)); share.tap()
            XCTAssertTrue(app.otherElements["PopoverDismissRegion"].waitForExistence(timeout: 3))
            app.otherElements["PopoverDismissRegion"].tap()
            XCTAssertTrue(share.waitForExistence(timeout: 3))
        }
        attach(app, "repeated-share-return")
    }
    @MainActor func testShareExtensionLocalMetadataAndRepeatedReturn() {
        let app = XCUIApplication(); app.launchArguments = ["--simulator-qa"]; app.launch()
        for _ in 0..<3 {
            let share = app.buttons["実際の共有拡張を開く"]
            XCTAssertTrue(share.waitForExistence(timeout: 10)); share.tap()
            let candidates = app.cells.matching(identifier: "聖書コンパニオン")
            let companion = candidates.element(boundBy: candidates.count - 1)
            XCTAssertTrue(companion.waitForExistence(timeout: 5)); companion.tap()
            XCTAssertTrue(app.staticTexts["使徒の働き 23:1"].waitForExistence(timeout: 5))
            let people = app.buttons["人物"]
            XCTAssertTrue(people.exists); people.tap()
            XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "パウロ")).firstMatch.waitForExistence(timeout: 5))
            attach(app, "share-extension-local-people")
            XCTAssertTrue(app.buttons["閉じる"].exists); app.buttons["閉じる"].tap()
            XCTAssertTrue(share.waitForExistence(timeout: 5))
        }
    }
    @MainActor func testKeyboardSendAndFollowupReachOnlyLocalFixture() {
        let app = XCUIApplication(); app.launchArguments = ["--simulator-qa"]; app.launch()
        XCTAssertTrue(app.buttons["質問画面"].waitForExistence(timeout: 10)); app.buttons["質問画面"].tap()
        let field = app.descendants(matching: .any).matching(identifier: "question-draft").firstMatch; XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("background")
        let send = app.buttons["質問を送る"]; expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: send); waitForExpectations(timeout: 5); send.tap()
        XCTAssertTrue(app.staticTexts["固定データ: background"].waitForExistence(timeout: 5))
        field.tap(); field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10) + "followup")
        XCTAssertTrue(send.isEnabled); send.tap()
        XCTAssertTrue(app.staticTexts["固定データ: followup"].waitForExistence(timeout: 5))
        attach(app, "keyboard-send-and-followup-complete")
    }
    @MainActor func testReadingPinnedTextAndHorizontalPages() {
        let app = XCUIApplication(); app.launchArguments = ["--simulator-qa"]; app.launch()
        XCTAssertTrue(app.buttons["読書画面"].waitForExistence(timeout: 10)); app.buttons["読書画面"].tap()
        let header = app.descendants(matching: .any).matching(identifier: "shared-scripture-header").firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "JCB")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["読んだ箇所を、もう少し深く。"].exists)
        XCTAssertTrue(app.staticTexts["「良心に従ってきた」という発言"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["固定標準解説1"].exists)
        let initialY = header.frame.minY
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.55))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.55))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(app.scrollViews["reading-page-地図"].waitForExistence(timeout: 3))
        app.buttons["人物"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "パウロ")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(header.frame.minY, initialY, accuracy: 2)
        app.buttons["本文を展開"].tap(); XCTAssertTrue(app.buttons["折り畳む"].exists)
        attach(app, "reading-pinned-original-and-people")
        app.buttons["解説"].tap(); app.buttons["地図"].tap(); app.buttons["解説"].tap()
        XCTAssertTrue(header.exists)
        XCTAssertTrue(app.staticTexts["「良心に従ってきた」という発言"].exists)
        XCTAssertFalse(app.staticTexts["固定標準解説2"].exists)
        attach(app, "reading-repeat-tabs")
    }
    @MainActor func testStaticChapterJapaneseAndSourceDisclosure() {
        let app = XCUIApplication(); app.launchArguments = ["--simulator-qa"]; app.launch()
        XCTAssertTrue(app.buttons["使徒18–23章の静的解説"].waitForExistence(timeout: 10))
        app.buttons["使徒18–23章の静的解説"].tap()
        XCTAssertTrue(app.staticTexts["出典に基づく日本語編集"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["コリントでの出会いと働き"].exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "別のAIが原典とWEBに照合")).firstMatch.exists)
        attach(app, "static-commentary-japanese")
    }
    @MainActor func testOriginalRequiresExplicitSpoilerConsent() {
        let app = XCUIApplication(); app.launchArguments = ["--simulator-qa"]; app.launch()
        XCTAssertTrue(app.buttons["使徒23:1の静的解説"].waitForExistence(timeout: 10)); app.buttons["使徒23:1の静的解説"].tap()
        let original = app.buttons["英語の注解原文・出典を読む"]
        if !original.isHittable { app.swipeUp() }
        XCTAssertTrue(original.waitForExistence(timeout: 5)); original.tap()
        let consent = app.buttons["先の内容を含む英語原文を開く"]
        XCTAssertTrue(consent.waitForExistence(timeout: 5))
        attach(app, "original-spoiler-consent")
        consent.tap()
        XCTAssertTrue(app.staticTexts["Matthew Henry’s Complete Commentary"].waitForExistence(timeout: 5))
        attach(app, "commentary-original-source")
    }
    @MainActor func testChapterContextAndParallelNavigationRequireConsent() {
        let app = XCUIApplication(); app.launchArguments = ["--simulator-qa"]; app.launch()
        let fixture = app.buttons["サムエル記下22:1の資料"]
        XCTAssertTrue(fixture.waitForExistence(timeout: 10)); fixture.tap()
        let original = app.buttons["英語の注解原文・出典を読む"]
        XCTAssertTrue(original.waitForExistence(timeout: 5)); original.tap()
        let consent = app.buttons["先の内容を含む英語原文を開く"]
        XCTAssertTrue(consent.waitForExistence(timeout: 5)); consent.tap()
        let chapterNote = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "各節の独立した詳細注解を示すものではありません")).firstMatch
        XCTAssertTrue(chapterNote.waitForExistence(timeout: 5))
        attach(app, "samuel22-chapter-context")
        let parallel = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "原典が参照する")).firstMatch
        for _ in 0..<30 { if parallel.exists && parallel.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(parallel.exists); XCTAssertTrue(parallel.isHittable)
        attach(app, "samuel22-parallel-navigation")
        parallel.tap()
        XCTAssertTrue(consent.waitForExistence(timeout: 5))
        attach(app, "psalm18-separate-consent")
    }
    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
