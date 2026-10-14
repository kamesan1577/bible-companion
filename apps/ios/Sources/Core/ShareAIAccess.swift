import Foundation

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
}
