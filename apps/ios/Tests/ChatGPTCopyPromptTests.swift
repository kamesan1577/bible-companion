import XCTest
@testable import CompanionCore
final class ChatGPTCopyPromptTests: XCTestCase {
    private let passage = Passage(book: "ACT", start: Verse(chapter: 26, verse: 32), end: Verse(chapter: 26, verse: 32))
    func testUsesOnlyExplicitUserFacingInputsAndPreservesUnicode() throws {
        let prompt = try ChatGPTCopyPrompt.make(question: "  上訴しなければ？ 🙏 & # +\nなぜ？  ", passage: passage, translation: "聖書 新共同訳", sharedText: "上訴していなかったら\nhttps://www.bible.com/bible/1819/ACT.26.32\n別の共有箇所")
        XCTAssertTrue(prompt.contains("ACT 26:32")); XCTAssertTrue(prompt.contains("聖書 新共同訳"))
        XCTAssertTrue(prompt.contains("上訴しなければ？ 🙏 & # +\nなぜ？")); XCTAssertTrue(prompt.contains("別の共有箇所"))
        XCTAssertFalse(prompt.contains("https://")); XCTAssertFalse(prompt.contains("system")); XCTAssertFalse(prompt.contains("token"))
    }
    func testNoInferredTranslationAndNoSilentTruncation() throws {
        let prompt = try ChatGPTCopyPrompt.make(question: "なぜ", passage: passage, translation: nil, sharedText: "共有した原文")
        XCTAssertTrue(prompt.contains("共有情報に訳名なし")); XCTAssertFalse(prompt.contains("WEB"))
        XCTAssertThrowsError(try ChatGPTCopyPrompt.make(question: String(repeating: "a", count: 2001), passage: passage, translation: nil, sharedText: "原文"))
        XCTAssertThrowsError(try ChatGPTCopyPrompt.make(question: "質問", passage: passage, translation: nil, sharedText: String(repeating: "a", count: 20001)))
        XCTAssertThrowsError(try ChatGPTCopyPrompt.make(question: " ", passage: passage, translation: nil, sharedText: "原文"))
        XCTAssertThrowsError(try ChatGPTCopyPrompt.make(question: "質問", passage: passage, translation: nil, sharedText: "https://example.com"))
    }

    func testQuestionURLIsLosslessAndHasOnlyOneQueryItem() throws {
        let prompt = "日本語\n節の本文 🙏 & # + % ? = /\n質問です"
        let url = try ChatGPTQuestionLink.make(prompt: prompt)
        XCTAssertEqual(url.scheme, "https"); XCTAssertEqual(url.host, "chatgpt.com")
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.queryItems, [URLQueryItem(name: "q", value: prompt)])
        XCTAssertNil(parts.fragment); XCTAssertTrue(url.absoluteString.contains("%2B")); XCTAssertTrue(url.absoluteString.contains("%0A"))
    }
    func testLongURLFailsWithoutTruncatingTheClipboardPrompt() throws {
        let prompt = String(repeating: "日本語", count: 1500)
        XCTAssertThrowsError(try ChatGPTQuestionLink.make(prompt: prompt))
        XCTAssertEqual(prompt.count, 4500)
        XCTAssertThrowsError(try ChatGPTQuestionLink.make(prompt: ""))
    }
    func testHandoffExpiresAndCannotCrossAccounts() {
        let now = Date(timeIntervalSince1970: 10000)
        let handoff = ChatGPTHandoff(ownerID: "A", prompt: "question", now: now)
        XCTAssertTrue(handoff.isUsable(ownerID: "A", now: now))
        XCTAssertFalse(handoff.isUsable(ownerID: "B", now: now))
        XCTAssertFalse(handoff.isUsable(ownerID: nil, now: now))
        XCTAssertFalse(handoff.isUsable(ownerID: "A", now: now.addingTimeInterval(600)))
        XCTAssertFalse(handoff.isUsable(ownerID: "A", now: now.addingTimeInterval(-1)))
    }
}
