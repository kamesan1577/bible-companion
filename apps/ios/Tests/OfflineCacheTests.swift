import XCTest
@testable import CompanionCore

final class OfflineCacheTests: XCTestCase, @unchecked Sendable {
    private let now = Date(timeIntervalSince1970: 1791907200)
    private func response(_ edit: ((inout [String: Any]) -> Void)? = nil) throws -> ReadingResponse {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: Self.self)
        #endif
        let url = try XCTUnwrap(bundle.url(forResource: "reading", withExtension: "json"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        object["checkedAt"] = now.timeIntervalSince1970; edit?(&object)
        return try JSONDecoder().decode(ReadingResponse.self, from: JSONSerialization.data(withJSONObject: object))
    }
    private func manifest(_ snapshot: PublicReadingSnapshot, changed: Bool = false, revoked: Bool = false, missing: Bool = false, checkedAt: Date? = nil, restricted: Bool = false, unreviewed: Bool = false, generationRevoked: Bool = false) throws -> ContentManifest {
        let items: [[String: Any]] = missing ? [] : snapshot.policy.dependencies.map { ["id": $0.id, "version": changed ? "changed-version" : $0.version, "rights_status": revoked ? "revoked" : "approved", "active": revoked ? 0 : 1, "license": restricted ? "restricted" : "public-domain", "reviewed": !unreviewed, "visibility": "public", "generationAllowed": !generationRevoked] }
        return try JSONDecoder().decode(ContentManifest.self, from: JSONSerialization.data(withJSONObject: ["version": "manifest-current", "items": items, "checkedAt": (checkedAt ?? now).timeIntervalSince1970]))
    }
    func testOfflineValidationFailureClearsOnlyItsOwnNewMarker() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let marker = TestCacheMarker(); let cache = PublicReadingCache(directory: root, marker: marker)
        let first = try await cache.beginValidation()
        XCTAssertTrue(marker.requiresValidation())
        await cache.validationFailedBeforeManifest(first)
        XCTAssertFalse(marker.requiresValidation())
        marker.setRequired(true)
        let recovery = try await cache.beginValidation()
        await cache.validationFailedBeforeManifest(recovery)
        XCTAssertTrue(marker.requiresValidation())
    }
    func testOverlappingOfflineAttemptsDoNotInheritTransientIntent() async throws {
        let marker = TestCacheMarker()
        let cache = PublicReadingCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), marker: marker)
        let first = try await cache.beginValidation(); let second = try await cache.beginValidation()
        await cache.validationFailedBeforeManifest(first)
        await cache.validationFailedBeforeManifest(second)
        XCTAssertFalse(marker.requiresValidation())
        let observed = try await cache.beginValidation()
        await cache.manifestReceived(observed)
        let later = try await cache.beginValidation()
        await cache.validationFailedBeforeManifest(later)
        XCTAssertTrue(marker.requiresValidation())
    }
    func testOldValidationCannotClearNewerTransaction() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = TestCacheMarker(); let cache = PublicReadingCache(directory: root, marker: marker)
        let first = try await cache.beginValidation(); let second = try await cache.beginValidation()
        await cache.validationFailedBeforeManifest(first)
        XCTAssertTrue(marker.requiresValidation())
        let snapshot = try PublicReadingSnapshot(response: response(), fetchedAt: now)
        do { try await cache.reconcile(manifest(snapshot), at: now, attempt: first); XCTFail() } catch { }
        XCTAssertTrue(marker.requiresValidation())
        try await cache.reconcile(manifest(snapshot), at: now, attempt: second)
        XCTAssertFalse(marker.requiresValidation())
    }
    func testFailedReconciliationRemainsBlockedAcrossCacheInstances() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = TestCacheMarker()
        let cache = PublicReadingCache(directory: root, marker: marker)
        let value = try response(); let snapshot = try PublicReadingSnapshot(response: value, fetchedAt: now)
        try await cache.store(value, at: now)
        // A JSON-named directory is an I/O failure, rather than decodable corruption.
        let obstruction = root.appendingPathComponent("protected.json")
        try FileManager.default.createDirectory(at: obstruction, withIntermediateDirectories: true)
        do { try await cache.reconcile(manifest(snapshot), at: now); XCTFail("Expected disk failure") } catch { }
        XCTAssertTrue(marker.requiresValidation())
        let reopened = PublicReadingCache(directory: root, marker: marker)
        let blocked = try await reopened.load(snapshot.key, at: now)
        XCTAssertNil(blocked)
        try FileManager.default.removeItem(at: obstruction)
        try await reopened.reconcile(manifest(snapshot), at: now)
        XCTAssertFalse(marker.requiresValidation())
        let restored = try await reopened.load(snapshot.key, at: now)
        XCTAssertNotNil(restored)
    }
    func testFutureCitationCannotHideBehindBoundedHeader() throws {
        let value = try response { object in
            var overview = object["overview"] as! [String: Any]
            var citations = overview["citations"] as! [[String: Any]]
            citations[0]["passage"] = ["book": "ACT", "start": ["chapter": 28, "verse": 1], "end": ["chapter": 28, "verse": 2]]
            overview["citations"] = citations; object["overview"] = overview
        }
        XCTAssertThrowsError(try PublicReadingSnapshot(response: value, fetchedAt: now))
    }
    func testActualBackendManifestContract() throws {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: Self.self)
        #endif
        let url = try XCTUnwrap(bundle.url(forResource: "content-manifest", withExtension: "json"))
        let manifest = try JSONDecoder().decode(ContentManifest.self, from: Data(contentsOf: url))
        let snapshot = try PublicReadingSnapshot(response: response(), fetchedAt: now)
        XCTAssertTrue(snapshot.policy.dependencies.allSatisfy(manifest.permits))
        XCTAssertTrue(manifest.items.allSatisfy { $0.reviewed && $0.license == "public-domain" })
    }
    func testOldServerCheckCannotRenewBodyTTL() throws {
        let value = try response { $0["checkedAt"] = self.now.addingTimeInterval(-3600).timeIntervalSince1970 }
        let snapshot = try PublicReadingSnapshot(response: value, fetchedAt: now)
        XCTAssertEqual(snapshot.expiresAt, now.addingTimeInterval(86400 - 3600))
        XCTAssertFalse(snapshot.isUsable(at: snapshot.expiresAt))
    }
    func testEligiblePDOverviewCachesButStripsOtherPayload() throws {
        let snapshot = try PublicReadingSnapshot(response: response(), fetchedAt: now)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        for prohibited in ["people", "places", "artworks", "sources", "ownerID", "importId", "sharedText", "question", "accessToken"] { XCTAssertNil(object[prohibited]) }
        XCTAssertTrue(snapshot.isUsable(at: now)); XCTAssertTrue(snapshot.readingResponse().people.isEmpty)
    }
    func testTTLExpiresAndOfflineReadsCannotRenewIt() throws {
        let snapshot = try PublicReadingSnapshot(response: response(), fetchedAt: now)
        XCTAssertTrue(snapshot.isUsable(at: now.addingTimeInterval(86_399)))
        XCTAssertFalse(snapshot.isUsable(at: now.addingTimeInterval(86_400)))
        XCTAssertEqual(snapshot.fetchedAt, now)
    }
    func testRevalidationDoesNotRenewBodyTTL() throws {
        var snapshot = try PublicReadingSnapshot(response: response(), fetchedAt: now)
        try snapshot.revalidate(using: manifest(snapshot, checkedAt: now.addingTimeInterval(3600)), at: now.addingTimeInterval(3600))
        XCTAssertEqual(snapshot.lastValidatedAt, now.addingTimeInterval(3600))
        XCTAssertFalse(snapshot.isUsable(at: now.addingTimeInterval(86_400)))
    }
    func testVersionRevocationAndMissingDependencyFailBeforeTTL() throws {
        let snapshot = try PublicReadingSnapshot(response: response(), fetchedAt: now)
        XCTAssertTrue(snapshot.isAllowed(by: try manifest(snapshot), at: now))
        XCTAssertFalse(snapshot.isAllowed(by: try manifest(snapshot, changed: true), at: now))
        XCTAssertFalse(snapshot.isAllowed(by: try manifest(snapshot, revoked: true), at: now))
        XCTAssertFalse(snapshot.isAllowed(by: try manifest(snapshot, missing: true), at: now))
    }
    func testSameVersionLicenseChangeAndStaleManifestRejected() throws {
        let snapshot = try PublicReadingSnapshot(response: response(), fetchedAt: now)
        XCTAssertFalse(snapshot.isAllowed(by: try manifest(snapshot, restricted: true), at: now))
        XCTAssertFalse(snapshot.isAllowed(by: try manifest(snapshot, unreviewed: true), at: now))
        XCTAssertFalse(snapshot.isAllowed(by: try manifest(snapshot, generationRevoked: true), at: now))
        XCTAssertFalse(snapshot.isAllowed(by: try manifest(snapshot, checkedAt: now.addingTimeInterval(-301)), at: now))
        XCTAssertFalse(snapshot.isAllowed(by: try manifest(snapshot, checkedAt: now.addingTimeInterval(61)), at: now))
    }
    func testRejectsUnapprovedGrantAndFuturePolicyVersion() throws {
        for (key, value) in [("eligible", false as Any), ("policyVersion", 2 as Any), ("maxAgeSeconds", 604800 as Any), ("allowedFields", ["overview", "sources"] as Any)] {
            XCTAssertThrowsError(try PublicReadingSnapshot(response: response { object in var policy = object["offlineCache"] as! [String: Any]; policy[key] = value; object["offlineCache"] = policy }, fetchedAt: now))
        }
    }
    func testRejectsAIGeneratedOverview() throws {
        XCTAssertThrowsError(try PublicReadingSnapshot(response: response { object in var overview = object["overview"] as! [String: Any]; overview["modelInvoked"] = true; object["overview"] = overview }, fetchedAt: now))
    }
    func testRejectsNonPublicDomainCitation() throws {
        XCTAssertThrowsError(try PublicReadingSnapshot(response: response { object in var overview = object["overview"] as! [String: Any]; var citations = overview["citations"] as! [[String: Any]]; citations[0]["license"] = "restricted-JCB"; overview["citations"] = citations; object["overview"] = overview }, fetchedAt: now))
    }
    func testRejectsFutureServerTimestampAndClockRollback() throws {
        XCTAssertThrowsError(try PublicReadingSnapshot(response: response { $0["checkedAt"] = self.now.timeIntervalSince1970 + 120 }, fetchedAt: now))
        let snapshot = try PublicReadingSnapshot(response: response(), fetchedAt: now)
        XCTAssertFalse(snapshot.isUsable(at: now.addingTimeInterval(-120)))
    }
    func testKeySeparatesTranslationAndSpoilerMode() throws {
        let passage = try response().passage
        XCTAssertNotEqual(ReadingCacheKey(passage: passage, translation: "JCB"), ReadingCacheKey(passage: passage, translation: "WEB"))
        XCTAssertNotEqual(ReadingCacheKey(passage: passage, translation: "JCB"), ReadingCacheKey(passage: passage, translation: "JCB", spoilerAllowed: true))
        XCTAssertFalse(ReadingCacheKey(passage: passage, translation: "../../other").isValid)
    }
    func testDiskCacheRoundTripRevokeAndExpiry() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = PublicReadingCache(directory: directory); let response = try response()
        try await cache.store(response, at: now)
        let key = ReadingCacheKey(passage: response.passage, translation: response.translation)
        let first = try await cache.load(key, at: now); XCTAssertNotNil(first)
        try await cache.reconcile(manifest(try XCTUnwrap(first), revoked: true), at: now)
        let revoked = try await cache.load(key, at: now); XCTAssertNil(revoked)
        try await cache.store(response, at: now)
        let expired = try await cache.load(key, at: now.addingTimeInterval(86_400)); XCTAssertNil(expired)
    }
    func testFutureCacheSchemaIsDiscardedWithoutReplay() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = PublicReadingCache(directory: directory); let response = try response()
        try await cache.store(response, at: now)
        let key = ReadingCacheKey(passage: response.passage, translation: response.translation)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]); object["schemaVersion"] = 99
        try JSONSerialization.data(withJSONObject: object).write(to: file)
        let future = try await cache.load(key, at: now); XCTAssertNil(future)
    }
}

private final class TestCacheMarker: PublicCacheValidationMarker, @unchecked Sendable {
    private let lock = NSLock()
    private var required = false
    func requiresValidation() -> Bool { lock.lock(); defer { lock.unlock() }; return required }
    func setRequired(_ value: Bool) { lock.lock(); required = value; lock.unlock() }
}
