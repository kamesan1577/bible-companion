import Foundation

public struct ComparisonState: Codable, Sendable {
    public let requestId: String
    public let status: String
    public let phase: String
    public let saved: Bool
    public let trialCount: Int
    public let completedCount: Int
    public let nextTrialIndex: Int?
    public let activeTrialIndex: Int?
    public let expiresAt: TimeInterval?
    public let trials: JSONValue
    public let results: JSONValue?
    public let errorCode: String?
    public var withoutResultBodies: Self { Self(requestId: requestId, status: status, phase: phase, saved: saved, trialCount: trialCount, completedCount: completedCount, nextTrialIndex: nextTrialIndex, activeTrialIndex: activeTrialIndex, expiresAt: expiresAt, trials: trials, results: nil, errorCode: errorCode) }
    public var terminalMessage: String {
        if status == "complete" { return "比較が完了しました。" }
        if let errorCode {
            if ["comparison_expired", "plan_changed", "source_policy_changed"].contains(errorCode) {
                return "比較は終了しました。" + NetworkFailure.server(status: 409, code: errorCode).userMessage
            }
            if let explanation = AIAvailabilityExplanation.message(for: errorCode, owner: true) { return "比較は終了しました。" + explanation }
            if errorCode == "cancelled_before_start" { return "比較は開始前に中止されました。" }
            return "比較は終了しました（\(errorCode)）。状態と利用量を確認してください。"
        }
        if status == "expired" { return NetworkFailure.server(status: 409, code: "comparison_expired").userMessage }
        if status == "cancelled" { return "比較を中止しました。実行済みの利用量が戻るとは限りません。" }
        return "比較は終了しました（\(status)）。状態と利用量を確認してください。"
    }
    public var isTerminal: Bool { phase == "terminal" && ["complete", "failed", "cancelled", "expired"].contains(status) }
}
public struct ActiveComparisonResponse: Codable, Sendable { public let comparison: ComparisonState? }
public struct ComparisonStepResponse: Codable, Sendable {
    public let state: ComparisonState
    public let trialIndex: Int
    public let result: AnswerResult?
    public let replayed: Bool
    public let resultAvailability: String
}
public struct PendingComparison: Codable, Sendable {
    public let schemaVersion: Int
    public let ownerID: String
    public let plan: JSONValue
    public let confirmationHash: String
    public let createdAt: Date
    public var attemptedTrialIndex: Int?
    public var requestID: String { plan["requestId"].string ?? "" }
    public var trialCount: Int { plan["models"].array.count * plan["questions"].array.count }
    public init(ownerID: String, plan: JSONValue, confirmationHash: String, createdAt: Date = Date()) throws {
        self.schemaVersion = 1; self.ownerID = ownerID; self.plan = plan; self.confirmationHash = confirmationHash; self.createdAt = createdAt; attemptedTrialIndex = nil
        guard isValid(owner: ownerID, at: createdAt) else { throw NetworkFailure.invalidResponse }
    }
    public func isValid(owner: String, at date: Date = Date()) -> Bool {
        guard schemaVersion == 1, ownerID == owner, UUID(uuidString: ownerID) != nil, UUID(uuidString: requestID) != nil,
              (20...256).contains(confirmationHash.utf8.count), createdAt.timeIntervalSince1970 > 0, createdAt <= date.addingTimeInterval(60),
              attemptedTrialIndex.map({ (0..<trialCount).contains($0) }) ?? true,
              (1...2).contains(plan["models"].array.count), (1...10).contains(plan["questions"].array.count), plan["saveResults"].bool != nil else { return false }
        let ids = plan["models"].array.compactMap { $0["modelId"].string }
        let modePairs = plan["models"].array.compactMap { model -> String? in
            guard let id = model["modelId"].string, let mode = AnswerMode(rawValue: model["answerMode"].string ?? "reviewed-claim-selection") else { return nil }
            return id + ":" + mode.rawValue
        }
        guard ids.count == plan["models"].array.count, modePairs.count == ids.count, Set(modePairs).count == ids.count, ids.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 256 }) else { return false }
        return plan["questions"].array.allSatisfy {
            guard let question = $0["question"].string, (1...2000).contains(question.utf16.count),
                  let data = try? JSONEncoder().encode($0["passage"]), let passage = try? JSONDecoder().decode(Passage.self, from: data) else { return false }
            return passage.isValid && $0["spoilerAllowed"].bool != nil
        }
    }
    public func validate(_ state: ComparisonState) throws {
        guard state.requestId == requestID else { throw NetworkFailure.invalidResponse }
        if state.status == "cancelled", state.phase == "terminal", state.errorCode == "cancelled_before_start",
           state.trialCount == 0, state.completedCount == 0, !state.saved, state.expiresAt == nil,
           state.nextTrialIndex == nil, state.activeTrialIndex == nil, state.trials == .array([]), state.results == nil || state.results == .null { return }
        guard state.trialCount == trialCount, state.saved == plan["saveResults"].bool,
              (0...trialCount).contains(state.completedCount), state.expiresAt?.isFinite == true,
              ["preparing", "ready", "executing", "terminal"].contains(state.phase),
              state.nextTrialIndex.map({ (0..<trialCount).contains($0) }) ?? true,
              state.activeTrialIndex.map({ (0..<trialCount).contains($0) }) ?? true else { throw NetworkFailure.invalidResponse }
        if state.phase == "ready" { guard state.nextTrialIndex == state.completedCount, state.activeTrialIndex == nil else { throw NetworkFailure.invalidResponse } }
        if state.phase == "terminal" { guard state.isTerminal, state.nextTrialIndex == nil else { throw NetworkFailure.invalidResponse } }
    }
    public func nextTrial(in state: ComparisonState, at date: Date = Date()) throws -> Int? {
        try validate(state)
        guard state.phase == "ready", state.activeTrialIndex == nil else { return nil }
        guard (state.expiresAt ?? 0) > date.timeIntervalSince1970 else { throw NetworkFailure.server(status: 409, code: "comparison_expired") }
        if let attemptedTrialIndex {
            guard let next = state.nextTrialIndex, attemptedTrialIndex <= next else { throw NetworkFailure.invalidResponse }
            return attemptedTrialIndex
        }
        return state.nextTrialIndex
    }
    public func acknowledges(trial index: Int, in state: ComparisonState) throws -> Bool {
        try validate(state)
        guard (0..<trialCount).contains(index) else { throw NetworkFailure.invalidResponse }
        return state.completedCount > index || state.isTerminal
    }
    public var startBody: JSONValue { .object(["plan": plan, "confirmationHash": .string(confirmationHash)]) }
    public func stepBody(index: Int) -> JSONValue { .object(["plan": plan, "confirmationHash": .string(confirmationHash), "trialIndex": .number(Double(index))]) }
}

public enum ComparisonDisplay {
    public static func status(_ code: String) -> String {
        switch code {
        case "queued": "待機中"
        case "running": "実行中"
        case "complete": "完了"
        case "failed": "失敗"
        case "cancelled": "中止済み"
        case "expired": "有効期限切れ"
        default: "状態は未確認"
        }
    }
    public static func phase(_ code: String) -> String {
        switch code {
        case "preparing": "準備中"
        case "ready": "実行待ち"
        case "executing": "実行中"
        case "terminal": "終了"
        default: "処理段階は未確認"
        }
    }
}
