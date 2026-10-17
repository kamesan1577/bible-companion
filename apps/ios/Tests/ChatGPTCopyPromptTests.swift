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
}
