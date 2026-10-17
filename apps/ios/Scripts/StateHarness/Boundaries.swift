// Fault-injection boundaries for AppStore control-flow tests only.
// These are not Apple framework declarations or Keychain/App Group implementations.
import Foundation
import CompanionCore

protocol ObservableObject: AnyObject {}
@propertyWrapper struct Published<Value> { var wrappedValue: Value; init(wrappedValue: Value) { self.wrappedValue = wrappedValue } }
enum InjectedFailure: Error { case locked }
struct StoredSession { let token: String; let expiresAt: TimeInterval; let user: Account }
enum SecurityError: Error { case cancelled }
@MainActor final class WebLogin {
    static var attempts = 0
    func login(client: APIClient) async throws -> TokenResponse { Self.attempts += 1; throw SecurityError.cancelled }
    func cancel() {}
}
@MainActor enum SessionVault {
    static var cleanupPending = false
    static var session: StoredSession?
    static var failRead = false
    static var failClear = false
    static var clears = 0
    static func read() throws -> StoredSession? { if failRead { throw InjectedFailure.locked }; return session }
    static func save(_ value: StoredSession) throws { session = value }
    static func clear() throws { clears += 1; if failClear { throw InjectedFailure.locked }; session = nil }
}
@MainActor enum PrivateHistoryStore {
    static var failRead = false
    static var clears = 0
    static func read(owner: String) throws -> [ImportRecord] { if failRead { throw InjectedFailure.locked }; return [] }
    static func save(_ value: [ImportRecord], owner: String) throws {}
    static func clear() throws { clears += 1 }
}
@MainActor enum ShareInbox {
    enum InboxError: Error { case unavailable, oversized, full }
    static var owner: String?
    static var shares: [PendingShare] = []
    static var failOwner = false
    static var unavailable = false
    static var failClear = false
    static var clears = 0
    static var capability: ShareAIAccess?
    static var accessSaveCount = 0
    static var accessVerifyCount = 0
    static var failAccessSave = false
    static var failAccessReadback = false
    static func setOwner(_ value: String?) throws {
        if unavailable { throw InboxError.unavailable }
        if failOwner { throw InjectedFailure.locked }
        if owner != value { capability = nil }
        owner = value
    }
    static func saveAIAccess(_ value: ShareAIAccess) throws {
        accessSaveCount += 1
        if failAccessSave { throw ShareAIAccessReadError.writeFailed }
        guard value.isValid(owner: owner) else { throw ShareAIAccessReadError.ownerMismatch }
        capability = value
        _ = try verifiedAIAccess(expectedOwner: value.ownerID)
    }
    static func verifiedAIAccess(expectedOwner: String? = nil) throws -> ShareAIAccess {
        accessVerifyCount += 1
        if unavailable { throw ShareAIAccessReadError.appGroupUnavailable }
        if failAccessReadback { throw ShareAIAccessReadError.writeFailed }
        guard let capability else { throw ShareAIAccessReadError.missing }
        guard expectedOwner == nil || expectedOwner == owner else { throw ShareAIAccessReadError.ownerMismatch }
        return try ShareAIAccess.validated(from: JSONEncoder().encode(capability), owner: owner)
    }
    static func renewableAIAccess(expectedOwner: String? = nil) throws -> ShareAIAccess {
        if unavailable { throw ShareAIAccessReadError.appGroupUnavailable }
        guard let capability else { throw ShareAIAccessReadError.missing }
        return try ShareAIAccess.validated(from: JSONEncoder().encode(capability), owner: expectedOwner ?? owner, allowingRenewal: true)
    }
    static func currentAIAccess(baseURL: URL, expectedOwner: String? = nil) async throws -> ShareAIAccess {
        try verifiedAIAccess(expectedOwner: expectedOwner)
    }
    static func clearAIAccess() throws {
        if unavailable { throw ShareAIAccessReadError.appGroupUnavailable }
        accessClears += 1; capability = nil
    }
    static var accessClears = 0
    static func submissionKey(share: PendingShare, owner: String, ranges: [Passage], translation: String?) throws -> String {
        // The state harness only needs a stable-shaped idempotency key; it does not
        // exercise the production SHA-256 derivation.
        "harness-\(share.id.uuidString)-\(owner)"
    }
    static func pending() throws -> [PendingShare] { if unavailable { throw InboxError.unavailable }; return shares }
    static func remove(_ id: UUID) throws { shares.removeAll { $0.id == id } }
    static func clear() throws {
        clears += 1
        if unavailable { throw InboxError.unavailable }
        if failClear { throw InjectedFailure.locked }
        owner = nil; capability = nil; shares = []
    }
}
@MainActor enum PendingQuestionStore {
    static var clears = 0; static var record: PendingQuestion?
    static func clear() throws { clears += 1; record = nil }
    static func read(owner: String) throws -> PendingQuestion? { record?.ownerID == owner ? record : nil }
    static func save(_ value: PendingQuestion) throws { record = value }
    static func remove(owner: String, request: String) throws { if record?.ownerID == owner && record?.requestID == request { record = nil } }
}
@MainActor enum ComparisonStore {
    static var clears = 0; static var record: PendingComparison?
    static func clear() throws { clears += 1; record = nil }
    static func read(owner: String) throws -> PendingComparison? { record?.ownerID == owner ? record : nil }
    static func save(_ value: PendingComparison) throws { record = value }
    static func remove(owner: String, requestID: String) throws { if record?.ownerID == owner && record?.requestID == requestID { record = nil } }
    static func recoveryRequestID(owner: String) throws -> String? { try read(owner: owner)?.requestID }
    static func removeRecovered(owner: String, requestID: String) throws { try remove(owner: owner, requestID: requestID) }
}
@MainActor enum ExportFiles { static var clears = 0; static func cleanup() throws { clears += 1 } }
