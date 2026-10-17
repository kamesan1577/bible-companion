import SwiftUI
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
            case .readings: ImportedHistoryList()
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
    @State private var showGuide = false
    @State private var prepareAfterGuide = false
    @State private var showSignOut = false
    @State private var notice: String?
    @State private var showChatGPT = (try? SharePresentationPreferences.isChatGPTVisible()) ?? true
    @State private var presentationError: String?
    var body: some View {
        Form {
            Section("YouVersionから解説を読む") {
                Button("質問する準備を確認") { store.showAISetup = true }
                Text("初回のログインとAI利用の確認をここで行えます。読書の途中でも開けます。").bibleTextStyle(.caption)
                Button("共有の手順を見る", systemImage: "questionmark.circle") { showGuide = true }
            }
            Section("共有画面の表示") {
                Toggle("ChatGPTボタンを表示", isOn: Binding(get: { showChatGPT }, set: { value in
                    do { try SharePresentationPreferences.setChatGPTVisible(value); showChatGPT = value; presentationError = nil }
                    catch { presentationError = "表示設定を保存できませんでした。もう一度お試しください。" }
                })).accessibilityIdentifier("chatgpt-visibility")
                Text("共有した本文と質問を確認してコピーするボタンです。ChatGPTを開いて貼り付けてください。自動送信はしません。").bibleTextStyle(.caption)
                if let presentationError { Text(presentationError) }
            }
            Section("アカウント") {
                if let account = store.account {
                    LabeledContent("ログイン中", value: account.display_name)
                    Button("ログアウトする", role: .destructive) { showSignOut = true }.disabled(store.isTransitioning)
                } else {
                    Button(store.isAuthenticating ? "ログインしています" : "ログインする") { store.signIn() }.disabled(!store.endpointConfigured || store.isAuthenticating || store.isTransitioning || store.restoreNeedsRetry || store.localCleanupRequired)
                    Text("初めての方も、このボタンからiPhoneの案内に従って登録できます。").bibleTextStyle(.caption)
                    if store.isAuthenticating { Button("ログインをやめる") { store.cancelSignIn() } }
                }
                if store.isTransitioning { ProgressView("ログインを確認しています") }
                if let error = store.errorMessage { Text(error).bibleTextStyle(.body) }
                if !store.endpointConfigured { Text("アプリの接続設定に問題があります。最新版に更新して、もう一度お試しください。").bibleTextStyle(.caption) }
                DisclosureGroup("ログイン方法と、ログインできないとき") {
                    Text("パスキーを使い、Face IDなどiPhoneの画面の案内に従ってログインします。パスキーをすべて失った場合、このアプリからはアカウントを復旧できません。iPhoneで使っているパスワード管理アプリに、パスキーが残っているか確認してください。").bibleTextStyle(.caption)
                }
            }
            if store.restoreNeedsRetry { Section("保存したログインを開けません") {
                Text("iPhoneのロックを解除してから、もう一度確認してください。").bibleTextStyle(.body)
                Button("ログインを確認し直す") { Task { await store.restore() } }.disabled(store.isTransitioning)
                Button("この端末のログインを消す", role: .destructive) { showSignOut = true }.disabled(store.isTransitioning)
            } }
            if store.localCleanupRequired { Section("端末内データ") { Text("前のログインのデータを消し終えるまで、新しいログインはできません。"); Button("端末内データの削除をやり直す", role: .destructive) { store.retryLocalCleanup() } } }
            if store.exportCleanupRequired { Section("書き出しの一時ファイル") { Button("一時ファイルの削除をやり直す", role: .destructive) { store.retryExportCleanup() } } }
            Section("AI解説と質問") {
                Text("AIは間違えることがあります。聖書本文や出典もあわせてお確かめください。").bibleTextStyle(.body)
                Button("送る情報を確認してAIを使う") { store.showAISetup = true }
                if let policy = store.aiPolicy {
                    LabeledContent("AIへの送信", value: policy.workersAiConsent ? "同意しています" : "同意していません")
                    if policy.workersAiConsent { Button("AIへの送信をやめる") { setConsent(false) }.disabled(store.isConsentUpdating) }
                }
                Text("この設定をやめても、アプリに入っている聖書の説明・人物・地名は読めます。").bibleTextStyle(.caption)
                if let notice { Text(notice).bibleTextStyle(.body) }
            }
            Section("今日の無料枠") {
                if let usage = store.usage {
                    let used = usage.budgetUnits.consumed + usage.budgetUnits.reserved
                    ProgressView(value: min(used / max(usage.limit, 1), 1))
                    LabeledContent("残りの目安", value: "約\(Int(max(0, 1 - used / max(usage.limit, 1)) * 100))％")
                    LabeledContent("次に使えるようになる日時") { Text(Date(timeIntervalSince1970: usage.resetAt), format: .dateTime.month().day().hour().minute()) }
                    Text("回答の長さなどで使う量が変わります。作成中の回答の分も含めた目安です。使い切った場合は、回復するまでAI回答を利用できません。").bibleTextStyle(.caption)
                    if store.account?.canDebug == true {
                        DisclosureGroup { Text("消費 \(usage.budgetUnits.consumed.formatted()) / 予約 \(usage.budgetUnits.reserved.formatted()) / 上限 \(usage.limit.formatted())") } label: { Label("開発者専用：利用枠の計算", systemImage: "ladybug.fill") }.bibleForeground(.danger)
                    }
                } else { Text(store.account == nil ? "ログインすると、残っている無料枠を確認できます。" : "「残りの無料枠を確認する」を押してください。通信できないときは表示できません。").bibleTextStyle(.caption) }
                Button("残りの無料枠を確認する") { Task { await store.loadUsage() } }.disabled(store.account == nil)
            }
            if let notice = store.shareNotice { Section("YouVersionから受け取った箇所") { Text(notice); Button("受け取った箇所を開き直す") { store.refreshInbox() } } }
            if let owner = store.account { Section("自分の記録") {
                NavigationLink("返事を待っている質問を確認する") { PendingQuestionView(ownerID: owner.id, client: store.client) }
                NavigationLink("読書の記録を書き出す") { ExportView(ownerID: owner.id, client: store.client) }
            } }
            Section { DisclosureGroup("表示・保存・削除について") {
                Text("文字の大きさ、明るさ、動きはiPhoneの設定に合わせます。").bibleTextStyle(.body)
                Text("人物と地名はアプリに入っています。絵画の画像は、利用できることを確認してから端末に保存します。読んだ箇所の履歴はアカウントごとに分けます。").bibleTextStyle(.body)
                Text("取得した参考説明の一部は最長24時間、通信せずに読めるよう保存します。接続時に版と利用条件を確認し直します。共有した聖書本文、参考説明の全文、AIの回答は、端末には永続保存しません。送った質問は二重送信を防ぐため、結果を確認するまで端末内に保護して置きます。").bibleTextStyle(.body)
                Text("質問と回答はアカウントの履歴としてサービス側に保存されます。開発者用の比較結果も、保存を選んだものは残ります。下の「個人データ」から削除できます。事業者のバックアップから消える時期は決まっていません。").bibleTextStyle(.body)
            } }
            if let owner = store.account { Section("個人データ") {
                NavigationLink("読書データをすべて削除する") { PrivacyDeleteView(intent: DeletionIntent(ownerID: owner.id, sessionEpoch: store.sessionEpoch, kind: .readingData)) }
                NavigationLink("アカウントを削除する") { PrivacyDeleteView(intent: DeletionIntent(ownerID: owner.id, sessionEpoch: store.sessionEpoch, kind: .account)) }
            } }
            if let owner = store.account, owner.canDebug == true { Section("開発者専用") { NavigationLink("モデル・接続・比較を確認する") { DeveloperView(ownerID: owner.id, client: store.client) } }.bibleForeground(.danger) }
        }
        .bibleCanvas().navigationTitle("設定")
        .sheet(isPresented: $showGuide, onDismiss: { if prepareAfterGuide { prepareAfterGuide = false; store.showAISetup = true } }) { FirstRunGuide(onPrepare: { prepareAfterGuide = true; showGuide = false }) }
        .confirmationDialog("この端末からログアウトしますか？", isPresented: $showSignOut, titleVisibility: .visible) {
            Button("ログアウトする", role: .destructive) { Task { await store.signOut() } }
        } message: { Text("この端末のログインと、待っている共有内容を消します。アカウントに保存した読書履歴は消しません。") }
    }
    private func setConsent(_ enabled: Bool) {
        let epoch = store.sessionEpoch
        Task {
            do { try await store.consent(enabled, expectedEpoch: epoch); guard store.sessionEpoch == epoch else { return }; notice = enabled ? "AIを使えるようになりました。" : "AIへの送信をやめました。保存された聖書の説明は引き続き読めます。" }
            catch { if store.sessionEpoch == epoch { store.handle(error) } }
        }
    }
}
