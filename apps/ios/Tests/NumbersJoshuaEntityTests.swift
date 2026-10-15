import XCTest
@testable import CompanionCore

@MainActor final class NumbersJoshuaEntityTests: XCTestCase {
    private func verse(_ book: String, _ chapter: Int, _ verse: Int) -> Passage {
        Passage(book: book, start: Verse(chapter: chapter, verse: verse), end: Verse(chapter: chapter, verse: verse))
    }
    private func profile(_ book: String, _ chapter: Int, _ v: Int, _ id: String) async throws -> ResolvedEntityProfile {
        let result = try await BundledEntityIndex.shared.lookup(verse(book, chapter, v), kind: id.hasPrefix("person:") ? "person" : "place")
        return try XCTUnwrap(result.occurrences.first { $0.id == id }?.profile)
    }
    func testHosheaUsesExistingJoshuaIDWithoutPrematureIdentityLink() async throws {
        let p = try await profile("NUM", 13, 8, "person:joshua_1727")
        XCTAssertEqual(p.nameJa, "ホセア")
        XCTAssertFalse(p.profile.summaryJa.contains("ヨシュア"))
        XCTAssertNil(p.wikipedia)
        XCTAssertTrue(p.sources.allSatisfy { $0.knownBy == nil || $0.knownBy! <= Verse(chapter: 13, verse: 8) })
    }
    func testLeviPersonalAndCollectiveReferencesResolveSeparately() async throws {
        let collective = try await profile("NUM", 1, 47, "person:levi_1820")
        let individual = try await profile("NUM", 3, 17, "person:levi_1820")
        XCTAssertEqual(collective.profile.identityType, "collective")
        XCTAssertNotEqual(individual.profile.identityType, "collective")
        XCTAssertEqual(individual.nameJa, "レビ")
    }
    func testBohanFatherIsNotTheReubenTribe() async throws {
        let collective = try await profile("JOS", 1, 12, "person:reuben_2429")
        let father = try await profile("JOS", 15, 6, "person:reuben_2429")
        XCTAssertEqual(collective.profile.identityType, "collective")
        XCTAssertEqual(father.profile.identityType, "unidentified-eponym")
        XCTAssertFalse(collective.facts.contains { $0.textJa.contains("ボハン") })
        XCTAssertFalse(father.profile.summaryJa.contains("18:17"))
    }
    func testJosephBoneInformationIsGatedAndContextRetained() async throws {
        let early = try await profile("JOS", 14, 4, "person:joseph_1710")
        let burial = try await profile("JOS", 24, 32, "person:joseph_1710")
        XCTAssertEqual(early.profile.identityType, "collective")
        XCTAssertFalse((early.profile.summaryJa + early.contextNotes.joined() + early.facts.map(\.textJa).joined()).contains("骨"))
        XCTAssertTrue((burial.contextNotes.joined() + burial.facts.map(\.textJa).joined()).contains("骨"))
    }
    func testExplicitPlaceAliasesDoNotProduceDuplicateCardsOrPins() async throws {
        for (chapter, v, canonical, alias) in [(15,9,"place:kiriath-jearim_701","place:baalah_135"),(19,47,"place:dan_323","place:leshem_727"),(15,15,"place:debir_325","place:kiriath-sepher_703"),(15,49,"place:debir_325","place:kiriath-sannah_702"),(15,60,"place:kiriath-jearim_701","place:kiriath-baal_699")] {
            let result = try await BundledEntityIndex.shared.lookup(verse("JOS", chapter, v), kind: "place")
            XCTAssertEqual(result.occurrences.filter { $0.id == canonical }.count, 1)
            XCTAssertFalse(result.occurrences.contains { $0.id == alias })
        }
        let early = try await profile("JOS", 10, 38, "place:debir_325")
        XCTAssertFalse(early.facts.contains { $0.textJa.contains("セフェル") || $0.textJa.contains("サンナ") })
    }
    func testMachirSameAncestorIsNotRepeatedAndJacobUsesPersonalName() async throws {
        let first = try await profile("NUM",26,29,"person:machir_1877")
        XCTAssertFalse(first.contextNotes.contains { $0.hasPrefix("マキル：") })
        XCTAssertTrue(first.contextNotes.contains { $0.contains("マキル人") })
        let jacob = try await profile("NUM",32,11,"person:israel_682")
        XCTAssertEqual(jacob.nameJa,"ヤコブ")
        XCTAssertNotEqual(jacob.profile.identityType,"collective")
        let ancestors = try await profile("NUM",1,20,"person:israel_682")
        XCTAssertNil(ancestors.wikipedia)
        XCTAssertFalse(ancestors.sources.contains { $0.title.contains("ヤコブ") })
    }
    func testIsraelAndJacobBothRemainVisibleAtJosephBurial() async throws {
        let p = try await profile("JOS",24,32,"person:israel_682")
        XCTAssertEqual(p.profile.identityType,"collective")
        XCTAssertTrue(p.contextNotes.contains { $0.hasPrefix("ヤコブ：") })
        XCTAssertTrue((p.contextNotes.joined()+p.facts.map(\.textJa).joined()).contains("骨"))
        XCTAssertTrue(p.contextNotes.joined().contains("買"))
    }
    func testLuzAliasIdentityWaitsForItsSourceRevelation() async throws {
        let index=BundledEntityIndex.shared
        let early=try await index.lookup(verse("JOS",16,2),kind:"place")
        XCTAssertTrue(early.occurrences.contains { $0.id == "place:luz_737" })
        XCTAssertNil(early.occurrences.first { $0.id == "place:luz_737" }?.profile?.wikipedia)
        let later=try await index.lookup(verse("JOS",18,13),kind:"place")
        XCTAssertFalse(later.occurrences.contains { $0.id == "place:luz_737" })
        XCTAssertEqual(later.occurrences.filter { $0.id == "place:bethel_202" }.count,1)
        let range=Passage(book:"JOS",start:Verse(chapter:16,verse:2),end:Verse(chapter:18,verse:13))
        let ranged=try await index.lookup(range,kind:"place")
        XCTAssertFalse(ranged.occurrences.contains { $0.id == "place:luz_737" })
        let future=try await index.lookup(verse("JOS",16,2),kind:"place",includeFuture:true)
        XCTAssertFalse(future.occurrences.contains { $0.id == "place:luz_737" })
        XCTAssertEqual(future.occurrences.filter { $0.id == "place:bethel_202" }.count,1)
    }
    func testNumbersAndJoshuaStayIsolatedFromPublishedBooks() async throws {
        let num = try await profile("NUM", 1, 1, "person:god_1324")
        let jos = try await profile("JOS", 1, 1, "person:god_1324")
        let rom = try await profile("ROM", 1, 1, "person:god_1324")
        XCTAssertTrue(num.sources.allSatisfy { !$0.id.hasPrefix("JOS-") })
        XCTAssertTrue(jos.sources.allSatisfy { !$0.id.hasPrefix("NUM-") })
        XCTAssertTrue(rom.profile.summaryJa.contains("神の福音"))
    }
}
