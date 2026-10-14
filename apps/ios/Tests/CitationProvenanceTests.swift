import Foundation
import XCTest
@testable import CompanionCore

final class CitationProvenanceTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: Self.self)
        #endif
        return try Data(contentsOf: XCTUnwrap(bundle.url(forResource: name, withExtension: "json")))
    }
    func testActualMaterialAnswerRetainsEveryReferenceAndAttribution() throws {
        let response = try JSONDecoder().decode(RequestResult.self, from: fixture("material-answer"))
        let citation = try XCTUnwrap(response.result?.citations.first)
        let provenance = try XCTUnwrap(citation.materialProvenance)
        XCTAssertEqual(citation.sourceKind, "commentary"); XCTAssertTrue(citation.kindLabel.contains("聖書本文の引用ではありません"))
        XCTAssertEqual(provenance.kind, "reviewed-material-summary"); XCTAssertEqual(provenance.materialId, "place-cenchreae")
        XCTAssertEqual(provenance.references.count, 4)
        let pleiades = try XCTUnwrap(provenance.references.first { $0.license == "cc-by-3.0" })
        XCTAssertTrue(pleiades.attribution?.contains("G. Reger") == true)
        XCTAssertEqual(pleiades.safeLicenseURL?.host, "creativecommons.org")
        XCTAssertTrue(provenance.references.allSatisfy { $0.safeURL != nil })
        let restored = try JSONDecoder().decode(Citation.self, from: JSONEncoder().encode(citation))
        XCTAssertEqual(restored.materialProvenance?.references.last?.attribution, pleiades.attribution)
    }
    func testLegacyAndUnknownKindsDoNotBecomeScripture() throws {
        let source = try JSONDecoder().decode(RequestResult.self, from: fixture("material-answer"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(source.result!.citations[0])) as? [String: Any])
        object.removeValue(forKey: "materialProvenance"); object.removeValue(forKey: "sourceKind")
        let legacy = try JSONDecoder().decode(Citation.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.materialProvenance); XCTAssertEqual(legacy.kindLabel, "出典の種別は未確認")
        object["sourceKind"] = "scripture"
        XCTAssertEqual(try JSONDecoder().decode(Citation.self, from: JSONSerialization.data(withJSONObject: object)).kindLabel, "聖書本文")
        object["sourceKind"] = "future-kind"
        XCTAssertEqual(try JSONDecoder().decode(Citation.self, from: JSONSerialization.data(withJSONObject: object)).kindLabel, "出典の種別は未確認")
    }
    func testReferenceLinksRejectOpaqueCredentialsAndNonHTTPS() throws {
        for url in ["https:relative", "https://user:password@example.com", "http://example.com", "file:///tmp/source"] {
            let object: [String: Any] = ["id": "test", "title": "test", "url": url, "publisher": "test", "license": "cc-by-3.0", "licenseUrl": url]
            let value = try JSONDecoder().decode(CitationMaterialProvenance.Reference.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertNil(value.safeURL); XCTAssertNil(value.safeLicenseURL)
        }
    }
    func testMaterialSummaryCannotEnterOverviewCacheEvenWithForgedGrant() throws {
        let now = Date(timeIntervalSince1970: 1791907200)
        var reading = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("reading")) as? [String: Any])
        let answer = try JSONDecoder().decode(RequestResult.self, from: fixture("material-answer"))
        let material = try JSONSerialization.jsonObject(with: JSONEncoder().encode(answer.result!.citations[0].materialProvenance!))
        var overview = reading["overview"] as! [String: Any]
        var citations = overview["citations"] as! [[String: Any]]
        citations[0]["materialProvenance"] = material; overview["citations"] = citations; reading["overview"] = overview
        let forged = try JSONDecoder().decode(ReadingResponse.self, from: JSONSerialization.data(withJSONObject: reading))
        XCTAssertThrowsError(try PublicReadingSnapshot(response: forged, fetchedAt: now))
        let clean = try JSONDecoder().decode(ReadingResponse.self, from: fixture("reading"))
        let snapshot = try PublicReadingSnapshot(response: clean, fetchedAt: now)
        var disk = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        disk["overview"] = overview
        let malformed = try JSONDecoder().decode(PublicReadingSnapshot.self, from: JSONSerialization.data(withJSONObject: disk))
        XCTAssertFalse(malformed.isUsable(at: now))
    }
}
