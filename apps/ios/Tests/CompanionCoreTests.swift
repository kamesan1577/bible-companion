import XCTest
@testable import CompanionCore

final class CompanionCoreTests: XCTestCase {
    func testShareOwnerMarkerIsBoundedAndNeverTreatsCorruptionAsUnbound() throws {
        XCTAssertNil(try ShareOwnerMarker.decode(Data()))
        let owner = UUID().uuidString
        XCTAssertEqual(try ShareOwnerMarker.decode(Data(owner.utf8)), owner)
        XCTAssertThrowsError(try ShareOwnerMarker.decode(Data([0xff])))
        XCTAssertThrowsError(try ShareOwnerMarker.decode(Data("old-owner".utf8)))
        XCTAssertThrowsError(try ShareOwnerMarker.decode(Data(repeating: 65, count: 65)))
    }

    private let cross = Passage(book: "ACT", start: Verse(chapter: 18, verse: 24), end: Verse(chapter: 19, verse: 7))
    func testSingleVerseLabel() { XCTAssertEqual(Passage(book: "JHN", start: Verse(chapter: 3, verse: 16), end: Verse(chapter: 3, verse: 16)).reference, "3:16") }
    func testSameChapterLabel() { XCTAssertEqual(Passage(book: "ACT", start: Verse(chapter: 18, verse: 24), end: Verse(chapter: 18, verse: 28)).reference, "18:24–28") }
    func testCrossChapterLabelAndCount() { XCTAssertEqual(cross.reference, "18:24–19:7"); XCTAssertEqual(cross.verseCount, 12) }
    func testCanonLoadsAllBooks() { XCTAssertEqual(Canon.books.count, 66); XCTAssertEqual(Canon.verseCounts.count, 66) }
    func testRejectImpossibleVerse() { XCTAssertFalse(Passage(book: "ACT", start: Verse(chapter: 18, verse: 29), end: Verse(chapter: 19, verse: 7)).isValid) }
    func testRejectReverseRange() { XCTAssertFalse(Passage(book: "ACT", start: cross.end, end: cross.start).isValid) }
    func testRejectUnknownBook() { XCTAssertFalse(Passage(book: "XXX", start: cross.start, end: cross.end).isValid) }
    func testSegmentsPreserveWhole() { XCTAssertEqual(cross.chapterSegments.count, 2); XCTAssertEqual(cross.chapterSegments.reduce(0) { $0 + $1.verseCount }, cross.verseCount) }
    func testSubsetKeepsOriginalSpoilerEnd() throws {
        let scope = try QuestionScope(reading: cross, target: cross.chapterSegments[0])
        XCTAssertFalse(scope.isWhole)
        XCTAssertTrue(scope.allowsSource(cross.chapterSegments[1]))
        XCTAssertFalse(scope.allowsSource(Passage(book: "ACT", start: Verse(chapter: 19, verse: 8), end: Verse(chapter: 19, verse: 10))))
    }
    func testRejectOutsideQuestionTarget() { XCTAssertThrowsError(try QuestionScope(reading: cross.chapterSegments[0], target: cross)) }
    func testWholeScope() throws { XCTAssertTrue(try QuestionScope(reading: cross, target: cross).isWhole) }
    func testParseYouVersionCrossChapter() throws {
        let parsed = try SharedImportParser.parse("https://www.bible.com/bible/83/ACT.18.24-19.7.JCB")
        XCTAssertEqual(parsed.ranges, [cross]); XCTAssertEqual(parsed.translation, "JCB")
    }
    func testNumericTranslationNeverGuessed() throws {
        let parsed = try SharedImportParser.parse("https://www.bible.com/bible/83/JHN.3.16")
        XCTAssertNil(parsed.translation); XCTAssertTrue(parsed.needsConfirmation)
    }
    func testJapaneseCrossChapter() throws { XCTAssertEqual(try SharedImportParser.parse("使徒の働き 18:24–19:7 (JCB)").ranges, [cross]) }
    func testFullWidthReference() throws { XCTAssertEqual(try SharedImportParser.parse("使徒 １８：２４－１９：７").ranges, [cross]) }
    func testDoesNotParseNumbersInUnrelatedText() { XCTAssertThrowsError(try SharedImportParser.parse("今日の読書 18:24–19:7")) }
    func testDoesNotFetchOrTrustArbitraryURL() { XCTAssertThrowsError(try SharedImportParser.parse("https://evil.example/bible/83/ACT.18.24.JCB")) }
    func testRejectLongShare() { XCTAssertThrowsError(try SharedImportParser.parse(String(repeating: "a", count: 20_001))) }
    func testRejectMalformedTrailingRange() { XCTAssertThrowsError(try SharedImportParser.parse("ACT 18:24-19:7-10")) }
    func testRejectOverflowingEndVerse() { XCTAssertThrowsError(try SharedImportParser.parse("ACT 18:24-" + String(repeating: "9", count: 50))) }
    func testRejectOverflowingEndChapter() { XCTAssertThrowsError(try SharedImportParser.parse("ACT 18:24-" + String(repeating: "9", count: 50) + ":7")) }
    func testNeverTruncateMultipleReferences() { XCTAssertThrowsError(try SharedImportParser.parse("ACT 18:24\nJHN 3:16")) }
    func testNeverTruncateURLAndDifferentReference() { XCTAssertThrowsError(try SharedImportParser.parse("https://bible.com/bible/83/JHN.3.16.JCB\nACT 18:24")) }
    func testQueueBindsOriginalAccount() {
        let share = PendingShare(ownerID: "a", text: "ACT 18:24")
        XCTAssertFalse(share.requiresAccountConfirmation(currentOwner: "a")); XCTAssertTrue(share.requiresAccountConfirmation(currentOwner: "b"))
        XCTAssertTrue(PendingShare(ownerID: nil, text: "ACT 18:24").requiresAccountConfirmation(currentOwner: "a"))
    }
    func testQueueExpiresIn24Hours() {
        let date = Date(timeIntervalSince1970: 100_000)
        let share = PendingShare(ownerID: nil, text: "ACT 18:24", createdAt: date)
        XCTAssertFalse(share.isExpired(at: date.addingTimeInterval(86_399)))
        XCTAssertTrue(share.isExpired(at: date.addingTimeInterval(86_400)))
    }
    func testCancelledAndReplacedRequestsCannotRender() { var gate = RequestGate(); let first = gate.generation; gate.invalidate(); XCTAssertFalse(gate.accepts(first)); XCTAssertTrue(gate.accepts(gate.generation)) }
    func testOfflineMessageNeverPromisesAutomaticRetry() { XCTAssertTrue(NetworkFailure.offline.userMessage.contains("再送していません")) }
    func testReviewedMaterialCardsDecodeAndRespectBoundary() throws {
        let cards: [MaterialCard] = try fixture("materials")
        XCTAssertEqual(cards.count, 16)
        let early = Passage(book: "ACT", start: Verse(chapter: 18, verse: 1), end: Verse(chapter: 18, verse: 1))
        XCTAssertFalse(try XCTUnwrap(cards.first { $0.id == "person-sosthenes-act18" }).isDisplayable(reading: early))
        let art = try XCTUnwrap(cards.first { $0.kind == "artwork" })
        XCTAssertEqual(art.publicDomainImageURL?.host, "api.nga.gov")
        XCTAssertTrue(cards.allSatisfy { $0.reviewed && $0.rightsStatus == "approved" && !$0.provenance.isEmpty })
        XCTAssertTrue(cards.filter { $0.kind == "place" }.allSatisfy { $0.details["coordinates"]["certainty"].string == "approximate" })
    }
    func testActualResponseFixturesDecode() throws {
        let account: AccountResponse = try fixture("me"); XCTAssertFalse(account.user.id.isEmpty)
        let record: ImportRecord = try fixture("import"); XCTAssertTrue(record.ranges.allSatisfy(\.isValid))
        let conversation: Conversation = try fixture("conversation"); XCTAssertNotNil(conversation.readingBoundary); XCTAssertTrue(conversation.readingBoundary?.contains(conversation.passage) == true)
        let reading: ReadingResponse = try fixture("reading"); XCTAssertFalse(reading.overview.modelInvoked); XCTAssertEqual(reading.overview.mode, "source-only")
        XCTAssertEqual(reading.overview.referenceSystem?.translationAlignment, "unverified"); XCTAssertEqual(reading.overview.referenceSystem?.requestedTranslation, "JCB")
        let question: RequestResult = try fixture("question-result"); XCTAssertNotNil(question.result)
        XCTAssertEqual(question.result?.referenceSystem?.versification, "standard-kjv"); XCTAssertEqual(question.result?.referenceSystem?.translationAlignment, "unverified")
        let catalog: JSONValue = try fixture("model-catalog"); XCTAssertEqual(catalog["models"].array.count, 22)
        XCTAssertTrue(catalog["models"].array.allSatisfy { $0["termsReview"]["acceptancePerformed"].bool == false && $0["termsReview"]["status"].string == "unreviewed" && $0["enabled"].bool == false })
    }
    private func fixture<T: Decodable>(_ name: String) throws -> T {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: Self.self)
        #endif
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json"))
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
}
