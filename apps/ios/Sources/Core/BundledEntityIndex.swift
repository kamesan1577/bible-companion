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
    public func lookup(_ passage: Passage, kind: String, includeFuture: Bool = false) throws -> EntityIndexResult {
        guard passage.isValid, ["person", "place"].contains(kind) else { throw Failure.invalid }
        if index == nil {
            guard let url = Bundle.module.url(forResource: "entity-index", withExtension: "json") else { throw Failure.unavailable }
            let decoded = try JSONDecoder().decode(Index.self, from: Data(contentsOf: url))
            guard decoded.schemaVersion == 1, decoded.books.count == 66, decoded.chapters.count == 1189 else { throw Failure.invalid }
            index = decoded
        }
        guard let index, let bookIndex = index.books.firstIndex(of: passage.book) else { throw Failure.invalid }
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
        let result = matches.compactMap { pair -> IndexedOccurrence? in
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
            return IndexedOccurrence(entity: entity, directlyNamed: pair.value, sameBookVerses: references)
        }.sorted { $0.directlyNamed != $1.directlyNamed ? $0.directlyNamed : $0.entity.displayName < $1.entity.displayName }
        return EntityIndexResult(occurrences: result, sourceURL: URL(string: index.sourceURL), attribution: index.attribution)
    }
    public enum Failure: Error { case unavailable, invalid }
}
