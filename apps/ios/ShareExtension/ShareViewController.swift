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
            do {
                var parts: [String] = []
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
                guard !text.isEmpty, text.utf16.count <= 20_000 else { model.error = "章節やURLを短く共有してください。"; model.loading = false; return }
                model.sharedText = text
                if let parsed = try? SharedImportParser.parse(text) { model.translation = parsed.translation; model.labels = parsed.ranges.map(\.label); model.items = parsed.ranges.enumerated().map { .init(conversationId: "local-\($0.offset)", passage: $0.element) } }
                do { try ShareInbox.enqueue(text) } catch { model.storageNotice = "アプリへの引き継ぎは利用できません。この画面で資料を確認できます。" }
                await model.refresh()
            } catch { model.error = "共有内容を読み取れませんでした。もう一度共有してください。"; model.loading = false }
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
    @Published var canAsk = false
    @Published var items: [Item] = []
    @Published var answers: [String: AnswerResult] = [:]
    @Published var selectedIndex = 0
    @Published var draft = ""
    @Published var pendingRequest: String?
    var sharedText = ""
    private let startRequest = UUID().uuidString
    private var client: APIClient?
    var current: Item? { items.indices.contains(selectedIndex) ? items[selectedIndex] : nil }
    var answer: AnswerResult? { current.flatMap { answers[$0.id] } }
    func refresh() async {
        guard !sharedText.isEmpty, client == nil else { return }
        loading = true; error = nil
        defer { loading = false }
        do {
            guard let access = try ShareInbox.aiAccess() else { needsSetup = true; return }
            guard let raw = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String, let base = URL(string: raw) else { error = "接続先を確認できません。アプリを更新してください。"; return }
            let transport = try APIClient(baseURL: base); await transport.setToken(access.token)
            let started: Started = try await transport.post("/share/start", body: ["requestId": startRequest, "sharedText": sharedText])
            guard started.ownerId == access.ownerID, !started.items.isEmpty else { throw NetworkFailure.invalidResponse }
            client = transport; items = started.items; needsSetup = false; canAsk = true
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
        loading = true; error = nil
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
        if case NetworkFailure.server(let status, let code) = failure, status == 401 || code.hasPrefix("share_access") { needsSetup = true; pendingRequest = nil; error = nil; return }
        if case NetworkFailure.server(_, let code) = failure, ["standard_explanation_pending", "standard_explanation_unavailable"].contains(code) { pendingRequest = nil }
        error = (failure as? NetworkFailure)?.userMessage ?? "接続できませんでした。共有した箇所は保持しています。"
    }
}
private struct SharedPreviewView: View {
    @ObservedObject var model: SharedPreviewModel
    let close: () -> Void
    @State private var pane = "explanation"
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
                        if pane != "explanation" { OfflineEntityPane(passage: passage, kind: pane) }
                    }
                    if model.needsSetup {
                        Text("初回の設定が必要です。").bibleTextStyle(.heading)
                        Label("この画面を閉じる", systemImage: "1.circle.fill")
                        Label("ホーム画面の聖書コンパニオンを開く", systemImage: "2.circle.fill")
                        Label("ログインして「共有画面のAIを有効にする」を押す", systemImage: "3.circle.fill")
                        Text("設定後、YouVersionからもう一度共有してください。人物・地名の索引はこの画面でも確認できます。").bibleTextStyle(.caption)
                    }
                    if pane == "explanation", let answer = model.answer {
                        Text(answer.answer).bibleTextStyle(.body).textSelection(.enabled)
                        Text("AIによる解説 · 本文と出典を確かめてください").bibleTextStyle(.caption).foregroundStyle(.secondary)
                        DisclosureGroup("出典") { ForEach(Array(answer.citations.enumerated()), id: \.offset) { _, citation in Text(citation.title).bibleTextStyle(.caption) } }
                    }
                    if model.loading { ProgressView(model.items.isEmpty ? "箇所を確認しています" : "日本語の解説を作っています") }
                    if let error = model.error { Text(error).bibleTextStyle(.body) }
                    if model.pendingRequest != nil && !model.loading { Button("送信した回答を確認") { Task { await model.checkStatus() } }.buttonStyle(.borderedProminent) }
                    if model.canAsk && !model.needsSetup && !model.items.isEmpty && model.pendingRequest == nil {
                        TextField("気になったことを質問", text: $model.draft, axis: .vertical).lineLimit(2...5).bibleTextStyle(.body).disabled(model.loading)
                        Button("質問する") { Task { await model.sendQuestion() } }.buttonStyle(.borderedProminent).disabled(model.loading || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.draft.utf16.count > 2000)
                    }
                    if model.items.isEmpty && !model.needsSetup && !model.loading { Button("もう一度開く") { Task { await model.refresh() } } }
                }.padding(BibleTheme.Space.page).frame(maxWidth: .infinity, alignment: .leading)
            }.safeAreaInset(edge: .top) { if let passage = model.current?.passage { SharedScriptureHeader(passage: passage, translation: model.translation, text: model.sharedText) } }.bibleCanvas().navigationTitle("聖書コンパニオン").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("閉じる", action: close) } }
                .onChange(of: model.selectedIndex) { _, _ in Task { await model.explain() } }
        }
    }
}
