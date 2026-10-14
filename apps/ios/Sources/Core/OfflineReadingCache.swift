import Foundation

public struct OfflineCachePolicy: Codable, Sendable {
    public struct Dependency: Codable, Hashable, Sendable { public let id: String; public let version: String }
    public let eligible: Bool
    public let maxAgeSeconds: Int
    public let reason: String
    public let allowedFields: [String]
    public let dependencies: [Dependency]
    public let policyVersion: Int
}
public struct ContentManifest: Codable, Sendable {
    public struct Item: Codable, Sendable { public let id: String; public let version: String; public let rights_status: String; public let active: Int; public let license: String; public let reviewed: Bool; public let visibility: String; public let generationAllowed: Bool }
    public let version: String
    public let items: [Item]
    public let checkedAt: TimeInterval
    public func isFresh(at date: Date = Date()) -> Bool { checkedAt <= date.timeIntervalSince1970 + 60 && checkedAt >= date.timeIntervalSince1970 - 300 }
    public func permits(_ dependency: OfflineCachePolicy.Dependency) -> Bool {
        items.contains { $0.id == dependency.id && $0.version == dependency.version && $0.rights_status == "approved" && $0.active == 1 && $0.license == "public-domain" && $0.reviewed && $0.visibility == "public" && $0.generationAllowed }
    }
}
public struct ReadingCacheKey: Codable, Hashable, Sendable {
    public let passage: Passage
    public let translation: String?
    public let spoilerAllowed: Bool
    public let language: String
    public init(passage: Passage, translation: String?, spoilerAllowed: Bool = false, language: String = "ja") {
        self.passage = passage; self.translation = translation; self.spoilerAllowed = spoilerAllowed; self.language = language
    }
    public var isValid: Bool {
        passage.isValid && language == "ja" && (translation == nil || translation!.range(of: #"^[A-Z0-9-]{1,30}$"#, options: .regularExpression) != nil)
    }
    var filename: String {
        "\(passage.book)-\(passage.start.chapter)-\(passage.start.verse)-\(passage.end.chapter)-\(passage.end.verse)-\(translation ?? "unknown")-\(spoilerAllowed ? "spoilers" : "bounded")-\(language).json"
    }
}
public enum OfflineCacheError: Error, Equatable { case ineligible, corrupt, unsupportedVersion, oversized }
public struct PublicReadingSnapshot: Codable, Sendable {
    public let schemaVersion: Int
    public let key: ReadingCacheKey
    public let sourceVersion: String
    public let overview: ReadingResponse.Overview
    public let policy: OfflineCachePolicy
    public let fetchedAt: Date
    public let expiresAt: Date
    public private(set) var lastValidatedAt: Date
    public private(set) var manifestVersion: String?
    public init(response: ReadingResponse, fetchedAt: Date = Date()) throws {
        guard let policy = response.offlineCache, policy.eligible, policy.policyVersion == 1,
              policy.allowedFields == ["overview"], policy.maxAgeSeconds > 0, policy.maxAgeSeconds <= 86_400,
              response.overview.mode == "source-only", !response.overview.modelInvoked,
              response.overview.contentKind == nil || response.overview.contentKind == "curated-reference",
              !response.overview.citations.isEmpty, response.overview.citations.allSatisfy({ $0.license == "public-domain" && $0.materialProvenance == nil && $0.passage.isValid }),
              policy.dependencies.count == response.overview.citations.count,
              Set(policy.dependencies).count == policy.dependencies.count,
              response.overview.citations.allSatisfy({ citation in policy.dependencies.contains { $0.id == citation.sourceId && $0.version == citation.version } }) else { throw OfflineCacheError.ineligible }
        guard let checkedAt = response.checkedAt, checkedAt <= fetchedAt.timeIntervalSince1970 + 60, checkedAt >= fetchedAt.timeIntervalSince1970 - 86_400 else { throw OfflineCacheError.ineligible }
        let key = ReadingCacheKey(passage: response.passage, translation: response.translation, spoilerAllowed: response.spoilerAllowed)
        guard key.isValid, let scope = try? QuestionScope(reading: key.passage, target: key.passage, spoilerAllowed: key.spoilerAllowed), response.overview.citations.allSatisfy({ scope.allowsSource($0.passage) }) else { throw OfflineCacheError.ineligible }
        schemaVersion = 1; self.key = key; sourceVersion = response.sourceVersion; overview = response.overview; self.policy = policy
        self.fetchedAt = fetchedAt; lastValidatedAt = fetchedAt; expiresAt = min(fetchedAt, Date(timeIntervalSince1970: checkedAt)).addingTimeInterval(TimeInterval(policy.maxAgeSeconds)); manifestVersion = nil
    }
    public func isUsable(at date: Date = Date()) -> Bool {
        schemaVersion == 1 && key.isValid && policy.eligible && policy.policyVersion == 1 && policy.allowedFields == ["overview"] && policy.maxAgeSeconds > 0 && policy.maxAgeSeconds <= 86_400 &&
        overview.mode == "source-only" && !overview.modelInvoked && (overview.contentKind == nil || overview.contentKind == "curated-reference") && !overview.citations.isEmpty &&
        overview.citations.allSatisfy { citation in citation.license == "public-domain" && citation.materialProvenance == nil && citation.passage.isValid && (key.spoilerAllowed || (citation.passage.book == key.passage.book && citation.passage.end <= key.passage.end)) && policy.dependencies.contains { $0.id == citation.sourceId && $0.version == citation.version } } &&
        date >= fetchedAt.addingTimeInterval(-60) && date < expiresAt && expiresAt <= fetchedAt.addingTimeInterval(TimeInterval(policy.maxAgeSeconds)) && lastValidatedAt <= date.addingTimeInterval(60) && lastValidatedAt >= fetchedAt.addingTimeInterval(-60)
    }
    public func isAllowed(by manifest: ContentManifest, at date: Date = Date()) -> Bool { manifest.isFresh(at: date) && !policy.dependencies.isEmpty && policy.dependencies.allSatisfy(manifest.permits) }
    public mutating func revalidate(using manifest: ContentManifest, at date: Date = Date()) throws {
        guard isUsable(at: date), isAllowed(by: manifest, at: date) else { throw OfflineCacheError.ineligible }
        lastValidatedAt = date; manifestVersion = manifest.version // Does not extend the hard body TTL.
    }
    public func readingResponse() -> ReadingResponse {
        ReadingResponse(passage: key.passage, translation: key.translation, spoilerAllowed: key.spoilerAllowed, sourceVersion: sourceVersion, overview: overview, materialNotice: "この端末には解説の概要のみ保存しています。地図・人物・絵画の資料は、接続後に確認できます。", cache: "device-public", offlineCache: policy, checkedAt: lastValidatedAt.timeIntervalSince1970, people: [], places: [], artworks: [])
    }
}

/// Non-content state lives outside protected cache files. A failed reconciliation
/// must remain fail-closed across process restarts, without erasing valid offline
/// caches merely because the network is unavailable.
public protocol PublicCacheValidationMarker: Sendable {
    func requiresValidation() -> Bool
    func setRequired(_ required: Bool)
}
public final class DefaultsPublicCacheMarker: PublicCacheValidationMarker, @unchecked Sendable {
    private let key: String
    public init(key: String) { self.key = "publicCacheValidationRequired." + key }
    public func requiresValidation() -> Bool { UserDefaults.standard.bool(forKey: key) }
    public func setRequired(_ required: Bool) { UserDefaults.standard.set(required, forKey: key) }
}

/// Stores public seed-derived overviews only. This directory never contains owner
/// IDs, import IDs, shared text, questions, answers, credentials, cards or images.
public actor PublicReadingCache {
    public static let maximumEntryBytes = 256_000
    private let root: URL
    private let marker: any PublicCacheValidationMarker
    private var validationAttempt: (id: UUID, previouslyRequired: Bool)?
    public init(directory: URL, marker: (any PublicCacheValidationMarker)? = nil) { root = directory; self.marker = marker ?? DefaultsPublicCacheMarker(key: "publicReadingOverviews.v1") }
    public func beginValidation() throws -> UUID {
        let attempt = UUID()
        validationAttempt = (attempt, validationAttempt?.previouslyRequired ?? marker.requiresValidation())
        marker.setRequired(true)
        guard marker.requiresValidation() else { throw OfflineCacheError.ineligible }
        return attempt
    }
    public func manifestReceived(_ attempt: UUID) {
        guard validationAttempt?.id == attempt else { return }
        // Once a manifest is observed, only reconciliation may clear the marker.
        validationAttempt = (attempt, true)
    }
    public func validationFailedBeforeManifest(_ attempt: UUID) {
        guard let current = validationAttempt, current.id == attempt else { return }
        if !current.previouslyRequired { marker.setRequired(false) }
        validationAttempt = nil
    }
    public func store(_ response: ReadingResponse, at date: Date = Date()) throws {
        let snapshot = try PublicReadingSnapshot(response: response, fetchedAt: date)
        try write(snapshot); try prune(at: date)
    }
    public func load(_ key: ReadingCacheKey, at date: Date = Date()) throws -> PublicReadingSnapshot? {
        guard key.isValid else { throw OfflineCacheError.ineligible }
        guard !marker.requiresValidation() else { return nil }
        let file = root.appendingPathComponent(key.filename)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let snapshot: PublicReadingSnapshot
        do { snapshot = try read(file) }
        catch let error as DecodingError { _ = error; try? FileManager.default.removeItem(at: file); return nil }
        catch is OfflineCacheError { try? FileManager.default.removeItem(at: file); return nil }
        catch { throw error }
        guard snapshot.key == key, snapshot.isUsable(at: date) else { try? FileManager.default.removeItem(at: file); return nil }
        return snapshot
    }
    public func reconcile(_ manifest: ContentManifest, at date: Date = Date(), attempt: UUID? = nil) throws {
        if let attempt, validationAttempt?.id != attempt { throw OfflineCacheError.ineligible }
        guard manifest.isFresh(at: date) else { throw OfflineCacheError.ineligible }
        marker.setRequired(true)
        try prepare()
        for file in try entries() {
            var snapshot: PublicReadingSnapshot
            do { snapshot = try read(file) }
            catch is DecodingError { try FileManager.default.removeItem(at: file); continue }
            catch is OfflineCacheError { try FileManager.default.removeItem(at: file); continue }
            catch { throw error } // Preserve protected/temporarily unreadable files.
            guard snapshot.isUsable(at: date), snapshot.isAllowed(by: manifest, at: date) else { try FileManager.default.removeItem(at: file); continue }
            try snapshot.revalidate(using: manifest, at: date); try write(snapshot)
        }
        marker.setRequired(false); validationAttempt = nil
    }
    public func invalidateAfterPolicyChange(_ key: ReadingCacheKey) throws {
        marker.setRequired(true)
        try remove(key)
    }
    public func remove(_ key: ReadingCacheKey) throws {
        guard key.isValid else { throw OfflineCacheError.ineligible }
        let file = root.appendingPathComponent(key.filename)
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
    private func prepare() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        #if os(iOS)
        var directory = root; var values = URLResourceValues(); values.isExcludedFromBackup = true; try directory.setResourceValues(values)
        #endif
    }
    private func entries() throws -> [URL] { try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" } }
    private func read(_ file: URL) throws -> PublicReadingSnapshot {
        let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
        let data = try handle.read(upToCount: Self.maximumEntryBytes + 1) ?? Data()
        guard data.count <= Self.maximumEntryBytes else { throw OfflineCacheError.oversized }
        return try JSONDecoder().decode(PublicReadingSnapshot.self, from: data)
    }
    private func write(_ snapshot: PublicReadingSnapshot) throws {
        try prepare(); let data = try JSONEncoder().encode(snapshot)
        guard data.count <= Self.maximumEntryBytes else { throw OfflineCacheError.oversized }
        #if os(iOS)
        try data.write(to: root.appendingPathComponent(snapshot.key.filename), options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: root.appendingPathComponent(snapshot.key.filename), options: .atomic)
        #endif
    }
    private func prune(at date: Date) throws {
        var valid: [(URL, Date)] = []
        for file in try entries() {
            do {
                let snapshot = try read(file)
                if snapshot.isUsable(at: date) { valid.append((file, snapshot.fetchedAt)) }
                else { try? FileManager.default.removeItem(at: file) }
            } catch is DecodingError { try? FileManager.default.removeItem(at: file) }
            catch is OfflineCacheError { try? FileManager.default.removeItem(at: file) }
            catch { continue }
        }
        for (file, _) in valid.sorted(by: { $0.1 > $1.1 }).dropFirst(64) { try FileManager.default.removeItem(at: file) }
    }
}
