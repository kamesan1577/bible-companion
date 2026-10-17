import XCTest
@testable import CompanionCore

@MainActor final class KingsEntityTests: XCTestCase {
    private func lookup(_ book: String, _ chapter: Int, _ verse: Int, _ kind: String = "person") async throws -> EntityIndexResult {
        let at = Verse(chapter: chapter, verse: verse)
        return try await BundledEntityIndex.shared.lookup(Passage(book: book, start: at, end: at), kind: kind)
    }
    func testSolomonsScribesAndRecorderDoNotBecomeNamesakes() async throws {
        let list = try await lookup("1KI", 4, 3)
        XCTAssertNotNil(list.occurrences.first { $0.id == "person:ahiah_127" }?.profile)
        XCTAssertNotNil(list.occurrences.first { $0.id == "person:jehoshaphat_806" }?.profile)
        XCTAssertFalse(list.occurrences.contains { $0.id == "person:ahijah_136" || $0.id == "person:jehoshaphat_807" })
    }
    func testBenjaminDistrictDoesNotIntroduceTheAncestor() async throws {
        let people = try await lookup("1KI", 4, 18)
        XCTAssertFalse(people.occurrences.contains { $0.id == "person:benjamin_463" })
        let places = try await lookup("1KI", 4, 18, "place")
        XCTAssertNotNil(places.occurrences.first { $0.id == "place:benjamin-territory_1293" }?.profile)
    }
    func testAdrammelechDeityAndRoyalAssassinRemainSeparate() async throws {
        let worship = try await lookup("2KI", 17, 31)
        let deity = try XCTUnwrap(worship.occurrences.first { $0.id == "person:adrammelech_103" }?.profile)
        XCTAssertEqual(deity.profile.detailLinkLabelJa, "この神名について")
        XCTAssertFalse(worship.occurrences.contains { $0.id == "person:adrammelech_104" })
        let assassination = try await lookup("2KI", 19, 37)
        XCTAssertNotNil(assassination.occurrences.first { $0.id == "person:adrammelech_104" }?.profile)
        XCTAssertFalse(assassination.occurrences.contains { $0.id == "person:adrammelech_103" })
    }
    func testBerodachBaladanAndHisFatherHaveSeparateCards() async throws {
        let envoys = try await lookup("2KI", 20, 12)
        XCTAssertNotNil(envoys.occurrences.first { $0.id == "person:merodach-baladan_483" }?.profile)
        XCTAssertNotNil(envoys.occurrences.first { $0.id == "person:baladan_594" }?.profile)
    }
    func testJacobUsesTheIndividualContextWithoutRevealingLaterArticle() async throws {
        let covenant = try await lookup("2KI", 13, 23)
        let jacob = try XCTUnwrap(covenant.occurrences.first { $0.id == "person:israel_682" }?.profile)
        XCTAssertEqual(jacob.nameJa, "ヤコブ")
        XCTAssertNotEqual(jacob.profile.identityType, "collective")
        XCTAssertNil(jacob.wikipedia)
        let renamed = try await lookup("2KI", 17, 34)
        XCTAssertNotNil(renamed.occurrences.first { $0.id == "person:israel_682" }?.profile?.wikipedia)
    }
}
