import Foundation

/// The same projection supplies visible rows and their tab counts.
public enum ReadingContentProjection {
    public static func materials(_ cards: [MaterialCard], kind: String, passage: Passage) -> [MaterialCard] {
        var seen = Set<String>()
        return cards.filter { card in
            card.kind == kind && card.isDisplayable(reading: passage)
                && card.passages.contains { $0.book == passage.book && $0.start <= passage.end && passage.start <= $0.end }
                && seen.insert(card.id).inserted
        }
    }
    public static func additions(_ result: EntityIndexResult?, covered: [String]) -> [IndexedOccurrence] {
        let coveredIDs = Set(covered); var seen = Set<String>()
        return (result?.occurrences ?? []).filter {
            Set($0.profile?.profile.materialCardIDs ?? []).isDisjoint(with: coveredIDs) && seen.insert($0.id).inserted
        }
    }
    /// English commentary behind future-content confirmation and global dictionary search are not counted.
    public static func explanationCount(edits: [CommentaryEdit], publicText: String) -> Int {
        Set(edits.map(\.id)).count + (publicText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1)
    }
    public static func badgeText(_ count: Int) -> String { count > 99 ? "99+" : String(max(0, count)) }
}
