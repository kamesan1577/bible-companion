import Foundation
import CryptoKit
import Darwin
import CompanionCore

/// App Group stores pending shares and a limited, expiring share-only capability.
/// The general session token, private answers and account history are never shared.
/// Per-file atomic replacement avoids a read-modify-write race between app and extension.
enum ShareInbox {
    enum InboxError: Error { case unavailable, oversized, full, coordinationFailed }
    static var groupID: String {
        let configured = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String ?? "group.invalid.biblecompanion"
        let profileURL = Bundle.main.bundleURL.appendingPathComponent("embedded.mobileprovision")
        let groups: [String]?
        if FileManager.default.fileExists(atPath: profileURL.path) {
            groups = (try? Data(contentsOf: profileURL)).map(ProvisionedAppGroup.groups(inProfile:)) ?? []
        } else { groups = nil }
        return ProvisionedAppGroup.resolve(configured: configured, groups: groups) ?? "group.invalid.biblecompanion"
    }
    private static func directory() throws -> URL {
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else { throw InboxError.unavailable }
        let url = root.appendingPathComponent("PendingShares", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var writable = url; try writable.setResourceValues(values)
        return url
    }
    private static func withLock<T>(_ action: (URL) throws -> T) throws -> T {
        let root = try directory()
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinatorError: NSError?
        var outcome: Result<T, Error>?
        coordinator.coordinate(writingItemAt: root, options: [], error: &coordinatorError) { location in
            outcome = Result { try action(location) }
        }
        if let coordinatorError { throw coordinatorError }
        guard let outcome else { throw InboxError.coordinationFailed }
        return try outcome.get()
    }
    private static func readOwner(at root: URL) throws -> String? {
        let file = root.appendingPathComponent("owner.marker")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
        return try ShareOwnerMarker.decode(handle.read(upToCount: ShareOwnerMarker.maximumBytes + 1) ?? Data())
    }
    private static func isMissing(_ error: Error) -> Bool {
        let value = error as NSError
        return (value.domain == NSCocoaErrorDomain && value.code == CocoaError.fileReadNoSuchFile.rawValue)
            || (value.domain == NSPOSIXErrorDomain && value.code == Int(ENOENT))
    }
    private static func storageError(_ error: Error, writing: Bool = false) -> ShareAIAccessReadError {
        if let typed = error as? ShareAIAccessReadError { return typed }
        if let inbox = error as? InboxError, case .unavailable = inbox { return .appGroupUnavailable }
        let value = error as NSError
        if value.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(value.code) { return .protectedDataUnavailable }
        if value.domain == NSCocoaErrorDomain && [CocoaError.fileReadNoPermission.rawValue, CocoaError.fileWriteNoPermission.rawValue].contains(value.code) { return .protectedDataUnavailable }
        return writing ? .writeFailed : .readFailed
    }
    private static func readBytes(_ file: URL, limit: Int, missingAllowed: Bool = false) throws -> Data? {
        do {
            let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
            let data = try handle.read(upToCount: limit + 1) ?? Data()
            guard data.count <= limit else { throw ShareAIAccessReadError.corrupted }
            return data
        } catch {
            if missingAllowed && isMissing(error) { return nil }
            throw error
        }
    }

    private static func validatedAccess(at root: URL, expectedOwner: String? = nil) throws -> ShareAIAccess {
        let capability = root.appendingPathComponent("ai-access.capability")
        let data: Data
        do {
            guard let bytes = try readBytes(capability, limit: 4096) else { throw ShareAIAccessReadError.missing }
            data = bytes
        } catch {
            if isMissing(error) { throw ShareAIAccessReadError.missing }
            throw error
        }
        let ownerFile = root.appendingPathComponent("owner.marker")
        guard let ownerData = try readBytes(ownerFile, limit: ShareOwnerMarker.maximumBytes, missingAllowed: true) else {
            throw ShareAIAccessReadError.ownerMismatch
        }
        let decodedOwner: String?
        do { decodedOwner = try ShareOwnerMarker.decode(ownerData) }
        catch { throw ShareAIAccessReadError.corrupted }
        guard let owner = decodedOwner else { throw ShareAIAccessReadError.ownerMismatch }
        if let expectedOwner, expectedOwner != owner { throw ShareAIAccessReadError.ownerMismatch }
        return try ShareAIAccess.validated(from: data, owner: owner)
    }

    /// Reads and validates the share-only capability while preserving a safe reason
    /// for the extension to choose an appropriate user-facing recovery action.
    static func verifiedAIAccess(expectedOwner: String? = nil) throws -> ShareAIAccess {
        do {
            return try withLock { try validatedAccess(at: $0, expectedOwner: expectedOwner) }
        } catch {
            throw storageError(error)
        }
    }
    /// Records that the extension has opened this exact current capability.
    /// The receipt is diagnostic only and does not authorize access.
    static func acknowledgeExtensionRead(_ access: ShareAIAccess) throws {
        do {
            try withLock { root in
                let current = try validatedAccess(at: root, expectedOwner: access.ownerID)
                guard current.token == access.token, current.ownerID == access.ownerID,
                      current.expiresAt == access.expiresAt else { throw ShareAIAccessReadError.ownerMismatch }
                let receipt = ShareAIAccessReadReceipt(token: access.token, readAt: Date())
                let data = try JSONEncoder().encode(receipt)
                try data.write(to: root.appendingPathComponent("extension-read.receipt"), options: [.atomic, .completeFileProtection])
            }
        } catch {
            throw storageError(error, writing: true)
        }
    }

    /// Checks only whether a valid receipt matches the currently active capability.
    /// A missing or stale receipt is a normal false result; storage/corruption errors
    /// remain typed for callers that need to show a recovery state.
    static func extensionHasReadCurrentAccess(expectedOwner: String) throws -> Bool {
        do {
            return try withLock { root in
                let current = try validatedAccess(at: root, expectedOwner: expectedOwner)
                guard let data = try readBytes(root.appendingPathComponent("extension-read.receipt"), limit: 1024, missingAllowed: true) else { return false }
                return try ShareAIAccessReadReceipt.matches(data, token: current.token)
            }
        } catch {
            throw storageError(error)
        }
    }
    static func setOwner(_ owner: String?) throws {
        guard owner == nil || UUID(uuidString: owner ?? "") != nil else { throw NetworkFailure.invalidResponse }
        try withLock { root in
            if try readOwner(at: root) != owner {
                let file = root.appendingPathComponent("ai-access.capability")
                if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
                let receipt = root.appendingPathComponent("extension-read.receipt")
                if FileManager.default.fileExists(atPath: receipt.path) { try FileManager.default.removeItem(at: receipt) }
            }
            try Data((owner ?? "").utf8).write(to: root.appendingPathComponent("owner.marker"), options: [.atomic, .completeFileProtection])
        }
    }
    static func saveAIAccess(_ value: ShareAIAccess) throws {
        do {
            try withLock { root in
                let owner = try readOwner(at: root)
                let data = try JSONEncoder().encode(value)
                _ = try ShareAIAccess.validated(from: data, owner: owner)
                let file = root.appendingPathComponent("ai-access.capability")
                try data.write(to: file, options: [.atomic, .completeFileProtection])
                guard let saved = try readBytes(file, limit: 4096),
                      let verified = try? ShareAIAccess.validated(from: saved, owner: owner),
                      verified.token == value.token, verified.ownerID == value.ownerID,
                      verified.expiresAt == value.expiresAt else {
                    throw ShareAIAccessReadError.writeFailed
                }
                let receipt = root.appendingPathComponent("extension-read.receipt")
                if FileManager.default.fileExists(atPath: receipt.path) { try FileManager.default.removeItem(at: receipt) }
            }
        } catch {
            throw storageError(error, writing: true)
        }
    }
    static func aiAccess() throws -> ShareAIAccess? {
        do { return try verifiedAIAccess() }
        catch ShareAIAccessReadError.missing,
              ShareAIAccessReadError.expired,
              ShareAIAccessReadError.ownerMismatch,
              ShareAIAccessReadError.corrupted { return nil }
    }
    static func clearAIAccess() throws {
        try withLock { root in
            for name in ["ai-access.capability", "extension-read.receipt"] {
                let file = root.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
            }
        }
    }
    static func enqueue(_ text: String) throws {
        guard !text.isEmpty, text.utf16.count <= 20_000, text.utf8.count <= 60_000 else { throw InboxError.oversized }
        try withLock { root in
            guard try pending(at: root).count < 20 else { throw InboxError.full }
            let share = PendingShare(ownerID: try readOwner(at: root), text: text)
            let url = root.appendingPathComponent(share.id.uuidString).appendingPathExtension("json")
            try JSONEncoder().encode(share).write(to: url, options: [.atomic, .completeFileProtection])
        }
    }
    static func pending() throws -> [PendingShare] { try withLock { try pending(at: $0) } }
    private static func pending(at root: URL) throws -> [PendingShare] {
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        return try files.compactMap { url in
            let handle = try FileHandle(forReadingFrom: url)
            let data: Data
            do { data = try handle.read(upToCount: 256_001) ?? Data(); try handle.close() }
            catch { try? handle.close(); throw error } // Preserve protected/transient read failures.
            guard data.count <= 256_000 else { throw InboxError.oversized }
            guard let share = try? JSONDecoder().decode(PendingShare.self, from: data), !share.isExpired() else { try FileManager.default.removeItem(at: url); return nil }
            return share
        }.sorted { $0.createdAt < $1.createdAt }
    }
    static func submissionKey(share: PendingShare, owner: String, ranges: [Passage], translation: String?) throws -> String {
        struct Identity: Encodable { let shareID: UUID; let owner: String; let ranges: [Passage]; let translation: String? }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let digest = SHA256.hash(data: try encoder.encode(Identity(shareID: share.id, owner: owner, ranges: ranges, translation: translation)))
        var bytes = Array(digest.prefix(16)); bytes[6] = (bytes[6] & 0x0f) | 0x40; bytes[8] = (bytes[8] & 0x3f) | 0x80
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let lengths = [8, 4, 4, 4, 12]; var index = hex.startIndex
        return lengths.map { length in let end = hex.index(index, offsetBy: length); defer { index = end }; return String(hex[index..<end]) }.joined(separator: "-")
    }
    static func remove(_ id: UUID) throws { try withLock { root in try FileManager.default.removeItem(at: root.appendingPathComponent(id.uuidString).appendingPathExtension("json")) } }
    static func clear() throws {
        try withLock { root in
            for name in ["ai-access.capability", "extension-read.receipt"] {
                let file = root.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
            }
            try Data().write(to: root.appendingPathComponent("owner.marker"), options: [.atomic, .completeFileProtection])
            for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) where url.pathExtension == "json" { try FileManager.default.removeItem(at: url) }
        }
    }
}

/// Account-scoped history metadata only. No shared source bodies/AI answers persist.
/// Public overview caching has a separate rights/TTL policy in CompanionCore.
enum PrivateHistoryStore {
    private static func root() throws -> URL {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("PrivateHistory", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var writable = root; try writable.setResourceValues(values)
        return root
    }
    private static func file(owner: String) throws -> URL {
        guard UUID(uuidString: owner) != nil else { throw NetworkFailure.invalidResponse }
        return try root().appendingPathComponent(owner).appendingPathExtension("json")
    }
    static func read(owner: String) throws -> [ImportRecord] {
        let path = try file(owner: owner)
        guard FileManager.default.fileExists(atPath: path.path) else { return [] }
        return try JSONDecoder().decode([ImportRecord].self, from: Data(contentsOf: path))
    }
    static func save(_ items: [ImportRecord], owner: String) throws { try JSONEncoder().encode(items).write(to: file(owner: owner), options: [.atomic, .completeFileProtection]) }
    static func clear() throws { let path = try root(); for file in try FileManager.default.contentsOfDirectory(at: path, includingPropertiesForKeys: nil) { try FileManager.default.removeItem(at: file) } }
}

enum PendingQuestionStore {
    private static func root() throws -> URL {
        var root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("PendingQuestions", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true; try root.setResourceValues(values)
        return root
    }
    private static func file(owner: String) throws -> URL {
        guard UUID(uuidString: owner) != nil else { throw NetworkFailure.invalidResponse }
        return try root().appendingPathComponent(owner).appendingPathExtension("json")
    }
    private static func readBytes(_ path: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: path); defer { try? handle.close() }
        let data = try handle.read(upToCount: PendingQuestionCodec.maximumBytes + 1) ?? Data()
        guard data.count <= PendingQuestionCodec.maximumBytes else { throw PendingQuestionCodec.Failure.oversized }
        return data
    }
    static func recoveryRequestID(owner: String) throws -> String? {
        try PendingQuestionCodec.recoveryRequestID(readBytes(file(owner: owner)), owner: owner)
    }
    static func removeRecovered(owner: String, request: String) throws {
        guard try recoveryRequestID(owner: owner) == request else { return }
        try FileManager.default.removeItem(at: file(owner: owner))
    }
    static func read(owner: String) throws -> PendingQuestion? {
        let path = try file(owner: owner)
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        let decoded = try PendingQuestionCodec.decode(readBytes(path), owner: owner)
        if decoded.needsMigration { try PendingQuestionCodec.encode(decoded.pending).write(to: path, options: [.atomic, .completeFileProtection]) }
        return decoded.pending
    }
    static func save(_ pending: PendingQuestion) throws {
        if let existing = try read(owner: pending.ownerID), existing.requestID != pending.requestID { throw NetworkFailure.server(status: 409, code: "pending_request_unresolved") }
        try PendingQuestionCodec.encode(pending).write(to: file(owner: pending.ownerID), options: [.atomic, .completeFileProtection])
    }
    static func remove(owner: String, request: String) throws {
        guard try read(owner: owner)?.requestID == request else { return }
        try FileManager.default.removeItem(at: file(owner: owner))
    }
    static func clear() throws { for url in try FileManager.default.contentsOfDirectory(at: root(), includingPropertiesForKeys: nil) { try FileManager.default.removeItem(at: url) } }
}
