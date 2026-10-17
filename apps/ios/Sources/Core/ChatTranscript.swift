import Foundation

public struct ChatEntry: Identifiable, Codable, Sendable {
    public let id: String
    public let role: String
    public let text: String
    public let answer: AnswerResult?
    public let incomplete: Bool?
    public let failureReason: String?
    public let standard: Bool
    public init(id: String, role: String, text: String, answer: AnswerResult? = nil, standard: Bool = false, incomplete: Bool? = nil, failureReason: String? = nil) {
        self.id = id; self.role = role; self.text = text; self.answer = answer; self.standard = standard; self.incomplete = incomplete; self.failureReason = failureReason
    }
    public static func saved(_ message: ConversationMessage) -> ChatEntry {
        ChatEntry(id: message.id, role: message.role,
                  text: message.userText ?? message.visibleAnswer?.answer ?? "資料や表示条件が変わったため、この回答は表示できません。",
                  answer: message.visibleAnswer, standard: message.content["standardExplanation"].bool == true)
    }
}
public struct ChatTranscript: Codable, Sendable {
    public private(set) var entries: [ChatEntry] = []
    public init() {}
    public mutating func restore(_ messages: [ConversationMessage]) { entries = messages.filter { !($0.role == "user" && $0.content["standardExplanation"].bool == true) }.map(ChatEntry.saved) }
    public mutating func prepend(_ messages: [ConversationMessage]) {
        let known = Set(entries.map(\.id))
        let older = messages.filter { !known.contains($0.id) && !($0.role == "user" && $0.content["standardExplanation"].bool == true) }.map(ChatEntry.saved)
        entries = older + entries
    }
    public mutating func submit(id: String, question: String, standard: Bool) {
        guard !standard, !entries.contains(where: { $0.id == id + ":user" }) else { return }
        entries.append(ChatEntry(id: id + ":user", role: "user", text: question))
    }
    public mutating func complete(id: String, answer: AnswerResult, standard: Bool) {
        if let existing = entries.firstIndex(where: { $0.id == id + ":assistant" }) {
            guard entries[existing].incomplete == true else { return }; entries.remove(at: existing)
        }
        entries.append(ChatEntry(id: id + ":assistant", role: "assistant", text: answer.answer, answer: answer, standard: standard))
    }
    public mutating func interrupt(id: String, text: String, standard: Bool, failure: NetworkFailure) {
        guard !text.isEmpty, PartialAnswerFailure.mayRetain(failure), !entries.contains(where: { $0.id == id + ":assistant" }) else { return }
        entries.append(ChatEntry(id: id + ":assistant", role: "assistant", text: text, standard: standard, incomplete: true, failureReason: PartialAnswerFailure.diagnostic(failure)))
    }
    /// Explicit retry replaces only an unanswered local attempt; completed turns stay immutable.
    public mutating func discardUnanswered(id: String) {
        guard !entries.contains(where: { $0.id == id + ":assistant" }) else { return }
        entries.removeAll { $0.id == id + ":user" }
    }
    public mutating func clear() { entries = [] }
}
