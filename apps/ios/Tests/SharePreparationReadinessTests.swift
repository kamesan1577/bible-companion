import Foundation
import XCTest
@testable import CompanionCore

final class SharePreparationReadinessTests: XCTestCase {
    let owner = "11111111-1111-4111-8111-111111111111"
    let date = Date(timeIntervalSince1970: 2_000_000)
    func policy(enabled: Bool = true, consent: Bool = true, workers: Bool = true, grounded: Bool = true, version: String = "v1") throws -> AIPolicy {
        let object: [String: Any] = ["allowedAnswerModes": ["grounded-generation"], "groundedPolicyVersion": "v1", "groundedNoticeJa": "notice", "workersAiConsent": workers, "shareAiEnabled": enabled, "shareAiConsent": consent, "groundedConsent": ["accepted": grounded, "policyVersion": version]]
        return try JSONDecoder().decode(AIPolicy.self, from: JSONSerialization.data(withJSONObject: object))
    }
    func testSavedRequiresCurrentConsentAndVerifiedOwnerBoundUnexpiredAccess() throws {
        let access = ShareAIAccess(token: "bcs1_" + String(repeating: "a", count: 64), ownerID: owner, expiresAt: date.timeIntervalSince1970 + 300)
        func ready(_ value: AIPolicy?, _ candidate: ShareAIAccess? = nil, _ who: String? = nil) -> Bool {
            SharePreparationReadiness.isSaved(policy: value, owner: who ?? owner, access: candidate, at: date)
        }
        XCTAssertTrue(try ready(policy(), access))
        XCTAssertFalse(try ready(policy(), nil)) // consent success without saved/readable capability
        XCTAssertFalse(ready(nil, access))
        XCTAssertFalse(try ready(policy(enabled: false), access))
        XCTAssertFalse(try ready(policy(consent: false), access))
        XCTAssertFalse(try ready(policy(workers: false), access))
        XCTAssertFalse(try ready(policy(grounded: false), access))
        XCTAssertFalse(try ready(policy(version: "v0"), access))
        XCTAssertFalse(try ready(policy(), access, "22222222-2222-4222-8222-222222222222"))
        let expired = ShareAIAccess(token: access.token, ownerID: owner, expiresAt: date.timeIntervalSince1970)
        XCTAssertFalse(try ready(policy(), expired))
    }
}
