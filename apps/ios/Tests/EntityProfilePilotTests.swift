import XCTest
@testable import CompanionCore
@MainActor final class EntityProfilePilotTests: XCTestCase {
    let full = Passage(book: "ACT", start: Verse(chapter: 18, verse: 24), end: Verse(chapter: 19, verse: 7))
    func testActualScopeHasProfilesAndDistinctJohnIdentity() async throws {
        let people = try await BundledEntityIndex.shared.lookup(full, kind: "person")
        XCTAssertEqual(people.occurrences.count, 9)
        XCTAssertTrue(people.occurrences.allSatisfy { $0.profile != nil })
        XCTAssertTrue(people.occurrences.contains { $0.id == "person:john_1676" && $0.profile!.profile.identityNoteJa.contains("洗礼者") })
        XCTAssertFalse(people.occurrences.contains { $0.id == "person:john_1677" })
        for item in people.occurrences {
            XCTAssertFalse(item.profile!.sources.isEmpty)
            XCTAssertTrue(item.profile!.sources.allSatisfy { $0.safeURL != nil && !$0.attribution.isEmpty && !$0.license.isEmpty })
        }
    }
    func testSpoilerFactsRespectSelectedEndAndExplicitReveal() async throws {
        let early = Passage(book: "ACT", start: Verse(chapter: 18, verse: 24), end: Verse(chapter: 18, verse: 24))
        let hidden = try await BundledEntityIndex.shared.lookup(early, kind: "person")
        let shown = try await BundledEntityIndex.shared.lookup(early, kind: "person", includeFuture: true)
        XCTAssertTrue(hidden.occurrences.first { $0.id == "person:apollos_276" }!.profile!.facts.isEmpty)
        XCTAssertFalse(shown.occurrences.first { $0.id == "person:apollos_276" }!.profile!.facts.isEmpty)
        let first = Passage(book: "ACT", start: Verse(chapter: 19, verse: 1), end: Verse(chapter: 19, verse: 1))
        let group = try await BundledEntityIndex.shared.lookup(first, kind: "person")
        XCTAssertTrue(group.occurrences.first { $0.id == "person-disciples-act19" }!.profile!.facts.isEmpty)
        let completed = try await BundledEntityIndex.shared.lookup(full, kind: "person")
        XCTAssertFalse(completed.occurrences.first { $0.id == "person-disciples-act19" }!.profile!.facts.isEmpty)
    }
    func testProvinceIsNotRenderedAsCityAndLocationsRemainPersistent() async throws {
        let places = try await BundledEntityIndex.shared.lookup(full, kind: "place")
        XCTAssertEqual(places.occurrences.count, 4)
        XCTAssertTrue(places.occurrences.allSatisfy { $0.profile?.profile.modernLocationJa != nil && $0.profile?.profile.historicalRoleJa != nil })
        XCTAssertNil(places.occurrences.first { $0.id == "place:achaia_16" }!.entity.coordinate)
        XCTAssertEqual(places.occurrences.filter { $0.entity.coordinate != nil }.count, 3)
        let outside = try await BundledEntityIndex.shared.lookup(Passage(book: "ACT", start: Verse(chapter: 23, verse: 1), end: Verse(chapter: 23, verse: 1)), kind: "person")
        XCTAssertTrue(outside.occurrences.allSatisfy { $0.profile == nil })
    }
    func testExistingMaterialCardsResolveToProfilesWithoutChangingSpoilerBoundary() async throws {
        let early = Passage(book: "ACT", start: Verse(chapter: 18, verse: 24), end: Verse(chapter: 18, verse: 24))
        let apollos = try await BundledEntityIndex.shared.profile(forMaterialCardID: "person-apollos-act18-introduction", passage: early)
        XCTAssertEqual(apollos?.profile.id, "person:apollos_276")
        XCTAssertTrue(apollos?.facts.isEmpty == true)
        let corinth = try await BundledEntityIndex.shared.profile(forMaterialCardID: "place-corinth", passage: full)
        XCTAssertEqual(corinth?.profile.id, "place:corinth_306")
        let unlinked = try await BundledEntityIndex.shared.profile(forMaterialCardID: "person-sosthenes-act18", passage: full)
        XCTAssertNil(unlinked)
    }

    func testWikipediaReadingLinksKeepIdentityAndPrimarySourcesSeparate() async throws {
        let people = try await BundledEntityIndex.shared.lookup(full, kind: "person")
        let places = try await BundledEntityIndex.shared.lookup(full, kind: "place")
        let all = people.occurrences + places.occurrences
        XCTAssertEqual(all.count, 13)
        for item in all {
            let profile = try XCTUnwrap(item.profile)
            XCTAssertNotNil(profile.profile.wikipedia?.safeURL)
            XCTAssertTrue(profile.sources.allSatisfy { $0.safeURL?.host?.hasSuffix("wikipedia.org") != true })
        }
        let john = people.occurrences.first { $0.id == "person:john_1676" }!.profile!.profile.wikipedia!
        XCTAssertEqual(john.safeURL?.path, "/wiki/洗礼者ヨハネ")
        let corinth = places.occurrences.first { $0.id == "place:corinth_306" }!.profile!.profile.wikipedia!
        XCTAssertEqual(corinth.safeURL?.path, "/wiki/古代コリントス")
        let group = people.occurrences.first { $0.id == "person-disciples-act19" }!.profile!.profile.wikipedia!
        XCTAssertEqual(group.kind, "related-section")
        XCTAssertEqual(group.safeURL?.fragment, "Verse_1")
        XCTAssertTrue(group.labelJa.contains("関連節"))
        let aquila = people.occurrences.first { $0.id == "person:aquila_279" }!.profile!.profile.wikipedia!
        let priscilla = people.occurrences.first { $0.id == "person:priscilla_2370" }!.profile!.profile.wikipedia!
        XCTAssertEqual(aquila.safeURL?.path, priscilla.safeURL?.path)
        XCTAssertNotEqual(aquila.safeURL?.fragment, priscilla.safeURL?.fragment)
    }
    func testWikipediaLinkRejectsUnverifiedAndNonArticleDestinations() {
        func link(_ url: String, verified: Bool = true) -> WikipediaReadingLink {
            WikipediaReadingLink(title: "検証用", language: "ja", url: url, kind: "article", noteJa: "", checkedAt: "2026-10-15", identityVerified: verified)
        }
        XCTAssertNil(link("https://ja.wikipedia.org/wiki/洗礼者ヨハネ", verified: false).safeURL)
        XCTAssertNil(link("https://ja.wikipedia.org.evil.example/wiki/洗礼者ヨハネ").safeURL)
        XCTAssertNil(link("https://ja.wikipedia.org/wiki/洗礼者ヨハネ?action=edit").safeURL)
        XCTAssertNil(link("https://ja.wikipedia.org/wiki/Special:Search").safeURL)
    }

}
