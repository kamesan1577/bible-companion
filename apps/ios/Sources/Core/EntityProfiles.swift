import Foundation

public struct EntityProfileSource: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let url: String
    public let license: String
    public let licenseURL: String
    public let attribution: String
    public var safeURL: URL? { guard let u = URL(string: url), u.scheme == "https", u.host != nil, u.user == nil, u.password == nil else { return nil }; return u }
}
public struct EntityProfileFact: Codable, Sendable {
    public let textJa: String
    public let knownBy: Verse
    public let sourceIds: [String]
}
public struct WikipediaReadingLink: Codable, Sendable {
    public let title: String
    public let language: String
    public let url: String
    public let kind: String
    public let noteJa: String
    public let checkedAt: String
    public let identityVerified: Bool
    public var safeURL: URL? {
        guard identityVerified, ["ja", "en"].contains(language), ["article", "shared-section", "related-section"].contains(kind),
              let value = URL(string: url), value.scheme == "https", value.host == language + ".wikipedia.org",
              value.user == nil, value.password == nil, value.port == nil, value.query == nil,
              value.path.hasPrefix("/wiki/"), value.path.count > 6, !value.path.contains(":") else { return nil }
        return value
    }
    public var labelJa: String {
        let base = kind == "related-section" ? "Wikipediaの関連節を読む" : "Wikipediaで詳しく読む"
        return base + (language == "en" ? "（英語）" : "")
    }
}

public struct EntityProfile: Codable, Sendable, Identifiable {
    public let id: String
    public let kind: String
    public let nameJa: String
    public let subtitleJa: String
    public let summaryJa: String
    public let identityNoteJa: String
    public let knownBy: Verse
    public let passages: [Passage]
    public let sourceIds: [String]
    public let facts: [EntityProfileFact]
    public let modernLocationJa: String?
    public let historicalRoleJa: String?
    public let coordinate: [Double]?
    public let locationNoteJa: String?
    public let wikipedia: WikipediaReadingLink?
    public let materialCardIDs: [String]?
    public let supplemental: Bool
}
public struct ResolvedEntityProfile: Sendable {
    public let profile: EntityProfile
    public let facts: [EntityProfileFact]
    public let sources: [EntityProfileSource]
}
struct EntityProfileCatalog: Decodable {
    let schemaVersion: Int
    let sources: [EntityProfileSource]
    let profiles: [EntityProfile]
    func resolve(id: String, passage: Passage, includeFuture: Bool) -> ResolvedEntityProfile? {
        guard schemaVersion == 1, let p = profiles.first(where: { $0.id == id }), passage.book == "ACT", p.knownBy <= passage.end,
              p.passages.contains(where: { $0.book == passage.book && $0.start <= passage.end && passage.start <= $0.end }) else { return nil }
        let facts = p.facts.filter { includeFuture || $0.knownBy <= passage.end }
        let ids = Set(p.sourceIds + facts.flatMap(\.sourceIds))
        return ResolvedEntityProfile(profile: p, facts: facts, sources: sources.filter { ids.contains($0.id) })
    }
}
