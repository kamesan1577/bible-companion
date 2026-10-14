import Foundation

/// Conservative offline preview. The API revalidates every confirmed reference.
/// Unknown numeric translation IDs are deliberately never guessed.
public enum SharedImportParser {
    public enum ParseError: Error { case tooLong, unsupported, invalidRange }
    public static func parse(_ raw: String) throws -> ParsedImport {
        guard raw.utf8.count <= 60_000, raw.utf16.count <= 20_000 else { throw ParseError.tooLong }
        let text = raw.precomposedStringWithCompatibilityMapping
        var aliases = Canon.books.flatMap { book in [(book.id, book.id), (book.en, book.id), (book.ja, book.id), (book.ja.replacingOccurrences(of: "の福音書", with: ""), book.id)] }
        aliases += [("使徒", "ACT"), ("使徒行伝", "ACT"), ("使徒言行録", "ACT"), ("詩編", "PSA")]
        aliases.sort { $0.0.count > $1.0.count }
        let referenceLines = text.components(separatedBy: .newlines).filter { line in
            let compact = line.components(separatedBy: .whitespaces).joined().lowercased()
            return aliases.contains { alias, _ in
                let label = alias.components(separatedBy: .whitespaces).joined().lowercased()
                return compact.hasPrefix(label) && String(compact.dropFirst(label.count)).first?.isNumber == true
            }
        }
        let urlReferences = matches(#"https://(?:www\.)?(?:bible\.com|youversion\.com)/[^\s<>]+"#, in: text)
        // Delegate combined/multiple references to the strict server parser; never truncate them locally.
        guard referenceLines.count + urlReferences.count <= 1 else { throw ParseError.unsupported }
        if let match = matches(#"https://(?:www\.)?(?:bible\.com|youversion\.com)/[^\s<>]+"#, in: text).first,
           let url = URL(string: match[0].trimmingCharacters(in: CharacterSet(charactersIn: ")）。，"))),
           let path = matches(#"^/(?:[a-z]{2}/)?bible/\d+/([1-3]?[A-Z]{2,3})\.(\d+)\.(\d+)(?:-(?:(\d+)\.)?(\d+))?(?:\.([A-Z0-9]+))?/?$"#, in: url.path).first {
            let book = path[1].uppercased()
            let start = Verse(chapter: Int(path[2]) ?? 0, verse: Int(path[3]) ?? 0)
            let end = Verse(chapter: try number(path[4], fallback: start.chapter), verse: try number(path[5], fallback: start.verse))
            let passage = Passage(book: book, start: start, end: end)
            guard passage.isValid else { throw ParseError.invalidRange }
            let translation = path[6].isEmpty ? nil : path[6].uppercased()
            return ParsedImport(ranges: [passage], translation: translation, sourceUrl: "https://\(url.host ?? "bible.com")\(url.path)", needsConfirmation: translation == nil, warnings: translation == nil ? ["訳は未確認です。保存前に確認してください。"] : [])
        }
        for line in text.components(separatedBy: .newlines) {
            let compact = line.components(separatedBy: .whitespaces).joined()
            for (alias, book) in aliases {
                let compactAlias = alias.components(separatedBy: .whitespaces).joined()
                guard compact.lowercased().hasPrefix(compactAlias.lowercased()) else { continue }
                let tail = String(compact.dropFirst(compactAlias.count))
                guard let match = matches(#"^(\d+[:章]\d+(?:[-‐‑‒–—〜～](?:\d+[:章])?\d+)?節?)(?:[（(]?([A-Z][A-Z0-9-]{0,29})[）)]?)?$"#, in: tail).first else { continue }
                let numeric = match[1].replacingOccurrences(of: "章", with: ":").replacingOccurrences(of: "節", with: "")
                guard let numbers = matches(#"^(\d+):(\d+)(?:[-‐‑‒–—〜～](?:(\d+):)?(\d+))?$"#, in: numeric).first else { continue }
                let start = Verse(chapter: Int(numbers[1]) ?? 0, verse: Int(numbers[2]) ?? 0)
                let passage = Passage(book: book, start: start, end: Verse(chapter: try number(numbers[3], fallback: start.chapter), verse: try number(numbers[4], fallback: start.verse)))
                guard passage.isValid else { throw ParseError.invalidRange }
                let translation = match[2].isEmpty ? nil : match[2].uppercased()
                return ParsedImport(ranges: [passage], translation: translation, sourceUrl: nil, needsConfirmation: translation == nil, warnings: translation == nil ? ["訳は未確認です。保存前に確認してください。"] : [])
            }
        }
        throw ParseError.unsupported
    }
    private static func number(_ value: String, fallback: Int) throws -> Int {
        if value.isEmpty { return fallback }
        guard let number = Int(value) else { throw ParseError.invalidRange }
        return number
    }
    private static func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let source = text as NSString
        return expression.matches(in: text, range: NSRange(location: 0, length: source.length)).map { match in
            (0..<match.numberOfRanges).map { i in let range = match.range(at: i); return range.location == NSNotFound ? "" : source.substring(with: range) }
        }
    }
}

public struct PendingShare: Codable, Identifiable, Sendable {
    public let id: UUID
    public let ownerID: String?
    public let text: String
    public let createdAt: Date
    public init(id: UUID = UUID(), ownerID: String?, text: String, createdAt: Date = Date()) { self.id = id; self.ownerID = ownerID; self.text = text; self.createdAt = createdAt }
    public func requiresAccountConfirmation(currentOwner: String) -> Bool { ownerID != currentOwner }
    public func isExpired(at date: Date = Date()) -> Bool { date.timeIntervalSince(createdAt) >= 86_400 || createdAt > date.addingTimeInterval(60) }
}
/// Every response is accepted only for the current account/scope generation.
/// Cancelled or superseded network calls cannot repopulate a different reader.
public struct RequestGate: Sendable {
    public private(set) var generation: UUID = UUID()
    public init() {}
    @discardableResult public mutating func invalidate() -> UUID { generation = UUID(); return generation }
    public func accepts(_ candidate: UUID) -> Bool { generation == candidate }
}
public enum NetworkFailure: Error, Equatable, Sendable {
    case unconfigured, insecureEndpoint, unauthenticated, offline, invalidResponse, server(status: Int, code: String), cancelled
    public var userMessage: String {
        switch self {
        case .unconfigured: return "サーバーの接続先が未設定です。設定済みの構成でビルドしてください。"
        case .insecureEndpoint: return "接続先には有効な HTTPS アドレスが必要です。"
        case .unauthenticated: return "ログインし直してください。別のアカウントへ自動送信はしません。"
        case .offline: return "通信できません。保存済みの読書履歴は確認できます。質問は再送していません。"
        case .invalidResponse: return "応答を読み取れませんでした。"
        case .cancelled: return "中止しました。処理や利用量が発生している場合があります。"
        case .server(let status, let code):
            if code == "comparison_budget_exceeded" { return "比較の全体量が利用枠を超えています。質問数や最大出力トークンを減らし、残りの利用枠を確認してから新しい計画を確認してください。計画自体が大きすぎる場合、リセット後も実行できません。自動で設定は変更しません。" }
            if status == 429 && code == "rate_limited" { return "短時間にリクエストが集中しています。少し時間をおいてから確認してください。自動で再送はしていません。" }
            if status == 429 && code == "daily_budget_exceeded" { return "今回の処理に必要な利用枠が足りません。個人用とアプリ全体の両方の枠で制限されています。設定で利用状況と次のリセット時刻を確認してください。" }
            if let explanation = AIAvailabilityExplanation.message(for: code) { return explanation }
            if code == "grounded_consent_required" { return "実験的なAI解説の注意事項を、設定で確認して同意してください。" }
            if code == "answer_mode_disabled" { return "この回答方法は現在利用できません。利用可能な方法を確認してください。自動で別の方法へ切り替えません。" }
            if code == "invalid_consent_policy" { return "注意事項が更新されました。設定で最新版を読み直してください。" }
            if code == "ai_consent_required" { return "AIへの送信を設定で確認してください。" }
            if code == "comparison_expired" { return "比較の実行期限が切れました。終了した比較の状態と利用量を確認し、続ける場合は新しい計画を確認してください。実行済みの利用量が戻るとは限りません。" }
            if code == "plan_changed" { return "比較の条件または検証資料が変わり、前の確認を利用できません。現在の条件で計画と利用枠を確認し直してください。自動では実行しません。" }
            if code == "source_policy_changed" { return "資料が更新されました。オンラインで読み直してください。" }
            return "処理を完了できませんでした（\(code)）。内容を保ったまま、状態を確認できます。"
        }
    }
}

/// Invalid owner metadata is not silently downgraded to an unbound share.
public enum ShareOwnerMarker {
    public static let maximumBytes = 64
    public static func decode(_ data: Data) throws -> String? {
        guard data.count <= maximumBytes else { throw NetworkFailure.invalidResponse }
        if data.isEmpty { return nil }
        guard let owner = String(data: data, encoding: .utf8), UUID(uuidString: owner) != nil else { throw NetworkFailure.invalidResponse }
        return owner
    }
}


/// Presentation only: these codes never authorize a model or reveal operator identity.
/// BUDGET_UNVERIFIED does not distinguish initial setup, expiry, revocation or invalid evidence.
public enum AIAvailabilityExplanation {
    public static func message(for code: String, owner: Bool = false) -> String? {
        switch code {
        case "ai_not_connected", "model_unconnected", "CONNECTION_NOT_VERIFIED", "MODEL_UNCONNECTED":
            return owner
                ? "AIの接続が有効ではありません。運用CLIで初期設定と接続状態を確認してください。"
                : "AIの接続が有効ではありません。オーナーに初期設定と接続状態の確認を依頼してください。「資料のみ」で利用可能な出典を確認できます。"
        case "model_terms_unreviewed", "MODEL_TERMS_UNREVIEWED":
            return owner
                ? "現在のモデル規約の確認が必要です。運用手順に沿って規約を確認してください。この画面では同意を行いません。"
                : "現在のモデル規約が確認されていません。オーナーに確認を依頼してください。個人のAI送信への同意とは別の確認です。"
        case "budget_unverified", "BUDGET_UNVERIFIED":
            return owner
                ? "利用枠の検証資料が有効と確認できません。初期設定・期限切れ・失効などの区別はこの応答ではできません。運用CLIで資料を確認し、Free運用では必要に応じて証跡を更新してください。更新後は準備状況を再確認してください。"
                : "利用枠の検証資料が有効と確認できません。初期設定・期限切れ・失効などの区別はこの応答ではできません。オーナーに確認を依頼してください。日次上限の消費を示すものではありません。「資料のみ」で利用可能な出典を確認できます。"
        case "budget_exceeded", "BUDGET_EXCEEDED":
            return "今回の設定で必要な利用枠が足りません。最大出力トークンや質問の量を減らし、利用枠を再確認してください。計画が上限を超える場合、リセットを待つだけでは解消しません。"
        case "PAID_APPROVAL_REQUIRED":
            return "有料利用の承認がないため利用できません。Free運用では有効にできません。この画面では有料利用を承認しません。"
        case "model_disabled", "MODEL_DISABLED":
            return "このモデルは現在の利用条件では許可されていません。オーナーがモデルの利用区分と運用設定を確認してください。"
        default: return nil
        }
    }
    public static func catalogReason(_ code: String?) -> String {
        guard let code else { return "利用できない理由を確認できませんでした。" }
        return message(for: code, owner: true) ?? "利用不可（\(code)）。運用設定を確認してください。"
    }
}
