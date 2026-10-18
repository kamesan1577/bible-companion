import Foundation

public enum ExternalQuestionProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case chatGPT, claude, gemini
    public var id: String { rawValue }
    public var title: String { switch self { case .chatGPT: "ChatGPT"; case .claude: "Claude"; case .gemini: "Gemini" } }
    public var homeURL: URL {
        let value = switch self { case .chatGPT: "https://chatgpt.com/"; case .claude: "https://claude.ai/new"; case .gemini: "https://gemini.google.com/app" }
        return URL(string: value)!
    }
    public var deliveryNotice: String {
        self == .chatGPT ? "聖句・原文・質問をChatGPTへ渡します。開くと回答が始まる場合があります。" : "全文をコピーして\(title)を開きます。開いた先の入力欄に貼り付けて送信してください。自動入力は未確認です。"
    }
}
public struct ExternalQuestionHandoff: Sendable {
    public let provider: ExternalQuestionProvider
    public let prompt: String
    public let url: URL
    public let requiresPaste: Bool
    public var buttonTitle: String { requiresPaste ? "全文をコピーして\(provider.title)を開く" : "\(provider.title)へ送る" }
    public init(provider: ExternalQuestionProvider, question: String, passage: Passage, translation: String?, sharedText: String) throws {
        self.provider = provider
        // Explicit absence is never replaced by a guessed translation or an AI summary.
        let original = sharedText.trimmingCharacters(in: .whitespacesAndNewlines)
        prompt = try ChatGPTCopyPrompt.make(question: question, passage: passage, translation: translation,
            sharedText: original.isEmpty ? "（共有した原文はこの端末にありません。訳文を推測で引用せず、参照箇所と質問に基づいて答えてください。）" : original)
        if provider == .chatGPT, let direct = try? ChatGPTQuestionLink.make(prompt: prompt) { url = direct; requiresPaste = false }
        else { url = provider.homeURL; requiresPaste = true }
    }
}

/// A protected device-local visit; separate from existing private/cloud history.
/// No session, refresh capability or AI response is included.
public struct LocalReadingVisit: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let ownerID: String?
    public let passage: Passage
    public let translation: String?
    public let sharedText: String
    public let openedAt: Date
    public init(id: UUID = UUID(), ownerID: String?, passage: Passage, translation: String?, sharedText: String, openedAt: Date = Date()) {
        self.id = id; self.ownerID = ownerID; self.passage = passage; self.translation = translation; self.sharedText = sharedText; self.openedAt = openedAt
    }
    public func isValid(for owner: String?) -> Bool {
        ownerID == owner && passage.isValid && sharedText.utf16.count <= 20_000 && (translation?.count ?? 0) <= 30 && openedAt.timeIntervalSince1970.isFinite
    }
}
