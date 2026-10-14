import Foundation
import CryptoKit
import CompanionCore

/// App Group stores pending shares only, never credentials, answers or account history.
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
    static func setOwner(_ owner: String?) throws {
        guard owner == nil || UUID(uuidString: owner ?? "") != nil else { throw NetworkFailure.invalidResponse }
        try withLock { root in try Data((owner ?? "").utf8).write(to: root.appendingPathComponent("owner.marker"), options: [.atomic, .completeFileProtection]) }
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
