import Foundation
import XCTest
@testable import CompanionCore

final class AIPolicyTests: XCTestCase {
    func policy(workers: Bool = true, accepted: Bool = true, consentVersion: String? = "v1", allowed: [AnswerMode] = AnswerMode.allCases) throws -> AIPolicy {
        let object: [String: Any] = ["allowedAnswerModes": allowed.map(\.rawValue), "defaultAnswerMode": "reviewed-claim-selection", "groundedPolicyVersion": "v1", "groundedNoticeJa": "実験的な生成", "workersAiConsent": workers, "groundedConsent": ["accepted": accepted, "policyVersion": consentVersion as Any? ?? NSNull()]]
        return try JSONDecoder().decode(AIPolicy.self, from: JSONSerialization.data(withJSONObject: object))
    }
    func testBothConsentsAndExactVersionRequired() throws {
        XCTAssertTrue(try policy().permits(.groundedGeneration))
        XCTAssertFalse(try policy(workers: false).permits(.groundedGeneration))
        XCTAssertFalse(try policy(accepted: false).permits(.groundedGeneration))
        XCTAssertFalse(try policy(consentVersion: "v0").permits(.groundedGeneration))
        XCTAssertFalse(try policy(consentVersion: nil).permits(.groundedGeneration))
        XCTAssertTrue(try policy(accepted: false).permits(.reviewedClaimSelection))
    }
    func testAllowlistIsIndependentOfConsentAndNeverFallsBack() throws {
        XCTAssertFalse(try policy(allowed: [.reviewedClaimSelection]).permits(.groundedGeneration))
        XCTAssertFalse(try policy(allowed: []).permits(.reviewedClaimSelection))
        XCTAssertFalse(try policy(workers: false).permits(.reviewedClaimSelection))
    }
    func testConsentIntentIsBoundToOwnerSessionAndPresentedVersion() throws {
        let owner = UUID().uuidString, epoch = UUID(), value = try policy()
        let intent = GroundedConsentIntent(ownerID: owner, sessionEpoch: epoch, policy: value)
        XCTAssertTrue(intent.permits(ownerID: owner, epoch: epoch, currentPolicy: value))
        XCTAssertFalse(intent.permits(ownerID: UUID().uuidString, epoch: epoch, currentPolicy: value))
        XCTAssertFalse(intent.permits(ownerID: owner, epoch: UUID(), currentPolicy: value))
        XCTAssertFalse(intent.permits(ownerID: owner, epoch: epoch, currentPolicy: nil))
        let data = try JSONEncoder().encode(value)
        let changed = try JSONDecoder().decode(AIPolicy.self, from: Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "v1", with: "v2").utf8))
        XCTAssertFalse(intent.permits(ownerID: owner, epoch: epoch, currentPolicy: changed))
    }
    func testActualPolicyFixtureDoesNotClaimAIAvailable() throws {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: Self.self)
        #endif
        let url = try XCTUnwrap(bundle.url(forResource: "ai-policy", withExtension: "json"))
        let value = try JSONDecoder().decode(AIPolicy.self, from: Data(contentsOf: url))
        XCTAssertEqual(value.defaultAnswerMode, .reviewedClaimSelection)
        XCTAssertFalse(value.permits(.reviewedClaimSelection)); XCTAssertFalse(value.permits(.groundedGeneration))
    }
}
