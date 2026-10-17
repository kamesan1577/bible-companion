import Foundation
import XCTest
@testable import CompanionCore
final class ShareAIAccessTests: XCTestCase {
    let owner = "11111111-1111-4111-8111-111111111111"
    let date = Date(timeIntervalSince1970: 2000000)
    func testScopeExpiryAndTokenShape() {
        let token = "bcs1_" + String(repeating: "a", count: 64)
        XCTAssertTrue(ShareAIAccess(token: token, ownerID: owner, expiresAt: 2003600).isValid(owner: owner, at: date))
        XCTAssertFalse(ShareAIAccess(token: token, ownerID: owner, expiresAt: 2003600).isValid(owner: UUID().uuidString, at: date))
        XCTAssertFalse(ShareAIAccess(token: token, ownerID: owner, expiresAt: 2000000).isValid(owner: owner, at: date))
        XCTAssertFalse(ShareAIAccess(token: token, ownerID: owner, expiresAt: 2200000).isValid(owner: owner, at: date))
        XCTAssertFalse(ShareAIAccess(token: "general-session-token", ownerID: owner, expiresAt: 2003600).isValid(owner: owner, at: date))
    }
    func testWireOwnerNameIsExplicit() throws {
        let value = ShareAIAccess(token: "bcs1_" + String(repeating: "a", count: 64), ownerID: owner, expiresAt: 2003600)
        let data = try JSONEncoder().encode(value)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("ownerId"))
        XCTAssertTrue(try JSONDecoder().decode(ShareAIAccess.self, from: data).isValid(owner: owner, at: date))
    }

    func testValidatedCapabilityPreservesOwnerAndExpiryReasons() throws {
        let live = ShareAIAccess(token: "bcs1_" + String(repeating: "a", count: 64), ownerID: owner, expiresAt: 2003600)
        let liveData = try JSONEncoder().encode(live)
        XCTAssertEqual(try ShareAIAccess.validated(from: liveData, owner: owner, at: date).ownerID, owner)
        XCTAssertThrowsError(try ShareAIAccess.validated(from: liveData, owner: UUID().uuidString, at: date)) {
            XCTAssertEqual($0 as? ShareAIAccessReadError, .ownerMismatch)
        }
        let expired = ShareAIAccess(token: live.token, ownerID: owner, expiresAt: 2000000)
        XCTAssertThrowsError(try ShareAIAccess.validated(from: JSONEncoder().encode(expired), owner: owner, at: date)) {
            XCTAssertEqual($0 as? ShareAIAccessReadError, .expired)
        }
    }

    func testValidatedCapabilityRejectsCorruptionAndGeneralSessionToken() throws {
        XCTAssertThrowsError(try ShareAIAccess.validated(from: Data("not json".utf8), owner: owner, at: date)) {
            XCTAssertEqual($0 as? ShareAIAccessReadError, .corrupted)
        }
        let generic = ShareAIAccess(token: "general-session-token", ownerID: owner, expiresAt: 2003600)
        XCTAssertThrowsError(try ShareAIAccess.validated(from: JSONEncoder().encode(generic), owner: owner, at: date)) {
            XCTAssertEqual($0 as? ShareAIAccessReadError, .corrupted)
        }
        XCTAssertThrowsError(try ShareAIAccess.validated(from: Data(repeating: 0, count: 4097), owner: owner, at: date)) {
            XCTAssertEqual($0 as? ShareAIAccessReadError, .corrupted)
        }
    }

    func testReadReceiptMatchesOnlyCurrentTokenAndStoresOnlyDigest() throws {
        let token = "bcs1_" + String(repeating: "b", count: 64)
        let receipt = ShareAIAccessReadReceipt(token: token, readAt: date)
        let data = try JSONEncoder().encode(receipt)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains(token))
        XCTAssertTrue(json.contains(receipt.tokenDigest))
        XCTAssertTrue(try ShareAIAccessReadReceipt.matches(data, token: token, at: date.addingTimeInterval(10)))
        XCTAssertFalse(try ShareAIAccessReadReceipt.matches(data, token: "bcs1_" + String(repeating: "c", count: 64), at: date.addingTimeInterval(10)))
    }

    func testReadReceiptRejectsInvalidTimeAndMalformedData() throws {
        let token = "bcs1_" + String(repeating: "b", count: 64)
        let future = ShareAIAccessReadReceipt(token: token, readAt: date.addingTimeInterval(1))
        let futureData = try JSONEncoder().encode(future)
        XCTAssertThrowsError(try ShareAIAccessReadReceipt.matches(futureData, token: token, at: date)) {
            XCTAssertEqual($0 as? ShareAIAccessReadError, .corrupted)
        }
        XCTAssertThrowsError(try ShareAIAccessReadReceipt.matches(Data("{}".utf8), token: token, at: date)) {
            XCTAssertEqual($0 as? ShareAIAccessReadError, .corrupted)
        }
    }
}

extension ShareAIAccessTests {
    func testExpiredAccessCanOnlyBeReadForOwnerBoundRenewal() throws {
        let date = Date(); let owner = "00000000-0000-4000-8000-000000000123"
        let access = ShareAIAccess(token: "bcs1_" + String(repeating: "a", count: 64), ownerID: owner, expiresAt: date.addingTimeInterval(-1).timeIntervalSince1970, scopeID: String(repeating: "b", count: 64), refreshToken: "bcr1_" + String(repeating: "c", count: 64), refreshExpiresAt: date.addingTimeInterval(86400).timeIntervalSince1970)
        let bytes = try JSONEncoder().encode(access)
        XCTAssertThrowsError(try ShareAIAccess.validated(from: bytes, owner: owner, at: date))
        XCTAssertEqual(try ShareAIAccess.validated(from: bytes, owner: owner, at: date, allowingRenewal: true).conversationScope, String(repeating: "b", count: 64))
        XCTAssertThrowsError(try ShareAIAccess.validated(from: bytes, owner: "00000000-0000-4000-8000-000000000124", at: date, allowingRenewal: true))
        XCTAssertFalse(access.isValid(owner: owner, at: date))
    }
}

extension ShareAIAccessTests {
    func testRenewableSavedConfigurationDoesNotBecomeUnpreparedAtAccessExpiry() throws {
        let now = Date(); let owner = "00000000-0000-4000-8000-000000000123"
        let access = ShareAIAccess(token: "bcs1_" + String(repeating:"a",count:64), ownerID: owner, expiresAt: now.addingTimeInterval(-1).timeIntervalSince1970, scopeID: String(repeating:"b",count:64), refreshToken:"bcr1_"+String(repeating:"c",count:64), refreshExpiresAt:now.addingTimeInterval(86400).timeIntervalSince1970)
        XCTAssertFalse(access.isValid(owner:owner,at:now)); XCTAssertTrue(access.canRenew(at:now))
        let data = try JSONEncoder().encode(access)
        XCTAssertNoThrow(try ShareAIAccess.validated(from:data,owner:owner,at:now,allowingRenewal:true))
    }
}
