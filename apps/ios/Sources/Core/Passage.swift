import Foundation

public struct Verse: Codable, Hashable, Comparable, Sendable {
    public var chapter: Int
    public var verse: Int
    public init(chapter: Int, verse: Int) { self.chapter = chapter; self.verse = verse }
    public static func < (lhs: Self, rhs: Self) -> Bool { (lhs.chapter, lhs.verse) < (rhs.chapter, rhs.verse) }
    public var label: String { "\(chapter):\(verse)" }
}
public struct Passage: Codable, Hashable, Sendable {
    public var book: String
    public var start: Verse
    public var end: Verse
    public init(book: String, start: Verse, end: Verse) { self.book = book; self.start = start; self.end = end }
    public var reference: String {
        if start == end { return start.label }
        if start.chapter == end.chapter { return "\(start.label)–\(end.verse)" }
        return "\(start.label)–\(end.label)"
    }
    public var bookName: String { Canon.books.first { $0.id == book }?.ja ?? book }
    public var label: String { "\(bookName) \(reference)" }
    public var isValid: Bool {
        guard let counts = Canon.verseCounts[book], start <= end else { return false }
        for coordinate in [start, end] {
            guard coordinate.chapter > 0, coordinate.chapter <= counts.count else { return false }
            let chapterVerseCount = counts[coordinate.chapter - 1]
            guard coordinate.verse > 0, coordinate.verse <= chapterVerseCount else { return false }
        }
        return true
    }
    public func contains(_ other: Passage) -> Bool { isValid && other.isValid && book == other.book && start <= other.start && other.end <= end }
    public var verseCount: Int {
        guard isValid, let counts = Canon.verseCounts[book] else { return 0 }
        if start.chapter == end.chapter { return end.verse - start.verse + 1 }
        let middle = counts[start.chapter..<(end.chapter - 1)].reduce(0, +)
        return counts[start.chapter - 1] - start.verse + 1 + middle + end.verse
    }
    public var chapterSegments: [Passage] {
        guard isValid, let counts = Canon.verseCounts[book] else { return [] }
        return (start.chapter...end.chapter).map { chapter in
            Passage(book: book, start: Verse(chapter: chapter, verse: chapter == start.chapter ? start.verse : 1), end: Verse(chapter: chapter, verse: chapter == end.chapter ? end.verse : counts[chapter - 1]))
        }
    }
}
public enum Canon {
    public struct Book: Codable, Identifiable, Sendable { public let id: String; public let en: String; public let ja: String; public let chapters: Int }
    public static let books: [Book] = resource("books") ?? []
    public static let verseCounts: [String: [Int]] = resource("verse-counts") ?? [:]
    private static func resource<T: Decodable>(_ name: String) -> T? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
public struct QuestionScope: Codable, Hashable, Sendable {
    public let reading: Passage
    public let target: Passage
    public let spoilerAllowed: Bool
    public init(reading: Passage, target: Passage, spoilerAllowed: Bool = false) throws {
        guard reading.contains(target) else { throw ScopeError.outsideReading }
        self.reading = reading; self.target = target; self.spoilerAllowed = spoilerAllowed
    }
    public enum ScopeError: Error { case outsideReading }
    public var isWhole: Bool { reading == target }
    public func allowsSource(_ passage: Passage) -> Bool { passage.isValid && (spoilerAllowed || (passage.book == reading.book && passage.end <= reading.end)) }
}
