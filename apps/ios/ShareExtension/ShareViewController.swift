import UIKit
import SwiftUI
import UniformTypeIdentifiers
import CompanionCore

/// The extension displays public references in place; it never launches the containing app.
@MainActor final class ShareViewController: UIViewController {
    private let model = SharedPreviewModel()
    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: SharedPreviewView(model: model, close: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) }))
        addChild(host); view.addSubview(host.view); host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor), host.view.topAnchor.constraint(equalTo: view.topAnchor), host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
        host.didMove(toParent: self)
        Task {
            var parts: [String] = []
            do {
                let inputs = extensionContext?.inputItems as? [NSExtensionItem] ?? []
                for input in inputs {
                    if let text = input.attributedContentText?.string { parts.append(text) }
                    for provider in (input.attachments ?? []).prefix(5) {
                        let type = provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) ? UTType.url.identifier : UTType.plainText.identifier
                        if provider.hasItemConformingToTypeIdentifier(type), let value = try await load(provider, type: type) { parts.append(value) }
                    }
                }
                var seen = Set<String>()
                let text = parts.filter { seen.insert($0).inserted }.joined(separator: "\n")
                guard !text.isEmpty, text.utf16.count <= 20_000 else {
                    model.sharedText = String(text.prefix(20_000))
                    model.shareTextWasTruncated = !text.isEmpty
                    model.shareParseFailed = true
                    model.error = "共有内容から章節を確認できませんでした。YouVersionで節と本文を選び直してから、もう一度共有してください。受け取った内容は下で端末内表示できます。"
                    model.loading = false
                    return
                }
                model.sharedText = text
                if let parsed = try? SharedImportParser.parse(text) { model.translation = parsed.translation; model.labels = parsed.ranges.map(\.label); model.items = parsed.ranges.enumerated().map { .init(conversationId: "local-\($0.offset)", passage: $0.element) } }
                else { model.shareParseFailed = true }
                do { try ShareInbox.enqueue(text) }
                catch let accessError as ShareAIAccessReadError { model.storageNotice = SharedPreviewModel.accessMessage(for: accessError) }
                catch { model.storageNotice = "共有内容をアプリへ安全に引き継いだことを確認できません。ここに表示される範囲だけを確認し、続ける場合はこの画面を閉じてYouVersionから共有し直してください。" }
                await model.refresh()
            } catch {
                let partial = parts.joined(separator: "\n")
                model.sharedText = String(partial.prefix(20_000))
                model.shareTextWasTruncated = partial.utf16.count > 20_000
                model.shareParseFailed = true
                model.error = "共有内容を完全に読み取れませんでした。YouVersionで節と本文を選び直してから、もう一度共有してください。受け取れた部分は下で端末内表示できます。"
                model.loading = false
            }
        }
    }
    private func load(_ provider: NSItemProvider, type: String) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type, options: nil) { value, error in
                if let error { continuation.resume(throwing: error) }
                else if let url = value as? URL { continuation.resume(returning: url.absoluteString) }
                else { continuation.resume(returning: value as? String) }
            }
        }
    }
}
@MainActor private final class SharedPreviewModel: ObservableObject {
    struct Started: Decodable, Sendable { let ownerId: String; let importId: String; let items: [Item] }
    struct Item: Decodable, Sendable, Identifiable { let conversationId: String; let passage: Passage; var id: String { conversationId } }
    @Published var loading = true
    @Published var error: String?
    @Published var labels: [String] = []
    @Published var storageNotice: String?
    @Published var translation: String?
    @Published var needsSetup = false
    @Published var setupMessage = "共有AIの利用状態を確認できません。原因はこの画面から特定できません。アプリ内の準備画面で状態を確認してください。"
    @Published var canAsk = false
    @Published var canRetryStart = false
    @Published var canRetryExplanation = false
    @Published var items: [Item] = []
    @Published var answers: [String: AnswerResult] = [:]
    @Published var selectedIndex = 0
    @Published var draft = ""
    @Published var pendingRequest: String?
    @Published var shareParseFailed = false
    @Published var shareTextWasTruncated = false
    var sharedText = ""
    private let startRequest = UUID().uuidString
    private var client: APIClient?
    var current: Item? { items.indices.contains(selectedIndex) ? items[selectedIndex] : nil }
    var answer: AnswerResult? { current.flatMap { answers[$0.id] } }
    func refresh() async {
        guard !sharedText.isEmpty, client == nil else { return }
        loading = true; error = nil; canRetryStart = false
        defer { loading = false }
        do {
            let access: ShareAIAccess
            do { access = try ShareInbox.verifiedAIAccess() }
            catch let accessError as ShareAIAccessReadError {
                needsSetup = true
                setupMessage = Self.accessMessage(for: accessError)
                return
            } catch {
                needsSetup = true
                setupMessage = "共有AIの保存状態を確認できません。原因を特定できないため、アプリ内の準備画面で状態を確認してください。"
                return
            }
            do { try ShareInbox.acknowledgeExtensionRead(access) }
            catch {
                storageNotice = "共有AIの読み取り確認をアプリへ保存できませんでした。解説の利用権限は変更せず、このまま共有した箇所の確認を続けます。"
            }
            guard let raw = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String, let base = URL(string: raw) else { error = "接続先を確認できません。アプリを更新してください。"; return }
            let transport = try APIClient(baseURL: base); await transport.setToken(access.token)
            let started: Started
            do { started = try await transport.post("/share/start", body: ["requestId": startRequest, "sharedText": sharedText]) }
            catch {
                if case NetworkFailure.server(_, let code) = error, code == "invalid_passage" {
                    self.error = "共有文から章節を読み取れませんでした。YouVersionで章節を選び直してから共有してください。"
                } else {
                    canRetryStart = true
                    show(error)
                }
                return
            }
            guard started.ownerId == access.ownerID, !started.items.isEmpty else { throw NetworkFailure.invalidResponse }
            client = transport; items = started.items; needsSetup = false; shareParseFailed = false; canAsk = true
            loading = false
            await explain()
        } catch { show(error) }
    }
    func explain() async {
        guard answer == nil else { return }
        await send("この箇所の出来事と意味を、初めて読む人にも分かる日本語で短く説明してください。", standard: true)
    }
    func sendQuestion() async {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, question.utf16.count <= 2000 else { return }
        await send(question)
        if error == nil { draft = "" }
    }
    private func send(_ question: String, standard: Bool = false) async {
        guard let client, let item = current, !loading, pendingRequest == nil else { return }
        loading = true; error = nil; canRetryExplanation = false
        defer { loading = false }
        let request = UUID().uuidString; pendingRequest = request
        struct Input: Encodable, Sendable { let requestId: String; let question: String; let answerMode = "grounded-generation" }
        do {
            let result: RequestResult
            if standard { result = try await client.post("/share/conversations/\(item.id)/explanation", body: ["requestId": request]) }
            else { result = try await client.post("/share/conversations/\(item.id)/questions", body: Input(requestId: request, question: question)) }
            guard result.status == "complete", let answer = result.result else { throw NetworkFailure.invalidResponse }
            answers[item.id] = answer; pendingRequest = nil
        } catch { show(error) }
    }
    func checkStatus() async {
        guard let client, let request = pendingRequest, let item = current, !loading else { return }
        loading = true; error = nil; defer { loading = false }
        do {
            let result: RequestResult = try await client.get("/share/requests/\(request)")
            if result.status == "complete", let answer = result.result { answers[item.id] = answer; pendingRequest = nil }
            else if ["failed", "cancelled"].contains(result.status) { pendingRequest = nil; error = "前の処理は終了しました。もう一度質問できます。" }
            else { error = "回答を準備しています。少ししてから確認してください。" }
        } catch { show(error) }
    }
    private func show(_ failure: Error) {
        if case NetworkFailure.unauthenticated = failure {
            let recovery = ShareAuthRecoveryState.unauthenticated(pendingRequest: pendingRequest)
            needsSetup = recovery.requiresAppRecheck
            canRetryStart = recovery.canRetryShareStart
            pendingRequest = recovery.pendingRequest
            setupMessage = recovery.setupMessage
            error = recovery.error
            switch recovery.automaticAction {
            case .none: break
            }
            return
        }
        if case NetworkFailure.server(_, let code) = failure, ["grounded_consent_required", "ai_consent_required", "invalid_consent_policy"].contains(code) {
            needsSetup = true
            pendingRequest = nil
            setupMessage = code == "invalid_consent_policy"
                ? "同意条件が更新されています。アプリ内の準備画面を開き、最新の注意事項を確認してください。内容を確認するまで解説は開始しません。"
                : "共有AIの利用同意が確認できません。アプリ内の準備画面で注意事項と同意状態を確認してください。"
            error = nil
            return
        }
        if case NetworkFailure.server(let status, let code) = failure, status == 401 || code.hasPrefix("share_access") {
            needsSetup = true
            canRetryStart = false
            setupMessage = Self.apiAccessMessage(status: status, code: code)
            error = nil
            return
        }
        if case NetworkFailure.server(_, let code) = failure, let availability = AIAvailabilityExplanation.message(for: code) {
            needsSetup = true
            pendingRequest = nil
            setupMessage = availability
            error = nil
            return
        }
        if case NetworkFailure.server(_, let code) = failure, ["standard_explanation_pending", "standard_explanation_unavailable"].contains(code) { pendingRequest = nil; canRetryExplanation = true }
        error = (failure as? NetworkFailure)?.userMessage ?? "接続できませんでした。共有した箇所は保持しています。"
    }
    static func accessMessage(for failure: ShareAIAccessReadError) -> String {
        switch failure {
        case .appGroupUnavailable:
            return "アプリとこの共有画面の間で、設定を受け取れませんでした。同意を繰り返す必要はありません。アプリを開き、準備画面に問題が出ていないか確認してください。"
        case .protectedDataUnavailable:
            return "端末の保護データまたは共有用保存領域へのアクセスが拒否されました。端末のロックを解除して再試行してください。ロック以外の権限・一時的な問題の可能性もあるため、解決しない場合はアプリの共有機能を確認してください。"
        case .readFailed:
            return "共有AIの保存状態を読み取れませんでした。アプリ内の準備画面で状態を確認し、画面を閉じてから共有し直してください。"
        case .missing:
            return "共有AIの利用情報が保存されていません。アプリ内の準備画面でログイン状態と同意を確認し、必要な設定を保存してから共有し直してください。"
        case .expired:
            return "共有AIの利用情報の期限が切れています。アプリ内の準備画面でログインと同意状態を確認し、必要な場合は設定し直してから共有してください。"
        case .ownerMismatch:
            return "共有AIの利用情報とアプリ側のアカウント確認情報が一致しません。別アカウントが原因とは限らないため、アプリでログイン状態と共有設定を確認してください。アカウント情報はこの画面には表示しません。"
        case .corrupted:
            return "共有AIの保存情報を安全に確認できませんでした。アプリ内の準備画面を開き、ログインと同意状態を確認してください。内容を確認できるまで解説は開始しません。"
        case .writeFailed:
            return "共有内容をアプリ間保存領域へ保存できませんでした。現在画面で確認できる内容だけを表示しています。画面を閉じ、YouVersionからもう一度共有してください。"
        }
    }
    private static func apiAccessMessage(status: Int, code: String) -> String {
        if code == "unauthenticated" || code == "invalid_token" {
            return "サーバーがログインを確認できませんでした。アプリを開いてログイン状態を確認し、YouVersionから共有し直してください。初回設定が原因とは限りません。"
        }
        if code == "share_access_expired" {
            return "共有AIの利用情報が期限切れとサーバーから通知されました。アプリ内の準備画面で状態を確認し、必要な更新後にもう一度共有してください。"
        }
        if code == "share_access_owner_mismatch" {
            return "サーバー側で共有AIのアカウントを確認できませんでした。アプリで利用中のアカウントと共有設定を確認してください。アカウント情報は表示しません。"
        }
        return "共有AIの認証が拒否されました（HTTP \(status)）。初回設定・期限・アカウント・保存状態のどれが原因か、この画面からは特定できません。アプリ内の準備画面で状態を確認し、必要な対応後に共有し直してください。"
    }
}
private struct SharedPreviewView: View {
    @ObservedObject var model: SharedPreviewModel
    let close: () -> Void
    @State private var pane = "explanation"
    @State private var showSetupSteps = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BibleTheme.Space.page) {
                    if model.items.count > 1 {
                        Picker("表示する箇所", selection: $model.selectedIndex) { ForEach(Array(model.items.enumerated()), id: \.offset) { index, item in Text(item.passage.label).tag(index) } }.pickerStyle(.menu).disabled(model.loading || model.pendingRequest != nil)
                    }
                    Text(model.current?.passage.label ?? model.labels.first ?? "共有した箇所").bibleTextStyle(.heading)
                    if let passage = model.current?.passage {
                        Picker("表示", selection: $pane) { Text("解説").tag("explanation"); Text("人物").tag("person"); Text("地名").tag("place") }.pickerStyle(.segmented)
                        if pane != "explanation" { OfflineEntityPane(passage: passage, kind: pane, inlineDetails: true) }
                    }
                    if model.needsSetup {
                        Text("この画面で解説を開けません").bibleTextStyle(.heading)
                        Text(model.setupMessage).bibleTextStyle(.body)
                        Text("選んだ箇所はこの画面に残しています。必要なときは、下の手順でアプリの設定を確認できます。").bibleTextStyle(.body)
                        Button("準備の手順を見る") { showSetupSteps = true }.buttonStyle(.bordered)
                        if showSetupSteps {
                            Label("共有画面を閉じる", systemImage: "1.circle.fill")
                            Label("聖書コンパニオンの「YouVersionから解説を読む準備」を開く", systemImage: "2.circle.fill")
                            Label("問題が表示された項目だけ確認し、設定を保存する", systemImage: "3.circle.fill")
                            Label("YouVersionで同じ箇所を選び、もう一度共有する", systemImage: "4.circle.fill")
                            Button("共有画面を閉じる", action: close).buttonStyle(.borderedProminent)
                        }
                        if model.current?.passage != nil { Text("人物・地名の索引はこの画面でも確認できます。").bibleTextStyle(.caption) }
                    }
                    if model.shareParseFailed {
                        Text("共有から章節を読み取れませんでした。YouVersionで節と本文を選択し直し、共有し直してください。").bibleTextStyle(.body)
                        Button("共有画面を閉じる", action: close).buttonStyle(.borderedProminent)
                        DisclosureGroup("受け取った共有内容を端末内で確認") {
                            Text(model.sharedText.isEmpty ? "共有内容は受け取れませんでした。" : model.sharedText)
                                .bibleTextStyle(.caption)
                                .textSelection(.enabled)
                            if model.shareTextWasTruncated { Text("長さ制限のため末尾を省略しています。").bibleTextStyle(.caption) }
                        }
                    }
                    if let notice = model.storageNotice { Text(notice).bibleTextStyle(.caption).foregroundStyle(.secondary) }
                    if pane == "explanation", let answer = model.answer {
                        Text(answer.answer).bibleTextStyle(.body).textSelection(.enabled)
                        Text("AIによる解説 · 本文と出典を確かめてください").bibleTextStyle(.caption).foregroundStyle(.secondary)
                        DisclosureGroup("出典") { ForEach(Array(answer.citations.enumerated()), id: \.offset) { _, citation in Text(citation.title).bibleTextStyle(.caption) } }
                    }
                    if model.loading { ProgressView(model.items.isEmpty ? "箇所を確認しています" : "日本語の解説を作っています") }
                    if let error = model.error { Text(error).bibleTextStyle(.body) }
                    if model.canRetryExplanation && model.answer == nil && model.pendingRequest == nil {
                        Button("解説をもう一度確認") { Task { await model.explain() } }.buttonStyle(.borderedProminent).disabled(model.loading)
                    }
                    if model.pendingRequest != nil && !model.loading { Button("送信した回答を確認") { Task { await model.checkStatus() } }.buttonStyle(.borderedProminent) }
                    if model.canAsk && !model.needsSetup && !model.items.isEmpty && model.pendingRequest == nil {
                        TextField("気になったことを質問", text: $model.draft, axis: .vertical).lineLimit(2...5).bibleTextStyle(.body).disabled(model.loading)
                        Button("質問する") { Task { await model.sendQuestion() } }.buttonStyle(.borderedProminent).disabled(model.loading || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.draft.utf16.count > 2000)
                    }
                    if model.canRetryStart && !model.needsSetup && !model.loading { Button("共有した箇所をもう一度確認") { Task { await model.refresh() } }.buttonStyle(.borderedProminent) }
                }.padding(BibleTheme.Space.page).frame(maxWidth: .infinity, alignment: .leading)
            }.safeAreaInset(edge: .top) { if let passage = model.current?.passage { SharedScriptureHeader(passage: passage, translation: model.translation, text: model.sharedText) } }.bibleCanvas().navigationTitle("聖書コンパニオン").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("閉じる", action: close) } }
                .onChange(of: model.selectedIndex) { _, _ in Task { await model.explain() } }
        }
    }
}
