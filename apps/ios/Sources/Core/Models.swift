import Foundation

public struct Account: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let display_name: String
    public let role: String
    public var canDebug: Bool? = nil
    public var isOwner: Bool { role == "owner" }
}
public struct TokenResponse: Codable, Sendable { public let accessToken: String; public let tokenType: String; public let expiresAt: TimeInterval; public let user: Account }
public struct AccountResponse: Codable, Sendable { public let user: Account }
public struct ImportRecord: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let idempotencyKey: String
    public let ranges: [Passage]
    public let translation: String?
    public let sourceUrl: String?
    public let createdAt: TimeInterval
    public var title: String { ranges.map(\.label).joined(separator: "、") }
}
public struct ImportPage: Codable, Sendable { public let items: [ImportRecord]; public let nextCursor: String? }
public struct ParsedImport: Codable, Sendable {
    public let ranges: [Passage]; public let translation: String?; public let sourceUrl: String?; public let needsConfirmation: Bool; public let warnings: [String]
}
public struct ImportInput: Encodable, Sendable {
    public let idempotencyKey: String; public let ranges: [Passage]; public let translation: String?
    public init(idempotencyKey: String, ranges: [Passage], translation: String?) { self.idempotencyKey = idempotencyKey; self.ranges = ranges; self.translation = translation }
}
public struct Citation: Codable, Identifiable, Sendable {
    public let sourceKind: String?
    public let materialProvenance: CitationMaterialProvenance?
    public var kindLabel: String {
        if materialProvenance != nil { return "資料の要約（聖書本文の引用ではありません）" }
        switch sourceKind { case "scripture": return "聖書本文"; case "commentary": return "解説資料"; default: return "出典の種別は未確認" }
    }
    public let sourceId: String; public let title: String; public let url: String?; public let passage: Passage; public let version: String; public let license: String
    public var id: String { sourceId + ":" + version }
    public var safeURL: URL? { guard let url, let value = URL(string: url), value.scheme == "https", value.host?.isEmpty == false, value.user == nil, value.password == nil else { return nil }; return value }
}
public struct ReferenceSystem: Codable, Sendable {
    public static let fallbackNotice = "章節はプロテスタント66巻・標準KJVの区分を基準にしています。選択した翻訳との節番号の一致は未確認です。"
    public let canon: String; public let versification: String; public let requestedTranslation: String?; public let translationAlignment: String; public let noticeJa: String
}
public struct AnswerResult: Codable, Sendable {
    public let budgetPolicy: JSONValue?
    public let referenceSystem: ReferenceSystem?
    public let answer: String; public let status: String; public let citations: [Citation]; public let modelId: String; public let modelInvoked: Bool; public let mode: String; public let warnings: [String]; public let spoilerAllowed: Bool?
    public let usage: JSONValue; public let timing: JSONValue
}
public struct RequestResult: Codable, Sendable { public let requestId: String; public let status: String; public let result: AnswerResult? }
public struct Conversation: Codable, Identifiable, Sendable {
    public let id: String; public let importId: String; public let passage: Passage; public let readingBoundary: Passage?; public let spoilerAllowed: Bool; public let createdAt: TimeInterval; public let messages: [ConversationMessage]?; public let nextMessageCursor: String?; public let sourcePolicyVersion: Int?
}
public struct ConversationMessage: Codable, Identifiable, Sendable { public let id: String; public let role: String; public let content: JSONValue; public let createdAt: TimeInterval }
public struct ReadingResponse: Codable, Sendable {
    public struct Overview: Codable, Sendable { public let contentKind: String?; public let noticeJa: String?; public let referenceSystem: ReferenceSystem?; public let text: String; public let citations: [Citation]; public let mode: String; public let modelInvoked: Bool }
    public let passage: Passage; public let translation: String?; public let spoilerAllowed: Bool; public let sourceVersion: String; public let overview: Overview; public let materialNotice: String; public let cache: String
    public let offlineCache: OfflineCachePolicy?; public let checkedAt: TimeInterval?
    public let people: [MaterialCard]; public let places: [MaterialCard]; public let artworks: [MaterialCard]
}
public struct UsageResponse: Codable, Sendable {
    public struct Units: Codable, Sendable { public let reserved: Double; public let consumed: Double }
    public let day: String; public let resetAt: TimeInterval; public let budgetUnits: Units; public let limit: Double; public let unitKind: String; public let actualNeurons: Double?
}
public enum JSONValue: Codable, Sendable, Hashable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self { case .string(let v): try c.encode(v); case .number(let v): try c.encode(v); case .bool(let v): try c.encode(v); case .object(let v): try c.encode(v); case .array(let v): try c.encode(v); case .null: try c.encodeNil() }
    }
    public subscript(_ key: String) -> JSONValue { if case .object(let o) = self { return o[key] ?? .null }; return .null }
    public var string: String? { if case .string(let value) = self { return value }; return nil }
    public var bool: Bool? { if case .bool(let value) = self { return value }; return nil }
    public var array: [JSONValue] { if case .array(let value) = self { return value }; return [] }
    public var display: String { switch self { case .string(let v): return v; case .number(let v): return String(v); case .bool(let v): return v ? "true" : "false"; case .null: return "未確認"; default: guard let data = try? JSONEncoder().encode(self) else { return "" }; return String(decoding: data, as: UTF8.self) } }
}

public struct MaterialCard: Codable, Identifiable, Sendable {
    public struct Boundary: Codable, Sendable { public let book: String; public let chapter: Int; public let verse: Int }
    public struct Provenance: Codable, Identifiable, Sendable {
        public let id: String; public let title: String; public let url: String; public let publisher: String; public let checkedAt: String; public let license: String
        public let attribution: String?; public let licenseUrl: String?
        public var safeLicenseURL: URL? { guard let licenseUrl, let value = URL(string: licenseUrl), value.scheme == "https", value.host != nil, value.user == nil, value.password == nil else { return nil }; return value }
        public var safeURL: URL? { guard let value = URL(string: url), value.scheme == "https", value.host?.isEmpty == false, value.user == nil, value.password == nil else { return nil }; return value }
    }
    public let id: String; public let kind: String; public let title: String; public let summary: String
    public let passages: [Passage]; public let spoilerEnd: Boundary; public let version: String; public let reviewed: Bool; public let rightsStatus: String; public let relationship: String
    public let provenance: [Provenance]; public let details: JSONValue
    public func isDisplayable(reading: Passage) -> Bool {
        Passage(book: spoilerEnd.book, start: Verse(chapter: spoilerEnd.chapter, verse: spoilerEnd.verse), end: Verse(chapter: spoilerEnd.chapter, verse: spoilerEnd.verse)).isValid && reviewed && rightsStatus == "approved" && spoilerEnd.book == reading.book && Verse(chapter: spoilerEnd.chapter, verse: spoilerEnd.verse) <= reading.end
    }
    public var publicDomainImageURL: URL? {
        guard details["media"]["rights"].string == "public-domain", let raw = details["media"]["url"].string,
              let value = URL(string: raw), value.scheme == "https", value.user == nil, value.password == nil else { return nil }
        return value
    }
}
