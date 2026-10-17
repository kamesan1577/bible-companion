import XCTest
@testable import CompanionCore

@MainActor final class EzraNehemiahEntityTests: XCTestCase {
    private func passage(_ book: String, _ startChapter: Int, _ startVerse: Int, _ endChapter: Int? = nil, _ endVerse: Int? = nil) -> Passage {
        Passage(book: book, start: Verse(chapter: startChapter, verse: startVerse), end: Verse(chapter: endChapter ?? startChapter, verse: endVerse ?? startVerse))
    }

    private func lookup(_ book: String, _ chapter: Int, _ verse: Int, _ kind: String = "person") async throws -> EntityIndexResult {
        try await BundledEntityIndex.shared.lookup(passage(book, chapter, verse), kind: kind)
    }

    func testAdaiah75AppearsAtItsOwnVerseWithPrimaryAttribution() async throws {
        let earlier = try await lookup("EZR", 10, 29)
        XCTAssertFalse(earlier.occurrences.contains { $0.id == "person:adaiah_75" })
        let current = try await lookup("EZR", 10, 39)
        let adaiah = try XCTUnwrap(current.occurrences.first { $0.id == "person:adaiah_75" }?.profile)
        XCTAssertEqual(adaiah.profile.knownBy, Verse(chapter: 10, verse: 39))
        XCTAssertNil(adaiah.wikipedia)
        XCTAssertTrue(adaiah.sources.contains { $0.url.hasSuffix("EZR10.htm#V39") && $0.license == "Public Domain" })
        XCTAssertTrue(adaiah.sources.allSatisfy { $0.safeURL != nil })
        let range = try await BundledEntityIndex.shared.lookup(passage("EZR", 10, 29, 10, 39), kind: "person")
        XCTAssertEqual(range.occurrences.filter { $0.id == "person:adaiah_75" }.count, 1)
        XCTAssertFalse(range.occurrences.contains { $0.id == "person:adaiah_74" })
    }

    func testHeldBeerothDoesNotBecomeAResolvedOrLocatedPlace() async throws {
        let neh = try await lookup("NEH", 7, 29, "place")
        XCTAssertFalse(neh.occurrences.contains { $0.id == "place:beeroth_168" })
    }

    func testEzraProfileDoesNotLeakAcrossBookCatalogs() async throws {
        let ezra = try await lookup("EZR", 10, 39)
        XCTAssertNotNil(ezra.occurrences.first { $0.id == "person:adaiah_75" }?.profile)
        let neh = try await lookup("NEH", 10, 39)
        XCTAssertFalse(neh.occurrences.contains { $0.id == "person:adaiah_75" })
    }

    func testNehemiahAthaiahKeepsItsOwnIdentityAndFirstVerse() async throws {
        let earlier = try await lookup("NEH", 11, 1)
        XCTAssertFalse(earlier.occurrences.contains { $0.id == "person:athaiah_358" })
        let current = try await lookup("NEH", 11, 4)
        let adaiah = try XCTUnwrap(current.occurrences.first { $0.id == "person:athaiah_358" }?.profile)
        XCTAssertEqual(adaiah.profile.knownBy, Verse(chapter: 11, verse: 4))
        XCTAssertNil(adaiah.wikipedia)
        XCTAssertTrue(adaiah.sources.contains { $0.url.hasSuffix("NEH11.htm#V4") && $0.license == "Public Domain" })
        XCTAssertFalse(current.occurrences.contains { $0.id == "person:adaiah_75" })
        let ezra = try await lookup("EZR", 10, 39)
        XCTAssertFalse(ezra.occurrences.contains { $0.id == "person:athaiah_358" })
    }

    func testHeldElnathanIdentityIsAbsentAtTheAmbiguousThreeNameVerse() async throws {
        let result = try await lookup("EZR", 8, 16)
        XCTAssertFalse(result.occurrences.contains { $0.id == "person:elnathan_1180" })
    }
    func testHaggaiFutureFactAndSourceStayHiddenUntilTheirOwnVerse() async throws {
        let first = try await lookup("EZR", 5, 1)
        let initial = try XCTUnwrap(first.occurrences.first { $0.id == "person:haggai_1349" }?.profile)
        XCTAssertTrue(initial.facts.isEmpty)
        XCTAssertFalse(initial.sources.contains { $0.url.hasSuffix("EZR06.htm#V14") })
        let later = try await BundledEntityIndex.shared.lookup(passage("EZR", 5, 1, 6, 14), kind: "person")
        let revealed = try XCTUnwrap(later.occurrences.first { $0.id == "person:haggai_1349" }?.profile)
        XCTAssertTrue(revealed.facts.contains { $0.knownBy == Verse(chapter: 6, verse: 14) })
        XCTAssertTrue(revealed.sources.contains { $0.url.hasSuffix("EZR06.htm#V14") && $0.license == "Public Domain" })
    }

    func testUnresolvedHashabiahDoesNotMergeTwoNarrativeRoles() async throws {
        for verse in [19, 24] {
            let result = try await lookup("EZR", 8, verse)
            XCTAssertFalse(result.occurrences.contains { $0.id == "person:hashabiah_1434" })
        }
    }

    func testAijaHasPrimaryAttributionAndNoInventedModernCoordinates() async throws {
        let result = try await lookup("NEH", 11, 31, "place")
        let aija = try XCTUnwrap(result.occurrences.first { $0.id == "place:aija_39" }?.profile)
        XCTAssertNil(aija.profile.coordinate)
        XCTAssertNil(aija.wikipedia)
        XCTAssertTrue(aija.sources.contains { $0.url.hasSuffix("NEH11.htm#V31") && $0.license == "Public Domain" })
        XCTAssertTrue(aija.sources.allSatisfy { $0.safeURL != nil })
    }

    func testHezekiahListNameKeepsUnidentifiedScopeAndSeparateKingID() async throws {
        let result = try await lookup("EZR", 2, 16)
        let name = try XCTUnwrap(result.occurrences.first { $0.id == "person:hezekiah_1514" }?.profile)
        XCTAssertEqual(name.profile.identityType, "unidentified-eponym")
        XCTAssertFalse(name.profile.identityNoteJa.isEmpty)
        XCTAssertFalse(result.occurrences.contains { $0.id == "person:hezekiah_1512" })
        XCTAssertNil(name.wikipedia)
        XCTAssertTrue(name.sources.contains { $0.url.hasSuffix("EZR02.htm#V16") && $0.license == "Public Domain" })
    }


    func testFourMaaseiahListEntriesKeepSeparateIdentities() async throws {
        let members = [(18, "person:maaseiah_1854"), (21, "person:maaseiah_1855"), (22, "person:maaseiah_1856"), (30, "person:maaseiah_1857")]
        for (verse, id) in members {
            let result = try await lookup("EZR", 10, verse)
            XCTAssertNotNil(result.occurrences.first { $0.id == id }?.profile)
            for (_, other) in members where other != id {
                XCTAssertFalse(result.occurrences.contains { $0.id == other })
            }
        }
    }

    func testMosesAttributedLawKeepsContextAndOwnFactSourceGates() async throws {
        let first = try await lookup("EZR", 3, 2)
        let occurrence = try XCTUnwrap(first.occurrences.first { $0.id == "person:moses_2108" })
        XCTAssertFalse(occurrence.directlyNamed)
        let initial = try XCTUnwrap(occurrence.profile)
        XCTAssertTrue(initial.facts.isEmpty)
        XCTAssertFalse(initial.sources.contains { $0.url.hasSuffix("EZR06.htm#V18") || $0.url.hasSuffix("EZR07.htm#V6") })
        let middle = try await lookup("EZR", 6, 18)
        let middleOccurrence = try XCTUnwrap(middle.occurrences.first { $0.id == "person:moses_2108" })
        XCTAssertFalse(middleOccurrence.directlyNamed)
        let middleProfile = try XCTUnwrap(middleOccurrence.profile)
        XCTAssertTrue(middleProfile.facts.contains { $0.knownBy == Verse(chapter: 6, verse: 18) })
        XCTAssertFalse(middleProfile.sources.contains { $0.url.hasSuffix("EZR07.htm#V6") })
        let range = try await BundledEntityIndex.shared.lookup(passage("EZR", 3, 2, 7, 6), kind: "person")
        let revealed = try XCTUnwrap(range.occurrences.first { $0.id == "person:moses_2108" }?.profile)
        XCTAssertEqual(revealed.facts.count, 2)
        XCTAssertTrue(revealed.sources.contains { $0.url.hasSuffix("EZR07.htm#V6") })
    }

    func testDavidLaterWorshipSourcesStayHiddenAtCityReference() async throws {
        let first = try await lookup("NEH", 3, 15)
        let occurrence = try XCTUnwrap(first.occurrences.first { $0.id == "person:david_994" })
        XCTAssertFalse(occurrence.directlyNamed)
        let initial = try XCTUnwrap(occurrence.profile)
        XCTAssertTrue(initial.facts.isEmpty)
        XCTAssertFalse(initial.sources.contains { $0.url.contains("NEH12.htm") })
        let range = try await BundledEntityIndex.shared.lookup(passage("NEH", 3, 15, 12, 46), kind: "person")
        let revealed = try XCTUnwrap(range.occurrences.first { $0.id == "person:david_994" }?.profile)
        XCTAssertTrue(revealed.facts.contains { $0.knownBy == Verse(chapter: 12, verse: 46) })
        XCTAssertTrue(revealed.sources.contains { $0.url.hasSuffix("NEH12.htm#V46") })
    }

    func testFamilyLabelsKeepUnidentifiedScopeAndContext() async throws {
        let labels = [("EZR", 2, 44, "person:keros_1781"), ("EZR", 2, 45, "person:lebanah_1814"), ("EZR", 2, 52, "person:mehida_1981"), ("NEH", 7, 58, "person:darkon_981"), ("NEH", 7, 62, "person:delaiah_1002"), ("NEH", 7, 12, "person:elam_1052"), ("NEH", 7, 63, "person:habaiah_1333"), ("NEH", 7, 53, "person:harhur_1415")]
        for (book, chapter, verse, id) in labels {
            let result = try await lookup(book, chapter, verse)
            let occurrence = try XCTUnwrap(result.occurrences.first { $0.id == id })
            XCTAssertFalse(occurrence.directlyNamed)
            let profile = try XCTUnwrap(occurrence.profile)
            XCTAssertEqual(profile.profile.identityType, "unidentified-eponym")
            XCTAssertNil(profile.wikipedia)
        }
    }

    func testDariusReignReferenceIsContext() async throws {
        let result = try await lookup("NEH", 12, 22)
        let occurrence = try XCTUnwrap(result.occurrences.first { $0.id == "person:darius_979" })
        XCTAssertFalse(occurrence.directlyNamed)
        XCTAssertNotNil(occurrence.profile)
    }

    func testJozadakFatherMentionsResolveOnceAsContextWithLaterSourcesGated() async throws {
        let before = try await lookup("EZR", 3, 1)
        XCTAssertFalse(before.occurrences.contains { ["person:josedech_815", "person:jozadak_1747"].contains($0.id) })
        for (chapter, verse) in [(3, 2), (3, 8), (5, 2), (10, 18)] {
            let result = try await lookup("EZR", chapter, verse)
            let canonical = result.occurrences.filter { $0.id == "person:jozadak_1747" }
            XCTAssertEqual(canonical.count, 1)
            XCTAssertFalse(try XCTUnwrap(canonical.first).directlyNamed)
            XCTAssertFalse(result.occurrences.contains { $0.id == "person:josedech_815" })
        }
        let first = try await lookup("EZR", 3, 2)
        let initial = try XCTUnwrap(first.occurrences.first { $0.id == "person:jozadak_1747" }?.profile)
        XCTAssertTrue(initial.facts.isEmpty)
        XCTAssertEqual(initial.sources.count, 1)
        XCTAssertTrue(initial.sources.allSatisfy { $0.url.hasSuffix("EZR03.htm#V2") })
        let range = try await BundledEntityIndex.shared.lookup(passage("EZR", 3, 2, 10, 18), kind: "person")
        let resolved = try XCTUnwrap(range.occurrences.first { $0.id == "person:jozadak_1747" }?.profile)
        XCTAssertEqual(resolved.facts.count, 3)
        XCTAssertEqual(resolved.sources.count, 4)
    }

    func testHachaliahFatherReferencesStayContextAndLaterSourceIsGated() async throws {
        for (chapter, verse) in [(1, 1), (10, 1)] {
            let result = try await lookup("NEH", chapter, verse)
            let father = try XCTUnwrap(result.occurrences.first { $0.id == "person:hachaliah_1336" })
            XCTAssertFalse(father.directlyNamed)
            XCTAssertNotNil(father.profile)
        }
        let first = try await lookup("NEH", 1, 1)
        let initial = try XCTUnwrap(first.occurrences.first { $0.id == "person:hachaliah_1336" }?.profile)
        XCTAssertTrue(initial.facts.isEmpty)
        XCTAssertFalse(initial.sources.contains { $0.url.hasSuffix("NEH10.htm#V1") })
    }

    func testIddoUnusedLaterSourceDoesNotAppearOrResolveAsSamePerson() async throws {
        let first = try await lookup("NEH", 12, 4)
        let initial = try XCTUnwrap(first.occurrences.first { $0.id == "person:iddo_1597" }?.profile)
        XCTAssertTrue(initial.sources.contains { $0.url.hasSuffix("NEH12.htm#V4") })
        XCTAssertFalse(initial.sources.contains { $0.url.hasSuffix("NEH12.htm#V16") })
        let later = try await lookup("NEH", 12, 16)
        XCTAssertFalse(later.occurrences.contains { $0.id == "person:iddo_1597" })
    }

    func testJoiadaLineageProfileGatesLaterPriestTitleAndUnresolvedTemporalMention() async throws {
        let first = try await lookup("NEH", 12, 10)
        let occurrence = try XCTUnwrap(first.occurrences.first { $0.id == "person:joiada_1680" })
        XCTAssertFalse(occurrence.directlyNamed)
        let initial = try XCTUnwrap(occurrence.profile)
        XCTAssertEqual(initial.profile.historicalRoleJa, "系譜に記されるエリアシブの子。")
        XCTAssertTrue(initial.facts.isEmpty)
        XCTAssertFalse(initial.sources.contains { $0.url.hasSuffix("NEH13.htm#V28") })
        let unresolved = try await lookup("NEH", 12, 22)
        XCTAssertFalse(unresolved.occurrences.contains { $0.id == "person:joiada_1680" })
        let later = try await lookup("NEH", 13, 28)
        let revealed = try XCTUnwrap(later.occurrences.first { $0.id == "person:joiada_1680" }?.profile)
        XCTAssertTrue(revealed.facts.contains { $0.knownBy == Verse(chapter: 13, verse: 28) })
        XCTAssertTrue(revealed.sources.contains { $0.url.hasSuffix("NEH13.htm#V28") })
    }

    func testMeremothLineageAndLaterRepairStayBehindTheirOwnGates() async throws {
        let first = try await lookup("NEH", 3, 4)
        let occurrence = try XCTUnwrap(first.occurrences.first { $0.id == "person:meremoth_2006" })
        XCTAssertTrue(occurrence.directlyNamed)
        let initial = try XCTUnwrap(occurrence.profile)
        XCTAssertTrue(initial.profile.summaryJa.contains("ウリヤの子"))
        XCTAssertTrue(initial.profile.summaryJa.contains("ハッコツの孫"))
        XCTAssertFalse(initial.profile.summaryJa.contains("3:21"))
        XCTAssertFalse(initial.profile.historicalRoleJa?.contains("複数箇所") ?? false)
        XCTAssertTrue(initial.facts.isEmpty)
        XCTAssertFalse(initial.sources.contains { $0.url.hasSuffix("NEH03.htm#V21") })
        let later = try await lookup("NEH", 3, 21)
        let revealed = try XCTUnwrap(later.occurrences.first { $0.id == "person:meremoth_2006" }?.profile)
        XCTAssertTrue(revealed.facts.contains { $0.knownBy == Verse(chapter: 3, verse: 21) })
        XCTAssertTrue(revealed.sources.contains { $0.url.hasSuffix("NEH03.htm#V21") })
        let unresolved = try await lookup("NEH", 10, 5)
        XCTAssertFalse(unresolved.occurrences.contains { $0.id == "person:meremoth_2006" })
    }

    func testPriestFamilyLabelsAndChiefEntryUseFreshPrimaryRelationships() async throws {
        let families = try await lookup("NEH", 12, 17)
        for id in ["person:miniamin_2077", "person:moadiah_1874"] {
            let occurrence = try XCTUnwrap(families.occurrences.first { $0.id == id })
            XCTAssertFalse(occurrence.directlyNamed)
            let resolved = try XCTUnwrap(occurrence.profile)
            XCTAssertEqual(resolved.profile.identityType, "unidentified-eponym")
            XCTAssertEqual(resolved.profile.detailLinkLabelJa, "この名前について")
            XCTAssertTrue(resolved.facts.isEmpty)
            XCTAssertTrue(resolved.sources.contains { $0.url.hasSuffix("NEH12.htm#V17") })
        }
        let chiefs = try await lookup("NEH", 10, 20)
        let meshullam = try XCTUnwrap(chiefs.occurrences.first { $0.id == "person:meshullam_2035" })
        XCTAssertTrue(meshullam.directlyNamed)
        XCTAssertNotNil(meshullam.profile)
    }

    func testSanballat2470ShowsFirstAppearanceAndRevealsGatedFactsByVerse() async throws {
        let first = try await lookup("NEH", 2, 10)
        let occurrence = try XCTUnwrap(first.occurrences.first { $0.id == "person:sanballat_2470" })
        XCTAssertTrue(occurrence.directlyNamed)
        let initial = try XCTUnwrap(occurrence.profile)
        XCTAssertEqual(initial.profile.knownBy, Verse(chapter: 2, verse: 10))
        XCTAssertEqual(initial.profile.sourceIds, ["webp-neh-batch12-author3-sanballat_2470-2-10"])
        XCTAssertTrue(initial.facts.isEmpty)
        XCTAssertTrue(initial.sources.contains {
            $0.id == "webp-neh-batch12-author3-sanballat_2470-2-10" &&
            $0.url.hasSuffix("NEH02.htm#V10") && $0.license == "Public Domain" && $0.safeURL != nil
        })
        XCTAssertFalse(initial.sources.contains { $0.url.hasSuffix("NEH02.htm#V19") || $0.url.hasSuffix("NEH13.htm#V28") })

        let second = try await lookup("NEH", 2, 19)
        let secondProfile = try XCTUnwrap(second.occurrences.first { $0.id == "person:sanballat_2470" }?.profile)
        let wallReportFact = try XCTUnwrap(secondProfile.facts.first { $0.knownBy == Verse(chapter: 2, verse: 19) })
        XCTAssertTrue(wallReportFact.textJa.contains("城壁再建"))
        XCTAssertTrue(wallReportFact.sourceIds.contains("webp-neh-batch12-author3-sanballat_2470-2-19"))
        XCTAssertTrue(secondProfile.sources.contains {
            $0.id == "webp-neh-batch12-author3-sanballat_2470-2-19" &&
            $0.url.hasSuffix("NEH02.htm#V19") && $0.license == "Public Domain"
        })
        XCTAssertFalse(secondProfile.facts.contains { $0.knownBy == Verse(chapter: 13, verse: 28) })
        XCTAssertFalse(secondProfile.sources.contains { $0.url.hasSuffix("NEH13.htm#V28") })

        let last = try await lookup("NEH", 13, 28)
        let lastProfile = try XCTUnwrap(last.occurrences.first { $0.id == "person:sanballat_2470" }?.profile)
        let familyFact = try XCTUnwrap(lastProfile.facts.first { $0.knownBy == Verse(chapter: 13, verse: 28) })
        XCTAssertTrue(familyFact.textJa.contains("婿"))
        XCTAssertTrue(familyFact.sourceIds.contains("webp-neh-batch12-author3-sanballat_2470-13-28"))
        XCTAssertTrue(lastProfile.sources.contains {
            $0.id == "webp-neh-batch12-author3-sanballat_2470-13-28" &&
            $0.url.hasSuffix("NEH13.htm#V28") && $0.license == "Public Domain"
        })
    }

}
