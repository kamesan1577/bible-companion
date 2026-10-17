import XCTest
@testable import CompanionCore

@MainActor final class SamuelEntityTests: XCTestCase {
    private func lookup(_ book: String, _ c: Int, _ v: Int, _ kind: String = "person") async throws -> EntityIndexResult {
        let at = Verse(chapter:c, verse:v)
        return try await BundledEntityIndex.shared.lookup(Passage(book:book,start:at,end:at),kind:kind)
    }
    func testUnbornChildIsNotNamedBeforeSamuelIsNamed() async throws {
        let promised = try await lookup("1SA",1,11)
        XCTAssertFalse(promised.occurrences.contains { $0.id == "person:samuel_2469" })
        let named = try await lookup("1SA",1,20)
        XCTAssertNotNil(named.occurrences.first { $0.id == "person:samuel_2469" }?.profile)
    }
    func testBookLocalAhimelechIdentitiesRemainSeparate() async throws {
        let priest = try await lookup("1SA",21,1)
        XCTAssertNotNil(priest.occurrences.first { $0.id == "person:ahimelech_126" }?.profile)
        XCTAssertFalse(priest.occurrences.contains { $0.id == "person:ahimelech_149" })
        let hittite = try await lookup("1SA",26,6)
        XCTAssertNotNil(hittite.occurrences.first { $0.id == "person:ahimelech_148" }?.profile)
        XCTAssertFalse(hittite.occurrences.contains { $0.id == "person:ahimelech_126" })
        let list = try await lookup("2SA",8,17)
        let son = try XCTUnwrap(list.occurrences.first { $0.id == "person:ahimelech_149" }?.profile)
        XCTAssertTrue(son.profile.summaryJa.contains("アビヤタルの子"))
    }
    func testJacobIndividualAndIsraelPeopleResolveWithinTheirContexts() async throws {
        let recalled = try await lookup("1SA",12,8)
        let jacob = try XCTUnwrap(recalled.occurrences.first { $0.id == "person:israel_682" }?.profile)
        XCTAssertEqual(jacob.nameJa,"ヤコブ")
        XCTAssertNotEqual(jacob.profile.identityType,"collective")
        let both = try await lookup("2SA",23,1)
        let israel = try XCTUnwrap(both.occurrences.first { $0.id == "person:israel_682" }?.profile)
        XCTAssertEqual(israel.profile.identityType,"collective")
        XCTAssertTrue(israel.contextNotes.contains { $0.contains("ヤコブ") })
        XCTAssertTrue(israel.sources.allSatisfy { $0.knownBy == nil || $0.knownBy! <= Verse(chapter:23,verse:1) })
    }
    func testUnnamedGiantDoesNotRevealLaterGathOrSummary() async throws {
        let first = try await lookup("2SA",21,16)
        let giant = try XCTUnwrap(first.occurrences.first { $0.id == "person:the_giant_in_gath_2848" }?.profile)
        XCTAssertFalse(giant.nameJa.contains("ガト"))
        XCTAssertFalse(giant.profile.identityNoteJa.contains("21:22"))
        XCTAssertNil(giant.wikipedia)
        let later = try await lookup("2SA",21,22)
        XCTAssertNotNil(later.occurrences.first { $0.id == "person:the_giant_in_gath_2848" }?.profile?.wikipedia)
    }
    func testDuplicateTownNamesCollapseAndUncertainRegionHasNoPoint() async throws {
        let town = try await lookup("1SA",11,9,"place")
        XCTAssertEqual(town.occurrences.filter { $0.id == "place:jabesh-gilead_611" }.count,1)
        XCTAssertFalse(town.occurrences.contains { $0.id == "place:jabesh_610" })
        let region = try await lookup("1SA",6,1,"place")
        let philistia = try XCTUnwrap(region.occurrences.first { $0.id == "place:philistia_943" })
        XCTAssertNil(philistia.entity.coordinate)
        XCTAssertNil(philistia.candidateMapNote)
    }
}
