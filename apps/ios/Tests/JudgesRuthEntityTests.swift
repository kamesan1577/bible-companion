import XCTest
@testable import CompanionCore

@MainActor final class JudgesRuthEntityTests: XCTestCase {
    private func verse(_ book: String, _ c: Int, _ v: Int) -> Passage {
        Passage(book: book, start: Verse(chapter: c, verse: v), end: Verse(chapter: c, verse: v))
    }
    private func lookup(_ book: String, _ c: Int, _ v: Int, _ kind: String) async throws -> EntityIndexResult {
        try await BundledEntityIndex.shared.lookup(verse(book, c, v), kind: kind)
    }
    func testUnnamedChildDoesNotRevealSamsonBeforeNaming() async throws {
        let early = try await lookup("JDG", 13, 3, "person")
        XCTAssertFalse(early.occurrences.contains { $0.id == "person:samson_2468" })
        let named = try await lookup("JDG", 13, 24, "person")
        XCTAssertNotNil(named.occurrences.first { $0.id == "person:samson_2468" }?.profile)
    }
    func testSecondLuzRemainsDistinctAfterBethelAliasRevelation() async throws {
        let first = try await lookup("JDG", 1, 23, "place")
        XCTAssertEqual(first.occurrences.filter { $0.id == "place:bethel_202" }.count, 1)
        XCTAssertFalse(first.occurrences.contains { $0.id == "place:luz_737" })
        let second = try await lookup("JDG", 1, 26, "place")
        XCTAssertNotNil(second.occurrences.first { $0.id == "place:luz_738" }?.profile)
        XCTAssertFalse(second.occurrences.contains { $0.id == "place:bethel_202" })
    }
    func testDanNamesDoNotRevealCityBeforeRenaming() async throws {
        let before = try await lookup("JDG", 18, 7, "place")
        let laish = try XCTUnwrap(before.occurrences.first { $0.id == "place:laish_713" }?.profile)
        XCTAssertFalse(laish.profile.summaryJa.contains("改名"))
        XCTAssertFalse(laish.profile.summaryJa.contains("ダンと呼"))
        let after = try await lookup("JDG", 18, 29, "place")
        XCTAssertEqual(after.occurrences.filter { $0.id == "place:dan_323" }.count, 1)
        XCTAssertFalse(after.occurrences.contains { $0.id == "place:laish_713" })
        let people = try await lookup("JDG", 18, 29, "person")
        let dan = try XCTUnwrap(people.occurrences.first { $0.id == "person:dan_973" }?.profile)
        XCTAssertEqual(dan.profile.identityType, "collective")
        XCTAssertFalse(dan.contextNotes.isEmpty)
        let israel = try XCTUnwrap(people.occurrences.first { $0.id == "person:israel_682" }?.profile)
        XCTAssertNotEqual(israel.profile.identityType, "collective")
    }
    func testRuthPlaceAndFamilyRevelationsKeepTheirBoundaries() async throws {
        let beginning = try await lookup("RUT", 1, 1, "place")
        XCTAssertNotNil(beginning.occurrences.first { $0.id == "place:bethlehem_218" }?.profile)
        let origin = try await lookup("RUT", 1, 2, "place")
        XCTAssertFalse(origin.occurrences.contains { $0.id == "place:ephrathah_404" })
        let blessing = try await lookup("RUT", 4, 11, "place")
        XCTAssertNotNil(blessing.occurrences.first { $0.id == "place:ephrathah_404" }?.profile)
        let wives = try await lookup("RUT", 1, 4, "person")
        for item in wives.occurrences.compactMap({ $0.profile }) {
            XCTAssertTrue(item.sources.allSatisfy { $0.knownBy == nil || $0.knownBy! <= Verse(chapter: 1, verse: 4) })
            XCTAssertFalse(item.facts.contains { $0.textJa.contains("4:10") })
        }
    }
}
