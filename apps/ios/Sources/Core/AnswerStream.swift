import Foundation

public enum AnswerProgress: String, Sendable, Codable {
    case preparing, cached, generating, receiving, validating, saving
    public var label: String {
        switch self {
        case .preparing: return "質問と関連する資料を確認しています"
        case .cached: return "保存された標準解説を確認しています"
        case .generating: return "AIへ回答を依頼しています"
        case .receiving: return "AIから回答を受信しています"
        case .validating: return "回答の出典と表示範囲を確認しています"
        case .saving: return "回答を保存しています"
        }
    }
}
public enum AnswerUpdate: Sendable {
    case progress(AnswerProgress)
    case preview(String)
}

/// Actual SSE frames, including split UTF-8/CRLF. No raw model JSON or reasoning is surfaced.
public struct AnswerEventParser: Sendable {
    private var bytes = Data()
    private var lines: [String] = []
    private var frameBytes = 0
    private var events = 0
    private var terminal = false
    public init() {}
    public mutating func append(_ data: Data) throws -> [(String, Data)] {
        bytes.append(data)
        guard bytes.count <= 4_000_000 else { throw NetworkFailure.invalidResponse }
        var result: [(String, Data)] = []
        while let newline = bytes.firstIndex(of: 10) {
            var line = bytes.prefix(upTo: newline)
            if line.last == 13 { line = line.dropLast() }
            guard let text = String(data: line, encoding: .utf8) else { throw NetworkFailure.invalidResponse }
            bytes.removeSubrange(...newline)
            frameBytes += line.count
            guard frameBytes <= 4_000_000 else { throw NetworkFailure.invalidResponse }
            if text.isEmpty {
                if !lines.isEmpty {
                    let type = lines.first(where: { $0.hasPrefix("event:") }).map { String($0.dropFirst(6)).trimmingCharacters(in: .whitespaces) } ?? "message"
                    let content = lines.filter { $0.hasPrefix("data:") }.map { String($0.dropFirst(5)).replacingOccurrences(of: "^ ", with: "", options: .regularExpression) }.joined(separator: "\n")
                    if !content.isEmpty {
                        guard !terminal, ["progress", "preview", "complete", "failure"].contains(type), events < 512 else { throw NetworkFailure.invalidResponse }
                        events += 1; terminal = type == "complete" || type == "failure"
                        result.append((type, Data(content.utf8)))
                    }
                }
                lines = []; frameBytes = 0
            } else if !text.hasPrefix(":") { lines.append(text) }
        }
        return result
    }
    public func finish() throws {
        guard terminal, bytes.isEmpty, lines.isEmpty else { throw NetworkFailure.invalidResponse }
    }
}

/// URLSession's serialized delegate queue owns this receiver until transfer completion.
final class AnswerStreamReceiver: @unchecked Sendable {
    var parser = AnswerEventParser()
    var result: RequestResult?
    var failure: NetworkFailure?
    private var detected: Bool?
    private var prefix = Data()
    let update: @Sendable (AnswerUpdate) -> Void
    init(update: @escaping @Sendable (AnswerUpdate) -> Void) { self.update = update }
    func receive(_ data: Data) throws {
        var incoming = data
        if detected == nil {
            prefix.append(data)
            guard let first = prefix.first(where: { ![9,10,13,32].contains($0) }) else { return }
            detected = first != 123 // JSON fallback/errors from older backends.
            incoming = prefix; prefix = Data()
        }
        guard detected == true else { return }
        for (event, payload) in try parser.append(incoming) {
            switch event {
            case "progress":
                struct Update: Decodable { let stage: AnswerProgress }
                update(.progress(try JSONDecoder().decode(Update.self, from: payload).stage))
            case "preview":
                struct Preview: Decodable { let text: String }
                let value = try JSONDecoder().decode(Preview.self, from: payload)
                guard value.text.utf16.count <= 2000 else { throw NetworkFailure.invalidResponse }
                update(.preview(value.text))
            case "complete": result = try JSONDecoder().decode(RequestResult.self, from: payload)
            case "failure":
                struct Failure: Decodable { let status: Int; let code: String }
                let value = try JSONDecoder().decode(Failure.self, from: payload)
                failure = value.status == 401 ? .unauthenticated : .server(status: value.status, code: value.code)
            default: throw NetworkFailure.invalidResponse
            }
        }
    }
}
