import SwiftUI
import CompanionCore
import CryptoKit
import UIKit

@MainActor final class SharedPreviewModel: ObservableObject {
    struct Started: Decodable, Sendable { let ownerId: String; let importId: String; let items: [Item] }
    struct Item: Codable, Sendable, Identifiable { let conversationId: String; let passage: Passage; var id: String { conversationId } }
#if DEBUG && targetEnvironment(simulator)
    var probeChatGPTOpen: (() -> Void)?
    var probeBrowserOpen: (() -> Void)?
    @Published var chatGPTOpenProbeResult = ""
#endif
    @Published var loading = false
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
    @Published var transcripts: [String: ChatTranscript] = [:]
    @Published var status = ""
    @Published var preview = ""
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var pendingStandard = false
    private var pendingQuestion = ""
    private var pendingItemID: String?
    private var lastSubmissionID: String?
    private var accessOwner: String?
    private var accessToken: String?
    var entries: [ChatEntry] { current.flatMap { transcripts[$0.id]?.entries } ?? [] }
    var canSend: Bool { !shareParseFailed && current != nil && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.utf16.count <= 2000 && queued.count < 10 }
    @Published var selectedIndex = 0
    @Published var draft = "" { didSet { persist() } }
    struct Queued: Codable, Identifiable { let id: String; let question: String; let index: Int }
    @Published private(set) var queued: [Queued] = []
    @Published private(set) var aiRequests = 0
    private var draining = false
    private var snapshotURL: URL?
    private struct Snapshot: Codable { let saved: Date; let selectedIndex: Int; let start: String; let draft: String; let items: [Item]; let transcripts: [String: ChatTranscript]; let answers: [String: AnswerResult]; let queued: [Queued]; let pending: String?; let pendingItem: String?; let question: String; let standard: Bool; let lastSubmission: String? }
    @Published var pendingRequest: String?
    @Published var shareParseFailed = false
    @Published var shareTextWasTruncated = false
    var sharedText = ""
    private var startRequest = UUID().uuidString
    private var client: APIClient?
    var current: Item? { items.indices.contains(selectedIndex) ? items[selectedIndex] : nil }
    var answer: AnswerResult? { current.flatMap { answers[$0.id] } }
    func refresh() async {
        guard !sharedText.isEmpty, client == nil else { return }
        if accessOwner != nil && !checkOwner() { return }
        let active = UUID(); generation = active
        loading = true; error = nil; canRetryStart = false
        defer { if generation == active { loading = false } }
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
            guard generation == active else { return }
            guard started.ownerId == access.ownerID, !started.items.isEmpty else { throw NetworkFailure.invalidResponse }
            accessOwner = access.ownerID; accessToken = access.token
            client = transport; items = started.items;
            if let directory = snapshotURL?.deletingLastPathComponent().deletingLastPathComponent() {
                let key = SHA256.hash(data: Data((access.ownerID + access.token + sharedText).utf8)).map { String(format: "%02x", $0) }.joined()
                let destination = directory.appendingPathComponent("ShareChats").appendingPathComponent(key + ".json")
                if let previous = snapshotURL, previous != destination { try? FileManager.default.removeItem(at: previous) }
                snapshotURL = destination
            }
            needsSetup = false; shareParseFailed = false; canAsk = true
            loading = false
            persist()
        } catch { show(error) }
    }
    func explain() async {
        guard answer == nil else { return }
        await send("この箇所の出来事と意味を、初めて読む人にも分かる日本語で短く説明してください。", standard: true)
    }
    /// Called after local parsing. No network or inference on opening, selection or tab changes.
    func prepare() {
        loading = false
        canAsk = !shareParseFailed
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        if let access = try? ShareInbox.verifiedAIAccess() {
            accessOwner = access.ownerID; accessToken = access.token
            restoreSnapshot(directory: directory, owner: access.ownerID, token: access.token)
        } else {
            // Signed-out drafts are never restored into an authenticated account's conversation.
            do { let owner = try ShareInbox.localDraftOwner(); restoreSnapshot(directory: directory, owner: owner ?? "signed-out", token: "draft-only") }
            catch { storageNotice = "下書きの保存先を確認できません。入力はこの画面に残します。" }
        }
    }
    private func restoreSnapshot(directory: URL, owner: String, token: String) {
        let key = SHA256.hash(data: Data((owner + token + sharedText).utf8)).map { String(format: "%02x", $0) }.joined()
        let folder = directory.appendingPathComponent("ShareChats", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            var writable = folder; try writable.setResourceValues(values)
            snapshotURL = folder.appendingPathComponent(key + ".json")
            if let data = try? Data(contentsOf: snapshotURL!), data.count <= 1_000_000,
               let saved = try? JSONDecoder().decode(Snapshot.self, from: data), Date().timeIntervalSince(saved.saved) < 86400 {
                startRequest = saved.start; selectedIndex = saved.selectedIndex; items = saved.items; transcripts = saved.transcripts; answers = saved.answers
                queued = saved.queued; pendingRequest = saved.pending; pendingItemID = saved.pendingItem
                pendingQuestion = saved.question; pendingStandard = saved.standard; lastSubmissionID = saved.lastSubmission; draft = saved.draft
            }
            // Expired, revoked and unrelated sessions never become visible in this share.
            for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) {
                if let date = try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, Date().timeIntervalSince(date) >= 86400 { try? FileManager.default.removeItem(at: file) }
            }
        } catch { storageNotice = "会話を端末に保存できません。この画面を閉じると履歴や下書きが失われる場合があります。" }
    }
    private func persist() {
        guard let snapshotURL else { return }
        let value = Snapshot(saved: Date(), selectedIndex: selectedIndex, start: startRequest, draft: draft, items: items, transcripts: transcripts, answers: answers, queued: queued, pending: pendingRequest, pendingItem: pendingItemID, question: pendingQuestion, standard: pendingStandard, lastSubmission: lastSubmissionID)
        do { let data = try JSONEncoder().encode(value); guard data.count <= 1_000_000 else { return }; try data.write(to: snapshotURL, options: [.atomic, .completeFileProtection]) }
        catch { storageNotice = "下書きと会話を保存できませんでした。入力はこの画面に残しています。" }
    }
    func sendQuestion() async {
        guard canSend else { return }
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        queued.append(Queued(id: UUID().uuidString, question: question, index: selectedIndex))
        draft = ""; persist()
        await drain()
    }
    private func drain() async {
        guard !draining else { return }
        draining = true
        defer { draining = false; persist() }
        if client == nil { await refresh() }
        guard client != nil, !needsSetup, pendingRequest == nil else { return }
        while let next = queued.first, !Task.isCancelled {
            guard items.indices.contains(next.index) else { error = "質問する箇所を確認できません。送信待ちの質問は残しています。"; break }
            selectedIndex = next.index
            if pendingQuestion == next.question, let itemID = pendingItemID, let lastSubmissionID { transcripts[itemID]?.discardUnanswered(id: lastSubmissionID) }
            await send(next.question)
            if pendingRequest != nil || error != nil || needsSetup { break }
            queued.removeFirst(); persist()
        }
    }
    func removeQueued(_ id: String) { queued.removeAll { $0.id == id }; persist() }
    private func send(_ question: String, standard: Bool = false) async {
        guard checkOwner(), let client, let item = current, !loading, pendingRequest == nil else { return }
        loading = true; error = nil; canRetryExplanation = false; preview = ""; status = AnswerProgress.preparing.label
        let active = UUID(); generation = active
        defer { if generation == active { loading = false; preview = "" } }
        let request = UUID().uuidString; pendingRequest = request; lastSubmissionID = request
        pendingItemID = item.id; pendingStandard = standard; pendingQuestion = question
        transcripts[item.id, default: ChatTranscript()].submit(id: request, question: question, standard: standard)
        aiRequests += 1
        persist()
        struct Input: Encodable, Sendable { let requestId: String; let question: String; let answerMode = "grounded-generation" }
        do {
            let update: @Sendable (AnswerUpdate) -> Void = { [weak self] update in
                Task { @MainActor in
                    guard let self, self.generation == active, self.loading, self.checkOwner() else { return }
                    switch update { case .progress(let stage): self.status = stage.label; case .preview(let text): self.preview = text; self.status = AnswerProgress.receiving.label }
                }
            }
            let result: RequestResult
            if standard { result = try await client.postAnswer("/share/conversations/\(item.id)/explanation", body: ["requestId": request], requestID: request, update: update) }
            else { result = try await client.postAnswer("/share/conversations/\(item.id)/questions", body: Input(requestId: request, question: question), requestID: request, update: update) }
            guard generation == active, checkOwner() else { return }
            guard result.status == "complete", let answer = result.result else { throw NetworkFailure.invalidResponse }
            if standard { answers[item.id] = answer }
            transcripts[item.id, default: ChatTranscript()].complete(id: request, answer: answer, standard: standard)
            pendingRequest = nil
            persist()
        } catch { if generation == active { show(error); persist() } }
    }
    func checkStatus() async {
        if client == nil { await refresh() }
        guard checkOwner(), let client, let request = pendingRequest, let itemID = pendingItemID, !loading else { return }
        loading = true; error = nil; defer { loading = false }
        do {
            let result: RequestResult = try await client.get("/share/requests/\(request)")
            guard checkOwner() else { return }
            if result.status == "complete", let answer = result.result {
                if pendingStandard { answers[itemID] = answer }
                transcripts[itemID, default: ChatTranscript()].complete(id: request, answer: answer, standard: pendingStandard); pendingRequest = nil; if queued.first?.question == pendingQuestion { queued.removeFirst() }; persist()
            }
            else if ["failed", "cancelled"].contains(result.status) { pendingRequest = nil; error = "前の処理は終了しました。もう一度質問できます。" }
            else { error = "回答を準備しています。少ししてから確認してください。" }
        } catch { show(error) }
    }
    func startQuestion() { guard canSend else { return }; let question = draft.trimmingCharacters(in: .whitespacesAndNewlines); queued.append(Queued(id: UUID().uuidString, question: question, index: selectedIndex)); draft = ""; persist(); if !draining { task = Task { await drain() } } }
    func resumeQueue() { guard !loading, !draining else { return }; task = Task { await drain() } }
    func cancel() {
        generation = UUID(); task?.cancel(); task = nil; loading = false; preview = ""
        guard let client, let pendingRequest else { return }
        task = Task {
            do { let _: JSONValue = try await client.delete("/share/requests/\(pendingRequest)"); if self.pendingRequest == pendingRequest { self.pendingRequest = nil; persist(); error = "中止しました。利用量が発生している場合があります。" } }
            catch { self.error = "待つのをやめました。再送前に送信した回答の状態を確認してください。" }
        }
    }
    func retry() {
        guard pendingRequest == nil, !loading, !pendingQuestion.isEmpty else { return }
        if let itemID = pendingItemID, let lastSubmissionID { transcripts[itemID]?.discardUnanswered(id: lastSubmissionID) }
        error = nil
        if !queued.isEmpty { resumeQueue() }
        else { let question = pendingQuestion; let standard = pendingStandard; task = Task { await send(question, standard: standard) } }
    }

#if DEBUG
    private var isQA = false
    func configureQA(client: APIClient, initial: AnswerResult? = nil, restore: Bool = false) {
        self.client = client; isQA = true; loading = false; canAsk = true; storageNotice = nil
        if items.isEmpty { items = [Item(conversationId: "00000000-0000-4000-8000-000000000123", passage: Passage(book: "ACT", start: Verse(chapter: 24, verse: 23), end: Verse(chapter: 24, verse: 24)))] }
        if let initial { answers[items[0].id] = initial }
        if restore, let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first { restoreSnapshot(directory: directory, owner: "fixture-owner", token: "fixture-session") }
    }
#endif
    private func checkOwner() -> Bool {
#if DEBUG
        if isQA { return true }
#endif
        guard let access = try? ShareInbox.verifiedAIAccess(), access.ownerID == accessOwner, access.token == accessToken else {
            generation = UUID(); task?.cancel(); snapshotURL = nil; answers = [:]; transcripts = [:]; queued = []; preview = ""; draft = ""; client = nil; loading = false; canAsk = false; needsSetup = true
            setupMessage = "ログイン状態または共有設定が変わりました。画面を閉じて共有し直してください。"; return false
        }
        return true
    }
    func revalidateAccess() { if accessOwner != nil { _ = checkOwner() } }
    func close() { persist(); generation = UUID(); task?.cancel(); task = nil; preview = "" }
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
struct SharedPreviewView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var model: SharedPreviewModel
    let close: () -> Void
    @State private var pane = "explanation"
    @State private var showSetupSteps = false
    @State private var showChatGPT = (try? SharePresentationPreferences.isChatGPTVisible()) ?? true
    private struct ChatGPTPreview: Identifiable { let id = UUID(); let prompt: String?; let error: String? }
    @State private var chatGPTPreview: ChatGPTPreview?
    @FocusState private var composerFocused: Bool
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: BibleTheme.Space.page) {
#if DEBUG
                    Text("AI requests: \(model.aiRequests)").bibleTextStyle(.caption).accessibilityIdentifier("share-ai-request-count")
#if targetEnvironment(simulator)
                    if let probe = model.probeChatGPTOpen { Button("QA: ChatGPT open probe", action: probe) }
                    if let probe = model.probeBrowserOpen { Button("QA: browser control probe", action: probe) }
                    Text(model.chatGPTOpenProbeResult).accessibilityIdentifier("chatgpt-open-probe-result")
#endif
#endif
                    if model.items.count > 1 {
                        Picker("表示する箇所", selection: $model.selectedIndex) { ForEach(Array(model.items.enumerated()), id: \.offset) { index, item in Text(item.passage.label).tag(index) } }.pickerStyle(.menu).disabled(model.loading || model.pendingRequest != nil)
                    }
                    Text(model.current?.passage.label ?? model.labels.first ?? "共有した箇所").bibleTextStyle(.heading)
                    if let passage = model.current?.passage {
                        Picker("表示", selection: $pane) { Text("解説").tag("explanation"); Text("人物").tag("person"); Text("地名").tag("place") }.pickerStyle(.segmented)
                        if pane != "explanation" { OfflineEntityPane(passage: passage, kind: pane, inlineDetails: true) }
                    }
                    if model.needsSetup {
                        Text("質問を送るには準備が必要です").bibleTextStyle(.heading)
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
                        Text("最初の解説").bibleTextStyle(.heading)
                        Text(answer.answer).bibleTextStyle(.body).textSelection(.enabled)
                        DisclosureGroup("出典") { ForEach(Array(answer.citations.enumerated()), id: \.offset) { _, citation in Text(citation.title).bibleTextStyle(.caption) } }
                    }
                    if pane == "explanation" {
                        if model.entries.isEmpty && !model.loading { Text("気になったことを、そのまま質問できます。").bibleTextStyle(.body) }
                        ChatMessagesView(entries: model.entries.filter { !$0.standard })
                        if model.loading { ChatWaitingView(status: model.status, preview: model.preview) }
                    }
                    if model.draft.utf16.count > 2000 { Text("質問は2000文字以内にしてください。下書きは残しています。").bibleTextStyle(.caption) }
                    if model.queued.count >= 10 { Text("順番待ちは10件までです。回答を待つか、不要な質問を取り消してください。").bibleTextStyle(.caption) }
                    ForEach(model.queued) { question in
                        HStack { Text("送信待ち: " + question.question).bibleTextStyle(.caption); Button("取り消す") { model.removeQueued(question.id) }.disabled(model.loading && model.queued.first?.id == question.id) }
                    }
                    if !model.queued.isEmpty && !model.loading && model.pendingRequest == nil { Button("待っている質問を送る") { model.resumeQueue() } }
                    if let error = model.error { Text(error).bibleTextStyle(.body) }
                    if model.canRetryExplanation && model.answer == nil && model.pendingRequest == nil {
                        Button("解説をもう一度確認") { Task { await model.explain() } }.buttonStyle(.borderedProminent).disabled(model.loading)
                    }
                    if model.pendingRequest != nil && !model.loading { Button("送信した回答を確認") { Task { await model.checkStatus() } }.buttonStyle(.borderedProminent) }
                    if model.error != nil && model.pendingRequest == nil && !model.loading && !model.canRetryExplanation { Button("同じ質問をもう一度送る") { model.retry() } }
                    Color.clear.frame(height: 1).id("chat-bottom")
                    if model.canRetryStart && !model.needsSetup && !model.loading { Button("共有した箇所をもう一度確認") { Task { await model.refresh() } }.buttonStyle(.borderedProminent) }
                }.padding(BibleTheme.Space.page).frame(maxWidth: .infinity, alignment: .leading)
            }.scrollDismissesKeyboard(.interactively)
                .onChange(of: model.pendingRequest) { _, value in if value != nil { withAnimation { proxy.scrollTo("chat-bottom", anchor: .bottom) } } }
                .onChange(of: composerFocused) { _, focused in if focused { withAnimation { proxy.scrollTo("chat-bottom", anchor: .bottom) } } }
                .overlay(alignment: .bottomTrailing) { if !model.entries.isEmpty { Button { withAnimation { proxy.scrollTo("chat-bottom", anchor: .bottom) } } label: { Image(systemName: "arrow.down.circle.fill").bibleTextStyle(.heading).padding() }.accessibilityLabel("最新のメッセージへ") } }
            }.safeAreaInset(edge: .bottom) {
                if !model.shareParseFailed {
                    HStack(alignment: .bottom) {
                        TextField("気になったことを質問", text: $model.draft, axis: .vertical).accessibilityIdentifier("share-question-draft").lineLimit(1...4).focused($composerFocused).bibleTextStyle(.body).frame(maxWidth: .infinity, maxHeight: 120).clipped().submitLabel(.send).onSubmit { model.startQuestion() }
                        if model.loading { Button { model.cancel() } label: { ChatComposerIcon(systemName: "stop.circle") }.accessibilityLabel("回答の準備をやめる") }
                        if showChatGPT {
                            Button {
                                do {
                                    guard let passage = model.current?.passage else { return }
                                    let prompt = try ChatGPTCopyPrompt.make(question: model.draft, passage: passage, translation: model.translation, sharedText: model.sharedText)
                                    chatGPTPreview = ChatGPTPreview(prompt: prompt, error: nil)
                                } catch { chatGPTPreview = ChatGPTPreview(prompt: nil, error: "質問と共有本文を確認してください。質問は2,000文字、共有文は20,000文字までです。") }
                            } label: { ChatGPTCopyComposerLabel() }
                            .accessibilityLabel("ChatGPT用の本文と質問を確認").accessibilityIdentifier("chatgpt-copy-preview")
                            .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.current == nil)
                        }
                        Button { pane = "explanation"; model.startQuestion() } label: { ChatComposerIcon(systemName: "arrow.up.circle.fill") }.accessibilityLabel("質問を送る").disabled(!model.canSend)
                    }.padding(BibleTheme.Space.md).bibleCanvas()
                }
            }.safeAreaInset(edge: .top) { if let passage = model.current?.passage { SharedScriptureHeader(passage: passage, translation: model.translation, text: model.sharedText, compact: composerFocused) } }.bibleCanvas().navigationTitle("聖書コンパニオン").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarLeading) { if composerFocused { Button { composerFocused = false } label: { Image(systemName: "keyboard.chevron.compact.down") }.accessibilityLabel("キーボードを閉じる") } }; ToolbarItem(placement: .topBarTrailing) { Button("閉じる", action: close) } }
                .sheet(item: $chatGPTPreview) { preview in
                    NavigationStack {
                        ScrollView { VStack(alignment: .leading, spacing: BibleTheme.Space.page) {
                            Text("コピー後、ChatGPTを開いて貼り付けてください。質問付きで直接開く機能には対応していません。")
                            Text("コピーする内容は以下だけです。会話履歴やアカウント情報は含みません。")
                            if let error = preview.error { Text(error) }
                            else if let chatGPTPrompt = preview.prompt {
                                Text(chatGPTPrompt).textSelection(.enabled).accessibilityIdentifier("chatgpt-copy-content")
                                Button("本文と質問をコピー") {
                                    UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: chatGPTPrompt]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(600)])
                                    chatGPTPreview = nil
                                }.accessibilityIdentifier("chatgpt-copy-confirm")
                            }
                        }.padding() }.navigationTitle("ChatGPT用にコピー")
                        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { chatGPTPreview = nil } } }
                    }
                }
                .onDisappear { model.close() }
                .onChange(of: scenePhase) { _, phase in if phase == .active { model.revalidateAccess(); showChatGPT = (try? SharePresentationPreferences.isChatGPTVisible()) ?? showChatGPT } }

        }
    }
}
