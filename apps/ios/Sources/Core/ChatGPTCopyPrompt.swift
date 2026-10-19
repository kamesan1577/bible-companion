import Foundation

/// User-facing content shared by the explicit clipboard and URL handoff paths.
public enum ChatGPTCopyPrompt {
    public enum Failure: Error { case emptyQuestion, oversized, missingBody }
    public static func make(question: String, passage: Passage, translation: String?, sharedText: String) throws -> String {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { throw Failure.emptyQuestion }
        guard question.utf16.count <= 2000, sharedText.utf16.count <= 20000 else { throw Failure.oversized }
        let body = SharedTextContent.removeRepeatedWholeBlock(sharedText.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: .newlines).filter {
            let line = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return !line.hasPrefix("https://") && !line.hasPrefix("http://")
        }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
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

/// Deduplicate representations of the same share, not repeated phrases inside scripture.
public enum SharedTextContent {
    /// Remove only repeated complete body+reference+translation representations.
    /// Comparison normalization never rewrites the retained original block.
    public static func removeRepeatedWholeBlock(_ text: String) -> String {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: .newlines)
        var result: [String] = [], pending: [String] = [], seen = Set<String>()
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let reference = withoutDirections(line).precomposedStringWithCompatibilityMapping.trimmingCharacters(in: .whitespacesAndNewlines)
            if let parsed = try? SharedImportParser.parse(reference), parsed.sourceUrl == nil {
                let body = pending.joined(separator: "\n")
                let normalizedBody = comparisonBody(body)
                let key = parsed.ranges.map { $0.book + " " + $0.reference }.joined(separator: ";")
                    + "|" + (parsed.translation?.uppercased() ?? "") + "|" + normalizedBody
                if normalizedBody.isEmpty || seen.insert(key).inserted {
                    result.append(contentsOf: pending); result.append(line)
                }
                pending = []
            } else { pending.append(line) }
            index += 1
        }
        // Unrecognised references, prose and trailing notes are never discarded.
        result.append(contentsOf: pending)
        return result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static func withoutDirections(_ value: String) -> String {
        String(value.unicodeScalars.filter { scalar in
            let v = scalar.value
            return v != 0x061C && v != 0x200E && v != 0x200F && !(0x202A...0x202E).contains(v) && !(0x2066...0x2069).contains(v)
        })
    }
    private static func comparisonBody(_ value: String) -> String {
        var body = withoutDirections(value).precomposedStringWithCanonicalMapping
            .components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Ignore a balanced outer quote wrapper only. Internal quotation, wording,
        // spacing, punctuation and separate verse references remain significant.
        for (open, close): (Character, Character) in [("「", "」"), ("『", "』"), ("“", "”"), ("‘", "’"), ("\"", "\"")] {
            guard body.first == open, body.last == close, body.count > 2 else { continue }
            let chars = Array(body)
            var depth = 0, valid = true
            if open == close { valid = chars.filter { $0 == open }.count == 2 }
            else {
                for i in chars.indices {
                    if chars[i] == open { depth += 1 }
                    if chars[i] == close { depth -= 1 }
                    if depth < 0 || (depth == 0 && i != chars.count - 1) { valid = false; break }
                }
                valid = valid && depth == 0
            }
            if valid { body = String(chars.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines) }
            break
        }
        return body
    }
    public static func combine(_ parts: [String]) -> String {
        var known = Set<String>(); var result: [String] = []
        for part in parts {
            let normalized = part.trimmingCharacters(in: .whitespacesAndNewlines)
            let body = normalized.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("https://") && !$0.trimmingCharacters(in: .whitespaces).hasPrefix("http://") }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let key = body.isEmpty ? normalized : body
            if !normalized.isEmpty, known.insert(key).inserted { result.append(normalized) }
        }
        return result.joined(separator: "\n")
    }
}
