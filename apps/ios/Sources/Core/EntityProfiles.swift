import Foundation

public struct EntityProfileSource: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let url: String
    public let license: String
    public let licenseURL: String
    public let attribution: String
    public let knownBy: Verse?
    public let category: String?
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
    public let relationVerified: Bool?
    public let knownBy: Verse?
    public init(title: String, language: String, url: String, kind: String, noteJa: String, checkedAt: String, identityVerified: Bool, relationVerified: Bool? = nil, knownBy: Verse? = nil) {
        self.title = title; self.language = language; self.url = url; self.kind = kind
        self.noteJa = noteJa; self.checkedAt = checkedAt; self.identityVerified = identityVerified
        self.relationVerified = relationVerified; self.knownBy = knownBy
    }
    public var safeURL: URL? {
        guard (identityVerified || (kind == "related-section" && relationVerified == true && !noteJa.isEmpty)), ["ja", "en"].contains(language), ["article", "shared-section", "related-section"].contains(kind),
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

public struct EntityProfileName: Codable, Sendable {
    public let nameJa: String
    public let knownBy: Verse
}
public struct EntityProfileOccurrence: Codable, Sendable {
    public let entityID: String
    public let chapter: Int
    public let verse: Int
    public let directlyNamed: Bool
}

public struct EntityProfile: Codable, Sendable, Identifiable {
    public let id: String
    public let kind: String
    public let nameJa: String
    public let identityType: String?
    public let names: [EntityProfileName]?
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
    public let contextProfiles: [EntityProfile]?
    public var detailLinkLabelJa: String { identityType == "ritual-area" ? "この祭儀上の場所について" : identityType == "territory" ? "この地域について" : identityType == "collective" ? "この集団名について" : identityType == "expression" ? "この表現について" : identityType == "office-title" ? "この称号について" : identityType == "unidentified-eponym" ? "この名前について" : kind == "person" ? "この人物について" : "この場所について" }
}
public struct ResolvedEntityProfile: Sendable {
    public let profile: EntityProfile
    public let facts: [EntityProfileFact]
    public let sources: [EntityProfileSource]
    public let nameJa: String
    public let contextNotes: [String]
    public let wikipedia: WikipediaReadingLink?
}
struct EntityProfileAlias: Decodable {
    let aliasID: String
    let canonicalID: String
    let knownBy: Verse
}
struct EntityProfileCatalog: Decodable {
    let schemaVersion: Int
    let sources: [EntityProfileSource]
    let profiles: [EntityProfile]
    let occurrences: [EntityProfileOccurrence]?
    let sourceBoundAliases: [EntityProfileAlias]?
    func canonicalID(_ id: String, at end: Verse, includeFuture: Bool) -> String {
        sourceBoundAliases?.first { $0.aliasID == id && (includeFuture || $0.knownBy <= end) }?.canonicalID ?? id
    }
    func resolve(id: String, passage: Passage, includeFuture: Bool) -> ResolvedEntityProfile? {
        guard schemaVersion == 1, let base = profiles.first(where: { $0.id == id }) else { return nil }
        let overlaps: (EntityProfile) -> Bool = { p in
            p.knownBy <= passage.end && p.passages.contains { $0.book == passage.book && $0.start <= passage.end && passage.start <= $0.end }
        }
        let contexts = (base.contextProfiles ?? []).filter(overlaps)
        let exactContext = contexts.first { p in p.passages.contains { $0.book == passage.book && $0.start <= passage.start && passage.end <= $0.end } }
        // A single verse may name both an ancestor and the clan bearing that name.
        // Keep the base with a context note when both meanings genuinely occur.
        let selectedContext = overlaps(base) ? nil : (exactContext ?? contexts.first)
        guard let p = selectedContext ?? (overlaps(base) ? base : nil) else { return nil }
        let facts = p.facts.filter { includeFuture || $0.knownBy <= passage.end }
        let shownContexts = selectedContext == nil ? contexts : []
        let contextFacts = shownContexts.flatMap { $0.facts.filter { includeFuture || $0.knownBy <= passage.end } }
        let ids = Set(p.sourceIds + facts.flatMap(\.sourceIds) + shownContexts.flatMap(\.sourceIds) + contextFacts.flatMap(\.sourceIds))
        return ResolvedEntityProfile(profile: p, facts: facts, sources: sources.filter { ids.contains($0.id) && (includeFuture || $0.knownBy == nil || $0.knownBy! <= passage.end) }, nameJa: p.names?.filter { includeFuture || $0.knownBy <= passage.end }.sorted { $0.knownBy < $1.knownBy }.last?.nameJa ?? p.nameJa, contextNotes: shownContexts.map { context in context.nameJa + "：" + ([context.summaryJa] + context.facts.filter { includeFuture || $0.knownBy <= passage.end }.map(\.textJa)).joined(separator: "\n") }, wikipedia: p.wikipedia.flatMap { includeFuture || $0.knownBy == nil || $0.knownBy! <= passage.end ? $0 : nil })

    }
}
