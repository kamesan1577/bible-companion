import XCTest
@testable import CompanionCore

@MainActor final class ChroniclesEntityTests: XCTestCase {
    private func lookup(_ chapter: Int, _ verse: Int, _ kind: String = "person") async throws -> EntityIndexResult {
        let at = Verse(chapter: chapter, verse: verse)
        return try await BundledEntityIndex.shared.lookup(Passage(book: "1CH", start: at, end: at), kind: kind)
    }
    private func text(_ value: ResolvedEntityProfile) -> String {
        ([value.nameJa, value.profile.summaryJa, value.profile.identityNoteJa] + value.facts.map(\.textJa)).joined(separator: "\n")
    }
    func testIsraelAncestorDoesNotShowCollectiveOrLaterJacobName() async throws {
        let result = try await lookup(1, 34)
        let israel = try XCTUnwrap(result.occurrences.first { $0.id == "person:israel_682" }?.profile)
        XCTAssertEqual(israel.profile.identityType, "individual-context-variant")
        XCTAssertFalse(text(israel).contains("ヤコブ"))
        XCTAssertNil(israel.wikipedia)
    }
    func testSonsOfIsraelAppearAtTheirOwnVerse() async throws {
        let early = try await lookup(2, 1)
        let first = try XCTUnwrap(early.occurrences.first { $0.id == "person:israel_682" }?.profile)
        XCTAssertFalse(text(first).contains("ヨセフ"))
        XCTAssertFalse(text(first).contains("アシェル"))
        let later = try await lookup(2, 2)
        let next = try XCTUnwrap(later.occurrences.first { $0.id == "person:israel_682" }?.profile)
        XCTAssertTrue(text(next).contains("ヨセフ"))
        XCTAssertTrue(text(next).contains("アシェル"))
    }
    func testGadGenealogyUsesTheIndividualContext() async throws {
        let result = try await lookup(2, 2)
        let gad = try XCTUnwrap(result.occurrences.first { $0.id == "person:gad_1262" }?.profile)
        XCTAssertEqual(gad.nameJa, "ガド")
        XCTAssertFalse(text(gad).contains("ガド族"))
    }
    func testEphraimMourningRemainsHiddenUntilVerse22() async throws {
        let early = try await lookup(7, 20)
        let first = try XCTUnwrap(early.occurrences.first { $0.id == "person:ephraim_1206" }?.profile)
        XCTAssertFalse(text(first).contains("殺"))
        XCTAssertFalse(text(first).contains("嘆"))
        let later = try await lookup(7, 22)
        let next = try XCTUnwrap(later.occurrences.first { $0.id == "person:ephraim_1206" }?.profile)
        XCTAssertTrue(text(next).contains("嘆"))
    }
    func testWrongHezronAndCalebNamesakesAreNotIntroduced() async throws {
        let hezron = try await lookup(2, 24)
        let caleb46 = try await lookup(2, 46)
        let caleb48 = try await lookup(2, 48)
        XCTAssertFalse(hezron.occurrences.contains { $0.id == "person:hezron_1519" })
        XCTAssertFalse(caleb46.occurrences.contains { $0.id == "person:caleb_537" })
        XCTAssertFalse(caleb48.occurrences.contains { $0.id == "person:caleb_537" })
    }
    func testGenealogicalGedorDoesNotBecomeAMapLocation() async throws {
        let result = try await lookup(4, 4, "place")
        XCTAssertFalse(result.occurrences.contains { $0.id == "place:gedor_456" })
    }
    func testJabeshShortNameHasOneCardAndAppearsAtVerse12() async throws {
        let early = try await lookup(10, 11, "place")
        let first = try XCTUnwrap(early.occurrences.first { $0.id == "place:jabesh-gilead_611" }?.profile)
        XCTAssertEqual(first.nameJa, "ヤベシュ・ギレアデ")
        XCTAssertFalse(text(first).contains("葬"))
        let late = try await lookup(10, 12, "place")
        XCTAssertFalse(late.occurrences.contains { $0.id == "place:jabesh_610" })
        let next = try XCTUnwrap(late.occurrences.first { $0.id == "place:jabesh-gilead_611" }?.profile)
        XCTAssertTrue(next.nameJa.hasPrefix("ヤベシュ（"))
        XCTAssertTrue(text(next).contains("七日間"))
        XCTAssertNil(next.profile.coordinate)
    }
    func testBaalahAliasDoesNotLeakIntoPreviousVerseOrDuplicateTheTown() async throws {
        let early = try await lookup(13, 5, "place")
        let first = try XCTUnwrap(early.occurrences.first { $0.id == "place:kiriath-jearim_701" }?.profile)
        XCTAssertFalse(text(first).contains("バアラ"))
        XCTAssertFalse(first.wikipedia?.noteJa.contains("バアラ") ?? false)
        let late = try await lookup(13, 6, "place")
        XCTAssertFalse(late.occurrences.contains { $0.id == "place:baalah_135" })
        let next = try XCTUnwrap(late.occurrences.first { $0.id == "place:kiriath-jearim_701" }?.profile)
        XCTAssertTrue(next.nameJa.hasPrefix("バアラ（"))
        XCTAssertTrue(text(next).contains("ユダ"))
        XCTAssertNil(next.profile.coordinate)
    }
    func testPrimaryOnlyDescriptionKeepsPrimaryRightsAndCorrectGenealogy() async throws {
        let result = try await lookup(7, 27)
        let joshua = try XCTUnwrap(result.occurrences.first { $0.id == "person:joshua_1727" }?.profile)
        XCTAssertTrue(text(joshua).contains("エフライム"))
        XCTAssertFalse(text(joshua).contains("ベニヤミン"))
        XCTAssertNil(joshua.wikipedia)
        XCTAssertFalse(joshua.sources.isEmpty)
        XCTAssertTrue(joshua.sources.allSatisfy { $0.category == "primary-text" && !$0.license.isEmpty && !$0.attribution.isEmpty })
    }
    func testJoashKingshipAndDeathStayHiddenAtRescueVerse() async throws {
        let store = BundledEntityIndex.shared
        let early = try await store.lookup(Passage(book: "2CH", start: Verse(chapter: 22, verse: 11), end: Verse(chapter: 22, verse: 11)), kind: "person")
        let first = try XCTUnwrap(early.occurrences.first { $0.id == "person:joash_1632" }?.profile)
        XCTAssertFalse(text(first).contains("王として"))
        XCTAssertFalse(text(first).contains("殺しました"))
        let later = try await store.lookup(Passage(book: "2CH", start: Verse(chapter: 23, verse: 11), end: Verse(chapter: 23, verse: 11)), kind: "person")
        let next = try XCTUnwrap(later.occurrences.first { $0.id == "person:joash_1632" }?.profile)
        XCTAssertTrue(text(next).contains("王として"))
        XCTAssertFalse(text(next).contains("殺しました"))
    }

    func testShobalFirstMentionDoesNotNameTheLaterJudahNamesake() async throws {
        let early = try await lookup(1, 38)
        let first = try XCTUnwrap(early.occurrences.first { $0.id == "person:shobal_2719" }?.profile)
        XCTAssertFalse(text(first).contains("ユダ"))
        XCTAssertFalse(text(first).contains("アリアン"))
        let later = try await lookup(1, 40)
        let next = try XCTUnwrap(later.occurrences.first { $0.id == "person:shobal_2719" }?.profile)
        XCTAssertTrue(text(next).contains("アリアン"))
    }

}
