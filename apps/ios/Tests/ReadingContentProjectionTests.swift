import XCTest
@testable import CompanionCore

final class ReadingContentProjectionTests: XCTestCase {
    private func cards() throws -> [MaterialCard] {
#if SWIFT_PACKAGE
        let bundle = Bundle.module
#else
        let bundle = Bundle(for: Self.self)
#endif
        let url = try XCTUnwrap(bundle.url(forResource: "materials", withExtension: "json"))
        return try JSONDecoder().decode([MaterialCard].self, from: Data(contentsOf: url))
    }
    func testArtworkCountUsesVisibleUniqueCardsAndCompleteSceneBoundary() throws {
        let art = try XCTUnwrap(try cards().first { $0.kind == "artwork" })
        let before = Passage(book: "ACT", start: Verse(chapter: 9, verse: 3), end: Verse(chapter: 9, verse: 6))
        let complete = Passage(book: "ACT", start: Verse(chapter: 9, verse: 3), end: Verse(chapter: 9, verse: 7))
        XCTAssertTrue(ReadingContentProjection.materials([art], kind: "artwork", passage: before).isEmpty)
        XCTAssertEqual(ReadingContentProjection.materials([art, art], kind: "artwork", passage: complete).map(\.id), [art.id])
        XCTAssertTrue(ReadingContentProjection.materials([art], kind: "person", passage: complete).isEmpty)
        let retelling = Passage(book: "ACT", start: Verse(chapter: 22, verse: 6), end: Verse(chapter: 22, verse: 9))
        XCTAssertTrue(ReadingContentProjection.materials([art], kind: "artwork", passage: retelling).isEmpty)
    }
    func testEntityCardsAndCountUseSameDuplicateSuppression() async throws {
        let passage = Passage(book: "ACT", start: Verse(chapter: 18, verse: 24), end: Verse(chapter: 18, verse: 28))
        let result = try await BundledEntityIndex.shared.lookup(passage, kind: "person")
        let linked = try XCTUnwrap(result.occurrences.first { !($0.profile?.profile.materialCardIDs?.isEmpty ?? true) })
        let covered = linked.profile!.profile.materialCardIDs ?? []
        let duplicate = EntityIndexResult(occurrences: result.occurrences + [linked], sourceURL: result.sourceURL, attribution: result.attribution)
        let additions = ReadingContentProjection.additions(duplicate, covered: covered)
        XCTAssertFalse(additions.contains { $0.id == linked.id })
        XCTAssertEqual(Set(additions.map(\.id)).count, additions.count)
    }
    func testExplanationCountsOnlyVisibleEditsAndActualPublicBlock() async throws {
        let passage = Passage(book: "ACT", start: Verse(chapter: 18, verse: 24), end: Verse(chapter: 18, verse: 28))
        let edits = try await StaticCommentary.shared.edits(for: passage)
        XCTAssertFalse(edits.isEmpty)
        XCTAssertEqual(ReadingContentProjection.explanationCount(edits: edits + edits, publicText: "本文資料"), edits.count + 1)
        XCTAssertEqual(ReadingContentProjection.explanationCount(edits: [], publicText: " \n"), 0)
    }
    func testBadgeCapRetainsCompactWidth() {
        XCTAssertEqual(ReadingContentProjection.badgeText(0), "0")
        XCTAssertEqual(ReadingContentProjection.badgeText(99), "99")
        XCTAssertEqual(ReadingContentProjection.badgeText(100), "99+")
        XCTAssertEqual(ReadingContentProjection.badgeText(12345), "99+")
    }
}
