import Foundation

/// Attribution travels with a reviewed material summary even when quoted in an AI answer.
public struct CitationMaterialProvenance: Codable, Sendable {
    public struct Reference: Codable, Identifiable, Sendable {
        public let id: String
        public let title: String
        public let url: String
        public let publisher: String
        public let license: String
        public let licenseUrl: String?
        public let attribution: String?
        public let checkedAt: String?
        public var safeURL: URL? { Self.https(url) }
        public var safeLicenseURL: URL? { Self.https(licenseUrl) }
        private static func https(_ raw: String?) -> URL? {
            guard let raw, let value = URL(string: raw), value.scheme == "https", value.host?.isEmpty == false, value.user == nil, value.password == nil else { return nil }
            return value
        }
    }
    public let kind: String
    public let materialId: String
    public let materialVersion: String
    public let materialKind: String
    public let references: [Reference]
    public var kindLabel: String {
        switch materialKind { case "person": "人物資料"; case "place": "地理資料"; case "artwork": "美術資料"; default: "資料" }
    }
}
