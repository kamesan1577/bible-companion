import Foundation

public struct IndexedEntity: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let kind: String
    public let name: String
    public let nameJa: String?
    public let appearances: [Int]
    public let coordinate: [Double]?
    public let coordinateStatus: String?
    public var displayName: String { nameJa ?? name }
}
public struct IndexedOccurrence: Sendable, Identifiable {
    public var id: String { entity.id }
    public let entity: IndexedEntity
    public let directlyNamed: Bool
    public let sameBookVerses: [Passage]
    public let profile: ResolvedEntityProfile?
    public var candidateMapNote: String? = nil
}
public struct EntityIndexResult: Sendable {
    public let occurrences: [IndexedOccurrence]
    public let sourceURL: URL?
    public let attribution: String
}
public actor BundledEntityIndex {
    public static let shared = BundledEntityIndex()
    private struct Index: Decodable {
        let schemaVersion: Int; let sourceURL: String; let attribution: String
        let books: [String]; let entities: [IndexedEntity]; let chapters: [String: [[IntOrArray]]]
    }
    private enum IntOrArray: Decodable {
        case number(Int), array([Int])
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let n = try? c.decode(Int.self) { self = .number(n) } else { self = .array(try c.decode([Int].self)) }
        }
        var number: Int? { if case .number(let value) = self { value } else { nil } }
        var array: [Int] { if case .array(let values) = self { values } else { [] } }
    }
    private var index: Index?
    private var catalogs: [String: EntityProfileCatalog] = [:]
    private struct CandidateMapPolicy: Decodable { let id: String; let allowCandidateMap: Bool; let allowFrom: Verse?; let displayNoteJa: String? }
    private var mapPolicies: [String: [CandidateMapPolicy]] = [:]
    public func lookup(_ passage: Passage, kind: String, includeFuture: Bool = false) throws -> EntityIndexResult {
        guard passage.isValid, ["person", "place"].contains(kind) else { throw Failure.invalid }
        if index == nil {
            guard let url = Bundle.module.url(forResource: "entity-index", withExtension: "json") else { throw Failure.unavailable }
            let decoded = try JSONDecoder().decode(Index.self, from: Data(contentsOf: url))
            guard decoded.schemaVersion == 1, decoded.books.count == 66, decoded.chapters.count == 1189 else { throw Failure.invalid }
            index = decoded
        }
        guard let index, let bookIndex = index.books.firstIndex(of: passage.book) else { throw Failure.invalid }
        let profileResource = passage.book == "ACT" ? "entity-profiles" : ["ROM", "LEV", "NUM", "JOS", "JDG", "RUT", "1SA", "2SA"].contains(passage.book) ? "entity-profiles-" + passage.book : nil
        if catalogs[passage.book] == nil, let profileResource,
           let url = Bundle.module.url(forResource: profileResource, withExtension: "json") {
            catalogs[passage.book] = try JSONDecoder().decode(EntityProfileCatalog.self, from: Data(contentsOf: url))
        }
        let profiles = catalogs[passage.book]
        let policyResource = passage.book == "ACT" ? "acts-map-policy" : passage.book.lowercased() + "-map-policy"
        if mapPolicies[passage.book] == nil {
            if ["ACT", "ROM", "LEV", "NUM", "JOS", "JDG", "RUT", "1SA", "2SA"].contains(passage.book), let url = Bundle.module.url(forResource: policyResource, withExtension: "json") {
                mapPolicies[passage.book] = try JSONDecoder().decode([CandidateMapPolicy].self, from: Data(contentsOf: url))
            } else { mapPolicies[passage.book] = [] }
        }
        let candidateMapPolicy = mapPolicies[passage.book] ?? []
        // Each reviewed book has an independent catalog and occurrence table.
        // Switching books must never replace or leak the fixed Acts catalog.
        if ["ACT", "ROM", "LEV", "NUM", "JOS", "JDG", "RUT", "1SA", "2SA"].contains(passage.book), let reviewed = profiles?.occurrences {
            let selected = reviewed.filter {
                let v = Verse(chapter: $0.chapter, verse: $0.verse)
                return passage.start <= v && v <= passage.end
            }
            var result: [IndexedOccurrence] = []
            let canonicalID: (String) -> String = { profiles?.canonicalID($0, at: passage.end, includeFuture: includeFuture) ?? $0 }
            for p in profiles?.profiles ?? [] where p.kind == kind {
                guard canonicalID(p.id) == p.id else { continue }
                let links = selected.filter { canonicalID($0.entityID) == p.id }
                guard !links.isEmpty || p.supplemental,
                      let resolved = profiles?.resolve(id: p.id, passage: passage, includeFuture: includeFuture) else { continue }
                var referencePositions = Set<Int>()
                let references = reviewed.filter { canonicalID($0.entityID) == p.id }.compactMap { link -> Passage? in
                    guard referencePositions.insert(link.chapter * 1000 + link.verse).inserted else { return nil }
                    let v = Verse(chapter: link.chapter, verse: link.verse)
                    // A shared canonical ID may denote a collective or a
                    // named ancestor. References follow the resolved context.
                    guard resolved.profile.passages.contains(where: { $0.book == passage.book && $0.start <= v && v <= $0.end }),
                          (includeFuture || v <= passage.end), v < passage.start || v > passage.end else { return nil }
                    return Passage(book: passage.book, start: v, end: v)
                }
                let upstream = index.entities.first { $0.id == p.id }
                let policy = candidateMapPolicy.first { $0.id == p.id && $0.allowCandidateMap && ($0.allowFrom == nil || $0.allowFrom! <= passage.end) }
                let candidate = policy != nil ? upstream?.coordinate : nil
                let point = p.coordinate ?? candidate
                let status = p.coordinate != nil ? "source-representative-point" : upstream?.coordinateStatus
                let entity = IndexedEntity(id: p.id, kind: p.kind, name: resolved.nameJa, nameJa: resolved.nameJa,
                    appearances: [], coordinate: point, coordinateStatus: point == nil ? nil : status)
                result.append(IndexedOccurrence(entity: entity, directlyNamed: links.contains { $0.directlyNamed }, sameBookVerses: references, profile: resolved, candidateMapNote: policy?.displayNoteJa))
            }
            result.sort { $0.directlyNamed != $1.directlyNamed ? $0.directlyNamed : $0.entity.displayName < $1.entity.displayName }
            return EntityIndexResult(occurrences: result, sourceURL: URL(string: index.sourceURL), attribution: index.attribution)
        }
        var matches: [Int: Bool] = [:]
        let directColumn = kind == "person" ? 1 : 3
        for chapter in passage.start.chapter...passage.end.chapter {
            for row in index.chapters[passage.book + "." + String(chapter)] ?? [] {
                guard row.count == 5, let verse = row[0].number else { continue }
                if chapter == passage.start.chapter && verse < passage.start.verse { continue }
                if chapter == passage.end.chapter && verse > passage.end.verse { continue }
                for i in row[directColumn].array { matches[i] = true }
                for i in row[directColumn + 1].array where matches[i] == nil { matches[i] = false }
            }
        }
        var result = matches.compactMap { pair -> IndexedOccurrence? in
            guard index.entities.indices.contains(pair.key) else { return nil }
            let entity = index.entities[pair.key]
            let references = entity.appearances.compactMap { code -> Passage? in
                guard code / 1_000_000 == bookIndex + 1 else { return nil }
                let chapter = code % 1_000_000 / 1000, verse = code % 1000
                if !includeFuture && (chapter > passage.end.chapter || (chapter == passage.end.chapter && verse > passage.end.verse)) { return nil }
                let range = Passage(book: passage.book, start: Verse(chapter: chapter, verse: verse), end: Verse(chapter: chapter, verse: verse))
                guard range.isValid else { return nil }
                if chapter >= passage.start.chapter && chapter <= passage.end.chapter && (chapter != passage.start.chapter || verse >= passage.start.verse) && (chapter != passage.end.chapter || verse <= passage.end.verse) { return nil }
                return range
            }
            let profile = profiles?.resolve(id: entity.id, passage: passage, includeFuture: includeFuture)
            let displayed = profile.map { p in IndexedEntity(id: entity.id, kind: entity.kind, name: entity.name, nameJa: p.nameJa, appearances: entity.appearances, coordinate: p.profile.coordinate, coordinateStatus: p.profile.coordinate == nil ? nil : "source-representative-point") } ?? entity
            return IndexedOccurrence(entity: displayed, directlyNamed: pair.value, sameBookVerses: references, profile: profile)
        }.sorted { $0.directlyNamed != $1.directlyNamed ? $0.directlyNamed : $0.entity.displayName < $1.entity.displayName }
        for p in profiles?.profiles ?? [] where p.supplemental && p.kind == kind {
            guard !result.contains(where: { $0.entity.id == p.id }), let profile = profiles?.resolve(id: p.id, passage: passage, includeFuture: includeFuture) else { continue }
            let entity = IndexedEntity(id: p.id, kind: p.kind, name: p.nameJa, nameJa: p.nameJa, appearances: [], coordinate: nil, coordinateStatus: nil)
            result.append(IndexedOccurrence(entity: entity, directlyNamed: false, sameBookVerses: [], profile: profile))
        }
        return EntityIndexResult(occurrences: result, sourceURL: URL(string: index.sourceURL), attribution: index.attribution)
    }
    public func profile(forMaterialCardID id: String, passage: Passage, includeFuture: Bool = false) throws -> ResolvedEntityProfile? {
        _ = try lookup(passage, kind: "person", includeFuture: includeFuture)
        guard let catalog = catalogs[passage.book],
              let profile = catalog.profiles.first(where: { $0.materialCardIDs?.contains(id) == true }) else { return nil }
        return catalog.resolve(id: profile.id, passage: passage, includeFuture: includeFuture)
    }
    public enum Failure: Error { case unavailable, invalid }
}
