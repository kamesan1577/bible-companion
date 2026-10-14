import XCTest
@testable import CompanionCore

final class ComparisonSessionTests: XCTestCase {
    func testJapaneseStatusLabelsKeepUnknownStatesExplicit() {
        XCTAssertEqual(ComparisonDisplay.status("expired"), "有効期限切れ")
        XCTAssertEqual(ComparisonDisplay.status("cancelled"), "中止済み")
        XCTAssertEqual(ComparisonDisplay.phase("ready"), "実行待ち")
        XCTAssertEqual(ComparisonDisplay.status("future-state"), "状態は未確認")
        XCTAssertEqual(ComparisonDisplay.phase("future-phase"), "処理段階は未確認")
    }

    let owner = "11111111-1111-4111-8111-111111111111"
    let now = Date(timeIntervalSince1970: 1_791_907_200)
    func pending() throws -> PendingComparison {
        let passage = Passage(book: "ACT", start: Verse(chapter: 18, verse: 24), end: Verse(chapter: 19, verse: 7))
        let passageJSON = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(passage))
        let plan: JSONValue = .object(["requestId": .string("22222222-2222-4222-8222-222222222222"), "models": .array(["model-A", "model-B"].map { .object(["modelId": .string($0), "settings": .object([:])]) }), "questions": .array([.object(["passage": passageJSON, "question": .string("背景は？"), "spoilerAllowed": .bool(false)])]), "saveResults": .bool(false)])
        return try PendingComparison(ownerID: owner, plan: plan, confirmationHash: String(repeating: "h", count: 43), createdAt: now)
    }
    func state(_ pending: PendingComparison, phase: String = "ready", completed: Int = 0, next: Int? = 0, active: Int? = nil, status: String = "running") -> ComparisonState {
        ComparisonState(requestId: pending.requestID, status: status, phase: phase, saved: false, trialCount: 2, completedCount: completed, nextTrialIndex: next, activeTrialIndex: active, expiresAt: now.timeIntervalSince1970 + 900, trials: .array([]), results: nil, errorCode: nil)
    }
    func testActualComparisonRouteFixtures() throws {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: Self.self)
        #endif
        func fixture<T: Decodable>(_ name: String) throws -> T {
            let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json"))
            return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
        }
        let start: ComparisonState = try fixture("comparison-start")
        let step: ComparisonStepResponse = try fixture("comparison-step")
        let expired: ComparisonState = try fixture("comparison-expired")
        let cancelled: ComparisonState = try fixture("comparison-cancelled-before-start")
        let ids = Set(start.trials.array.compactMap { $0["modelId"].string }).sorted()
        let plan: JSONValue = .object(["requestId": .string(start.requestId), "models": .array(ids.map { .object(["modelId": .string($0), "settings": .object([:])]) }), "questions": start.results?["questions"] ?? .array([]), "saveResults": .bool(start.saved)])
        let value = try PendingComparison(ownerID: owner, plan: plan, confirmationHash: String(repeating: "h", count: 43), createdAt: now)
        XCTAssertEqual(try value.nextTrial(in: start, at: now), 0)
        XCTAssertEqual(try value.nextTrial(in: step.state, at: now), 1)
        XCTAssertEqual(step.trialIndex, 0); XCTAssertNotNil(step.result)
        var expiredPlan = plan
        if case .object(var fields) = expiredPlan { fields["saveResults"] = .bool(false); expiredPlan = .object(fields) }
        let expiredPending = try PendingComparison(ownerID: owner, plan: expiredPlan, confirmationHash: String(repeating: "h", count: 43), createdAt: now)
        XCTAssertTrue(expired.isTerminal); XCTAssertNoThrow(try expiredPending.validate(expired))
        XCTAssertTrue(cancelled.isTerminal); XCTAssertNoThrow(try value.validate(cancelled))
    }
    func testOnlyServerReadyIndexCanAdvance() throws {
        let value = try pending()
        XCTAssertEqual(try value.nextTrial(in: state(value), at: now), 0)
        XCTAssertEqual(try value.nextTrial(in: state(value, completed: 1, next: 1), at: now), 1)
        XCTAssertNil(try value.nextTrial(in: state(value, phase: "executing", next: nil, active: 0), at: now))
        XCTAssertNil(try value.nextTrial(in: state(value, phase: "preparing", next: nil), at: now))
        XCTAssertNil(try value.nextTrial(in: state(value, phase: "terminal", completed: 2, next: nil, status: "complete"), at: now))
        XCTAssertNil(try value.nextTrial(in: state(value, phase: "terminal", next: nil, status: "expired"), at: now))
    }
    func testInvalidAdvanceAndExpiredStateRejected() throws {
        let value = try pending()
        XCTAssertThrowsError(try value.nextTrial(in: state(value, completed: 0, next: 1), at: now))
        XCTAssertThrowsError(try value.nextTrial(in: state(value, next: 0, active: 0), at: now))
        XCTAssertThrowsError(try value.nextTrial(in: state(value), at: now.addingTimeInterval(901)))
        XCTAssertThrowsError(try value.nextTrial(in: state(value, phase: "terminal", next: 0, status: "complete"), at: now))
    }
    func testUncertainIndexReplaysBeforeAdvancingAndNeedsAcknowledgment() throws {
        var value = try pending(); value.attemptedTrialIndex = 0
        let later = state(value, completed: 1, next: 1)
        XCTAssertEqual(try value.nextTrial(in: later, at: now), 0)
        XCTAssertFalse(try value.acknowledges(trial: 0, in: state(value, phase: "executing", next: nil, active: 0)))
        XCTAssertTrue(try value.acknowledges(trial: 0, in: later))
        value.attemptedTrialIndex = nil
        XCTAssertEqual(try value.nextTrial(in: later, at: now), 1)
    }
    func testPreStartCancellationTombstoneIsSafeTerminalException() throws {
        let value = try pending()
        let cancelled = ComparisonState(requestId: value.requestID, status: "cancelled", phase: "terminal", saved: false, trialCount: 0, completedCount: 0, nextTrialIndex: nil, activeTrialIndex: nil, expiresAt: nil, trials: .array([]), results: nil, errorCode: "cancelled_before_start")
        XCTAssertNoThrow(try value.validate(cancelled))
        XCTAssertNil(try value.nextTrial(in: cancelled, at: now))
        let wrong = ComparisonState(requestId: UUID().uuidString, status: "cancelled", phase: "terminal", saved: false, trialCount: 0, completedCount: 0, nextTrialIndex: nil, activeTrialIndex: nil, expiresAt: nil, trials: .array([]), results: nil, errorCode: "cancelled_before_start")
        XCTAssertThrowsError(try value.validate(wrong))
    }
    func testPresentationRedactionPreservesJobRecoveryMetadata() throws {
        let value = try pending()
        let original = state(value)
        let redacted = original.withoutResultBodies
        XCTAssertEqual(redacted.requestId, original.requestId); XCTAssertEqual(redacted.nextTrialIndex, original.nextTrialIndex)
        XCTAssertNil(redacted.results); XCTAssertNoThrow(try value.validate(redacted))
    }
    func testFrozenPlanRoundtripAndOwnerIsolation() throws {
        let value = try pending()
        let decoded = try JSONDecoder().decode(PendingComparison.self, from: JSONEncoder().encode(value))
        XCTAssertTrue(decoded.isValid(owner: owner, at: now)); XCTAssertEqual(decoded.plan, value.plan)
        XCTAssertFalse(decoded.isValid(owner: UUID().uuidString, at: now))
        XCTAssertEqual(decoded.startBody["confirmationHash"].string, value.confirmationHash)
        XCTAssertEqual(decoded.stepBody(index: 1)["plan"], value.plan)
    }
    func testSameModelDifferentModesFrozenButDuplicateOrUnknownModesRejected() throws {
        let original = try pending()
        guard case .object(let fields) = original.plan else { return XCTFail("Expected plan object") }
        func plan(_ modes: [String]) -> JSONValue {
            var copy = fields
            copy["models"] = .array(modes.map { .object(["modelId": .string("same-model"), "answerMode": .string($0), "settings": .object([:])]) })
            return .object(copy)
        }
        let frozen = plan(["reviewed-claim-selection", "grounded-generation"])
        let value = try PendingComparison(ownerID: owner, plan: frozen, confirmationHash: original.confirmationHash, createdAt: now)
        let restored = try JSONDecoder().decode(PendingComparison.self, from: JSONEncoder().encode(value))
        XCTAssertTrue(restored.isValid(owner: owner, at: now)); XCTAssertEqual(restored.stepBody(index: 1)["plan"], frozen)
        XCTAssertThrowsError(try PendingComparison(ownerID: owner, plan: plan(["grounded-generation", "grounded-generation"]), confirmationHash: original.confirmationHash, createdAt: now))
        XCTAssertThrowsError(try PendingComparison(ownerID: owner, plan: plan(["reviewed-claim-selection", "future-mode"]), confirmationHash: original.confirmationHash, createdAt: now))
    }

}
