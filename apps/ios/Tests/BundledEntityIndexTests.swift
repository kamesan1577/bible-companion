import XCTest
@testable import CompanionCore
@MainActor final class BundledEntityIndexTests: XCTestCase {
    func testActs2815PlacesHaveUniqueIDsAndUsableCandidateCoordinates() async throws {
        let passage = Passage(book: "ACT", start: Verse(chapter: 28, verse: 15), end: Verse(chapter: 28, verse: 15))
        let result = try await BundledEntityIndex.shared.lookup(passage, kind: "place")
        XCTAssertEqual(result.occurrences.count, 3)
        XCTAssertEqual(Set(result.occurrences.map(\.id)).count, 3)
        for item in result.occurrences {
            let point = try XCTUnwrap(item.entity.coordinate)
            XCTAssertEqual(point.count, 2)
            XCTAssertTrue(point[0].isFinite && abs(point[0]) <= 90)
            XCTAssertTrue(point[1].isFinite && abs(point[1]) <= 180)
            XCTAssertNotNil(item.profile)
        }
    }
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
