import Foundation
import XCTest
@testable import CompanionCore

final class PendingQuestionTests: XCTestCase {
    let owner = "11111111-1111-4111-8111-111111111111"
    let now = Date(timeIntervalSince1970: 1_791_907_200)
    func pending(question: String = "この場面の背景は？", owner: String? = nil, date: Date? = nil) -> PendingQuestion {
        PendingQuestion(ownerID: owner ?? self.owner, requestID: "22222222-2222-4222-8222-222222222222", conversationID: "33333333-3333-4333-8333-333333333333", question: question, sourceOnly: true, passageLabel: "使徒18:24–28", createdAt: date ?? now)
    }
    func testCurrentRoundtrip() throws {
        let value = try PendingQuestionCodec.decode(PendingQuestionCodec.encode(pending(), at: now), owner: owner, at: now)
        XCTAssertFalse(value.needsMigration); XCTAssertEqual(value.pending.question, pending().question)
    }
    func testLegacyMigrationPreservesFrozenIdentity() throws {
        let legacy = try JSONEncoder().encode(pending())
        let value = try PendingQuestionCodec.decode(legacy, owner: owner, at: now)
        XCTAssertTrue(value.needsMigration)
        let migrated = try PendingQuestionCodec.decode(PendingQuestionCodec.encode(value.pending, at: now), owner: owner, at: now)
        XCTAssertEqual(migrated.pending.requestID, pending().requestID)
    }
    func testFutureVersionBlocksReplayButRecoversCancellationID() throws {
        let data = try PendingQuestionCodec.encode(pending(), at: now)
        let future = Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"schemaVersion\":2", with: "\"schemaVersion\":9").utf8)
        XCTAssertThrowsError(try PendingQuestionCodec.decode(future, owner: owner, at: now))
        XCTAssertEqual(PendingQuestionCodec.recoveryRequestID(future, owner: owner), pending().requestID)
    }
    func testWrongOwnerNeverReadsOrRecovers() throws {
        let data = try PendingQuestionCodec.encode(pending(), at: now)
        let other = "44444444-4444-4444-8444-444444444444"
        XCTAssertThrowsError(try PendingQuestionCodec.decode(data, owner: other, at: now))
        XCTAssertNil(PendingQuestionCodec.recoveryRequestID(data, owner: other))
    }
    func testBoundsAndUTF16() {
        XCTAssertThrowsError(try PendingQuestionCodec.encode(pending(question: String(repeating: "😀", count: 1001)), at: now))
        XCTAssertThrowsError(try PendingQuestionCodec.encode(pending(question: "  "), at: now))
        XCTAssertThrowsError(try PendingQuestionCodec.encode(pending(date: now.addingTimeInterval(61)), at: now))
        XCTAssertThrowsError(try PendingQuestionCodec.decode(Data(repeating: 32, count: 32769), owner: owner, at: now))
        XCTAssertThrowsError(try PendingQuestionCodec.decode(Data("{bad".utf8), owner: owner, at: now))
    }
    func testOldUncertainRequestDoesNotExpireSilently() throws {
        let old = pending(date: now.addingTimeInterval(-86400 * 400))
        XCTAssertNoThrow(try PendingQuestionCodec.decode(PendingQuestionCodec.encode(old, at: now), owner: owner, at: now))
    }
    func testActualVersionOneWithoutModeMigratesOnlyToReviewed() throws {
        var record = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(pending())) as? [String: Any])
        record.removeValue(forKey: "answerMode")
        for object in [record, ["schemaVersion": 1, "pending": record]] {
            let value = try PendingQuestionCodec.decode(JSONSerialization.data(withJSONObject: object), owner: owner, at: now)
            XCTAssertTrue(value.needsMigration); XCTAssertEqual(value.pending.answerMode, .reviewedClaimSelection)
            XCTAssertEqual(value.pending.requestID, pending().requestID)
        }
    }
    func testVersionTwoFreezesGroundedModeInReplayBody() throws {
        let original = pending()
        let value = PendingQuestion(ownerID: owner, requestID: original.requestID, conversationID: original.conversationID, question: original.question, sourceOnly: false, passageLabel: original.passageLabel, createdAt: now, answerMode: .groundedGeneration)
        let restored = try PendingQuestionCodec.decode(PendingQuestionCodec.encode(value, at: now), owner: owner, at: now)
        XCTAssertFalse(restored.needsMigration); XCTAssertEqual(restored.pending.answerMode, .groundedGeneration)
        let body = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(restored.pending.body))
        XCTAssertEqual(body["answerMode"].string, "grounded-generation")
    }
    func testMissingUnknownOrLegacyGroundedModeCannotReplayButCanCancel() throws {
        let data = try PendingQuestionCodec.encode(pending(), at: now)
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for (version, mode) in [(2, nil as String?), (2, "future-mode"), (1, "grounded-generation")] {
            var changed = envelope, record = try XCTUnwrap(envelope["pending"] as? [String: Any])
            record["answerMode"] = mode; changed["pending"] = record; changed["schemaVersion"] = version
            let invalid = try JSONSerialization.data(withJSONObject: changed)
            XCTAssertThrowsError(try PendingQuestionCodec.decode(invalid, owner: owner, at: now))
            XCTAssertEqual(PendingQuestionCodec.recoveryRequestID(invalid, owner: owner), pending().requestID)
        }
    }

}
