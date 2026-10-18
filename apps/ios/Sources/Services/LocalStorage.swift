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
    /// Read-only diagnostics: never include paths, group/team IDs, owners or tokens.
    /// Profile metadata is not proof that the extension has opened its container.
    static func diagnosticReport() -> String {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        var lines = ["共有設定の診断 / \(version) (\(build))"]
        let profile = bundle.bundleURL.appendingPathComponent("embedded.mobileprovision")
        lines.append("本体の署名プロファイル：" + (FileManager.default.fileExists(atPath: profile.path) ? "あり" : "なし（Simulator・未再署名の可能性）"))
        let resolved = groupID
        lines.append("本体の共有グループ選択：" + (resolved == "group.invalid.biblecompanion" ? "確認できない" : "候補を選択済み"))
        let container = resolved == "group.invalid.biblecompanion" ? nil : FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: resolved)
        lines.append("本体の共有保存先：" + (container == nil ? "OSから取得できない" : "OSから取得できた"))
        if let plugins = bundle.builtInPlugInsURL,
           let urls = try? FileManager.default.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil),
           let extensionBundle = urls.filter({ $0.pathExtension == "appex" }).compactMap({ Bundle(url: $0) }).first {
            let configured = extensionBundle.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String ?? ""
            let url = extensionBundle.bundleURL.appendingPathComponent("embedded.mobileprovision")
            let exists = FileManager.default.fileExists(atPath: url.path)
            let groups = exists ? (try? Data(contentsOf: url)).map(ProvisionedAppGroup.groups(inProfile:)) ?? [] : nil
            let extensionGroup = ProvisionedAppGroup.resolve(configured: configured, groups: groups)
            lines.append("同梱共有拡張のグループ候補：" + (extensionGroup == resolved ? "本体と一致" : "本体との一致を確認できない"))
            lines.append("共有拡張の実際の読み取り：この診断だけでは未確認")
        } else { lines.append("同梱共有拡張：確認できない") }
        do {
            guard let container else { throw ShareAIAccessReadError.appGroupUnavailable }
            // Diagnostics inspect existing bytes only; no directory creation, lock or writes.
            _ = try validatedAccess(at: container.appendingPathComponent("PendingShares", isDirectory: true), allowingRenewal: true)
            lines.append("共有設定の読み取り：成功（診断のみ・送信許可ではありません）")
        }
        catch {
            if let failure = error as? ShareStorageFailure { lines.append("共有設定の読み取り：" + String(describing: failure.reason) + " (" + failure.diagnosticCode + ")") }
            else if let reason = ShareStorageFailure.reason(for: error) { lines.append("共有設定の読み取り：" + String(describing: reason)) }
            else { lines.append("共有設定の読み取り：原因未特定") }
        }
        lines.append("読み取りのみ。設定・ログイン・読書の記録は変更していません。署名権限はこの画面から変更できません。")
        return lines.joined(separator: "\n")
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
        let root: URL
        do { root = try directory() } catch { throw storageError(error, stage: .directory) }
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinatorError: NSError?
        var outcome: Result<T, Error>?
        coordinator.coordinate(writingItemAt: root, options: [], error: &coordinatorError) { location in
            outcome = Result { try action(location) }
        }
        if let coordinatorError { throw storageError(coordinatorError, stage: .coordination) }
        guard let outcome else { throw ShareStorageFailure(ShareAIAccessReadError.coordinationFailed, stage: .coordination) }
        return try outcome.get()
    }
    private static func readOwner(at root: URL) throws -> String? {
        let file = root.appendingPathComponent("owner.marker")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        do {
            let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
            let data = try handle.read(upToCount: ShareOwnerMarker.maximumBytes + 1) ?? Data()
            do { return try ShareOwnerMarker.decode(data) }
            catch { throw ShareStorageFailure(ShareAIAccessReadError.corrupted, stage: .ownerRead) }
        } catch { throw storageError(error, stage: .ownerRead) }
    }
    private static func isMissing(_ error: Error) -> Bool { ShareStorageFailure.isMissing(error) }
    private static func storageError(_ error: Error, writing: Bool = false, stage: ShareStorageFailure.Stage = .operation) -> Error {
        if error is ShareStorageFailure || error is ShareAIAccessReadError { return error }
        if let inbox = error as? InboxError, case .unavailable = inbox { return ShareAIAccessReadError.appGroupUnavailable }
        return ShareStorageFailure(error, stage: stage, writing: writing)
    }
    private static func readBytes(_ file: URL, limit: Int, missingAllowed: Bool = false, stage: ShareStorageFailure.Stage = .operation) throws -> Data? {
        do {
            let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
            let data = try handle.read(upToCount: limit + 1) ?? Data()
            guard data.count <= limit else { throw ShareAIAccessReadError.corrupted }
            return data
        } catch {
            if missingAllowed && isMissing(error) { return nil }
            throw storageError(error, stage: stage)
        }
    }

    private static func validatedAccess(at root: URL, expectedOwner: String? = nil, allowingRenewal: Bool = false) throws -> ShareAIAccess {
        let capability = root.appendingPathComponent("ai-access.capability")
        let data: Data
        do {
            guard let bytes = try readBytes(capability, limit: 4096, stage: .capabilityRead) else { throw ShareAIAccessReadError.missing }
            data = bytes
        } catch {
            if isMissing(error) { throw ShareAIAccessReadError.missing }
            throw error
        }
        let ownerFile = root.appendingPathComponent("owner.marker")
        guard let ownerData = try readBytes(ownerFile, limit: ShareOwnerMarker.maximumBytes, missingAllowed: true, stage: .ownerRead) else {
            throw ShareAIAccessReadError.ownerMismatch
        }
        let decodedOwner: String?
        do { decodedOwner = try ShareOwnerMarker.decode(ownerData) }
        catch { throw ShareAIAccessReadError.corrupted }
        guard let owner = decodedOwner else { throw ShareAIAccessReadError.ownerMismatch }
        if let expectedOwner, expectedOwner != owner { throw ShareAIAccessReadError.ownerMismatch }
        return try ShareAIAccess.validated(from: data, owner: owner, allowingRenewal: allowingRenewal)
    }

    /// Reads and validates the share-only capability while preserving a safe reason
    /// for the extension to choose an appropriate user-facing recovery action.
    static func verifiedAIAccess(expectedOwner: String? = nil) throws -> ShareAIAccess {
        do {
            return try withLock { try validatedAccess(at: $0, expectedOwner: expectedOwner) }
        } catch {
            if ShareStorageFailure.reason(for: error) == .missing { throw ShareAIAccessReadError.missing }
            throw storageError(error)
        }
    }
    static func renewableAIAccess(expectedOwner: String? = nil) throws -> ShareAIAccess {
        do { return try withLock { try validatedAccess(at: $0, expectedOwner: expectedOwner, allowingRenewal: true) } }
        catch {
            if ShareStorageFailure.reason(for: error) == .missing { throw ShareAIAccessReadError.missing }
            throw storageError(error)
        }
    }
    /// Compare-and-save rejects a late renewal after logout, account change or another refresh.
    static func saveRenewedAIAccess(_ value: ShareAIAccess, replacing previous: ShareAIAccess) throws {
        try withLock { root in
            let current = try validatedAccess(at: root, expectedOwner: previous.ownerID, allowingRenewal: true)
            guard current.token == previous.token, current.conversationScope == previous.conversationScope,
                  current.refreshToken == previous.refreshToken, value.ownerID == current.ownerID,
                  value.conversationScope == current.conversationScope, value.refreshToken == current.refreshToken else { throw ShareAIAccessReadError.ownerMismatch }
            let bytes = try JSONEncoder().encode(value)
            _ = try ShareAIAccess.validated(from: bytes, owner: current.ownerID)
            let path = root.appendingPathComponent("ai-access.capability")
            do { try bytes.write(to: path, options: [.atomic, .completeFileProtection]) }
            catch { throw storageError(error, writing: true, stage: .capabilityWrite) }
            guard let saved = try readBytes(path, limit: 4096, stage: .readback), saved == bytes else { throw ShareStorageFailure(ShareAIAccessReadError.writeFailed, stage: .readback) }
        }
    }
    /// At most one network renewal per caller; no question or inference is sent.
    static func currentAIAccess(baseURL: URL, expectedOwner: String? = nil) async throws -> ShareAIAccess {
        let old = try renewableAIAccess(expectedOwner: expectedOwner)
        guard old.expiresAt <= Date().addingTimeInterval(3600).timeIntervalSince1970, old.canRenew(), let refreshToken = old.refreshToken else { return try verifiedAIAccess(expectedOwner: expectedOwner) }
        let renewalClient = try APIClient(baseURL: baseURL); await renewalClient.setToken(refreshToken)
        let value: ShareAIAccess = try await renewalClient.post("/share/renew", body: [String: String]())
        try Task.checkCancellation()
        do { try saveRenewedAIAccess(value, replacing: old) }
        catch ShareAIAccessReadError.ownerMismatch {
            // Another process may have renewed the same scope while this call was in flight.
            let current = try verifiedAIAccess(expectedOwner: old.ownerID)
            guard current.conversationScope == old.conversationScope, current.refreshToken == old.refreshToken else { throw ShareAIAccessReadError.ownerMismatch }
            return current
        }
        return try verifiedAIAccess(expectedOwner: old.ownerID)
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
    /// Local identity marker only; reading it does not grant AI access.
    static func localDraftOwner() throws -> String? { try withLock { try readOwner(at: $0) } }
    static func saveChatGPTHandoff(prompt: String, expectedOwner: String?) throws {
        try withLock { root in
            guard try readOwner(at: root) == expectedOwner else { throw NetworkFailure.invalidResponse }
            let value = ChatGPTHandoff(ownerID: expectedOwner, prompt: prompt)
            guard value.isUsable(ownerID: expectedOwner) else { throw InboxError.oversized }
            try JSONEncoder().encode(value).write(to: root.appendingPathComponent("chatgpt.handoff"), options: [.atomic, .completeFileProtection])
        }
    }
    static func chatGPTHandoff(expectedOwner: String?) throws -> ChatGPTHandoff? {
        try withLock { root in
            let path = root.appendingPathComponent("chatgpt.handoff")
            guard let bytes = try readBytes(path, limit: 128_000, missingAllowed: true) else { return nil }
            let value = try JSONDecoder().decode(ChatGPTHandoff.self, from: bytes)
            guard try readOwner(at: root) == expectedOwner, value.ownerID == expectedOwner else { return nil }
            guard value.isUsable(ownerID: expectedOwner) else { try FileManager.default.removeItem(at: path); return nil }
            return value
        }
    }
    static func removeChatGPTHandoff(expected: ChatGPTHandoff) throws {
        try withLock { root in
            let path = root.appendingPathComponent("chatgpt.handoff")
            guard try readOwner(at: root) == expected.ownerID,
                  let bytes = try readBytes(path, limit: 128_000, missingAllowed: true),
                  try JSONDecoder().decode(ChatGPTHandoff.self, from: bytes) == expected else { throw NetworkFailure.invalidResponse }
            try FileManager.default.removeItem(at: path)
        }
    }

    static func setOwner(_ owner: String?) throws {
        guard owner == nil || UUID(uuidString: owner ?? "") != nil else { throw NetworkFailure.invalidResponse }
        try withLock { root in
            if try readOwner(at: root) != owner {
                let handoff = root.appendingPathComponent("chatgpt.handoff")
                if FileManager.default.fileExists(atPath: handoff.path) { try FileManager.default.removeItem(at: handoff) }
                let file = root.appendingPathComponent("ai-access.capability")
                if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
                let receipt = root.appendingPathComponent("extension-read.receipt")
                if FileManager.default.fileExists(atPath: receipt.path) { try FileManager.default.removeItem(at: receipt) }
            }
            do { try Data((owner ?? "").utf8).write(to: root.appendingPathComponent("owner.marker"), options: [.atomic, .completeFileProtection]) }
            catch { throw storageError(error, writing: true, stage: .ownerWrite) }
        }
    }
    static func saveAIAccess(_ value: ShareAIAccess) throws {
        do {
            try withLock { root in
                let owner = try readOwner(at: root)
                let data = try JSONEncoder().encode(value)
                do { _ = try ShareAIAccess.validated(from: data, owner: owner) }
                catch { throw ShareStorageFailure(error, stage: .validation) }
                let file = root.appendingPathComponent("ai-access.capability")
                do { try data.write(to: file, options: [.atomic, .completeFileProtection]) }
                catch { throw storageError(error, writing: true, stage: .capabilityWrite) }
                guard let saved = try readBytes(file, limit: 4096, stage: .readback),
                      let verified = try? ShareAIAccess.validated(from: saved, owner: owner),
                      verified.token == value.token, verified.ownerID == value.ownerID,
                      verified.expiresAt == value.expiresAt else {
                    throw ShareStorageFailure(ShareAIAccessReadError.writeFailed, stage: .readback)
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
            for name in ["ai-access.capability", "extension-read.receipt", "chatgpt.handoff"] {
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

/// Device presentation only; outside the account-owned inbox and AI consent.
enum SharePresentationPreferences {
    private static func file() throws -> URL {
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: ShareInbox.groupID) else { throw ShareInbox.InboxError.unavailable }
        let folder = root.appendingPathComponent("Presentation", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var writable = folder; try writable.setResourceValues(values)
        return folder.appendingPathComponent("chatgpt-button.json")
    }
    static func isChatGPTVisible() throws -> Bool {
        let url = try file()
        guard FileManager.default.fileExists(atPath: url.path) else { return true }
        return try JSONDecoder().decode(Bool.self, from: Data(contentsOf: url))
    }
    static func setChatGPTVisible(_ value: Bool) throws {
        try JSONEncoder().encode(value).write(to: file(), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
