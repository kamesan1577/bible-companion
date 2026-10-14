import Foundation

public struct ScripturePage: Codable, Sendable {
    public struct Corpus: Codable, Equatable, Sendable {
        public let id: String; public let version: String; public let edition: String
        public let language: String; public let license: String; public let manifestSha256: String
        public let referenceAlignment: String; public let editorialReview: String
    }
    public struct Item: Codable, Identifiable, Sendable {
        public let id: String; public let chapter: Int; public let verse: Int; public let text: String
        public var position: Verse { Verse(chapter: chapter, verse: verse) }
    }
    public struct Omission: Codable, Sendable {
        public let chapter: Int; public let verse: Int; public let reason: String
        public var position: Verse { Verse(chapter: chapter, verse: verse) }
    }
    public let available: Bool; public let passage: Passage; public let corpus: Corpus?
    public let items: [Item]; public let nextCursor: String?; public let sourcePolicyVersion: Int
    public let noticeJa: String; public let coverage: String; public let omissions: [Omission]
    public let unversifiedTextIncluded: Bool
    public func validate(expected: Passage, previous: ScripturePage? = nil, requestedCursor: String? = nil) throws {
        guard passage == expected, passage.isValid, items.count <= 100, omissions.count <= expected.verseCount,
              sourcePolicyVersion >= 0, !unversifiedTextIncluded, !noticeJa.isEmpty,
              nextCursor.map({ !$0.isEmpty && $0.utf8.count <= 1000 && $0 != requestedCursor }) ?? true,
              try JSONEncoder().encode(self).count <= 128 * 1024 else { throw NetworkFailure.invalidResponse }
        if let previous {
            guard previous.corpus == corpus, previous.sourcePolicyVersion == sourcePolicyVersion else {
                throw NetworkFailure.server(status: 409, code: "source_policy_changed")
            }
        }
        guard available else {
            guard corpus == nil, items.isEmpty, omissions.isEmpty, nextCursor == nil, coverage == "unavailable" else { throw NetworkFailure.invalidResponse }
            return
        }
        guard let corpus, corpus.id == "webp", corpus.edition == "engwebp", corpus.language == "en",
              corpus.license == "public-domain", corpus.referenceAlignment == "canonical-compatible", corpus.editorialReview == "unreviewed",
              !corpus.version.isEmpty, corpus.version.utf8.count <= 100,
              corpus.manifestSha256.count == 64, corpus.manifestSha256.allSatisfy({ "0123456789abcdef".contains($0) }), coverage == "source-coordinate-subset" else { throw NetworkFailure.invalidResponse }
        var positions = Set<Verse>(); var last: Verse?
        for item in items {
            guard expected.contains(Passage(book: expected.book, start: item.position, end: item.position)),
                  item.id == "webp:\(expected.book):\(item.chapter):\(item.verse)", !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  positions.insert(item.position).inserted, last.map({ $0 < item.position }) ?? true else { throw NetworkFailure.invalidResponse }
            last = item.position
        }
        for omission in omissions {
            guard expected.contains(Passage(book: expected.book, start: omission.position, end: omission.position)),
                  ["source_text_empty", "source_reference_missing"].contains(omission.reason), positions.insert(omission.position).inserted else { throw NetworkFailure.invalidResponse }
        }
        if nextCursor != nil && items.isEmpty { throw NetworkFailure.invalidResponse }
        if let previous, requestedCursor != nil, requestedCursor == previous.nextCursor, let last = previous.items.last?.position, let first = items.first?.position, first <= last { throw NetworkFailure.invalidResponse }
    }
}

/// Stores only opaque page positions, never scripture text.
public struct ScriptureCursorHistory: Sendable {
    public struct Request: Sendable { public let cursor: String?; public let destination: Int }
    private var cursors: [String?] = []
    public var pageNumber: Int { cursors.count }
    public init() {}
    public var previous: Request? {
        guard cursors.count > 1 else { return nil }
        return Request(cursor: cursors[cursors.count - 2], destination: cursors.count - 2)
    }
    public func next(cursor: String?) -> Request? {
        guard !cursors.isEmpty, let cursor else { return nil }
        return Request(cursor: cursor, destination: cursors.count)
    }
    public mutating func accept(cursor: String?, destination: Int, nextCursor: String?) throws {
        guard destination >= 0, destination <= cursors.count,
              destination == 0 ? cursor == nil : cursor != nil,
              cursor.map({ !$0.isEmpty && $0.utf8.count <= 1000 }) ?? true,
              nextCursor == nil || (nextCursor != cursor && !cursors.prefix(destination).contains(where: { $0 == nextCursor })) else { throw NetworkFailure.invalidResponse }
        cursors = Array(cursors.prefix(destination)) + [cursor]
    }
    public mutating func clear() { cursors = [] }
}
