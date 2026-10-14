import Foundation

public struct PassageSelection: Sendable, Equatable {
    public let reading: Passage
    public private(set) var start: Verse
    public private(set) var end: Verse
    public init(reading: Passage, selected: Passage? = nil) throws {
        let target = selected ?? reading
        guard reading.contains(target) else { throw QuestionScope.ScopeError.outsideReading }
        self.reading = reading; start = target.start; end = target.end
    }
    public var chapters: ClosedRange<Int> { reading.start.chapter...reading.end.chapter }
    public func verses(in chapter: Int) -> ClosedRange<Int>? {
        guard chapters.contains(chapter), let counts = Canon.verseCounts[reading.book] else { return nil }
        let lower = chapter == reading.start.chapter ? reading.start.verse : 1
        let upper = chapter == reading.end.chapter ? reading.end.verse : counts[chapter - 1]
        return lower...upper
    }
    public var passage: Passage { Passage(book: reading.book, start: start, end: end) }
    public var isValid: Bool { reading.contains(passage) }
    public mutating func selectChapter(_ chapter: Int, isStart: Bool) {
        guard let allowed = verses(in: chapter) else { return }
        if isStart { start = Verse(chapter: chapter, verse: min(max(start.verse, allowed.lowerBound), allowed.upperBound)) }
        else { end = Verse(chapter: chapter, verse: min(max(end.verse, allowed.lowerBound), allowed.upperBound)) }
    }
    public mutating func selectVerse(_ verse: Int, isStart: Bool) {
        let chapter = isStart ? start.chapter : end.chapter
        guard verses(in: chapter)?.contains(verse) == true else { return }
        if isStart { start.verse = verse } else { end.verse = verse }
    }
}
