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
        CurrentUI.menu("使徒23:1の人物",in:app).tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "パウロ")).firstMatch.waitForExistence(timeout: 5))
        attach(app, "bundled-people")
        app.navigationBars.buttons.firstMatch.tap()
        for _ in 0..<3 {
            let share = CurrentUI.menu("実際の共有拡張を開く", in: app)
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
            let share = CurrentUI.menu("実際の共有拡張を開く", in: app)
            XCTAssertTrue(share.waitForExistence(timeout: 10)); share.tap()
            let candidates = app.cells.matching(identifier: "聖書コンパニオン")
            guard candidates.firstMatch.waitForExistence(timeout: 5), candidates.count > 0 else { XCTFail("Share destination did not appear: \(app.debugDescription)"); return }
            let companion = candidates.element(boundBy: candidates.count - 1)
            XCTAssertTrue(companion.waitForExistence(timeout: 5)); companion.tap()
            XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@","使徒の働き 23:1")).firstMatch.waitForExistence(timeout:5))
            let people = app.buttons["人物"]
            XCTAssertTrue(people.exists); people.tap()
            XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "パウロ")).firstMatch.waitForExistence(timeout: 5))
            attach(app, "share-extension-local-people")
            XCTAssertTrue(app.buttons["閉じる"].exists); app.buttons["閉じる"].tap()
            // The app's button can exist underneath the returning system share sheet.
            // Wait for a usable host, rather than tapping through that presentation.
            let dismissShare = app.otherElements["PopoverDismissRegion"]
            if dismissShare.waitForExistence(timeout: 2), !share.isHittable { dismissShare.tap() }
            expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: share); waitForExpectations(timeout: 5)
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
    @MainActor func testReadingProviderSettingsReturnWithoutObsoleteConsentOrFalseSuccess() {
        let app = XCUIApplication(); app.launchArguments = ["--simulator-qa"]; app.launch()
        CurrentUI.menu("読書画面", in: app).tap()
        XCTAssertTrue(app.staticTexts["「良心に従ってきた」という発言"].waitForExistence(timeout: 10))
        let field = CurrentUI.input(app); field.tap(); field.typeText(" preparation-not-required")
        let draft = field.value as? String
        app.buttons["external-provider-settings"].tap()
        XCTAssertTrue(app.buttons["external-provider-picker"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["同意して解説を使う"].exists)
        XCTAssertFalse(app.staticTexts["質問する設定を保存しました"].exists)
        app.buttons["完了"].tap(); XCTAssertEqual(field.value as? String, draft)
        XCTAssertTrue(app.staticTexts["「良心に従ってきた」という発言"].exists)
        attach(app,"provider-return-original-reading-no-false-readiness")
    }
    @MainActor func testActualShareUnconfiguredBackendRetainsOfflineVerseAndComposer() {
        let app=XCUIApplication();app.launchArguments=["--simulator-qa"];app.launch()
        CurrentUI.openShare(app,title:"実際の共有拡張を開く")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@","使徒の働き 23:1")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["「良心に従ってきた」という発言"].waitForExistence(timeout:10))
        XCTAssertFalse(app.staticTexts["この画面で解説を開けません"].exists)
        XCTAssertFalse(app.buttons["準備の手順を見る"].exists)
        let field=CurrentUI.input(app);field.tap();field.typeText(" offline-source-retained")
        CurrentUI.keyboardSend(app);attach(app,"actual-share-offline-reader-keeps-passage")
        app.buttons["閉じる"].tap()
    }
    @MainActor func testExistingExplanationAndSourcePrecedeSingleExternalAction() {
        let app=XCUIApplication(); app.launchArguments=["--simulator-qa"];app.launch()
        CurrentUI.menu("読書画面",in:app).tap()
        let title=app.staticTexts["「良心に従ってきた」という発言"]
        XCTAssertTrue(title.waitForExistence(timeout:10))
        let send=app.buttons["external-question-send"]
        XCTAssertTrue(send.exists);XCTAssertEqual(app.buttons.matching(identifier:"external-question-send").count,1)
        XCTAssertLessThan(title.frame.minY,send.frame.minY)
        XCTAssertFalse(app.buttons["AIで解説・質問"].exists)
        let source=app.buttons["解釈と出典を確かめる"].firstMatch
        CurrentUI.reveal(source,in:app);source.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@","参考にした注解：Matthew Henry")).firstMatch.waitForExistence(timeout:5))
        attach(app,"existing-explanation-and-source-before-external-handoff")
    }
    @MainActor func testActualShareReadsProfilesAndMapWithoutGeneratedAnswer() {
        let app=XCUIApplication();app.launchArguments=["--simulator-qa"];app.launch()
        CurrentUI.openShare(app,title:"使徒18章を共有する")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@","使徒の働き 18:24–28")).firstMatch.exists)
        let people=app.buttons["人物"]
        expectation(for:NSPredicate(format:"label CONTAINS %@","件"),evaluatedWith:people);waitForExpectations(timeout:15)
        people.tap()
        let detail=app.buttons["entity-detail-person:apollos_276"]
        CurrentUI.reveal(detail,in:app);XCTAssertTrue(detail.isHittable);detail.tap()
        guard app.navigationBars["アポロ"].waitForExistence(timeout:8) else { attach(app,"share-profile-navigation-failed");XCTFail("Apollos profile destination not reached");return }
        let description=app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@","正確")).firstMatch
        CurrentUI.reveal(description,in:app);XCTAssertTrue(description.exists)
        attach(app,"actual-share-apollos-stored-profile")
        app.navigationBars["アポロ"].buttons.firstMatch.tap()
        let maps=app.buttons["地図"]
        expectation(for:NSPredicate(format:"label CONTAINS %@","件"),evaluatedWith:maps);waitForExpectations(timeout:15)
        maps.tap()
        let map=app.buttons["entity-map-place:alexandria_46"]
        CurrentUI.reveal(map,in:app);XCTAssertTrue(map.isHittable);map.tap()
        guard app.navigationBars["地図"].waitForExistence(timeout:8) else { attach(app,"share-map-navigation-failed");XCTFail("Alexandria map destination not reached");return }
        assertReviewedMap("アレクサンドリア", app:app)
        attach(app,"actual-share-alexandria-map-with-provenance")
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
        XCTAssertTrue(app.staticTexts["アポロ"].firstMatch.waitForExistence(timeout: 5))
        attach(app, "candidate-person-card-preserved")
        let detail = app.buttons["entity-detail-person:apollos_276"]
        scrollTo(detail, app: app); detail.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "雄弁")).firstMatch.waitForExistence(timeout: 5))
        attach(app, "candidate-apollos-description-from-card")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["地図"].tap()
        XCTAssertTrue(app.buttons["entity-detail-place:corinth_306"].exists)
        let alexDetail = app.buttons["entity-detail-place:alexandria_46"]
        scrollTo(alexDetail, app: app); alexDetail.tap()
        XCTAssertTrue(app.staticTexts["現在の場所"].waitForExistence(timeout:5))
        attach(app,"candidate-alexandria-description-in-selected-range")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let corinth=app.buttons["entity-map-place:corinth_306"]
        scrollTo(corinth,app:app);XCTAssertTrue(corinth.exists);corinth.tap()
        assertReviewedMap("コリント", app:app)
        attach(app,"current-corinth-map-in-selected-range")
    }
    @MainActor func testWikipediaReadingLinksKeepSourcesAndMaps() {
        let app = XCUIApplication(); app.launchArguments = ["--simulator-qa", "--qa-screen=entity-pilot-reading"]; app.launch()
        XCTAssertTrue(app.buttons["人物"].waitForExistence(timeout: 15)); app.buttons["人物"].tap()
        let detail = app.buttons["entity-detail-person:apollos_276"]
        scrollTo(detail, app: app); detail.tap()
        let wiki = app.descendants(matching: .any).matching(identifier: "wikipedia-person:apollos_276").firstMatch
        scrollTo(wiki,app:app); XCTAssertTrue(wiki.exists); XCTAssertTrue(wiki.label.contains("英語"))
        scrollTo(app.buttons["この説明の出典"],app:app); XCTAssertTrue(app.buttons["この説明の出典"].exists)
        XCTAssertTrue(app.staticTexts["外部記事には、この箇所より先の内容が含まれることがあります。"].exists)
        attach(app, "wikipedia-apollos-reading-link")
        app.buttons["この説明の出典"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "World English Bible")).firstMatch.waitForExistence(timeout: 5))
        attach(app, "wikipedia-primary-sources-preserved")
        app.navigationBars.buttons.element(boundBy: 0).tap(); app.buttons["地図"].tap()
        XCTAssertTrue(app.buttons["entity-detail-place:corinth_306"].exists)
        let alex=app.buttons["entity-detail-place:alexandria_46"]
        scrollTo(alex,app:app);alex.tap()
        let alexWiki=app.descendants(matching:.any).matching(identifier:"wikipedia-place:alexandria_46").firstMatch
        scrollTo(alexWiki,app:app);XCTAssertTrue(alexWiki.exists)
        attach(app,"wikipedia-alexandria-in-selected-range")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let corinth=app.buttons["entity-map-place:corinth_306"]
        scrollTo(corinth,app:app);corinth.tap()
        assertReviewedMap("コリント",app:app)
        let about=app.buttons["この場所について"];scrollTo(about,app:app);about.tap()
        let corinthWiki=app.descendants(matching:.any).matching(identifier:"wikipedia-place:corinth_306").firstMatch
        scrollTo(corinthWiki,app:app);XCTAssertTrue(corinthWiki.exists)
        XCTAssertTrue(app.staticTexts["古代コリントス"].exists)
        XCTAssertTrue(app.staticTexts["現在の場所"].exists)
        attach(app,"wikipedia-ancient-corinth-from-current-map")
    }
    @MainActor private func assertReviewedMap(_ place:String, app:XCUIApplication) {
        let map=app.descendants(matching:.any).matching(NSPredicate(format:"label == %@",place+"付近の概略地図。現代の地図上の代表位置です。")).firstMatch
        XCTAssertTrue(map.waitForExistence(timeout:8))
        let sources=app.staticTexts["位置情報の出典と権利"];scrollTo(sources,app:app);XCTAssertTrue(sources.exists)
        XCTAssertTrue(app.staticTexts["地図の背景には通信が必要な場合があります。現在地は取得していません。"].exists)
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
            if element.exists && element.frame.minY > 140 && element.frame.maxY < app.frame.height { return }
            app.swipeDown()
        }
    }
    @MainActor private func scrollTo(_ element: XCUIElement, app: XCUIApplication) {
        CurrentUI.reveal(element, in: app)
    }
    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 1) // Let native navigation and disclosure animations settle before comparison images.
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
