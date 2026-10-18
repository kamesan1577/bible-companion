import SwiftUI
import UIKit
import CompanionCore

struct HistoryView: View {
    enum SectionChoice: Int, CaseIterable, Identifiable {
        case readings, conversations, comparisons
        var id: Int { rawValue }
        var title: String { switch self { case .readings: "読書"; case .conversations: "会話"; case .comparisons: "比較" } }
    }
    @EnvironmentObject private var store: AppStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var section: SectionChoice = .readings
    private var choices: [SectionChoice] { store.account?.canDebug == true ? SectionChoice.allCases : [.readings, .conversations] }
    var body: some View {
        VStack(spacing: BibleTheme.Space.sm) {
            Group {
                if typeSize.isAccessibilitySize { picker.pickerStyle(.menu) }
                else { picker.pickerStyle(.segmented) }
            }.padding(.horizontal, BibleTheme.Space.page)
            switch section {
            case .readings: LocalReadingHistoryList()
            case .conversations:
                if let owner = store.account { ConversationListView(ownerID: owner.id, client: store.client) }
                else { BibleStateView(title: "ログインしてください", message: "会話は自分のアカウントだけで確認できます。") }
            case .comparisons:
                if store.account?.canDebug == true { SavedComparisonListView(client: store.client) }
                else { BibleStateView(title: "開発用アカウント専用です", message: "このアカウントでは比較履歴を表示できません。") }
            }
        }
        .bibleCanvas().navigationTitle("履歴")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("追加", systemImage: "plus") { store.showImport = true } } }
    }
    private var picker: some View { Picker("履歴の種類", selection: $section) { ForEach(choices) { Text($0.title).tag($0) } } }
}

private struct LocalReadingHistoryList: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var visits: [LocalReadingVisit] = []
    @State private var message: String?
    var body: some View {
        List {
            Section("この端末で開いた箇所") {
                ForEach(visits) { value in
                    NavigationLink { UnifiedReadingView(passage: value.passage, translation: value.translation, sharedText: value.sharedText) } label: {
                        VStack(alignment: .leading) { Text(value.passage.label); Text(value.openedAt, format: .dateTime.month().day().hour().minute()).bibleTextStyle(.caption) }
                    }
                }
                if visits.isEmpty { Text(message ?? "本体や共有画面で開くと、ここに記録されます。") }
            }
            if store.account != nil { Section { NavigationLink("以前のクラウド読書履歴") { ImportedHistoryList() } } }
        }.scrollContentBackground(.hidden).bibleCanvas().task { refresh() }.refreshable { refresh() }
        .onChange(of: store.account?.id) { _, _ in refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
    }
    private func refresh() {
        do { visits = try ShareInbox.readingVisits(owner: store.account?.id); message = nil }
        catch { visits = []; message = "端末内の記録を確認できません。記録は削除していません。" }
    }
}

private struct ImportedHistoryList: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        List {
            if store.account == nil { BibleStateView(title: "ログインしてください", message: "自分の読書履歴を確認できます。", systemImage: BibleTheme.Symbol.history).listRowSeparator(.hidden) }
            else if store.historyLoading { ProgressView("履歴を確認しています") }
            else if let error = store.historyError { BibleStateView(title: "履歴を確認できません", message: error); Button("再読み込み") { Task { await store.refreshHistory() } } }
            else if store.historyChecked && store.history.isEmpty { BibleStateView(title: "履歴はまだありません", message: "YouVersionから開いた箇所がここに並びます。右上の「追加」からも書名・章・節を入力できます。", systemImage: BibleTheme.Symbol.history).listRowSeparator(.hidden) }
            else if !store.historyChecked { Text("保存した読書履歴を読み込めます。").bibleTextStyle(.caption); Button("履歴を確認") { Task { await store.refreshHistory() } } }
            ForEach(store.history) { item in
                Button { store.select(item) } label: {
                    VStack(alignment: .leading, spacing: BibleTheme.Space.sm) {
                        Text(item.title).bibleTextStyle(.body).bibleForeground(.textPrimary)
                        HStack { Text(item.translation ?? "訳名なし"); Text(Date(timeIntervalSince1970: item.createdAt), style: .date) }.bibleTextStyle(.caption).bibleForeground(.textSecondary)
                    }.padding(.vertical, BibleTheme.Space.sm)
                }
            }
            if store.canLoadMore { Button("以前の履歴を読み込む") { Task { await store.refreshHistory(loadMore: true) } } }
            if store.isOffline { Text("通信できません。端末に保存された読書履歴と、まだ読める参考説明を表示します。").bibleTextStyle(.caption) }
        }
        .scrollContentBackground(.hidden).bibleCanvas()
        .refreshable { await store.refreshHistory() }
    }
}
struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var provider = ExternalQuestionProvider.chatGPT
    @State private var showGuide = false
    @State private var showSignOut = false
    var body: some View {
        Form {
            Section("質問の送信先") { ExternalProviderPicker(provider: $provider) }
            Section("使い方") {
                Button("YouVersionから共有する手順") { showGuide = true }
                Text("解説・地図・人物・絵画は本体と共有画面で共通です。質問は選択した外部サービスで続けます。").bibleTextStyle(.caption)
            }
            Section("アカウント") {
                if let account = store.account {
                    LabeledContent("ログイン中", value: account.display_name)
                    Button("ログアウトする", role: .destructive) { showSignOut = true }.disabled(store.isTransitioning)
                } else {
                    Button(store.isAuthenticating ? "ログインしています" : "ログインする") { store.signIn() }.disabled(!store.endpointConfigured || store.isAuthenticating || store.isTransitioning || store.restoreNeedsRetry || store.localCleanupRequired)
                    Text("外部サービスでの質問に、このアプリへのログインは必要ありません。アカウントは以前のクラウド記録の確認に使います。").bibleTextStyle(.caption)
                    if store.isAuthenticating { Button("ログインをやめる") { store.cancelSignIn() } }
                }
                if store.isTransitioning { ProgressView("ログインを確認しています") }
                if let error = store.errorMessage { Text(error) }
                if store.restoreNeedsRetry { Button("保存したログインを確認し直す") { Task { await store.restore() } }.disabled(store.isTransitioning) }
            }
            if let owner = store.account { Section("以前の記録") {
                NavigationLink("保存した会話を読む") { ConversationListView(ownerID: owner.id, client: store.client) }
                NavigationLink("送信済みの質問の状態を確認") { PendingQuestionView(ownerID: owner.id, client: store.client) }
                NavigationLink("読書の記録を書き出す") { ExportView(ownerID: owner.id, client: store.client) }
            } }
            Section("保存と外部サービス") {
                Text("最近開いた箇所・共有した原文・質問の下書きは、端末内の保護された共有領域にアカウントごとに分けて保存します。アプリを再起動しても残ります。外部サービスの回答をこのアプリは取得しません。").bibleTextStyle(.body)
                Text("送信操作で原文と質問をクリップボードへコピーします。コピーはこの端末だけで使え、10分後に期限切れになります。ChatGPTへの質問付きURLはブラウザ履歴などに残る場合があります。外部サービスの利用条件・料金・保存設定は各サービスで確認してください。").bibleTextStyle(.body)
                Text("端末内の新しい履歴・下書きは、下のクラウド記録削除とは別に保持します。以前の質問・回答やクラウド記録は、画面の更新だけでは削除しません。外部サービスでの会話は各サービス側で管理してください。").bibleTextStyle(.body)
            }
            if let owner = store.account { Section("個人データ") {
                NavigationLink("以前のクラウド読書データを削除する") { PrivacyDeleteView(intent: DeletionIntent(ownerID: owner.id, sessionEpoch: store.sessionEpoch, kind: .readingData)) }
                NavigationLink("アカウントを削除する") { PrivacyDeleteView(intent: DeletionIntent(ownerID: owner.id, sessionEpoch: store.sessionEpoch, kind: .account)) }
            } }
        }.bibleCanvas().navigationTitle("設定")
        .sheet(isPresented: $showGuide) { FirstRunGuide() }
        .confirmationDialog("この端末からログアウトしますか？", isPresented: $showSignOut, titleVisibility: .visible) {
            Button("ログアウトする", role: .destructive) { Task { await store.signOut() } }
        } message: { Text("この端末のログインと、待っている共有内容を消します。アカウントに保存した読書履歴は消しません。") }
    }
}
