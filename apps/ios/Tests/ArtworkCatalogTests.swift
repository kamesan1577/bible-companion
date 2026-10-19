import XCTest
@testable import CompanionCore

final class ArtworkCatalogTests: XCTestCase {
    func testReviewedCatalogDecodesAndUsesTheSameSafeCountAndImageProjection() throws {
#if SWIFT_PACKAGE
        let bundle = Bundle.module
#else
        let bundle = Bundle(for: Self.self)
#endif
        let url = try XCTUnwrap(bundle.url(forResource: "artwork-catalog", withExtension: "json"))
        let cards = try JSONDecoder().decode([MaterialCard].self, from: Data(contentsOf: url))
        XCTAssertGreaterThanOrEqual(cards.count, 40)
        XCTAssertEqual(Set(cards.map(\.id)).count, cards.count)
        for card in cards {
            let end = Verse(chapter: card.spoilerEnd.chapter, verse: card.spoilerEnd.verse)
            let passage = Passage(book: card.spoilerEnd.book, start: end, end: end)
            XCTAssertNotNil(card.publicDomainImageURL, card.id)
            XCTAssertEqual(ReadingContentProjection.materials([card,card],kind: "artwork",passage: passage).count,1,card.id)
            if end.verse > 1 {
                let before = Verse(chapter: end.chapter, verse: end.verse-1)
                XCTAssertTrue(ReadingContentProjection.materials([card],kind: "artwork",passage: Passage(book: passage.book,start: before,end: before)).isEmpty,card.id)
            }
            XCTAssertTrue(ReadingContentProjection.materials([card],kind: "artwork",passage: Passage(book: "LEV",start: Verse(chapter:19,verse:1),end: Verse(chapter:19,verse:2))).isEmpty,card.id)
        }
    }
}
