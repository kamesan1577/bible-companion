import XCTest
@testable import CompanionCore

final class ShareAuthRecoveryTests: XCTestCase {
    func testUnauthenticatedShowStatePreservesPendingRequestAndDoesNotResend() {
        let priorRequest = "pending-request-test"
        let recovery = ShareAuthRecoveryState.unauthenticated(pendingRequest: priorRequest)

        XCTAssertTrue(recovery.requiresAppRecheck)
        XCTAssertTrue(recovery.setupMessage.contains("初回同意が原因とは限りません"))
        XCTAssertFalse(recovery.setupMessage.contains("同意してください"))
        XCTAssertTrue(recovery.setupMessage.contains("アプリを一度開き"))
        XCTAssertEqual(recovery.pendingRequest, priorRequest)
        XCTAssertFalse(recovery.canRetryShareStart)
        XCTAssertNil(recovery.error)
        XCTAssertEqual(recovery.automaticAction, .none)
    }

    func testUnauthenticatedWithoutPendingRequestDoesNotInventPendingWork() {
        let recovery = ShareAuthRecoveryState.unauthenticated(pendingRequest: nil)

        XCTAssertTrue(recovery.requiresAppRecheck)
        XCTAssertNil(recovery.pendingRequest)
        XCTAssertFalse(recovery.canRetryShareStart)
        XCTAssertEqual(recovery.automaticAction, .none)
        XCTAssertFalse(recovery.setupMessage.contains("処理中の質問"))
    }
}
