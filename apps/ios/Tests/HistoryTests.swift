import XCTest
@testable import CompanionCore

final class HistoryTests: XCTestCase {
    private func fixture<T: Decodable>(_ name: String) throws -> T {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: Self.self)
        #endif
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: XCTUnwrap(bundle.url(forResource: name, withExtension: "json"))))
    }
    func testRealListAndMessageFixturesDecodeAndResumeExactBoundary() throws {
        let list: CursorPage<ConversationSummary> = try fixture("conversation-list")
        let comparisons: CursorPage<SavedComparisonSummary> = try fixture("comparison-list")
        let detail: Conversation = try fixture("conversation-detail")
        let item: ImportRecord = try fixture("import")
        XCTAssertFalse(list.items.isEmpty); XCTAssertTrue(comparisons.items.allSatisfy(\.saved))
        XCTAssertNotNil(detail.resumeRangeIndex(in: item))
        var window = MessageWindow(); try window.apply(detail, expectedID: detail.id, older: false)
        XCTAssertEqual(window.messages.count, 2)
        XCTAssertNotNil(window.messages.first?.userText); XCTAssertNotNil(window.messages.last?.visibleAnswer)
    }
    private func changed(_ base: Conversation, policy: Int? = nil, messages: [ConversationMessage]? = nil, cursor: String? = nil, spoilers: Bool? = nil) -> Conversation {
        Conversation(id: base.id, importId: base.importId, passage: base.passage, readingBoundary: base.readingBoundary, spoilerAllowed: spoilers ?? base.spoilerAllowed, createdAt: base.createdAt, messages: messages ?? base.messages, nextMessageCursor: cursor, sourcePolicyVersion: policy ?? base.sourcePolicyVersion)
    }
    func testRightsOrScopeChangeClearsPreviouslyVisibleWindow() throws {
        let detail: Conversation = try fixture("conversation-detail")
        for updated in [changed(detail, policy: (detail.sourcePolicyVersion ?? 0) + 1), changed(detail, spoilers: !detail.spoilerAllowed)] {
            var window = MessageWindow(); try window.apply(detail, expectedID: detail.id, older: false)
            XCTAssertThrowsError(try window.apply(updated, expectedID: detail.id, older: true))
            XCTAssertTrue(window.messages.isEmpty)
        }
    }
    func testDuplicateAndForeignPagesRejected() throws {
        let detail: Conversation = try fixture("conversation-detail")
        let message = try XCTUnwrap(detail.messages?.first)
        var window = MessageWindow()
        XCTAssertThrowsError(try window.apply(detail, expectedID: UUID().uuidString, older: false))
        XCTAssertThrowsError(try window.apply(changed(detail, messages: [message, message]), expectedID: detail.id, older: false))
    }
    func testMemoryWindowBoundsWithoutLosingOlderNavigation() throws {
        let detail: Conversation = try fixture("conversation-detail")
        var window = MessageWindow()
        for page in 0..<5 {
            let messages = (0..<50).map { index in ConversationMessage(id: UUID().uuidString, role: "user", content: .object(["text": .string("sample")]), createdAt: Double(1000 - page * 50 + index)) }
            let value = changed(detail, messages: messages, cursor: UUID().uuidString)
            try window.apply(value, expectedID: detail.id, older: page != 0)
        }
        XCTAssertEqual(window.messages.count, 200); XCTAssertTrue(window.omittedNewerMessages); XCTAssertNotNil(window.nextCursor)
    }
    func testHiddenMessageNeverExposesEmbeddedBody() {
        let message = ConversationMessage(id: UUID().uuidString, role: "assistant", content: .object(["hidden": .bool(true), "answer": .string("must remain hidden")]), createdAt: 1)
        XCTAssertTrue(message.isHidden); XCTAssertNil(message.visibleAnswer); XCTAssertNil(message.userText)
    }
}
