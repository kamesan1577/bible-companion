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
    func testSelectionDoesNotRevealLaterDetailedRanges() async throws {
        let one = Passage(book: "ACT", start: Verse(chapter: 23, verse: 1), end: Verse(chapter: 23, verse: 1))
        let edits = try await StaticCommentary.shared.edits(for: one)
        XCTAssertEqual(edits.map(\.id), ["ja-v1:ACT:23:1-1"])
        let whole = Passage(book: "ACT", start: Verse(chapter: 23, verse: 1), end: Verse(chapter: 23, verse: 35))
        let all = try await StaticCommentary.shared.edits(for: whole)
        XCTAssertFalse(all.contains { $0.id.hasSuffix("chapter-overview") })
        XCTAssertTrue(all.contains { $0.passage.end.verse == 35 })
    }
    func testSixChaptersContainShortRangesAndNoOverlappingOverviews() async throws {
        for chapter in 18...23 {
            let end = Canon.verseCounts["ACT"]![chapter-1]
            let range = Passage(book: "ACT", start: Verse(chapter: chapter, verse: 1), end: Verse(chapter: chapter, verse: end))
            let edits = try await StaticCommentary.shared.edits(for: range)
            XCTAssertFalse(edits.contains { $0.id.hasSuffix("chapter-overview") })
            var seen = Set<Int>()
            for edit in edits {
                XCTAssertLessThanOrEqual(edit.passage.end.verse - edit.passage.start.verse + 1, 8)
                for verse in edit.passage.start.verse...edit.passage.end.verse {
                    XCTAssertTrue(seen.insert(verse).inserted, "Overlapping Japanese explanation")
                }
            }
            XCTAssertEqual(seen, Set(1...end))
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
        XCTAssertEqual(Set(edits.map(\.id)), ["ja-v1:ACT:18:24-26", "ja-v1:ACT:18:27-28", "ja-v1:ACT:19:1-3", "ja-v1:ACT:19:4-7"])
    }
    func testProgressSeparatesShortRangesFromOriginalCoverage() async throws {
        let progress = try await StaticCommentary.shared.progress()
        XCTAssertEqual(progress.chapterOverviews, 0)
        XCTAssertEqual(progress.detailedCoordinates, 1007) // Acts WEB1004 + three retained samples
        XCTAssertEqual(progress.coveredCoordinates, progress.detailedCoordinates)
        XCTAssertEqual(progress.completeActsChapters, Array(1...28).filter { ![8, 15, 24].contains($0) })
        XCTAssertGreaterThan(progress.sourceComparedEntryIds.count, 200)
        for (chapter, verse) in [(8,37), (15,34), (24,7)] {
            let missing = Passage(book: "ACT", start: Verse(chapter: chapter, verse: verse), end: Verse(chapter: chapter, verse: verse))
            let entries = try await StaticCommentary.shared.edits(for: missing)
            XCTAssertTrue(entries.isEmpty, "Do not fabricate text missing from the local WEB corpus")
        }
    }

    func testWorkflowNotesAreHiddenAndPassageSpecificNotesRemain() async throws {
        let generic = Passage(book: "ACT", start: Verse(chapter: 13, verse: 1), end: Verse(chapter: 13, verse: 1))
        let edits = try await StaticCommentary.shared.edits(for: generic)
        XCTAssertFalse(edits.isEmpty)
        XCTAssertTrue(edits.allSatisfy { $0.editorialNoteForDisplay == nil })
        let specific = Passage(book: "ACT", start: Verse(chapter: 22, verse: 12), end: Verse(chapter: 22, verse: 16))
        let notes = try await StaticCommentary.shared.edits(for: specific)
        XCTAssertTrue(notes.contains { $0.editorialNoteForDisplay?.contains("ダマスコ") == true })
    }

}
