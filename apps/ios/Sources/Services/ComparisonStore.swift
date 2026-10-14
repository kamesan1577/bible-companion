import Foundation
import CompanionCore

/// Frozen owner-private plan only; comparison answer bodies are never persisted here.
enum ComparisonStore {
    static let maximumBytes = 131_072
    private static func root() throws -> URL {
        var root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("PendingComparisons", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true; try root.setResourceValues(values)
        return root
    }
    private static func file(owner: String) throws -> URL {
        guard UUID(uuidString: owner) != nil else { throw NetworkFailure.invalidResponse }
        return try root().appendingPathComponent(owner).appendingPathExtension("json")
    }
    private static func readBytes(owner: String) throws -> Data {
        let handle = try FileHandle(forReadingFrom: file(owner: owner)); defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw NetworkFailure.invalidResponse }
        return data
    }
    static func recoveryRequestID(owner: String) throws -> String? {
        guard let object = try JSONSerialization.jsonObject(with: readBytes(owner: owner)) as? [String: Any],
              object["ownerID"] as? String == owner, let plan = object["plan"] as? [String: Any],
              let request = plan["requestId"] as? String, UUID(uuidString: request) != nil else { return nil }
        return request
    }
    static func removeRecovered(owner: String, requestID: String) throws {
        guard try recoveryRequestID(owner: owner) == requestID else { return }
        try FileManager.default.removeItem(at: file(owner: owner))
    }
    static func read(owner: String) throws -> PendingComparison? {
        let url = try file(owner: owner)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try readBytes(owner: owner)
        let value = try JSONDecoder().decode(PendingComparison.self, from: data)
        guard value.isValid(owner: owner) else { throw NetworkFailure.invalidResponse }
        return value
    }
    static func save(_ value: PendingComparison) throws {
        guard value.isValid(owner: value.ownerID) else { throw NetworkFailure.invalidResponse }
        if let previous = try read(owner: value.ownerID) {
            guard previous.requestID == value.requestID, previous.plan == value.plan, previous.confirmationHash == value.confirmationHash else { throw NetworkFailure.server(status: 409, code: "pending_comparison_unresolved") }
        }
        let data = try JSONEncoder().encode(value)
        guard data.count <= maximumBytes else { throw NetworkFailure.invalidResponse }
        try data.write(to: file(owner: value.ownerID), options: [.atomic, .completeFileProtection])
    }
    static func remove(owner: String, requestID: String) throws {
        guard try read(owner: owner)?.requestID == requestID else { return }
        try FileManager.default.removeItem(at: file(owner: owner))
    }
    static func clear() throws {
        for file in try FileManager.default.contentsOfDirectory(at: root(), includingPropertiesForKeys: nil) { try FileManager.default.removeItem(at: file) }
    }
}
