import Foundation

public struct CursorPage<Item: Decodable & Sendable>: Decodable, Sendable {
    public let items: [Item]
    public let nextCursor: String?
}
public struct ConversationSummary: Codable, Identifiable, Sendable {
    public let id: String; public let importId: String; public let passage: Passage
    public let readingBoundary: Passage; public let spoilerAllowed: Bool
    public let createdAt: TimeInterval; public let messageCount: Int; public let lastMessageAt: TimeInterval?
}
public struct SavedComparisonSummary: Codable, Identifiable, Sendable {
    public let requestId: String; public let status: String; public let saved: Bool
    public let createdAt: TimeInterval; public let updatedAt: TimeInterval; public let trialCount: Int; public let errorCode: String?
    public var id: String { requestId }
}
public extension Conversation {
    func resumeRangeIndex(in item: ImportRecord) -> Int? {
        let boundary = readingBoundary ?? passage
        guard importId == item.id, boundary.contains(passage), let index = item.ranges.firstIndex(of: boundary) else { return nil }
        return index
    }
}
public extension ConversationMessage {
    var isHidden: Bool { content["hidden"].bool == true }
    var userText: String? { role == "user" && !isHidden ? content["text"].string : nil }
    var visibleAnswer: AnswerResult? {
        guard role == "assistant", !isHidden, let data = try? JSONEncoder().encode(content) else { return nil }
        return try? JSONDecoder().decode(AnswerResult.self, from: data)
    }
}
public struct MessageWindow: Sendable {
    public private(set) var conversation: Conversation?
    public private(set) var messages: [ConversationMessage] = []
    public private(set) var nextCursor: String?
    public private(set) var omittedNewerMessages = false
    public init() {}
    public mutating func clear() { self = MessageWindow() }
    public mutating func apply(_ page: Conversation, expectedID: String, older: Bool) throws {
        guard page.id == expectedID, (page.readingBoundary ?? page.passage).contains(page.passage),
              (page.messages?.count ?? 0) <= 50,
              page.nextMessageCursor.map({ UUID(uuidString: $0) != nil }) ?? true else { throw NetworkFailure.invalidResponse }
        if older, let previous = conversation {
            guard previous.id == page.id, previous.passage == page.passage, previous.readingBoundary == page.readingBoundary,
                  previous.spoilerAllowed == page.spoilerAllowed, let policy = previous.sourcePolicyVersion, page.sourcePolicyVersion == policy,
                  page.nextMessageCursor == nil || page.nextMessageCursor != nextCursor else { clear(); throw NetworkFailure.server(status: 409, code: "conversation_changed") }
        }
        let incoming = page.messages ?? []
        guard Set(incoming.map(\.id)).count == incoming.count, incoming.allSatisfy({ UUID(uuidString: $0.id) != nil && ["user", "assistant"].contains($0.role) }) else { throw NetworkFailure.invalidResponse }
        let ids = Set(incoming.map(\.id))
        let combined = older ? incoming + messages.filter { !ids.contains($0.id) } : incoming
        omittedNewerMessages = older && (omittedNewerMessages || combined.count > 200)
        messages = Array(combined.prefix(200)); conversation = page; nextCursor = page.nextMessageCursor
    }
}
