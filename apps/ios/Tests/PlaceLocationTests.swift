import XCTest
@testable import CompanionCore

final class PlaceLocationTests: XCTestCase {
    private let reading = Passage(book: "ACT", start: Verse(chapter: 18, verse: 1), end: Verse(chapter: 18, verse: 28))
    private func cards() throws -> [MaterialCard] {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: Self.self)
        #endif
        let url = try XCTUnwrap(bundle.url(forResource: "materials", withExtension: "json"))
        return try JSONDecoder().decode([MaterialCard].self, from: Data(contentsOf: url))
    }
    private func corinth(_ edit: (inout [String: Any]) -> Void) throws -> MaterialCard {
        let card = try XCTUnwrap(cards().first { $0.id == "place-corinth" })
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(card)) as? [String: Any]); edit(&object)
        return try JSONDecoder().decode(MaterialCard.self, from: JSONSerialization.data(withJSONObject: object))
    }
    func testThreeVerifiedPlacesHaveLicensedApproximateLocations() throws {
        let places = try cards().filter { $0.kind == "place" }
        XCTAssertEqual(places.count, 3)
        for card in places {
            let point = try XCTUnwrap(card.mapLocation(reading: reading))
            XCTAssertTrue((37...39).contains(point.latitude)); XCTAssertTrue((22...28).contains(point.longitude))
            XCTAssertEqual(point.source.license, "cc-by-3.0"); XCTAssertNotNil(point.source.safeLicenseURL)
            XCTAssertFalse(point.explanation.isEmpty)
        }
    }
    func testFutureUnrelatedAndUnreviewedPlacesCannotBecomePins() throws {
        let ephesus = try XCTUnwrap(cards().first { $0.id == "place-ephesus" })
        XCTAssertNil(ephesus.mapLocation(reading: Passage(book: "ACT", start: Verse(chapter: 18, verse: 1), end: Verse(chapter: 18, verse: 18))))
        XCTAssertNil(ephesus.mapLocation(reading: Passage(book: "GEN", start: Verse(chapter: 1, verse: 1), end: Verse(chapter: 1, verse: 3))))
        XCTAssertNil(try corinth { $0["reviewed"] = false }.mapLocation(reading: reading))
        XCTAssertNil(try corinth { $0["rightsStatus"] = "revoked" }.mapLocation(reading: reading))
    }
    func testInvalidOrExactCoordinatesFailClosed() throws {
        for (key, value) in [("latitude", 1000 as Any), ("longitude", -1000 as Any), ("certainty", "exact" as Any), ("sourceId", "unknown" as Any)] {
            let card = try corinth { object in var details = object["details"] as! [String: Any]; var point = details["coordinates"] as! [String: Any]; point[key] = value; details["coordinates"] = point; object["details"] = details }
            XCTAssertNil(card.mapLocation(reading: reading))
        }
    }
    func testOpaqueSourceURLCannotAuthorizeAPin() throws {
        let card = try corinth { object in var sources = object["provenance"] as! [[String: Any]]; for index in sources.indices where sources[index]["license"] as? String == "cc-by-3.0" { sources[index]["url"] = "https:relative-path" }; object["provenance"] = sources }
        XCTAssertNil(card.mapLocation(reading: reading))
    }
    func testMissingRequiredAttributionPreventsRendering() throws {
        let card = try corinth { object in var sources = object["provenance"] as! [[String: Any]]; for index in sources.indices where sources[index]["license"] as? String == "odbl-1.0" { sources[index]["attribution"] = nil }; object["provenance"] = sources }
        XCTAssertNil(card.mapLocation(reading: reading))
        let invalidLicense = try corinth { object in var sources = object["provenance"] as! [[String: Any]]; for index in sources.indices where sources[index]["license"] as? String == "cc-by-3.0" { sources[index]["licenseUrl"] = "http://example.com" }; object["provenance"] = sources }
        XCTAssertNil(invalidLicense.mapLocation(reading: reading))
    }
}
