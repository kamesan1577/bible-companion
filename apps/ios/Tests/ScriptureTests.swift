import XCTest
@testable import CompanionCore

final class ScriptureTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: Self.self)
        #endif
        return try Data(contentsOf: XCTUnwrap(bundle.url(forResource: name, withExtension: "json")))
    }
    private func page(_ edit: ((inout [String: Any]) -> Void)? = nil) throws -> ScripturePage {
        var value = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("scripture-page")) as? [String: Any])
        edit?(&value)
        return try JSONDecoder().decode(ScripturePage.self, from: JSONSerialization.data(withJSONObject: value))
    }
    func testActualEnglishPrimaryPageAndUnavailableAreDistinct() throws {
        let value = try page(); try value.validate(expected: value.passage)
        XCTAssertTrue(value.available); XCTAssertEqual(value.items.count, 3); XCTAssertEqual(value.corpus?.language, "en")
        let absent = try JSONDecoder().decode(ScripturePage.self, from: fixture("scripture-unavailable"))
        try absent.validate(expected: value.passage); XCTAssertFalse(absent.available); XCTAssertNil(absent.corpus)
    }
    func testRejectsWrongScopeAndUnverifiedCorpusMetadata() throws {
        let value = try page()
        XCTAssertThrowsError(try value.validate(expected: Passage(book: "ACT", start: Verse(chapter: 1, verse: 1), end: Verse(chapter: 1, verse: 3))))
        for key in ["license", "language", "referenceAlignment", "editorialReview", "manifestSha256"] {
            let invalid = try page { object in var corpus = object["corpus"] as! [String: Any]; corpus[key] = "unknown"; object["corpus"] = corpus }
            XCTAssertThrowsError(try invalid.validate(expected: value.passage))
        }
    }
    func testPolicyChangeAndCursorLoopAreRejected() throws {
        let value = try page()
        let changed = try page { $0["sourcePolicyVersion"] = 999 }
        XCTAssertThrowsError(try changed.validate(expected: value.passage, previous: value))
        let looping = try page { $0["nextCursor"] = "same" }
        XCTAssertThrowsError(try looping.validate(expected: value.passage, requestedCursor: "same"))
    }
    func testUnmappedOmissionsAreVisibleButNeverReplaceText() throws {
        let value = try page { object in
            var items = object["items"] as! [[String: Any]]; items.removeLast(); object["items"] = items
            object["omissions"] = [["chapter": 1, "verse": 3, "reason": "source_reference_missing"]]
        }
        try value.validate(expected: value.passage); XCTAssertEqual(value.items.count, 2); XCTAssertEqual(value.omissions.count, 1)
        let conflict = try page { $0["omissions"] = [["chapter": 1, "verse": 1, "reason": "source_text_empty"]] }
        XCTAssertThrowsError(try conflict.validate(expected: value.passage))
    }
    func testOversizedOrDuplicateBodiesAreRejected() throws {
        let duplicate = try page { object in let items = object["items"] as! [[String: Any]]; object["items"] = [items[0], items[0]] }
        XCTAssertThrowsError(try duplicate.validate(expected: duplicate.passage))
        let huge = try page { object in var items = object["items"] as! [[String: Any]]; items[0]["text"] = String(repeating: "x", count: 140_000); object["items"] = items }
        XCTAssertThrowsError(try huge.validate(expected: huge.passage))
    }
    func testThreePageNavigationCanGoBackThenForward() throws {
        var history = ScriptureCursorHistory()
        XCTAssertNil(history.previous); XCTAssertNil(history.next(cursor: "one"))
        try history.accept(cursor: nil, destination: 0, nextCursor: "one")
        let second = try XCTUnwrap(history.next(cursor: "one"))
        try history.accept(cursor: second.cursor, destination: second.destination, nextCursor: "two")
        let third = try XCTUnwrap(history.next(cursor: "two"))
        try history.accept(cursor: third.cursor, destination: third.destination, nextCursor: nil)
        XCTAssertEqual(history.pageNumber, 3)
        let back = try XCTUnwrap(history.previous); XCTAssertEqual(back.cursor, "one")
        try history.accept(cursor: back.cursor, destination: back.destination, nextCursor: "two")
        XCTAssertEqual(history.pageNumber, 2)
        let forward = try XCTUnwrap(history.next(cursor: "two"))
        try history.accept(cursor: forward.cursor, destination: forward.destination, nextCursor: nil)
        XCTAssertEqual(history.pageNumber, 3)
        XCTAssertThrowsError(try history.accept(cursor: "two", destination: 2, nextCursor: "one"))
        history.clear(); XCTAssertNil(history.previous); XCTAssertEqual(history.pageNumber, 0)
    }
    func testBackwardNavigationStillRejectsChangedCorpus() throws {
        let prior = try page { $0["nextCursor"] = "later" }
        let changed = try page { object in var corpus = object["corpus"] as! [String: Any]; corpus["version"] = "new-version"; object["corpus"] = corpus }
        XCTAssertThrowsError(try changed.validate(expected: prior.passage, previous: prior, requestedCursor: nil))
    }
    func testPrimaryOverviewIsNotGrantedOfflineStorage() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("reading-primary-text")) as? [String: Any])
        var grant = object["offlineCache"] as! [String: Any]; grant["eligible"] = true; grant["maxAgeSeconds"] = 86400; object["offlineCache"] = grant
        let value = try JSONDecoder().decode(ReadingResponse.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(value.overview.contentKind, "literal-primary-text"); XCTAssertNotNil(value.overview.noticeJa)
        XCTAssertThrowsError(try PublicReadingSnapshot(response: value, fetchedAt: Date(timeIntervalSince1970: value.checkedAt!)))
    }
}
