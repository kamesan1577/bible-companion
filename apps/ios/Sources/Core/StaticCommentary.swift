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
    public var editorialNoteForDisplay: String? {
        let workflowNotes: Set<String> = [
            "Acts 10–12のWEB本文の全対象節と割当JFB原文を照合した修正候補。独立二次点検待ち。",
            "Acts 13–17のWEB本文と割当JFB原文を照合した修正候補。独立二次点検待ち。",
            "Acts 9 WEB本文とJFB該当原文を照合した修正候補。人物同定は本文・注解の根拠範囲に限定。独立二次点検待ち。",
            "Acts 9 WEB本文とJFB該当原文を照合した修正候補。後年の回想は具体的内容を先取りせず、背景としてのみ記す。独立二次点検待ち。",
            "Acts 9:32–43のWEB本文全対象節とJFB該当原文を照合した修正候補。独立二次点検待ち。",
            "WEB本文全対象節と割当原典を再照合した修正候補。引用・解釈の範囲を限定。独立二次点検待ち。",
            "independent13-17.jsonのrevise指摘をWEB本文と割当JFB原文で再照合して修正。独立二次点検待ち。",
            "受領したLuna下書きです。原典との別段階の点検・人物ID照合・先読み検査は未完です。"
        ]
        return workflowNotes.contains(editorialNoteJa) ? nil : editorialNoteJa
    }
}
public struct CommentaryProgress: Sendable {
    public let editedRanges: Int
    public let coveredCoordinates: Int
    public let detailedRanges: Int
    public let detailedCoordinates: Int
    public let chapterOverviews: Int
    public let completeActsChapters: [Int]
    public let sourceComparedEntryIds: Set<String>
}
public struct CommentaryCrossReference: Decodable, Identifiable, Sendable {
    public let passage: Passage
    public let sourceReference: String
    public let relation: String
    public let noteJa: String
    public var id: String { "\(passage.book):\(passage.start.chapter):\(passage.start.verse):\(sourceReference)" }
}
public struct CommentaryOriginal: Decodable, Identifiable, Sendable {
    public let id: String
    public let editionId: String
    public let sourceLocator: String
    public let ranges: [Passage]
    public let originalText: String
    public let kind: String?
    public let crossReferences: [CommentaryCrossReference]?
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
    private struct Edits: Decodable { let entries: [CommentaryEdit]; let independentReviewedEntryIds: [String]? }
    private var catalog: Catalog?
    public func edits(for passage: Passage) throws -> [CommentaryEdit] {
        let values = try JSONDecoder().decode(Edits.self, from: data("JapaneseEdits")).entries
        return values.filter { passage.contains($0.passage) && $0.spoilerEnd <= passage.end }
    }
    public func progress() throws -> CommentaryProgress {
        let document = try JSONDecoder().decode(Edits.self, from: data("JapaneseEdits"))
        let entries = document.entries
        func coordinates(_ values: [CommentaryEdit]) -> Set<String> {
            Set(values.flatMap { entry -> [String] in
                guard entry.passage.start.chapter == entry.passage.end.chapter else { return [] }
                return (entry.passage.start.verse...entry.passage.end.verse).map {
                    "\(entry.passage.book):\(entry.passage.start.chapter):\($0)"
                }
            })
        }
        let detailed = entries.filter {
            !$0.id.hasSuffix("chapter-overview") && $0.passage.start.chapter == $0.passage.end.chapter && $0.passage.end.verse - $0.passage.start.verse < 8
        }
        let detailedCoordinates = coordinates(detailed)
        let actsChapters = (Canon.verseCounts["ACT"] ?? []).enumerated().compactMap { offset, count -> Int? in
            let chapter = offset + 1
            return (1...count).allSatisfy { detailedCoordinates.contains("ACT:\(chapter):\($0)") } ? chapter : nil
        }
        return CommentaryProgress(editedRanges: entries.count, coveredCoordinates: coordinates(entries).count,
            detailedRanges: detailed.count, detailedCoordinates: detailedCoordinates.count,
            chapterOverviews: entries.filter { $0.id.hasSuffix("chapter-overview") }.count, completeActsChapters: actsChapters, sourceComparedEntryIds: Set(document.independentReviewedEntryIds ?? []))
    }
    public func dictionary(matching query: String) throws -> [CommentaryDictionaryEntry] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        return Array(try JSONDecoder().decode([CommentaryDictionaryEntry].self, from: data("Easton")).filter { $0.headword.localizedCaseInsensitiveContains(term) }.prefix(30))
    }
    public func originals(for passage: Passage) throws -> [CommentaryOriginal] {
        let direct = try ["MHC", "JFB"].flatMap { name in
            try JSONDecoder().decode([CommentaryOriginal].self, from: data("\(name):\(passage.book)"))
        }
        let contexts = catalog?.files["ChapterContexts"] == nil ? [] : try JSONDecoder().decode([CommentaryOriginal].self, from: data("ChapterContexts"))
        return (direct + contexts).filter { item in
            item.ranges.contains { $0.book == passage.book && $0.start <= passage.end && passage.start <= $0.end }
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
