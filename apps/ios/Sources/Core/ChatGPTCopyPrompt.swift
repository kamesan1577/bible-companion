import Foundation

/// User-facing content shared by the explicit clipboard and URL handoff paths.
public enum ChatGPTCopyPrompt {
    public enum Failure: Error { case emptyQuestion, oversized, missingBody }
    public static func make(question: String, passage: Passage, translation: String?, sharedText: String) throws -> String {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { throw Failure.emptyQuestion }
        guard question.utf16.count <= 2000, sharedText.utf16.count <= 20000 else { throw Failure.oversized }
        let body = sharedText.components(separatedBy: .newlines).filter {
            let line = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return !line.hasPrefix("https://") && !line.hasPrefix("http://")
        }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw Failure.missingBody }
        return """
        次の聖書箇所と、共有した原文を踏まえて、質問に直接答えてください。本文から確認できることと解釈を区別してください。

        選択箇所：\(passage.label)（\(passage.book) \(passage.reference)）
        訳名：\(translation ?? "共有情報に訳名なし")
        共有した原文（複数箇所を含む場合があります）：
        \(body)

        質問：
        \(question)
        """
    }
}

public enum ChatGPTQuestionLink {
    /// Conservative interoperability policy, not a claimed ChatGPT server limit.
    public static let maximumURLBytes = 16_384
    public enum Failure: Error { case empty, tooLong }
    public static func make(prompt: String) throws -> URL {
        guard !prompt.isEmpty else { throw Failure.empty }
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard let encoded = prompt.addingPercentEncoding(withAllowedCharacters: unreserved),
              let url = URL(string: "https://chatgpt.com/?q=" + encoded) else { throw Failure.empty }
        guard url.absoluteString.utf8.count <= maximumURLBytes else { throw Failure.tooLong }
        return url
    }
}
public struct ChatGPTHandoff: Codable, Equatable, Sendable {
    public let ownerID: String?
    public let prompt: String
    public let expiresAt: Date
    public init(ownerID: String?, prompt: String, now: Date = Date()) {
        self.ownerID = ownerID; self.prompt = prompt; expiresAt = now.addingTimeInterval(600)
    }
    public func isUsable(ownerID: String?, now: Date = Date()) -> Bool {
        self.ownerID == ownerID && expiresAt > now && expiresAt.timeIntervalSince(now) <= 600 && !prompt.isEmpty && prompt.utf16.count <= 24_000
    }
}
