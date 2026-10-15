import XCTest

final class ReadingInteractionUITests: XCTestCase {
    @MainActor func testFourNewBookCommentaryRepresentativeRendering() {
        let app = XCUIApplication()
        app.launchArguments = ["--simulator-qa", "--qa-screen=proverbs-final"]; app.launch()
        XCTAssertTrue(app.staticTexts["伴侶、貧富、親しい友"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["解釈と出典を確かめる"].firstMatch.exists)
        attach(app, "proverbs-final-018")
        app.buttons["解釈と出典を確かめる"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "CCEL")).firstMatch.waitForExistence(timeout: 5))
        app.swipeUp()
        attach(app, "proverbs-final-source-018")
        app.terminate()
        app.launchArguments = ["--simulator-qa", "--qa-screen=ecclesiastes-final"]; app.launch()
        XCTAssertTrue(app.staticTexts["神のわざと人の理解の限界"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["解釈と出典を確かめる"].firstMatch.exists)
        attach(app, "ecclesiastes-final-018")
        app.buttons["解釈と出典を確かめる"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "CCEL")).firstMatch.waitForExistence(timeout: 5))
        app.swipeUp()
        attach(app, "ecclesiastes-final-source-018")
        app.terminate()
        app.launchArguments = ["--simulator-qa", "--qa-screen=song-final"]; app.launch()
        XCTAssertTrue(app.staticTexts["捜索と見張り人による傷"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["解釈と出典を確かめる"].firstMatch.exists)
        attach(app, "song-final-018")
        app.buttons["解釈と出典を確かめる"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "CCEL")).firstMatch.waitForExistence(timeout: 5))
        app.swipeUp()
        attach(app, "song-final-source-018")
        app.terminate()
        app.launchArguments = ["--simulator-qa", "--qa-screen=isaiah-final"]; app.launch()
        XCTAssertTrue(app.staticTexts["新しい天と地、喜びと長寿"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["解釈と出典を確かめる"].firstMatch.exists)
        attach(app, "isaiah-final-018")
        app.buttons["解釈と出典を確かめる"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "CCEL")).firstMatch.waitForExistence(timeout: 5))
        app.swipeUp()
        attach(app, "isaiah-final-source-018")
        app.terminate()
    }

    @MainActor func testRomansCommentaryAndExplicitDoxologyPlacement() {
        let app = XCUIApplication()
        app.launchArguments = ["--simulator-qa", "--qa-screen=romans-opening"]; app.launch()
        XCTAssertTrue(app.staticTexts["パウロの召命と福音"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["AIで編集。専門家の校閲なし。"].exists)
        attach(app, "romans-opening-017")
        app.terminate()
        app.launchArguments = ["--simulator-qa", "--qa-screen=romans-doxology"]; app.launch()
        XCTAssertTrue(app.buttons["解釈と出典を確かめる"].waitForExistence(timeout: 10))
        app.buttons["解釈と出典を確かめる"].tap()
        let note = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "14:24–26")).firstMatch
        for _ in 0..<3 { if note.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: note); waitForExpectations(timeout: 3)
        Thread.sleep(forTimeInterval: 1) // Capture after disclosure expansion completes.
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "別のAIによる本文・出典との照合")).firstMatch.exists)
        attach(app, "romans-doxology-placement-017")
    }
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
            guard candidates.firstMatch.waitForExistence(timeout: 5), candidates.count > 0 else { XCTFail("Share destination did not appear: \(app.debugDescription)"); return }
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
        XCTAssertTrue(app.staticTexts["この箇所の説明"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["コリントでの出会いと働き"].exists)
        app.buttons["解釈と出典を確かめる"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "別のAIによる本文・出典との照合")).firstMatch.exists)
        attach(app, "static-commentary-japanese")
    }
    @MainActor func testOriginalRequiresExplicitSpoilerConsent() {
        let app = XCUIApplication(); app.launchArguments = ["--simulator-qa"]; app.launch()
        XCTAssertTrue(app.buttons["使徒23:1の静的解説"].waitForExistence(timeout: 10)); app.buttons["使徒23:1の静的解説"].tap()
        let original = app.buttons["英語の注解を読む"]
        if !original.isHittable { app.swipeUp() }
        XCTAssertTrue(original.waitForExistence(timeout: 5)); original.tap()
        let consent = app.buttons["先の内容を含むことを確認して開く"]
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
        let original = app.buttons["英語の注解を読む"]
        XCTAssertTrue(original.waitForExistence(timeout: 5)); original.tap()
        let consent = app.buttons["先の内容を含むことを確認して開く"]
        XCTAssertTrue(consent.waitForExistence(timeout: 5)); consent.tap()
        let chapterNote = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "各節を個別に説明した文章ではありません")).firstMatch
        XCTAssertTrue(chapterNote.waitForExistence(timeout: 5))
        attach(app, "samuel22-chapter-context")
        let parallel = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "著者が参照した")).firstMatch
        for _ in 0..<30 { if parallel.exists && parallel.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(parallel.exists); XCTAssertTrue(parallel.isHittable)
        attach(app, "samuel22-parallel-navigation")
        parallel.tap()
        XCTAssertTrue(consent.waitForExistence(timeout: 5))
        attach(app, "psalm18-separate-consent")
    }
    @MainActor func testReadingPreparationReturnsWithoutRepeatingConsentOrFalseSuccess() {
        let app = XCUIApplication(); app.launchArguments = ["--simulator-qa", "--qa-share-enabled"]; app.launch()
        XCTAssertTrue(app.buttons["読書画面"].waitForExistence(timeout: 10)); app.buttons["読書画面"].tap()
        let ai = app.buttons["AIで解説・質問"]
        XCTAssertTrue(ai.waitForExistence(timeout: 5)); ai.tap()
        let prepare = app.buttons["YouVersionから解説を読む準備"]
        XCTAssertTrue(prepare.waitForExistence(timeout: 5)); prepare.tap()
        let save = app.buttons["共有から解説を読めるようにする"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["同意して解説を使う"].exists)
        save.tap()
        let storageFailure = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "同意を繰り返す必要はありません")).firstMatch
        XCTAssertTrue(storageFailure.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["設定を保存しました"].exists)
        XCTAssertFalse(app.buttons["同意して解説を使う"].exists)
        attach(app, "preparation-storage-failure-no-consent-loop")
        app.buttons["閉じる"].tap()
        XCTAssertTrue(app.staticTexts["「良心に従ってきた」という発言"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "shared-scripture-header").firstMatch.exists)
        XCTAssertTrue(app.buttons["AIで解説・質問"].exists)
        attach(app, "preparation-return-original-reading")
    }
    @MainActor func testActualShareRecoveryPreservesVerseAndShowsConcreteSteps() {
        let app = XCUIApplication(); app.launchArguments = ["--simulator-qa"]; app.launch()
        let share = app.buttons["実際の共有拡張を開く"]
        XCTAssertTrue(share.waitForExistence(timeout: 10)); share.tap()
        let candidates = app.cells.matching(identifier: "聖書コンパニオン")
        guard candidates.firstMatch.waitForExistence(timeout: 5), candidates.count > 0 else { XCTFail("Share destination did not appear: \(app.debugDescription)"); return }
        candidates.element(boundBy: candidates.count - 1).tap()
        XCTAssertTrue(app.staticTexts["この画面で解説を開けません"].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.staticTexts["使徒の働き 23:1"].exists)
        XCTAssertFalse(app.staticTexts["初回の設定が必要です。"].exists)
        let steps = app.buttons["準備の手順を見る"]
        XCTAssertTrue(steps.exists); steps.tap()
        let returnStep = app.staticTexts["YouVersionで同じ箇所を選び、もう一度共有する"]
        for _ in 0..<5 { if returnStep.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(returnStep.exists)
        attach(app, "actual-share-storage-recovery-keeps-verse")
        app.navigationBars.buttons["閉じる"].tap()
        XCTAssertTrue(share.waitForExistence(timeout: 5))
    }
    @MainActor func testExistingExplanationPrecedesSingleAIActionAndExplanationStillWorks() {
        let app = XCUIApplication(); app.launchArguments = ["--simulator-qa"]; app.launch()
        XCTAssertTrue(app.buttons["読書画面"].waitForExistence(timeout: 10)); app.buttons["読書画面"].tap()
        let title = app.staticTexts["「良心に従ってきた」という発言"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let ai = app.buttons["AIで解説・質問"]
        XCTAssertTrue(ai.exists); XCTAssertEqual(app.buttons.matching(identifier: "AIで解説・質問").count, 1)
        XCTAssertLessThan(title.frame.minY, ai.frame.minY)
        XCTAssertFalse(app.buttons["AIにこの箇所を説明してもらう"].exists)
        attach(app, "reading-existing-explanation-first-single-ai")
        ai.tap(); app.buttons["AIでこの箇所の解説を読む"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "固定標準解説")).firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["続けて質問する"].exists)
        attach(app, "single-ai-action-explanation-result")
    }
    @MainActor func testActualShareReadsProfilesAndMapWithoutGeneratedAnswer() {
        let app = XCUIApplication(); app.launchArguments = ["--simulator-qa"]; app.launch()
        let share = app.buttons["使徒18章を共有する"]
        XCTAssertTrue(share.waitForExistence(timeout: 10)); share.tap()
        let destinations = app.cells.matching(identifier: "聖書コンパニオン")
        guard destinations.firstMatch.waitForExistence(timeout: 5), destinations.count > 0 else { XCTFail("Share destination did not appear: \(app.debugDescription)"); return }
        destinations.element(boundBy: destinations.count - 1).tap()
        XCTAssertTrue(app.staticTexts["使徒の働き 18:24–28"].waitForExistence(timeout: 8), app.debugDescription)
        app.buttons["人物"].tap()
        let detail = app.descendants(matching: .any).matching(identifier: "entity-inline-detail-person:apollos_276").firstMatch
        scrollTo(detail, app: app); XCTAssertTrue(detail.exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "正確")).firstMatch.exists)
        attach(app, "actual-share-apollos-stored-detail")
        let places = app.buttons["地名"]; scrollToTop(places, app: app); places.tap()
        let map = app.descendants(matching: .any).matching(identifier: "entity-inline-map-place:alexandria_46").firstMatch
        scrollTo(map, app: app); XCTAssertTrue(map.exists)
        XCTAssertTrue(app.staticTexts["現在の場所"].firstMatch.exists)
        attach(app, "actual-share-alexandria-map")
    }

    @MainActor func testActsEarlyAndLateProfilesUseReadingTabs() {
        let app = XCUIApplication()
        for (screen, person, laterName) in [("entity-acts-early", "サウロ", "パウロ"), ("entity-acts-late", "ポプリウス", "")] {
            app.launchArguments = ["--simulator-qa", "--qa-screen=" + screen]; app.launch()
            XCTAssertTrue(app.buttons["人物"].waitForExistence(timeout: 15)); app.buttons["人物"].tap()
            let name = app.staticTexts[person].firstMatch
            scrollTo(name, app: app); XCTAssertTrue(name.exists)
            if !laterName.isEmpty { XCTAssertFalse(app.staticTexts[laterName].exists) }
            attach(app, screen + "-people")
            app.buttons["地図"].tap()
            attach(app, screen + "-places")
            app.terminate()
        }
    }
    @MainActor func testExistingCandidateMapRemainsAccessibleFromNewDescription() {
        let app = XCUIApplication()
        app.launchArguments = ["--simulator-qa", "--qa-screen=entity-existing-map"]; app.launch()
        XCTAssertTrue(app.buttons["地図"].waitForExistence(timeout: 15)); app.buttons["地図"].tap()
        let link = app.buttons["entity-candidate-map-place:jerusalem_636"]
        scrollTo(link, app: app); XCTAssertTrue(link.exists); link.tap()
        XCTAssertTrue(app.staticTexts["従来資料の候補位置"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "entity-candidate-map-content-place:jerusalem_636").firstMatch.exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "独立に位置を確認した地点ではありません")).firstMatch.exists)
        attach(app, "restored-jerusalem-candidate-map-with-provenance")
    }
    @MainActor func testEntityCardAndMapPreservation() {
        let app = XCUIApplication()
        app.launchArguments = ["--simulator-qa", "--qa-screen=entity-ui-baseline"]; app.launch()
        XCTAssertTrue(app.buttons["人物"].waitForExistence(timeout: 15)); app.buttons["人物"].tap()
        let originalTitle = app.staticTexts["アポロ：エペソに来る"]
        scrollTo(originalTitle, app: app)
        XCTAssertTrue(originalTitle.isHittable)
        attach(app, "baseline-018-person-card")
        app.buttons["地図"].tap()
        let mapLink = app.buttons["地図で概略位置を確認"].firstMatch
        scrollTo(mapLink, app: app)
        attach(app, "baseline-018-place-card")
        mapLink.tap()
        XCTAssertTrue(app.staticTexts["コリント"].firstMatch.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 3)
        attach(app, "baseline-018-mapkit-map")
        app.terminate()
        app.launchArguments = ["--simulator-qa", "--qa-screen=entity-pilot-reading"]; app.launch()
        XCTAssertTrue(app.buttons["人物"].waitForExistence(timeout: 15)); app.buttons["人物"].tap()
        XCTAssertTrue(originalTitle.waitForExistence(timeout: 5))
        attach(app, "candidate-person-card-preserved")
        let detail = app.buttons["entity-detail-person-apollos-act18-introduction"]
        scrollTo(detail, app: app); detail.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "雄弁")).firstMatch.waitForExistence(timeout: 5))
        attach(app, "candidate-apollos-description-from-card")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["地図"].tap()
        XCTAssertTrue(mapLink.waitForExistence(timeout: 5))
        attach(app, "candidate-place-card-preserved")
        mapLink.tap(); Thread.sleep(forTimeInterval: 3)
        attach(app, "candidate-mapkit-map-preserved")
        let mapDetail = app.buttons["map-entity-detail-place-corinth"]
        scrollTo(mapDetail, app: app); mapDetail.tap()
        XCTAssertTrue(app.staticTexts["現在の場所"].waitForExistence(timeout: 5))
        attach(app, "candidate-corinth-description-from-map")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let alexDetail = app.buttons["entity-detail-place:alexandria_46"]
        scrollTo(alexDetail, app: app); alexDetail.tap()
        XCTAssertTrue(app.staticTexts["現在の場所"].waitForExistence(timeout: 5))
        attach(app, "candidate-alexandria-description-from-card")
    }
    @MainActor func testWikipediaReadingLinksKeepSourcesAndMaps() {
        let app = XCUIApplication(); app.launchArguments = ["--simulator-qa", "--qa-screen=entity-pilot-reading"]; app.launch()
        XCTAssertTrue(app.buttons["人物"].waitForExistence(timeout: 15)); app.buttons["人物"].tap()
        let detail = app.buttons["entity-detail-person-apollos-act18-introduction"]
        scrollTo(detail, app: app); detail.tap()
        let wiki = app.descendants(matching: .any).matching(identifier: "wikipedia-person:apollos_276").firstMatch
        XCTAssertTrue(wiki.waitForExistence(timeout: 5)); XCTAssertTrue(wiki.label.contains("英語"))
        XCTAssertTrue(app.buttons["この説明の出典"].exists)
        XCTAssertTrue(app.staticTexts["外部記事には、この箇所より先の内容が含まれることがあります。"].exists)
        attach(app, "wikipedia-apollos-reading-link")
        app.buttons["この説明の出典"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "World English Bible")).firstMatch.waitForExistence(timeout: 5))
        attach(app, "wikipedia-primary-sources-preserved")
        app.navigationBars.buttons.element(boundBy: 0).tap(); app.buttons["地図"].tap()
        let mapLink = app.buttons["地図で概略位置を確認"].firstMatch
        XCTAssertTrue(mapLink.waitForExistence(timeout: 5)); mapLink.tap()
        let mapDetail = app.buttons["map-entity-detail-place-corinth"]
        scrollTo(mapDetail, app: app); mapDetail.tap()
        let corinthWiki = app.descendants(matching: .any).matching(identifier: "wikipedia-place:corinth_306").firstMatch
        scrollTo(corinthWiki, app: app)
        XCTAssertTrue(corinthWiki.exists)
        XCTAssertTrue(app.staticTexts["古代コリントス"].exists)
        attach(app, "wikipedia-ancient-corinth-from-map")
        app.navigationBars.buttons.element(boundBy: 0).tap(); app.navigationBars.buttons.element(boundBy: 0).tap()
        let alexDetail = app.buttons["entity-detail-place:alexandria_46"]
        scrollTo(alexDetail, app: app); alexDetail.tap()
        let alexWiki = app.descendants(matching: .any).matching(identifier: "wikipedia-place:alexandria_46").firstMatch
        scrollTo(alexWiki, app: app); XCTAssertTrue(alexWiki.exists)
        attach(app, "wikipedia-alexandria-reading-link")
    }
    @MainActor private func tapScreenFrame(_ element: XCUIElement, app: XCUIApplication) {
        let point = element.frame
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let anchor = origin.screenPoint
        let target = origin.withOffset(CGVector(dx: point.midX - anchor.x, dy: point.midY - anchor.y))
        print("Remote element frame=\(point), app=\(app.frame), origin=\(anchor), tap=\(target.screenPoint)")
        target.tap()
    }
    @MainActor private func scrollToTop(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<12 {
            if element.exists && element.isHittable && element.frame.minY > 140 && element.frame.maxY < app.frame.height { return }
            app.swipeDown()
        }
    }
    @MainActor private func scrollTo(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<14 {
            if element.exists && element.isHittable && element.frame.minY < app.frame.height * 0.78 { return }
            app.swipeUp()
        }
    }
    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 1) // Let native navigation and disclosure animations settle before comparison images.
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
