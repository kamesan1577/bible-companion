import XCTest
@testable import CompanionCore

final class EntitySameVerseContextTests: XCTestCase {
    private func catalog() throws -> EntityProfileCatalog {
        func position(_ verse: Int) -> [String: Int] { ["chapter": 26, "verse": verse] }
        func passage(_ verse: Int) -> [String: Any] { ["book": "NUM", "start": position(verse), "end": position(verse)] }
        func profile(_ name: String, _ summary: String, _ verses: [Int], _ type: String) -> [String: Any] {
            ["id": "person:gilead_1317", "kind": "person", "nameJa": name, "identityType": type,
             "subtitleJa": "本文中の用法", "summaryJa": summary, "identityNoteJa": "", "knownBy": position(29),
             "passages": verses.map(passage), "sourceIds": ["num26-29"], "facts": [], "supplemental": false]
        }
        var individual = profile("ギレアド", "マキルがギレアドの父となったと記されます。", [29], "individual")
        var collective = profile("ギレアド族", "同じ節にギレアド族も列挙されます。", [29, 30], "collective")
        collective["facts"] = [["textJa": "次の節に子孫の氏族名が列挙されます。", "knownBy": position(30), "sourceIds": ["num26-30"]]]
        individual["contextProfiles"] = [collective]
        let data = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "profiles": [individual], "sources": [["id": "num26-29", "title": "Numbers 26:29", "url": "https://ebible.org/engwebp/NUM26.htm#V29", "license": "Public domain", "licenseURL": "https://ebible.org/copyright.htm", "attribution": "World English Bible", "knownBy": position(29)], ["id": "num26-30", "title": "Numbers 26:30", "url": "https://ebible.org/engwebp/NUM26.htm#V30", "license": "Public domain", "licenseURL": "https://ebible.org/copyright.htm", "attribution": "World English Bible", "knownBy": position(30)]]])
        return try JSONDecoder().decode(EntityProfileCatalog.self, from: data)
    }

    func testSameVersePreservesBothAncestorAndClanMeaning() throws {
        let passage = Passage(book: "NUM", start: Verse(chapter: 26, verse: 29), end: Verse(chapter: 26, verse: 29))
        let resolved = try XCTUnwrap(catalog().resolve(id: "person:gilead_1317", passage: passage, includeFuture: false))
        XCTAssertEqual(resolved.nameJa, "ギレアド")
        XCTAssertEqual(resolved.contextNotes.count, 1)
        XCTAssertTrue(resolved.contextNotes[0].hasPrefix("ギレアド族："))
    }

    func testClanOnlyVerseSelectsClanWithoutInventingAncestorUse() throws {
        let passage = Passage(book: "NUM", start: Verse(chapter: 26, verse: 30), end: Verse(chapter: 26, verse: 30))
        let resolved = try XCTUnwrap(catalog().resolve(id: "person:gilead_1317", passage: passage, includeFuture: false))
        XCTAssertEqual(resolved.nameJa, "ギレアド族")
        XCTAssertTrue(resolved.contextNotes.isEmpty)
    }
    func testMixedRangeIncludesContextFactsOnlyAfterTheirSourceVerse() throws {
        let early = Passage(book: "NUM", start: Verse(chapter: 26, verse: 29), end: Verse(chapter: 26, verse: 29))
        let mixed = Passage(book: "NUM", start: Verse(chapter: 26, verse: 29), end: Verse(chapter: 26, verse: 30))
        let first = try XCTUnwrap(catalog().resolve(id: "person:gilead_1317", passage: early, includeFuture: false))
        let later = try XCTUnwrap(catalog().resolve(id: "person:gilead_1317", passage: mixed, includeFuture: false))
        XCTAssertFalse(first.contextNotes.joined().contains("子孫の氏族名"))
        XCTAssertFalse(first.sources.contains { $0.id == "num26-30" })
        XCTAssertTrue(later.contextNotes.joined().contains("子孫の氏族名"))
        XCTAssertTrue(later.sources.contains { $0.id == "num26-30" })
    }

}
