import XCTest
@testable import CompanionCore

final class ExternalQuestionProviderTests: XCTestCase {
    private let passage = Passage(book: "LEV", start: Verse(chapter: 19, verse: 1), end: Verse(chapter: 19, verse: 2))
    func testQuestionAndOriginalSurviveJapaneseNewlinesAndURLPunctuation() throws {
        let question = "なぜ聖なる者に？\nA&B + #50% = ?"
        let original = "主はモーセに告げた。\nレビ記 19:1-2 JCB"
        let handoff = try ExternalQuestionHandoff(provider: .chatGPT, question: question, passage: passage, translation: "JCB", sharedText: original)
        XCTAssertFalse(handoff.requiresPaste)
        let values = URLComponents(url: handoff.url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(values.first(where: { $0.name == "q" })?.value, handoff.prompt)
        XCTAssertTrue(handoff.prompt.contains(question)); XCTAssertTrue(handoff.prompt.contains("主はモーセに告げた。"))
        XCTAssertFalse(handoff.prompt.contains("system prompt")); XCTAssertEqual(handoff.url.host, "chatgpt.com")
    }
    func testUnverifiedProvidersUseBaseURLAndExplicitFullCopy() throws {
        for provider in [ExternalQuestionProvider.claude, .gemini] {
            let handoff = try ExternalQuestionHandoff(provider: provider, question: "これはなぜ？", passage: passage, translation: "JCB", sharedText: "原文")
            XCTAssertTrue(handoff.requiresPaste); XCTAssertNil(handoff.url.query)
            XCTAssertEqual(handoff.url, provider.homeURL); XCTAssertTrue(handoff.buttonTitle.contains("全文をコピー"))
            XCTAssertTrue(handoff.prompt.contains("これはなぜ？")); XCTAssertTrue(handoff.prompt.contains("原文"))
        }
    }
    func testLongPromptFallsBackWithoutTruncationAndAbsentOriginalIsHonest() throws {
        let original = String(repeating: "共有本文", count: 1500)
        let long = try ExternalQuestionHandoff(provider: .chatGPT, question: "なぜ？", passage: passage, translation: nil, sharedText: original)
        XCTAssertTrue(long.requiresPaste); XCTAssertTrue(long.prompt.contains(original)); XCTAssertNil(long.url.query)
        let absent = try ExternalQuestionHandoff(provider: .gemini, question: "なぜ？", passage: passage, translation: nil, sharedText: "")
        XCTAssertTrue(absent.prompt.contains("原文はこの端末にありません"))
        XCTAssertThrowsError(try ExternalQuestionHandoff(provider: .chatGPT, question: " ", passage: passage, translation: nil, sharedText: ""))
    }
    func testVisitValidationAndRoundTripRejectDifferentOwnerWithoutPrivateCredentials() throws {
        let owner = UUID().uuidString
        let visit = LocalReadingVisit(ownerID: owner, passage: passage, translation: "JCB", sharedText: "端末だけの原文")
        let data = try JSONEncoder().encode(visit)
        XCTAssertEqual(try JSONDecoder().decode(LocalReadingVisit.self, from: data), visit)
        XCTAssertTrue(visit.isValid(for: owner)); XCTAssertFalse(visit.isValid(for: nil)); XCTAssertFalse(visit.isValid(for: UUID().uuidString))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("token"))
        XCTAssertFalse(LocalReadingVisit(ownerID: nil, passage: passage, translation: nil, sharedText: String(repeating: "a", count: 20001)).isValid(for: nil))
    }
}
