import SwiftUI
import CompanionCore

struct ConversationListView: View {
    let ownerID: String
    let client: APIClient
    @StateObject private var model: HistoryPageModel<ConversationSummary>
    init(ownerID: String, client: APIClient) { self.ownerID = ownerID; self.client = client; _model = StateObject(wrappedValue: HistoryPageModel(client: client, path: "/v1/conversations")) }
    var body: some View {
        List {
            if model.hasLoadedSuccessfully && model.items.isEmpty && !model.loading && model.errorMessage == nil { BibleStateView(title: "保存した会話はまだありません", message: "保存した質問と回答を、この画面で確認できます。") }
            ForEach(model.items) { conversation in
                NavigationLink {
                    ConversationHistoryView(ownerID: ownerID, client: client, id: conversation.id)
                } label: {
                    VStack(alignment: .leading, spacing: BibleTheme.Space.sm) {
                        Text(conversation.passage.label).bibleTextStyle(.body)
                        Text("\(conversation.messageCount)件 · \(conversation.spoilerAllowed ? "先の内容も含む" : "\(conversation.readingBoundary.end.label)まで")").bibleTextStyle(.caption).bibleForeground(.textSecondary)
                        Text(Date(timeIntervalSince1970: conversation.lastMessageAt ?? conversation.createdAt), style: .date).bibleTextStyle(.caption)
                    }
                }
            }
            if model.loading { ProgressView("会話を確認しています") }
            if let error = model.errorMessage { Text(error).bibleTextStyle(.body); Button("再読み込み") { Task { await model.load() } } }
            if model.nextCursor != nil { Button("以前の会話を読み込む") { Task { await model.load(more: true) } }.disabled(model.loading) }
        }
        .scrollContentBackground(.hidden).bibleCanvas()
        .task { await model.load() }.refreshable { await model.load() }.onDisappear { model.cancel() }
    }
}
struct ConversationHistoryView: View {
    struct ResumeContext: Identifiable { let conversation: Conversation; let item: ImportRecord; let index: Int; var id: String { conversation.id } }
    let ownerID: String
    let client: APIClient
    @StateObject private var model: ConversationHistoryModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var resume: ResumeContext?
    init(ownerID: String, client: APIClient, id: String) { self.ownerID = ownerID; self.client = client; _model = StateObject(wrappedValue: ConversationHistoryModel(id: id, client: client)) }
    var body: some View {
        ScrollView {
            BibleReadingColumn {
                if let conversation = model.window.conversation {
                    BibleSectionHeader(title: conversation.passage.label, subtitle: "保存した会話")
                    BibleScopeNotice(text: conversation.spoilerAllowed ? "この会話には、今読んでいる箇所以降の内容も含まれます" : "\((conversation.readingBoundary ?? conversation.passage).end.label)までの内容です。以降は含みません")
                    if model.window.nextCursor != nil { Button("以前のメッセージを読み込む") { Task { await model.load(older: true) } }.disabled(model.loading) }
                    if model.window.omittedNewerMessages { Text("表示できるメッセージは最大200件です。さらに新しい内容がある場合は「再読み込み」を押してください。").bibleTextStyle(.caption) }
                    LazyVStack(alignment: .leading, spacing: BibleTheme.Space.section) {
                        ForEach(model.window.messages.filter { !($0.role == "user" && $0.content["standardExplanation"].bool == true) }) { message in SavedMessageView(message: message) }
                    }
                    if model.window.messages.isEmpty { BibleStateView(title: "メッセージはまだありません", message: "この会話で質問を続けられます。") }
                }
                if model.loading { BibleLoadingView(title: "会話を確認しています", message: "資料の利用条件を確認しています。") }
                if let error = model.errorMessage { BibleStateView(title: "会話を確認できません", message: error, systemImage: BibleTheme.Symbol.error) }
            }
        }
        .bibleCanvas().navigationTitle("会話").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("再読み込み", systemImage: "arrow.clockwise") { Task { await model.load() } }.disabled(model.loading) } }
        .safeAreaInset(edge: .bottom) {
            if let conversation = model.window.conversation, let item = model.item, let index = conversation.resumeRangeIndex(in: item) {
                Button("この会話で質問を続ける") { resume = ResumeContext(conversation: conversation, item: item, index: index) }.buttonStyle(.glass).disabled(model.loading)
                    .padding(.horizontal, BibleTheme.Space.page).padding(.vertical, BibleTheme.Space.sm)
            }
        }
        .task { await model.load() }.onDisappear { if resume == nil { model.clear() } }
        .onChange(of: scenePhase) { _, phase in if phase == .background { model.clear() } else if phase == .active && resume == nil { Task { await model.load() } } }
        .sheet(item: $resume, onDismiss: { Task { await model.load() } }) { context in
            QuestionView(ownerID: ownerID, client: client, item: context.item, rangeIndex: context.index, target: context.conversation.passage, conversation: context.conversation)
        }
    }
}
private struct SavedMessageView: View {
    let message: ConversationMessage
    var body: some View {
        BibleReadingSurface {
            VStack(alignment: .leading, spacing: BibleTheme.Space.md) {
                BibleSectionHeader(title: message.role == "user" ? "あなたの質問" : message.content["standardExplanation"].bool == true ? "最初の解説" : message.visibleAnswer?.mode == "source-only" ? "選択した箇所の資料" : "回答", subtitle: Date(timeIntervalSince1970: message.createdAt).formatted(date: .abbreviated, time: .shortened))
                if message.isHidden {
                    Text("資料の利用条件や版が変わったため、この回答は現在表示できません。保存した記録自体は変更していません。").bibleTextStyle(.body)
                } else if let text = message.userText { Text(text).bibleTextStyle(.body).textSelection(.enabled) }
                else if let answer = message.visibleAnswer { StoredAnswerView(answer: answer) }
                else { Text("この形式のメッセージは表示できません。保存した内容は変更していません。").bibleTextStyle(.body) }
            }
        }
    }
}
struct StoredAnswerView: View {
    @EnvironmentObject private var store: AppStore
    let answer: AnswerResult
    var body: some View {
        VStack(alignment: .leading, spacing: BibleTheme.Space.md) {
            Text(answer.mode == "source-only" ? "参考資料です。AIの回答ではありません。" : "AIの回答です。本文と出典もあわせてお確かめください。").bibleTextStyle(.caption).bibleForeground(.textSecondary)
            Text(answer.answer).bibleTextStyle(.body).textSelection(.enabled)
            Text(answer.referenceSystem?.noticeJa ?? ReferenceSystem.fallbackNotice).bibleTextStyle(.caption).bibleForeground(.textSecondary)
            CitationList(citations: answer.citations)
            if store.account?.canDebug == true { DisclosureGroup("開発者専用：回答の詳細") { Text(answer.modelId).bibleTextStyle(.caption); Text(answer.mode).bibleTextStyle(.caption); AnswerBudgetNotice(policy: answer.budgetPolicy); ForEach(answer.warnings, id: \.self) { Text($0).bibleTextStyle(.caption) } }.bibleForeground(.danger) }
        }
    }
}
struct SavedComparisonListView: View {
    let client: APIClient
    @StateObject private var model: HistoryPageModel<SavedComparisonSummary>
    init(client: APIClient) { self.client = client; _model = StateObject(wrappedValue: HistoryPageModel(client: client, path: "/v1/developer/comparisons")) }
    var body: some View {
        List {
            if model.hasLoadedSuccessfully && model.items.isEmpty && !model.loading && model.errorMessage == nil { BibleStateView(title: "保存した比較はまだありません", message: "モデル比較で保存を選んだ記録がここに並びます。") }
            ForEach(model.items) { item in
                NavigationLink { SavedComparisonView(client: client, id: item.requestId) } label: {
                    VStack(alignment: .leading, spacing: BibleTheme.Space.sm) {
                        Text("\(item.trialCount)試行の比較").bibleTextStyle(.body)
                        Text(Date(timeIntervalSince1970: item.createdAt), style: .date).bibleTextStyle(.caption)
                        Text(ComparisonDisplay.status(item.status)).bibleTextStyle(.caption).bibleForeground(.textSecondary)
                    }
                }
            }
            if model.loading { ProgressView("比較履歴を確認しています") }
            if let error = model.errorMessage { Text(error).bibleTextStyle(.body); Button("再読み込み") { Task { await model.load() } } }
            if model.nextCursor != nil { Button("以前の比較を読み込む") { Task { await model.load(more: true) } }.disabled(model.loading) }
        }
        .scrollContentBackground(.hidden).bibleCanvas().task { await model.load() }.refreshable { await model.load() }.onDisappear { model.cancel() }
    }
}
struct SavedComparisonView: View {
    @StateObject private var model: SavedComparisonModel
    @Environment(\.scenePhase) private var scenePhase
    init(client: APIClient, id: String) { _model = StateObject(wrappedValue: SavedComparisonModel(id: id, client: client)) }
    var body: some View {
        ScrollView {
            BibleReadingColumn {
                if let state = model.state {
                    BibleSectionHeader(title: "保存した比較", subtitle: "\(state.completedCount) / \(state.trialCount)試行 · \(ComparisonDisplay.status(state.status))")
                    if state.results?["hidden"].bool == true { Text("資料の利用条件や版が変わったため、保存した比較を現在表示できません。比較記録は変更していません。").bibleTextStyle(.body) }
                    ForEach(Array((state.results?["questions"].array ?? []).enumerated()), id: \.offset) { index, question in
                        DisclosureGroup("質問 \(index + 1)") { Text(question["question"].string ?? "質問を表示できません").bibleTextStyle(.body) }
                    }
                    ForEach(Array((state.results?["results"].array ?? []).enumerated()), id: \.offset) { index, trial in
                        BibleReadingSurface {
                            VStack(alignment: .leading, spacing: BibleTheme.Space.md) {
                                BibleSectionHeader(title: "試行 \(index + 1)")
                                if trial["result"]["hidden"].bool == true { Text("資料の利用条件や版が変わったため、この回答は現在表示できません。回答記録は変更していません。").bibleTextStyle(.body) }
                                else if let data = try? JSONEncoder().encode(trial["result"]), let answer = try? JSONDecoder().decode(AnswerResult.self, from: data) { StoredAnswerView(answer: answer) }
                                else { Text("回答本文は保存されていないか、現在表示できません。保存状態を変える操作ではありません。").bibleTextStyle(.body) }
                            }
                        }
                    }
                }
                if model.loading { BibleLoadingView(title: "比較を確認しています", message: "現在の出典の表示条件を確認しています。") }
                if let error = model.errorMessage { BibleStateView(title: "比較を確認できません", message: error, systemImage: BibleTheme.Symbol.error) }
            }
        }
        .bibleCanvas().navigationTitle("比較の記録").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("再読み込み", systemImage: "arrow.clockwise") { Task { await model.load() } } } }
        .task { await model.load() }.onDisappear { model.clear() }
        .onChange(of: scenePhase) { _, phase in if phase == .background { model.clear() } else if phase == .active { Task { await model.load() } } }
    }
}
