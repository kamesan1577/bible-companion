import XCTest
@testable import CompanionCore

@MainActor final class RomLeviticusEntityTests: XCTestCase {
    private func verse(_ book: String, _ chapter: Int, _ verse: Int) -> Passage {
        Passage(book: book, start: Verse(chapter: chapter, verse: verse), end: Verse(chapter: chapter, verse: verse))
    }

    func testFutureToggleExplicitlyRevealsLaterAdamName() async throws {
        let selected = verse("ROM", 5, 12)
        let hidden = try await BundledEntityIndex.shared.lookup(selected, kind: "person")
        let visible = try await BundledEntityIndex.shared.lookup(selected, kind: "person", includeFuture: true)
        let early = try XCTUnwrap(hidden.occurrences.first { $0.id == "person:adam_78" }?.profile)
        let later = try XCTUnwrap(visible.occurrences.first { $0.id == "person:adam_78" }?.profile)
        XCTAssertNotEqual(early.nameJa, "アダム")
        XCTAssertEqual(later.nameJa, "アダム")
        XCTAssertTrue(early.sources.allSatisfy { $0.knownBy == nil || $0.knownBy! <= selected.end })
    }

    func testRelatedWikipediaRequiresVerifiedRelationAndHonestNote() {
        func link(_ kind: String, _ relation: Bool?, _ note: String) -> WikipediaReadingLink {
            WikipediaReadingLink(title: "関連資料", language: "en", url: "https://en.wikipedia.org/wiki/Apelles", kind: kind, noteJa: note, checkedAt: "2026-10-15", identityVerified: false, relationVerified: relation)
        }
        XCTAssertNotNil(link("related-section", true, "同名の伝承との関連資料。本人の同定は未確定です。").safeURL)
        XCTAssertNil(link("article", true, "同一人物は未確定。").safeURL)
        XCTAssertNil(link("related-section", false, "関係未確認。").safeURL)
        XCTAssertNil(link("related-section", true, "").safeURL)
    }

    func testAlternatingActsRomansLeviticusLookupsKeepBookCatalogsIsolated() async throws {
        let index = BundledEntityIndex.shared

        // ACT 1:3 mentions God's Kingdom; ROM 1:1 calls it God's Good News;
        // LEV 1:1 says the LORD called Moses from the Tent of Meeting. Same
        // stable ID, but each book must resolve its own profile and citation.
        let acts = try await index.lookup(verse("ACT", 1, 3), kind: "person")
        let actsGod = try XCTUnwrap(acts.occurrences.first { $0.id == "person:god_1324" }?.profile)
        XCTAssertTrue(actsGod.profile.summaryJa.contains("使徒言行録1:3"))
        XCTAssertTrue(actsGod.sources.contains { $0.id == "person-god_1324-web-act-1-3" })

        let romans = try await index.lookup(verse("ROM", 1, 1), kind: "person")
        let romansGod = try XCTUnwrap(romans.occurrences.first { $0.id == "person:god_1324" }?.profile)
        XCTAssertTrue(romansGod.profile.summaryJa.contains("神の福音"))
        XCTAssertTrue(romansGod.sources.contains { $0.id.contains("webp-rom-01-01") })

        let leviticus = try await index.lookup(verse("LEV", 1, 1), kind: "person")
        let leviticusGod = try XCTUnwrap(leviticus.occurrences.first { $0.id == "person:god_1324" }?.profile)
        XCTAssertTrue(leviticusGod.profile.summaryJa.contains("会見の幕屋"))
        XCTAssertTrue(leviticusGod.sources.contains { $0.id.contains("webp-lev-1-1") })

        let actsAgain = try await index.lookup(verse("ACT", 1, 3), kind: "person")
        let actsGodAgain = try XCTUnwrap(actsAgain.occurrences.first { $0.id == "person:god_1324" }?.profile)
        XCTAssertEqual(actsGodAgain.profile.summaryJa, actsGod.profile.summaryJa)
        XCTAssertTrue(actsGodAgain.sources.contains { $0.id == "person-god_1324-web-act-1-3" })
    }

    func testIsraelCollectiveAndJacobContextAreSeparatedInRomansAndLeviticus() async throws {
        let index = BundledEntityIndex.shared

        // ROM 9:6: “they are not all Israel”; ROM 9:13 quotes Jacob and Esau.
        let romIsrael = try await index.lookup(verse("ROM", 9, 6), kind: "person")
        let romGroup = try XCTUnwrap(romIsrael.occurrences.first { $0.id == "person:israel_682" }?.profile)
        XCTAssertEqual(romGroup.profile.identityType, "collective")
        XCTAssertEqual(romGroup.nameJa, "イスラエルの民")
        XCTAssertTrue(romGroup.contextNotes.isEmpty)

        let romJacob = try await index.lookup(verse("ROM", 9, 13), kind: "person")
        let romPatriarch = try XCTUnwrap(romJacob.occurrences.first { $0.id == "person:israel_682" }?.profile)
        XCTAssertEqual(romPatriarch.nameJa, "ヤコブ")
        XCTAssertTrue(romJacob.occurrences.first { $0.id == "person:israel_682" }!.sameBookVerses.isEmpty)

        // A selected range containing both references keeps the collective as
        // the base profile while exposing Jacob in the contextual note.
        let romRange = Passage(book: "ROM", start: Verse(chapter: 9, verse: 4), end: Verse(chapter: 9, verse: 13))
        let rangedROM = try await index.lookup(romRange, kind: "person")
        let rangedIsrael = try XCTUnwrap(rangedROM.occurrences.first { $0.id == "person:israel_682" }?.profile)
        XCTAssertEqual(rangedIsrael.profile.identityType, "collective")
        XCTAssertEqual(rangedIsrael.nameJa, "イスラエルの民")
        XCTAssertTrue(rangedIsrael.contextNotes.contains { $0.hasPrefix("ヤコブ：") })

        // LEV 1:2 addresses Israel collectively; LEV 26:42 names Jacob as a
        // covenant partner. Neither reference should overwrite the other.
        let levIsrael = try await index.lookup(verse("LEV", 1, 2), kind: "person")
        let levGroup = try XCTUnwrap(levIsrael.occurrences.first { $0.id == "person:israel_682" }?.profile)
        XCTAssertEqual(levGroup.profile.identityType, "collective")
        XCTAssertEqual(levGroup.nameJa, "イスラエルの民")
        XCTAssertFalse(levGroup.profile.identityNoteJa.contains("ヤコブ"))
        XCTAssertFalse(levGroup.wikipedia?.noteJa.contains("ヤコブ") == true)

        let levJacob = try await index.lookup(verse("LEV", 26, 42), kind: "person")
        let levPatriarch = try XCTUnwrap(levJacob.occurrences.first { $0.id == "person:israel_682" }?.profile)
        XCTAssertEqual(levPatriarch.nameJa, "ヤコブ")
        XCTAssertTrue(levJacob.occurrences.first { $0.id == "person:israel_682" }!.sameBookVerses.isEmpty)
        // A wider selection with only the individual use must not invent a
        // collective occurrence merely because that ID is shared.
        for (book, chapter, first, last) in [("ROM", 9, 12, 13), ("LEV", 26, 41, 42)] {
            let range = Passage(book: book, start: Verse(chapter: chapter, verse: first), end: Verse(chapter: chapter, verse: last))
            let result = try await index.lookup(range, kind: "person")
            let jacob = try XCTUnwrap(result.occurrences.first { $0.id == "person:israel_682" }?.profile)
            XCTAssertEqual(jacob.nameJa, "ヤコブ")
            XCTAssertTrue(jacob.contextNotes.isEmpty)
        }


        let levRange = Passage(book: "LEV", start: Verse(chapter: 1, verse: 2), end: Verse(chapter: 26, verse: 42))
        let rangedLEV = try await index.lookup(levRange, kind: "person")
        let rangedLEVIsrael = try XCTUnwrap(rangedLEV.occurrences.first { $0.id == "person:israel_682" }?.profile)
        XCTAssertEqual(rangedLEVIsrael.nameJa, "イスラエルの民")
        XCTAssertTrue(rangedLEVIsrael.contextNotes.contains { $0.hasPrefix("ヤコブ：") })
    }

    func testHolySpiritDoesNotAppearBeforeRomansReferenceAndGatesFutureMaterial() async throws {
        let index = BundledEntityIndex.shared

        // ROM 1:4 says “Spirit of holiness”; the current entity mapping reserves
        // the Holy Spirit profile for the explicit reference in ROM 5:5.
        let before = try await index.lookup(verse("ROM", 1, 4), kind: "person")
        XCTAssertFalse(before.occurrences.contains { $0.id == "person:holy_spirit_7400" })

        let first = try await index.lookup(verse("ROM", 5, 5), kind: "person")
        let spirit = try XCTUnwrap(first.occurrences.first { $0.id == "person:holy_spirit_7400" }?.profile)
        XCTAssertEqual(spirit.profile.knownBy, Verse(chapter: 5, verse: 5))
        XCTAssertTrue(spirit.facts.isEmpty, "Facts from Romans 8 and later must remain gated at 5:5")
        XCTAssertTrue(spirit.sources.allSatisfy { $0.knownBy == nil || $0.knownBy! <= Verse(chapter: 5, verse: 5) })
        XCTAssertNotNil(spirit.wikipedia)
        if let wikipedia = spirit.wikipedia, let gate = wikipedia.knownBy {
            XCTAssertLessThanOrEqual(gate, Verse(chapter: 5, verse: 5))
        }
    }

    func testCanonicalRomansDoxologyUsesTheAlignedWEBSource() async throws {
        // In this pinned WEB witness the conventional ROM 16:25–27 doxology is
        // physically at ROM 14:24–26. The profile links the canonical interval
        // while keeping each source's canonical knownBy and raw WEB URL intact.
        let canonicalDoxology = Passage(book: "ROM", start: Verse(chapter: 16, verse: 25), end: Verse(chapter: 16, verse: 27))
        let result = try await BundledEntityIndex.shared.lookup(canonicalDoxology, kind: "person")
        let god = try XCTUnwrap(result.occurrences.first { $0.id == "person:god_1324" }?.profile)
        let aligned = try XCTUnwrap(god.sources.first { $0.id.contains("webp-rom-16-25") })
        XCTAssertEqual(aligned.knownBy, Verse(chapter: 16, verse: 25))
        XCTAssertTrue(aligned.title.contains("14:24"))
        XCTAssertEqual(aligned.safeURL?.path, "/engwebp/ROM14.htm")
        XCTAssertEqual(aligned.safeURL?.fragment, "V24")
        XCTAssertTrue(god.profile.passages.contains {
            $0.book == "ROM" && $0.start == Verse(chapter: 16, verse: 26) && $0.end == Verse(chapter: 16, verse: 26)
        })
        XCTAssertTrue(god.profile.passages.contains {
            $0.book == "ROM" && $0.start == Verse(chapter: 16, verse: 27) && $0.end == Verse(chapter: 16, verse: 27)
        })
    }

    func testSinaiMountainAndWildernessRemainDistinctAndHolyPlaceIsSpecific() async throws {
        let index = BundledEntityIndex.shared

        // LEV 7:38 explicitly says “in Mount Sinai ... in the wilderness of
        // Sinai”; they have separate IDs in the current catalog.
        let verse738 = try await index.lookup(verse("LEV", 7, 38), kind: "place")
        let mountain = try XCTUnwrap(verse738.occurrences.first { $0.id == "place:mount_sinai_855" })
        let wilderness = try XCTUnwrap(verse738.occurrences.first { $0.id == "place:sinai_1098" })
        XCTAssertNotEqual(mountain.id, wilderness.id)
        XCTAssertEqual(mountain.profile?.profile.knownBy, Verse(chapter: 7, verse: 38))
        XCTAssertNil(mountain.profile?.profile.coordinate)
        XCTAssertEqual(mountain.entity.coordinate, [28.58771, 33.921682])
        XCTAssertNotEqual(mountain.entity.coordinateStatus, "source-representative-point")
        XCTAssertTrue(mountain.candidateMapNote?.contains("未確定") == true)
        XCTAssertNil(wilderness.entity.coordinate)
        XCTAssertNotEqual(mountain.entity.displayName, wilderness.entity.displayName)

        // LEV 16:24 uses the indefinite “a holy place” and is not linked to the
        // specific Holy Place profile; LEV 16:16 names the specific ritual area.
        let generic = try await index.lookup(verse("LEV", 16, 24), kind: "place")
        XCTAssertFalse(generic.occurrences.contains { $0.id == "place:holy_place_574" })
        let specific = try await index.lookup(verse("LEV", 16, 16), kind: "place")
        let holyPlace = try XCTUnwrap(specific.occurrences.first { $0.id == "place:holy_place_574" }?.profile)
        XCTAssertEqual(holyPlace.profile.identityType, "ritual-area")
        XCTAssertEqual(holyPlace.profile.detailLinkLabelJa, "この祭儀上の場所について")
    }

    func testPharaohIsPresentedAsAnOfficeTitle() async throws {
        let result = try await BundledEntityIndex.shared.lookup(verse("ROM", 9, 17), kind: "person")
        let pharaoh = try XCTUnwrap(result.occurrences.first { $0.id == "person:pharaoh_2331" }?.profile)
        XCTAssertEqual(pharaoh.profile.kind, "person")
        XCTAssertEqual(pharaoh.profile.identityType, "office-title")
        XCTAssertEqual(pharaoh.profile.detailLinkLabelJa, "この称号について")
        XCTAssertEqual(pharaoh.nameJa, "ファラオ（称号）")
        XCTAssertTrue(pharaoh.profile.summaryJa.contains("個人名を示しません"))
    }
}
