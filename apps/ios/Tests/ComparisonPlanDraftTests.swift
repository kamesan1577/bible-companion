import XCTest
@testable import CompanionCore

final class ComparisonPlanDraftTests: XCTestCase {
    func testFailedReplanCannotKeepEarlierConfirmation() {
        var draft = ComparisonPlanDraft()
        let first = draft.begin()
        XCTAssertTrue(draft.accept(plan: .string("first"), estimate: .string("old budget"), generation: first))
        _ = draft.begin() // A later HTTP failure must not resurrect the earlier estimate.
        XCTAssertNil(draft.plan); XCTAssertNil(draft.estimate)
    }
    func testNavigationOrInputChangeRejectsLatePlan() {
        var draft = ComparisonPlanDraft()
        let old = draft.begin(); draft.invalidate()
        XCTAssertFalse(draft.accept(plan: .string("wrong scope"), estimate: .null, generation: old))
        XCTAssertNil(draft.plan)
    }
    func testOnlyLatestResponseCanPopulateConfirmation() {
        var draft = ComparisonPlanDraft()
        let old = draft.begin(), latest = draft.begin()
        XCTAssertTrue(draft.accept(plan: .string("latest"), estimate: .string("current"), generation: latest))
        XCTAssertFalse(draft.accept(plan: .string("old"), estimate: .string("stale"), generation: old))
        XCTAssertEqual(draft.plan, .string("latest")); XCTAssertEqual(draft.estimate, .string("current"))
    }
}
