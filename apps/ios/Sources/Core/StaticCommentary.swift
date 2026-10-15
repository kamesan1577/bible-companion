import Foundation
import CryptoKit

public struct CommentaryEdit: Decodable, Identifiable, Sendable {
    public let id: String
    public let passage: Passage
    public let titleJa: String
    public let summaryJa: String
    public let authorInterpretationJa: String
    public let editorialNoteJa: String
    public let sourceUnitIds: [String]
    public let spoilerEnd: Verse
}
public struct CommentaryOriginal: Decodable, Identifiable, Sendable {
    public let id: String
    public let editionId: String
    public let sourceLocator: String
    public let ranges: [Passage]
    public let originalText: String
}
public struct CommentaryDictionaryEntry: Decodable, Identifiable, Sendable {
    public let id: String
    public let headword: String
    public let originalText: String
}
public actor StaticCommentary {
    public static let shared = StaticCommentary()
    private struct FileRecord: Decodable { let file: String; let sha256: String }
    private struct Catalog: Decodable { let files: [String: FileRecord] }
    private struct Edits: Decodable { let entries: [CommentaryEdit] }
    private var catalog: Catalog?
    public func edits(for passage: Passage) throws -> [CommentaryEdit] {
        let values = try JSONDecoder().decode(Edits.self, from: data("JapaneseEdits")).entries
        return values.filter { passage.contains($0.passage) && $0.spoilerEnd <= passage.end }
    }
    public func dictionary(matching query: String) throws -> [CommentaryDictionaryEntry] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        return Array(try JSONDecoder().decode([CommentaryDictionaryEntry].self, from: data("Easton")).filter { $0.headword.localizedCaseInsensitiveContains(term) }.prefix(30))
    }
    public func originals(for passage: Passage) throws -> [CommentaryOriginal] {
        try ["MHC", "JFB"].flatMap { name in
            try JSONDecoder().decode([CommentaryOriginal].self, from: data("\(name):\(passage.book)")).filter { item in
                item.ranges.contains { $0.book == passage.book && $0.start <= passage.end && passage.start <= $0.end }
            }
        }
    }
    private func data(_ key: String) throws -> Data {
        if catalog == nil {
            guard let url = Bundle.module.url(forResource: "commentary-catalog", withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
            catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
        }
        guard let record = catalog?.files[key], let url = Bundle.module.url(forResource: String(record.file.dropLast(5)), withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
        let bytes = try Data(contentsOf: url)
        guard SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == record.sha256 else { throw CocoaError(.fileReadCorruptFile) }
        return bytes
    }
}
