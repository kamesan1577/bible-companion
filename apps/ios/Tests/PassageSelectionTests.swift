import XCTest
@testable import CompanionCore

final class PassageSelectionTests: XCTestCase {
    let reading = Passage(book: "ACT", start: Verse(chapter: 18, verse: 24), end: Verse(chapter: 19, verse: 7))
    func testArbitraryCrossChapterSubsetRetainsOriginalBoundary() throws {
        var selection = try PassageSelection(reading: reading)
        selection.selectVerse(26, isStart: true); selection.selectVerse(2, isStart: false)
        XCTAssertTrue(selection.isValid); XCTAssertEqual(selection.passage.reference, "18:26–19:2")
        let scope = try QuestionScope(reading: selection.reading, target: selection.passage)
        XCTAssertEqual(scope.reading.end, reading.end)
    }
    func testBoundsFollowRealChapterAndImportedRange() throws {
        var selection = try PassageSelection(reading: reading)
        XCTAssertEqual(selection.verses(in: 18), 24...28); XCTAssertEqual(selection.verses(in: 19), 1...7)
        selection.selectVerse(23, isStart: true); XCTAssertEqual(selection.start.verse, 24)
        selection.selectChapter(19, isStart: true); XCTAssertEqual(selection.start.verse, 7)
        selection.selectChapter(18, isStart: false); XCTAssertFalse(selection.isValid)
        selection.selectChapter(17, isStart: true); XCTAssertEqual(selection.start.chapter, 19)
    }
    func testInvalidInitialSelectionRejected() {
        XCTAssertThrowsError(try PassageSelection(reading: Passage(book: "ACT", start: Verse(chapter: 0, verse: 0), end: Verse(chapter: 1, verse: 1))))
        XCTAssertThrowsError(try PassageSelection(reading: reading, selected: Passage(book: "ACT", start: Verse(chapter: 19, verse: 7), end: Verse(chapter: 19, verse: 8))))
    }
}
