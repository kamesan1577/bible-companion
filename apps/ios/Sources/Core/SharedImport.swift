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
        // YouVersion commonly shares both a displayed reference and the URL for that same passage.
        // Accept equivalent duplicates only; distinct passages still go to strict server parsing.
        if referenceLines.count + urlReferences.count > 1 {
            let copies = try (referenceLines + urlReferences.map { $0[0] }).map { try parse($0) }
            guard let first = copies.first, copies.allSatisfy({ $0.ranges == first.ranges }) else { throw ParseError.unsupported }
            let translations = Set(copies.compactMap(\.translation))
            guard translations.count <= 1 else { throw ParseError.unsupported }
            let translation = translations.first
            return ParsedImport(ranges: first.ranges, translation: translation,
                sourceUrl: copies.compactMap(\.sourceUrl).first, needsConfirmation: translation == nil,
                warnings: translation == nil ? ["訳名を読み取れませんでした。保存する前に確認してください。"] : [])
        }
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
        case .unconfigured: return "現在この機能を利用できません。アプリの管理者に設定を確認してもらってください。"
        case .insecureEndpoint: return "安全な接続を確認できないため、処理を中止しました。アプリの管理者にお問い合わせください。"
        case .unauthenticated: return "ログイン状態を確認できません。ログインし直してください。別のアカウントへ自動送信はしません。"
        case .offline: return "インターネットに接続できません。保存済みの読書履歴は確認できますが、質問は送信されていません。接続後にもう一度お試しください。"
        case .invalidResponse: return "内容を確認できなかったため、処理を中止しました。時間をおいてからもう一度お試しください。"
        case .cancelled: return "処理を中止しました。利用状況に反映される場合があります。"
        case .server(let status, let code):
            if code == "comparison_budget_exceeded" { return "一度に扱う内容が大きく、今回は比較を進められませんでした。質問を減らすか、利用状況を確認して新しい内容をお試しください。設定は自動で変更していません。" }
            if status == 429 && code == "rate_limited" { return "利用が集中しています。少し時間をおいてから、もう一度お試しください。自動でやり直してはいません。" }
            if status == 429 && code == "daily_budget_exceeded" { return "利用上限に達したため、処理を続けられません。設定の利用状況から、再開できる時刻を確認してください。" }
            if let explanation = AIAvailabilityExplanation.message(for: code) { return explanation }
            if code == "grounded_consent_required" { return "試験的なAIの説明を使うには、設定の注意事項を読み、利用に同意してください。" }
            if code == "answer_mode_disabled" { return "選んだ説明方法は現在使えません。選べる方法を確認してください。別の方法へ自動では切り替えません。" }
            if code == "invalid_consent_policy" { return "注意事項が更新されました。設定で最新版を読み直してください。" }
            if code == "ai_consent_required" { return "AIを使う前に、設定で利用を許可してください。" }
            if code == "comparison_expired" { return "この比較の有効時間が過ぎました。状態と利用状況を確認し、続ける場合は内容をもう一度確認してください。すでに使われた分は戻らないことがあります。" }
            if code == "plan_changed" { return "確認後に条件が変わったため、処理を始められません。内容を見直し、もう一度確認してください。自動では開始しません。" }
            if code == "source_policy_changed" { return "資料が更新されました。最新の内容を読み直してから、もう一度お試しください。" }
            return "処理を完了できませんでした。内容は自動で変更・再送していません。時間をおいてから、もう一度お試しください。"
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
                ? "AI機能の準備ができていません。管理者向けの設定を確認してください。"
                : "AI機能は現在利用できません。管理者に準備状況の確認を依頼してください。「資料のみ」を選ぶと、利用できる出典を確認できます。"
        case "model_terms_unreviewed", "MODEL_TERMS_UNREVIEWED":
            return owner
                ? "利用前にAIの利用条件を確認する必要があります。管理者向けの手順で確認してください。この画面では同意できません。"
                : "AIの利用条件がまだ確認されていません。管理者に確認を依頼してください。これはAI送信に関するご自身の同意とは別の確認です。"
        case "budget_unverified", "BUDGET_UNVERIFIED":
            return owner
                ? "利用状況を確認する資料が整っていません。管理者向けの手順で確認し、必要な対応の後に状態を再確認してください。"
                : "利用状況を確認できないため、AIを利用できません。管理者に確認を依頼してください。これは利用上限に達したことを意味しません。「資料のみ」を選ぶと、利用できる出典を確認できます。"
        case "budget_exceeded", "BUDGET_EXCEEDED":
            return "この内容を扱うには利用枠が足りません。質問を短くするか、内容を減らして利用状況を確認してください。内容が大きすぎる場合は、利用状況が戻っても扱えないことがあります。"
        case "PAID_APPROVAL_REQUIRED":
            return "管理者が有料利用を許可していないため、この機能は使えません。この画面から許可することはできません。"
        case "model_disabled", "MODEL_DISABLED":
            return "このAIは現在利用できません。管理者に利用設定を確認してもらってください。"
        default: return nil
        }
    }
    public static func catalogReason(_ code: String?) -> String {
        guard let code else { return "利用できる状態か確認できませんでした。管理者に設定を確認してもらってください。" }
        return message(for: code, owner: true) ?? "現在利用できない状態です。管理者に設定を確認してもらってください。"
    }
}
