import Foundation

/// Explicit clipboard handoff, never a URL or an AI-system prompt.
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
