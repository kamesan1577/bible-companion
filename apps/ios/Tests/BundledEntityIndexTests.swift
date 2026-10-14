import XCTest
@testable import CompanionCore
@MainActor final class BundledEntityIndexTests: XCTestCase {
    func testCanonicalMetadataAndSameBookSpoilerBoundary() async throws {
        let passage = Passage(book: "ACT", start: Verse(chapter: 23, verse: 1), end: Verse(chapter: 23, verse: 1))
        let value = try await BundledEntityIndex.shared.lookup(passage, kind: "person")
        XCTAssertFalse(value.occurrences.isEmpty)
        XCTAssertTrue(value.occurrences.contains { $0.entity.name == "Paul" || $0.entity.displayName == "パウロ" })
        for occurrence in value.occurrences { for ref in occurrence.sameBookVerses { XCTAssertEqual(ref.book, "ACT"); XCTAssertTrue(ref.end.chapter < 23 || (ref.end.chapter == 23 && ref.end.verse <= 1)) } }
        let expanded = try await BundledEntityIndex.shared.lookup(passage, kind: "person", includeFuture: true)
        XCTAssertGreaterThan(expanded.occurrences.reduce(0) { $0 + $1.sameBookVerses.count }, value.occurrences.reduce(0) { $0 + $1.sameBookVerses.count })
    }
    func testEmptyVerseIsNotFilledWithUnrelatedEntitiesAndLicenseIsRetained() async throws {
        let passage = Passage(book: "PSA", start: Verse(chapter: 117, verse: 1), end: Verse(chapter: 117, verse: 2))
        let value = try await BundledEntityIndex.shared.lookup(passage, kind: "place")
        XCTAssertTrue(value.occurrences.isEmpty)
        XCTAssertTrue(value.sourceURL?.host == "github.com")
        XCTAssertTrue(value.attribution.contains("Theographic"))
    }
}
