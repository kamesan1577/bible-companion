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
            else if store.historyChecked && store.history.isEmpty { BibleStateView(title: "履歴はまだありません", message: "取り込んだ章節がここに並びます。", systemImage: BibleTheme.Symbol.history).listRowSeparator(.hidden) }
            else if !store.historyChecked { Text("サーバーの履歴は未確認です。").bibleTextStyle(.caption); Button("履歴を確認") { Task { await store.refreshHistory() } } }
            ForEach(store.history) { item in
                Button { store.select(item) } label: {
                    VStack(alignment: .leading, spacing: BibleTheme.Space.sm) {
                        Text(item.title).bibleTextStyle(.body).bibleForeground(.textPrimary)
                        HStack { Text(item.translation ?? "訳は未確認"); Text(Date(timeIntervalSince1970: item.createdAt), style: .date) }.bibleTextStyle(.caption).bibleForeground(.textSecondary)
                    }.padding(.vertical, BibleTheme.Space.sm)
                }
            }
            if store.canLoadMore { Button("以前の履歴を読み込む") { Task { await store.refreshHistory(loadMore: true) } } }
            if store.isOffline { Text("オフライン：保存済みの章節と、有効期限内の公開資料の概要を確認できます。").bibleTextStyle(.caption) }
        }
        .scrollContentBackground(.hidden).bibleCanvas()
        .refreshable { await store.refreshHistory() }
    }
}
struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showGuide = false
    @State private var showSignOut = false
    @State private var showAIConsent = false
    @State private var groundedConsentIntent: GroundedConsentIntent?
    @State private var notice: String?
    var body: some View {
        Form {
            Section { Button("使い方を見る", systemImage: "questionmark.circle") { showGuide = true } }
            Section("アカウント") {
                if let account = store.account {
                    LabeledContent("ログイン", value: account.display_name)
                    Button("ログアウト", role: .destructive) { showSignOut = true }.disabled(store.isTransitioning)
                    if store.isTransitioning { ProgressView("アカウントを確認しています") }
                } else {
                    Button(store.isAuthenticating ? "ログイン中" : "パスキーでログイン") { store.signIn() }.disabled(!store.endpointConfigured || store.isAuthenticating || store.isTransitioning || store.restoreNeedsRetry || store.localCleanupRequired)
                    if store.isAuthenticating { Button("ログインを中止") { store.cancelSignIn() } }
                }
                DisclosureGroup("パスキーとアカウント復旧") { Text("現在は初回登録とログインに対応しています。追加パスキーの登録・一覧・削除、すべてのパスキーを失った場合の復旧は、このアプリでは提供していません。既存のパスキーを失わないよう、ご利用の認証情報管理サービスで保管状況を確認してください。").bibleTextStyle(.caption) }
                if !store.endpointConfigured { Text("接続先が未設定です。実機ビルド時にHTTPSサーバーを設定してください。").bibleTextStyle(.caption) }
            }
            if store.exportCleanupRequired { Section("書き出しの一時ファイル") { Button("一時ファイルの削除を再試行", role: .destructive) { store.retryExportCleanup() } } }
            if store.restoreNeedsRetry { Section("ログイン情報の確認") { Button("保存したログインを再確認") { Task { await store.restore() } }.disabled(store.isTransitioning); Button("保存したログインを消去", role: .destructive) { showSignOut = true }.disabled(store.isTransitioning) } }
            if store.localCleanupRequired { Section("端末内データ") { Button("端末内データの削除を再試行", role: .destructive) { store.retryLocalCleanup() } } }
            if let owner = store.account { Section("自分の記録") {
                NavigationLink("送信済みの質問を確認") { PendingQuestionView(ownerID: owner.id, client: store.client) }
                NavigationLink("記録を書き出す") { ExportView(ownerID: owner.id, client: store.client) }
            } }
            Section { DisclosureGroup("AIと送信への同意") {
                Text("質問と関連する読書の文脈をCloudflare Workers AIへ送信します。APIキーはこのアプリには保存しません。").bibleTextStyle(.body)
                Button("送信に同意する") { showAIConsent = true }.disabled(store.account == nil || store.isConsentUpdating)
                Button("送信への同意を取り消す") { setConsent(false) }.disabled(store.account == nil || store.isConsentUpdating)
                Text("資料のみの閲覧はAIを呼び出しません。AI接続や利用枠が未確認の場合、生成は停止します。").bibleTextStyle(.caption)
                if let policy = store.aiPolicy {
                    LabeledContent("AI送信への同意", value: policy.workersAiConsent ? "同意済み" : "未同意")
                    LabeledContent("実験的な生成への同意", value: policy.groundedConsent.accepted && policy.groundedConsent.policyVersion == policy.groundedPolicyVersion ? "現在の説明に同意済み" : "未同意")
                    Text(policy.groundedNoticeJa).bibleTextStyle(.caption)
                    if !policy.allowedAnswerModes.contains(.groundedGeneration) { Text("根拠に基づく生成はサーバーでまだ有効になっていません。").bibleTextStyle(.caption) }
                    Button("生成の注意事項を確認して同意する") {
                        if let owner = store.account { groundedConsentIntent = GroundedConsentIntent(ownerID: owner.id, sessionEpoch: store.sessionEpoch, policy: policy) }
                    }
                    Button("実験的な生成への同意を取り消す") {
                        guard let owner = store.account else { return }
                        let intent = GroundedConsentIntent(ownerID: owner.id, sessionEpoch: store.sessionEpoch, policy: policy)
                        Task { do { try await store.consentGrounded(false, intent: intent) } catch { if store.sessionEpoch == intent.sessionEpoch { notice = "同意の取り消しを確認できませんでした。状態を再確認してください。" } } }
                    }
                } else { Text(store.isConsentUpdating ? "同意状況を更新しています。" : (store.aiPolicyError ?? "回答方法と同意状況は未確認です。")).bibleTextStyle(.caption) }
                Button("回答方法と同意状況を再確認") { Task { await store.loadAIPolicy() } }.disabled(store.account == nil)
            }
            }
            Section { DisclosureGroup("今日の利用量") {
                if let usage = store.usage {
                    LabeledContent("概算消費", value: usage.budgetUnits.consumed.formatted())
                    LabeledContent("処理中の予約枠", value: usage.budgetUnits.reserved.formatted())
                    LabeledContent("上限", value: usage.limit.formatted())
                    LabeledContent("次のリセット") { Text(Date(timeIntervalSince1970: usage.resetAt), format: .dateTime.month().day().hour().minute()) }
                    Text("サーバーの予算方式に基づく予約・消費の概算単位です。無料枠では推定値を使う場合があります。実測請求額ではありません。").bibleTextStyle(.caption)
                }
                else { Text(store.account == nil ? "ログイン後に利用量を確認できます。" : "利用量はまだ確認していません。表示がないことは消費ゼロを意味しません。").bibleTextStyle(.caption) }
                Button("利用量を確認") { Task { await store.loadUsage() } }.disabled(store.account == nil)
            }
            }
            if let notice = store.shareNotice { Section("共有機能") { Text(notice).bibleTextStyle(.body); Button("共有内容を再確認") { store.refreshInbox() } } }
            Section { DisclosureGroup("表示とデータの保存") {
                Text("文字サイズ、明るさ、透明度、動きはiPhoneの設定に従います。").bibleTextStyle(.body)
                Text("章節の履歴はアカウント別に保存します。公開が確認されたパブリックドメイン資料の概要だけを保存し、表示できる期限を最長24時間に制限します。接続時に出典の権利・版を再確認します。共有本文・資料原文・AI回答は、この端末には永続保存しません。未確認の質問は重複送信を防ぐため、処理確認まで端末に保護して保持します。会話の質問と回答はサーバーの履歴に保存されます。保存を選んだ比較結果もサーバーに残ります。個人データの削除から消去できますが、事業者バックアップの消去時期は未確定です。").bibleTextStyle(.caption)
            }
            }
            if let owner = store.account {
                Section("個人データ") {
                    NavigationLink("読書データをすべて削除") { PrivacyDeleteView(intent: DeletionIntent(ownerID: owner.id, sessionEpoch: store.sessionEpoch, kind: .readingData)) }
                    NavigationLink("アカウントを削除") { PrivacyDeleteView(intent: DeletionIntent(ownerID: owner.id, sessionEpoch: store.sessionEpoch, kind: .account)) }
                }
            }
            if let owner = store.account, owner.canDebug == true { Section("開発者") { NavigationLink("モデルと比較") { DeveloperView(ownerID: owner.id, client: store.client) } } }
            if let message = notice ?? store.errorMessage { Section { Text(message).bibleTextStyle(.body) } }
        }
        .bibleCanvas().navigationTitle("設定")
        .task { await store.loadAIPolicy() }
        .sheet(isPresented: $showGuide) { FirstRunGuide() }
        .sheet(item: $groundedConsentIntent, onDismiss: { Task { await store.loadAIPolicy() } }) { GroundedConsentView(intent: $0) }
        .confirmationDialog("ログアウトしますか？", isPresented: $showSignOut, titleVisibility: .visible) {
            Button("この端末からログアウト", role: .destructive) { Task { await store.signOut() } }
        } message: { Text("この端末の履歴と未取り込みの共有内容を消去します。サーバーの履歴は残ります。") }
        .confirmationDialog("Cloudflare Workers AIへの送信に同意しますか？", isPresented: $showAIConsent, titleVisibility: .visible) {
            Button("同意する") { setConsent(true) }
        } message: { Text("AIを使う質問では、質問文と関連する読書の文脈が送信されます。いつでも取り消せます。") }
    }
    private func setConsent(_ enabled: Bool) {
        let epoch = store.sessionEpoch
        Task {
            do {
                try await store.consent(enabled, expectedEpoch: epoch)
                guard store.sessionEpoch == epoch else { return }
                notice = enabled ? "AIへの送信に同意しました。質問画面でAIを選んだときに適用します。" : "AIへの送信同意を取り消しました。"
            } catch { if store.sessionEpoch == epoch { store.handle(error) } }
        }
    }

}
