import XCTest
@testable import CompanionCore

@MainActor final class ActsEntityCoverageTests: XCTestCase {
    func testAllActsVerseCoordinatesKeepSourcesAndSpoilerBoundaries() async throws {
        let lengths = [26,47,26,37,42,15,60,40,43,48,30,25,52,28,41,40,34,28,41,38,40,30,35,27,27,32,44,31]
        var visited = 0
        var mappedPlaceIDs = Set<String>()
        var checkedPlaceIDs = Set<String>()
        for (offset, length) in lengths.enumerated() {
            for verse in 1...length {
                let end = Verse(chapter: offset + 1, verse: verse)
                let passage = Passage(book: "ACT", start: end, end: end)
                for kind in ["person", "place"] {
                    let value = try await BundledEntityIndex.shared.lookup(passage, kind: kind)
                    XCTAssertEqual(Set(value.occurrences.map(\.id)).count, value.occurrences.count, passage.label)
                    for occurrence in value.occurrences {
                        if kind == "place", occurrence.entity.coordinate != nil { mappedPlaceIDs.insert(occurrence.id) }
                        if kind == "place", occurrence.profile?.profile.coordinate != nil { checkedPlaceIDs.insert(occurrence.id) }
                        let resolved = try XCTUnwrap(occurrence.profile, passage.label)
                        XCTAssertLessThanOrEqual(resolved.profile.knownBy, end)
                        XCTAssertFalse(resolved.sources.isEmpty, occurrence.id + " " + passage.label)
                        XCTAssertTrue(resolved.sources.allSatisfy { $0.safeURL != nil && ($0.knownBy == nil || $0.knownBy! <= end) })
                        XCTAssertTrue(resolved.facts.allSatisfy { $0.knownBy <= end })
                        XCTAssertTrue(occurrence.sameBookVerses.allSatisfy { $0.end <= end })
                    }
                }
                visited += 1
            }
        }
        XCTAssertEqual(visited, 1007)
        XCTAssertEqual(mappedPlaceIDs.count, 92)
        XCTAssertEqual(checkedPlaceIDs.count, 4)
        XCTAssertFalse(mappedPlaceIDs.contains("place:salmone_1020"), "Known wrong mainland coordinate must stay hidden")
        XCTAssertTrue(mappedPlaceIDs.contains("place:rome_1013"))
        XCTAssertTrue(mappedPlaceIDs.contains("place:shechem_1069"))
    }
    func testOfficeTitlesAndUnknownEponymsDoNotClaimIndividualsOrFutureFacts() async throws {
        let first = Passage(book: "ACT", start: Verse(chapter: 13, verse: 2), end: Verse(chapter: 13, verse: 2))
        let called = try await BundledEntityIndex.shared.lookup(first, kind: "person")
        let saul = try XCTUnwrap(called.occurrences.first { $0.id == "person:paul_2479" }?.profile)
        XCTAssertFalse(saul.facts.contains { $0.textJa.contains("セレウキア") })
        let later = Passage(book: "ACT", start: Verse(chapter: 13, verse: 4), end: Verse(chapter: 13, verse: 4))
        let sent = try await BundledEntityIndex.shared.lookup(later, kind: "person")
        XCTAssertTrue(sent.occurrences.first { $0.id == "person:paul_2479" }?.profile?.facts.contains { $0.textJa.contains("セレウキア") } == true)
        let titlePassage = Passage(book: "ACT", start: Verse(chapter: 17, verse: 7), end: Verse(chapter: 17, verse: 7))
        let titles = try await BundledEntityIndex.shared.lookup(titlePassage, kind: "person")
        let emperor = try XCTUnwrap(titles.occurrences.first { $0.id == "title:roman-emperor-acts" }?.profile)
        XCTAssertEqual(emperor.profile.identityType, "office-title")
        XCTAssertEqual(emperor.profile.detailLinkLabelJa, "この称号について")
        let school = Passage(book: "ACT", start: Verse(chapter: 19, verse: 9), end: Verse(chapter: 19, verse: 9))
        let names = try await BundledEntityIndex.shared.lookup(school, kind: "person")
        let tyrannus = try XCTUnwrap(names.occurrences.first { $0.id == "person:tyrannus_2886" })
        XCTAssertFalse(tyrannus.directlyNamed)
        XCTAssertEqual(tyrannus.profile?.profile.identityType, "unidentified-eponym")
        XCTAssertEqual(tyrannus.profile?.profile.detailLinkLabelJa, "この名前について")
    }
    func testExistingJerusalemCandidateCoordinateRemainsSeparateFromReviewedPoint() async throws {
        let passage = Passage(book: "ACT", start: Verse(chapter: 1, verse: 4), end: Verse(chapter: 1, verse: 4))
        let places = try await BundledEntityIndex.shared.lookup(passage, kind: "place")
        let jerusalem = try XCTUnwrap(places.occurrences.first { $0.id == "place:jerusalem_636" })
        XCTAssertEqual(jerusalem.entity.coordinate, [31.776667, 35.234167])
        XCTAssertNotEqual(jerusalem.entity.coordinateStatus, "source-representative-point")
        XCTAssertNil(jerusalem.profile?.profile.coordinate)
    }
    func testSameNamedSaulAndWrongPersonLinksDoNotCross() async throws {
        let passage = Passage(book: "ACT", start: Verse(chapter: 13, verse: 21), end: Verse(chapter: 13, verse: 21))
        let people = try await BundledEntityIndex.shared.lookup(passage, kind: "person")
        XCTAssertTrue(people.occurrences.contains { $0.id == "person:saul_2478" && $0.entity.displayName == "サウル" })
        XCTAssertFalse(people.occurrences.contains { $0.id == "person:benjamin_463" })
        let owner = Passage(book: "ACT", start: Verse(chapter: 9, verse: 11), end: Verse(chapter: 9, verse: 11))
        let judas = try await BundledEntityIndex.shared.lookup(owner, kind: "person")
        XCTAssertTrue(judas.occurrences.contains { $0.id == "person:judas_1758" })
    }
}
