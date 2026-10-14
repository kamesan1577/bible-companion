import Foundation

public enum AnswerMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case reviewedClaimSelection = "reviewed-claim-selection"
    case groundedGeneration = "grounded-generation"
    public var id: String { rawValue }
    public var label: String { self == .groundedGeneration ? "根拠に基づく生成（実験的）" : "編集確認済みの説明から選択" }
    public static let groundedWarning = "実験的なAI解説です。引用資料と読書範囲を確認しても、説明の正確さや未読の出来事を暗示しないことは保証できません。本文と出典を確認してください。"
}
public struct AIPolicy: Codable, Sendable {
    public struct GroundedConsent: Codable, Sendable { public let accepted: Bool; public let policyVersion: String? }
    public let allowedAnswerModes: [AnswerMode]
    public let defaultAnswerMode: AnswerMode?
    public let groundedPolicyVersion: String
    public let groundedNoticeJa: String
    public let workersAiConsent: Bool
    public let groundedConsent: GroundedConsent
    public func permits(_ mode: AnswerMode) -> Bool {
        allowedAnswerModes.contains(mode) && workersAiConsent && (mode != .groundedGeneration || (groundedConsent.accepted && !groundedPolicyVersion.isEmpty && groundedConsent.policyVersion == groundedPolicyVersion))
    }
}
public struct GroundedConsentIntent: Sendable, Identifiable {
    public var id: String { ownerID + ":" + policy.groundedPolicyVersion }
    public let ownerID: String; public let sessionEpoch: UUID; public let policy: AIPolicy
    public init(ownerID: String, sessionEpoch: UUID, policy: AIPolicy) { self.ownerID = ownerID; self.sessionEpoch = sessionEpoch; self.policy = policy }
    public func permits(ownerID: String?, epoch: UUID, currentPolicy: AIPolicy?) -> Bool {
        self.ownerID == ownerID && UUID(uuidString: self.ownerID) != nil && sessionEpoch == epoch &&
        !policy.groundedPolicyVersion.isEmpty && policy.groundedPolicyVersion == currentPolicy?.groundedPolicyVersion
    }
}
