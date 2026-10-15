import Foundation

public struct PendingQuestion: Codable, Sendable {
    public let ownerID: String
    public let requestID: String
    public let conversationID: String
    public let question: String
    public let standardExplanation: Bool
    public let sourceOnly: Bool
    public let answerMode: AnswerMode
    let hasExplicitAnswerMode: Bool
    public let passageLabel: String
    public let createdAt: Date
    public init(ownerID: String, requestID: String, conversationID: String, question: String, sourceOnly: Bool, passageLabel: String, createdAt: Date, answerMode: AnswerMode = .reviewedClaimSelection, standardExplanation: Bool = false) {
        self.standardExplanation = standardExplanation; self.ownerID = ownerID; self.requestID = requestID; self.conversationID = conversationID; self.question = question; self.sourceOnly = sourceOnly; self.answerMode = answerMode; hasExplicitAnswerMode = true; self.passageLabel = passageLabel; self.createdAt = createdAt
    }
    private enum CodingKeys: String, CodingKey { case standardExplanation, ownerID, requestID, conversationID, question, sourceOnly, answerMode, passageLabel, createdAt }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        standardExplanation = try c.decodeIfPresent(Bool.self, forKey: .standardExplanation) ?? false
        ownerID = try c.decode(String.self, forKey: .ownerID); requestID = try c.decode(String.self, forKey: .requestID)
        conversationID = try c.decode(String.self, forKey: .conversationID); question = try c.decode(String.self, forKey: .question)
        sourceOnly = try c.decode(Bool.self, forKey: .sourceOnly); passageLabel = try c.decode(String.self, forKey: .passageLabel); createdAt = try c.decode(Date.self, forKey: .createdAt)
        let mode = try c.decodeIfPresent(AnswerMode.self, forKey: .answerMode); hasExplicitAnswerMode = mode != nil; answerMode = mode ?? .reviewedClaimSelection
    }
    public struct Body: Encodable, Sendable { public let requestId: String; public let question: String; public let sourceOnly: Bool; public let answerMode: AnswerMode }
    public var body: Body { Body(requestId: requestID, question: question, sourceOnly: sourceOnly, answerMode: answerMode) }
    public func isValid(owner: String, at date: Date = Date()) -> Bool {
        ownerID == owner && UUID(uuidString: ownerID) != nil && UUID(uuidString: requestID) != nil && UUID(uuidString: conversationID) != nil &&
        (1...2000).contains(question.utf16.count) && !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (1...300).contains(passageLabel.utf16.count) && createdAt.timeIntervalSince1970.isFinite && createdAt.timeIntervalSince1970 > 0 && createdAt <= date.addingTimeInterval(60)
    }
}
public enum PendingQuestionCodec {
    public static let maximumBytes = 32_768
    public enum Failure: Error { case oversized, unsupportedVersion, invalidRecord }
    private struct Envelope: Codable { let schemaVersion: Int; let pending: PendingQuestion }
    private struct Version: Decodable { let schemaVersion: Int? }
    public struct Decoded: Sendable { public let pending: PendingQuestion; public let needsMigration: Bool }
    public static func decode(_ data: Data, owner: String, at date: Date = Date()) throws -> Decoded {
        guard data.count <= maximumBytes else { throw Failure.oversized }
        let decoder = JSONDecoder()
        let version = try decoder.decode(Version.self, from: data).schemaVersion
        let pending: PendingQuestion
        if let version {
            guard version == 1 || version == 2 else { throw Failure.unsupportedVersion }
            pending = try decoder.decode(Envelope.self, from: data).pending
        } else { pending = try decoder.decode(PendingQuestion.self, from: data) }
        guard pending.isValid(owner: owner, at: date), version == 2 ? pending.hasExplicitAnswerMode : pending.answerMode == .reviewedClaimSelection else { throw Failure.invalidRecord }
        return Decoded(pending: pending, needsMigration: version != 2)
    }
    public static func encode(_ pending: PendingQuestion, at date: Date = Date()) throws -> Data {
        guard pending.isValid(owner: pending.ownerID, at: date) else { throw Failure.invalidRecord }
        let data = try JSONEncoder().encode(Envelope(schemaVersion: 2, pending: pending))
        guard data.count <= maximumBytes else { throw Failure.oversized }
        return data
    }
    /// Only permits status/cancel recovery, never replaying a future-schema body.
    public static func recoveryRequestID(_ data: Data, owner: String) -> String? {
        guard data.count <= maximumBytes, UUID(uuidString: owner) != nil,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let record = (object["pending"] as? [String: Any]) ?? object
        guard record["ownerID"] as? String == owner, let request = record["requestID"] as? String, UUID(uuidString: request) != nil else { return nil }
        return request
    }
}
