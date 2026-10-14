import XCTest
@testable import CompanionCore

final class PrivateDeletionTests: XCTestCase {
    let owner = "11111111-1111-4111-8111-111111111111"
    func testExplicitConfirmationIsBoundToAccountAndSession() {
        let epoch = UUID(); let intent = DeletionIntent(ownerID: owner, sessionEpoch: epoch, kind: .readingData)
        XCTAssertTrue(intent.permits(ownerID: owner, epoch: epoch, typedConfirmation: "削除"))
        XCTAssertFalse(intent.permits(ownerID: owner, epoch: UUID(), typedConfirmation: "削除"))
        XCTAssertFalse(intent.permits(ownerID: UUID().uuidString, epoch: epoch, typedConfirmation: "削除"))
        XCTAssertFalse(intent.permits(ownerID: owner, epoch: epoch, typedConfirmation: ""))
        XCTAssertEqual(intent.body["confirmation"].string, "DELETE_MY_READING_DATA")
        XCTAssertEqual(PrivateDeletionKind.account.confirmation, "DELETE_MY_ACCOUNT")
    }
    func testActualServerDeletionAcknowledgments() throws {
        for (name, kind) in [("reading-data-deleted", PrivateDeletionKind.readingData), ("account-deleted", .account)] {
            #if SWIFT_PACKAGE
            let bundle = Bundle.module
            #else
            let bundle = Bundle(for: Self.self)
            #endif
            let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json"))
            let value = try JSONDecoder().decode(DeletionResult.self, from: Data(contentsOf: url))
            XCTAssertTrue(value.confirms(kind))
            XCTAssertEqual(value.backupErasurePolicy, "pending-deployment-decision")
        }
    }
    func testOnlyMatchingDeletionAcknowledgmentConfirmsOutcome() throws {
        let reading = try JSONDecoder().decode(DeletionResult.self, from: Data(#"{"deleted":true,"accountRetained":true,"backupErasurePolicy":"pending-deployment-decision"}"#.utf8))
        XCTAssertTrue(reading.confirms(.readingData)); XCTAssertFalse(reading.confirms(.account))
        let account = try JSONDecoder().decode(DeletionResult.self, from: Data(#"{"deleted":true,"sessionRevoked":true,"backupErasurePolicy":"pending-deployment-decision"}"#.utf8))
        XCTAssertTrue(account.confirms(.account)); XCTAssertFalse(account.confirms(.readingData))
    }
}
