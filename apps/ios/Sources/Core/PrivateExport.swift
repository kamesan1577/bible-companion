import Foundation

public struct ExportSnapshot: Codable, Sendable {
    public let version: Int
    public let snapshotId: String
    public let createdAt: TimeInterval
    public let expiresAt: TimeInterval
    public let sections: [String]
    public let maxPageBytes: Int
    public let maxPageItems: Int
    public let user: Account
    public let settings: JSONValue
    public let modelPreference: JSONValue?
}
public struct ExportPage: Codable, Sendable {
    public let version: Int
    public let snapshotId: String
    public let section: String
    public let items: [JSONValue]
    public let nextCursor: String?
}
public enum ExportFailure: Error, Equatable { case invalidSnapshot, invalidPage, expired, cursorLoop, incomplete, closed }

/// Writes one bounded page at a time. Never assembles the whole account in RAM.
/// The caller must remove output after cancellation, error or sharing completion.
public actor PrivateExportAssembler {
    public static let sections = ["imports", "conversations", "messages", "comparisons"]
    private let snapshot: ExportSnapshot
    private let file: URL
    private let handle: FileHandle
    private var sectionIndex = 0
    private var itemCount = 0
    private var cursor: String?
    private var seenCursors = Set<String>()
    private var closed = false
    public init(snapshot: ExportSnapshot, ownerID: String, directory: URL, at date: Date = Date(), initialWrite: @Sendable (FileHandle, Data) throws -> Void = { try $0.write(contentsOf: $1) }) throws {
        guard snapshot.version == 1, UUID(uuidString: snapshot.snapshotId) != nil,
              snapshot.user.id == ownerID, UUID(uuidString: ownerID) != nil,
              snapshot.sections == Self.sections, snapshot.maxPageItems > 0, snapshot.maxPageItems <= 25,
              snapshot.maxPageBytes > 0, snapshot.maxPageBytes <= 1_048_576,
              snapshot.createdAt.isFinite, snapshot.expiresAt.isFinite,
              snapshot.createdAt <= date.timeIntervalSince1970 + 60,
              snapshot.expiresAt > date.timeIntervalSince1970,
              snapshot.expiresAt <= snapshot.createdAt + 900 else { throw ExportFailure.invalidSnapshot }
        struct Metadata: Encodable {
            let version: Int; let snapshotId: String; let createdAt: TimeInterval; let expiresAt: TimeInterval
            let user: Account; let settings: JSONValue; let modelPreference: JSONValue?
        }
        let data = try JSONEncoder().encode(Metadata(version: snapshot.version, snapshotId: snapshot.snapshotId, createdAt: snapshot.createdAt, expiresAt: snapshot.expiresAt, user: snapshot.user, settings: snapshot.settings, modelPreference: snapshot.modelPreference))
        self.snapshot = snapshot
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        var root = directory; var values = URLResourceValues(); values.isExcludedFromBackup = true; try root.setResourceValues(values)
        #endif
        file = directory.appendingPathComponent("BibleCompanion-\(UUID().uuidString).json")
        #if os(iOS)
        try Data().write(to: file, options: [.atomic, .completeFileProtection])
        #else
        try Data().write(to: file, options: .atomic)
        #endif
        var opened: FileHandle?
        do {
            let writer = try FileHandle(forWritingTo: file); opened = writer
            try initialWrite(writer, Data(data.dropLast()))
            try initialWrite(writer, Data(",\"imports\":[".utf8))
            handle = writer
        } catch {
            try? opened?.close()
            try? FileManager.default.removeItem(at: file)
            throw error // Caller retries directory cleanup if removal also failed.
        }
    }
    public func nextRequest(at date: Date = Date()) throws -> (section: String, cursor: String?)? {
        guard !closed else { throw ExportFailure.closed }
        guard date.timeIntervalSince1970 < snapshot.expiresAt else { throw ExportFailure.expired }
        guard sectionIndex < Self.sections.count else { return nil }
        return (Self.sections[sectionIndex], cursor)
    }
    public func append(_ page: ExportPage, at date: Date = Date()) throws {
        guard let request = try nextRequest(at: date) else { throw ExportFailure.invalidPage }
        guard page.version == 1, page.snapshotId == snapshot.snapshotId, page.section == request.section,
              page.items.count <= snapshot.maxPageItems,
              try JSONEncoder().encode(page).count <= snapshot.maxPageBytes else { throw ExportFailure.invalidPage }
        if let next = page.nextCursor {
            guard !page.items.isEmpty, !next.isEmpty, next.utf8.count <= 4096, seenCursors.insert(next).inserted else { throw ExportFailure.cursorLoop }
        }
        for item in page.items {
            if itemCount > 0 { try handle.write(contentsOf: Data(",".utf8)) }
            try handle.write(contentsOf: JSONEncoder().encode(item)); itemCount += 1
        }
        cursor = page.nextCursor
        if cursor == nil {
            try handle.write(contentsOf: Data("]".utf8)); sectionIndex += 1; itemCount = 0; seenCursors = []
            if sectionIndex < Self.sections.count { try handle.write(contentsOf: Data(",\"\(Self.sections[sectionIndex])\":[".utf8)) }
        }
    }
    public func finish(at date: Date = Date()) throws -> URL {
        guard try nextRequest(at: date) == nil else { throw ExportFailure.incomplete }
        try handle.write(contentsOf: Data("}".utf8)); try handle.synchronize(); try handle.close(); closed = true
        return file
    }
    public func discard() throws {
        if !closed { try? handle.close(); closed = true }
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
}
