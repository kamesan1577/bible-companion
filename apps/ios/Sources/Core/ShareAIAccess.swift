import Foundation
import CryptoKit

/// Safe reason codes for capability-storage failures. Cases intentionally carry no
/// token, account identifier, file path, or underlying error text.
public enum ShareAIAccessReadError: Error, Equatable, Sendable {
    case appGroupUnavailable
    case protectedDataUnavailable
    case readFailed
    case missing
    case expired
    case ownerMismatch
    case corrupted
    case writeFailed
}

/// Limited first-party share capability, never the general account session.
public struct ShareAIAccess: Codable, Sendable {
    public let token: String
    public let ownerID: String
    public let expiresAt: TimeInterval
    public init(token: String, ownerID: String, expiresAt: TimeInterval) { self.token = token; self.ownerID = ownerID; self.expiresAt = expiresAt }
    private enum CodingKeys: String, CodingKey { case token, ownerID = "ownerId", expiresAt }
    public func isValid(owner: String?, at date: Date = Date()) -> Bool {
        guard owner == ownerID, UUID(uuidString: ownerID) != nil, expiresAt.isFinite,
              expiresAt > date.timeIntervalSince1970, expiresAt <= date.addingTimeInterval(86460).timeIntervalSince1970 else { return false }
        return token.range(of: #"^bcs1_[a-f0-9]{64}$"#, options: .regularExpression) != nil
    }

    /// Validates stored capability bytes without collapsing useful failure reasons.
    /// The caller should surface the error case, never the underlying data.
    public static func validated(from data: Data, owner: String?, at date: Date = Date()) throws -> ShareAIAccess {
        guard data.count <= 4096,
              let value = try? JSONDecoder().decode(ShareAIAccess.self, from: data),
              UUID(uuidString: value.ownerID) != nil,
              value.expiresAt.isFinite,
              value.token.range(of: #"^bcs1_[a-f0-9]{64}$"#, options: .regularExpression) != nil,
              value.expiresAt <= date.addingTimeInterval(86460).timeIntervalSince1970 else {
            throw ShareAIAccessReadError.corrupted
        }
        guard owner == value.ownerID else { throw ShareAIAccessReadError.ownerMismatch }
        guard value.expiresAt > date.timeIntervalSince1970 else { throw ShareAIAccessReadError.expired }
        return value
    }
}

/// A digest-only receipt that the share extension opened the current capability.
/// It stores neither the capability token nor account identity.
public struct ShareAIAccessReadReceipt: Codable, Sendable {
    public let tokenDigest: String
    public let readAt: TimeInterval

    public init(token: String, readAt: Date) {
        self.tokenDigest = Self.digest(token)
        self.readAt = readAt.timeIntervalSince1970
    }

    private enum CodingKeys: String, CodingKey { case tokenDigest, readAt }

    public static func digest(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Returns false for a valid but stale receipt; malformed or future-dated
    /// receipts are reported as corruption so callers can distinguish repair needs.
    public static func matches(_ data: Data, token: String, at date: Date = Date()) throws -> Bool {
        guard data.count <= 1024,
              let receipt = try? JSONDecoder().decode(ShareAIAccessReadReceipt.self, from: data),
              receipt.tokenDigest.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil,
              receipt.readAt.isFinite,
              receipt.readAt > 0,
              receipt.readAt <= date.timeIntervalSince1970 else {
            throw ShareAIAccessReadError.corrupted
        }
        return receipt.tokenDigest == digest(token)
    }
}

/// App-side saved state only; does not assert extension access or API acceptance.
public enum SharePreparationReadiness {
    public static func isSaved(policy: AIPolicy?, owner: String?, access: ShareAIAccess?, at date: Date = Date()) -> Bool {
        guard let policy, policy.shareAiEnabled == true, policy.shareAiConsent == true,
              policy.permits(.groundedGeneration), let owner, let access else { return false }
        return access.isValid(owner: owner, at: date)
    }
}
