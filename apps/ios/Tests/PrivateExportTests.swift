import XCTest
import Foundation
@testable import CompanionCore

final class PrivateExportTests: XCTestCase, @unchecked Sendable {
    let now = Date(timeIntervalSince1970: 1_791_907_200)
    let owner = "11111111-1111-4111-8111-111111111111"
    func snapshot() throws -> ExportSnapshot {
        let object: [String: Any] = ["version": 1, "snapshotId": "22222222-2222-4222-8222-222222222222", "createdAt": now.timeIntervalSince1970, "expiresAt": now.timeIntervalSince1970 + 900, "sections": PrivateExportAssembler.sections, "maxPageBytes": 1048576, "maxPageItems": 25, "user": ["id": owner, "display_name": "Sample", "role": "owner"], "settings": [:], "modelPreference": NSNull()]
        return try JSONDecoder().decode(ExportSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
    }
    func page(_ snapshot: ExportSnapshot, section: String, items: [JSONValue] = [], cursor: String? = nil) -> ExportPage {
        ExportPage(version: 1, snapshotId: snapshot.snapshotId, section: section, items: items, nextCursor: cursor)
    }
    func testFailedInitialWriteRollsBackPartialFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(try PrivateExportAssembler(snapshot: snapshot(), ownerID: owner, directory: root, at: now, initialWrite: { handle, data in
            try handle.write(contentsOf: data.prefix(8))
            throw CocoaError(.fileWriteOutOfSpace)
        }))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }
    func testActualExportRouteFixtures() async throws {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: Self.self)
        #endif
        let snapshotURL = try XCTUnwrap(bundle.url(forResource: "export-snapshot", withExtension: "json"))
        let pageURL = try XCTUnwrap(bundle.url(forResource: "export-page", withExtension: "json"))
        let value = try JSONDecoder().decode(ExportSnapshot.self, from: Data(contentsOf: snapshotURL))
        let page = try JSONDecoder().decode(ExportPage.self, from: Data(contentsOf: pageURL))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let date = Date(timeIntervalSince1970: value.createdAt + 1)
        let writer = try PrivateExportAssembler(snapshot: value, ownerID: value.user.id, directory: root, at: date)
        for section in PrivateExportAssembler.sections.prefix(while: { $0 != page.section }) {
            try await writer.append(self.page(value, section: section), at: date)
        }
        try await writer.append(page, at: date)
        try await writer.discard()
    }
    func testCompleteIncrementalJSONAndExplicitDiscard() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let value = try snapshot(); let writer = try PrivateExportAssembler(snapshot: value, ownerID: owner, directory: root, at: now)
        try await writer.append(page(value, section: "imports", items: [.object(["text": .string("quote \" and 日本語")])], cursor: "opaque+cursor/="), at: now)
        let next = try await writer.nextRequest(at: now); XCTAssertEqual(next?.cursor, "opaque+cursor/=")
        try await writer.append(page(value, section: "imports", items: [.object(["id": .string("second")])]), at: now)
        for section in PrivateExportAssembler.sections.dropFirst() { try await writer.append(page(value, section: section), at: now) }
        let file = try await writer.finish(at: now)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        XCTAssertEqual((object["imports"] as? [Any])?.count, 2)
        XCTAssertEqual((object["messages"] as? [Any])?.count, 0)
        XCTAssertNil(object["accessToken"])
        try await writer.discard(); XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
    func testIncompleteNeverFinalizesAndDiscardDeletes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = try PrivateExportAssembler(snapshot: snapshot(), ownerID: owner, directory: root, at: now)
        do { _ = try await writer.finish(at: now); XCTFail() } catch { XCTAssertEqual(error as? ExportFailure, .incomplete) }
        try await writer.discard(); XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        do { _ = try await writer.nextRequest(at: now); XCTFail() } catch { XCTAssertEqual(error as? ExportFailure, .closed) }
    }
    func testWrongOwnerAndExpiredSnapshotRejected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertThrowsError(try PrivateExportAssembler(snapshot: snapshot(), ownerID: UUID().uuidString, directory: root, at: now))
        XCTAssertThrowsError(try PrivateExportAssembler(snapshot: snapshot(), ownerID: owner, directory: root, at: now.addingTimeInterval(901)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }
    func testCrossSectionAndCursorLoopRejected() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let value = try snapshot(); let writer = try PrivateExportAssembler(snapshot: value, ownerID: owner, directory: root, at: now)
        do { try await writer.append(page(value, section: "messages"), at: now); XCTFail() } catch { XCTAssertEqual(error as? ExportFailure, .invalidPage) }
        try await writer.append(page(value, section: "imports", items: [.string("one")], cursor: "same"), at: now)
        do { try await writer.append(page(value, section: "imports", items: [.string("two")], cursor: "same"), at: now); XCTFail() } catch { XCTAssertEqual(error as? ExportFailure, .cursorLoop) }
        try await writer.discard()
    }
    func testPageBoundsAndExpiryDuringExport() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let value = try snapshot(); let writer = try PrivateExportAssembler(snapshot: value, ownerID: owner, directory: root, at: now)
        for items in [Array(repeating: JSONValue.string("small"), count: 26), [.string(String(repeating: "x", count: 1_048_576))]] {
            do { try await writer.append(page(value, section: "imports", items: items), at: now); XCTFail() } catch { XCTAssertEqual(error as? ExportFailure, .invalidPage) }
        }
        do { _ = try await writer.nextRequest(at: now.addingTimeInterval(900)); XCTFail() } catch { XCTAssertEqual(error as? ExportFailure, .expired) }
        try await writer.discard()
    }
}
