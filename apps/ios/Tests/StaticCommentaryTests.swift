import XCTest
@testable import CompanionCore
final class StaticCommentaryTests: XCTestCase, @unchecked Sendable {
    func testDictionarySearchIsExplicitAndSeparate() async throws {
        let empty = try await StaticCommentary.shared.dictionary(matching: " ")
        XCTAssertTrue(empty.isEmpty)
        let entries = try await StaticCommentary.shared.dictionary(matching: "Paul")
        XCTAssertFalse(entries.isEmpty)
        XCTAssertTrue(entries.allSatisfy { $0.headword.localizedCaseInsensitiveContains("Paul") && !$0.originalText.isEmpty })
    }
    func testDoesNotRevealChapterOverviewBeforeChapterEnd() async throws {
        let one = Passage(book: "ACT", start: Verse(chapter: 23, verse: 1), end: Verse(chapter: 23, verse: 1))
        let edits = try await StaticCommentary.shared.edits(for: one)
        XCTAssertEqual(edits.map(\.id), ["ja-v1:ACT:23:1-1"])
        let whole = Passage(book: "ACT", start: Verse(chapter: 23, verse: 1), end: Verse(chapter: 23, verse: 35))
        let all = try await StaticCommentary.shared.edits(for: whole)
        XCTAssertTrue(all.contains { $0.id == "ja-v1:ACT:23:chapter-overview" })
    }
    func testSixChapterOverviewsAndUntranslatedRange() async throws {
        for chapter in 18...23 {
            let end = Canon.verseCounts["ACT"]![chapter-1]
            let range = Passage(book: "ACT", start: Verse(chapter: chapter, verse: 1), end: Verse(chapter: chapter, verse: end))
            let edits = try await StaticCommentary.shared.edits(for: range)
            XCTAssertTrue(edits.contains { $0.id == "ja-v1:ACT:\(chapter):chapter-overview" })
        }
        let untranslated = Passage(book: "GEN", start: Verse(chapter: 2, verse: 1), end: Verse(chapter: 2, verse: 1))
        let edits = try await StaticCommentary.shared.edits(for: untranslated)
        XCTAssertTrue(edits.isEmpty)
        let originals = try await StaticCommentary.shared.originals(for: untranslated)
        XCTAssertFalse(originals.isEmpty)
    }
    func testCrossChapterSelectionKeepsBothEditedRanges() async throws {
        let range = Passage(book: "ACT", start: Verse(chapter: 18, verse: 24), end: Verse(chapter: 19, verse: 7))
        let edits = try await StaticCommentary.shared.edits(for: range)
        XCTAssertEqual(Set(edits.map(\.id)), ["ja-v1:ACT:18:24-28", "ja-v1:ACT:19:1-7"])
    }
}
