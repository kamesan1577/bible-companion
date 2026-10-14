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
}
