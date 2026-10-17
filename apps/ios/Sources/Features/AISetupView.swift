import SwiftUI
import CompanionCore

/// A single preparation flow, reachable without changing the selected reading.
struct AISetupView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var intent: GroundedConsentIntent?
    @State private var busy = false
    @State private var message: String?
    @State private var accessReady = false
    @State private var extensionReadConfirmed = false
    @State private var checking = false
    @State private var preparationTask: Task<Void, Never>?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if busy || checking {
                        HStack(spacing: BibleTheme.Space.md) {
                            ProgressView().progressViewStyle(.circular)
                            Text(busy ? "共有AIの設定を保存しています" : "利用状態を確認しています").bibleTextStyle(.body)
                        }
                        Text("完了するまでお待ちください。解説や質問はまだ送信しません。").bibleTextStyle(.caption)
                    } else {
                        TimelineView(.periodic(from: .now, by: 1)) { timeline in
                            ShareAIStatusLabel(status: ShareAIStatus.read(store: store, at: timeline.date))
                        }
                    }
                }
                if store.account == nil {
                    Section("ログインする") {
                        Text("あなたの質問と読書履歴を、ほかの人の記録と分けて保存します。iPhoneの案内に従ってログインしてください。初めての方も同じボタンから登録できます。").bibleTextStyle(.body)
                        Button(store.isAuthenticating ? "ログインしています" : "ログインして準備を始める") { store.signIn() }
                            .disabled(!store.endpointConfigured || store.isAuthenticating || store.isTransitioning || store.restoreNeedsRetry || store.localCleanupRequired)
                        if store.isAuthenticating { Button("ログインをやめる") { store.cancelSignIn() } }
                        if store.restoreNeedsRetry { Button("保存したログインを確認する") { Task { await store.restore() } }.disabled(store.isTransitioning) }
                        if store.localCleanupRequired { Text("前のログインの片づけが終わっていません。この画面を閉じ、設定の「端末内データ」から削除をやり直してください。").bibleTextStyle(.caption) }
                        if !store.endpointConfigured { Text("アプリの接続設定に問題があります。最新版に更新してから、もう一度お試しください。").bibleTextStyle(.caption) }
                        if let error = store.errorMessage { Text(error).bibleTextStyle(.body) }
                    }
                } else if accessReady {
                    Section("次はYouVersionで") {
                        Text("この画面を閉じてYouVersionに戻り、共有する節を選んでください。").bibleTextStyle(.body)
                        if extensionReadConfirmed {
                            Text("共有画面で、この設定を受け取れたことも確認できました。").bibleTextStyle(.caption)
                        } else {
                            Text("共有画面が設定を受け取れたかは、次に共有したときに確認できます。").bibleTextStyle(.caption)
                        }
                        Button("閉じてYouVersionで節を選ぶ") { dismiss() }.buttonStyle(.borderedProminent)
                    }
                } else {
                    Section("AIの使い方を確認する") {
                        Text(store.aiPolicy?.permits(.groundedGeneration) == true ? "この端末の共有画面で使う設定を保存します。有効期限は最長24時間です。この操作では解説や質問を送信しません。" : "送る情報・保存先・AIの注意点を確認する画面が開きます。同意するかは、その画面で選べます。").bibleTextStyle(.body)
                        if let policy = store.aiPolicy, policy.shareAiEnabled != true {
                            Text("現在、YouVersionの共有画面ではAI解説を使えません。このアプリで読書を続けられます。しばらくしてから、下のボタンで再確認してください。").bibleTextStyle(.body)
                            if policy.permits(.groundedGeneration) {
                                Button("このアプリの読書へ戻る") { dismiss() }
                            } else if policy.allowedAnswerModes.contains(.groundedGeneration), let owner = store.account {
                                Button("このアプリでAI解説を使う") { intent = GroundedConsentIntent(ownerID: owner.id, sessionEpoch: store.sessionEpoch, policy: policy) }
                            }
                            Button("使えるか再確認する") { Task { await refresh() } }.disabled(busy)
                        } else {
                            Button(store.aiPolicy?.permits(.groundedGeneration) == true ? (ShareAIStatus.read(store: store).needsRenewal ? "共有AIの設定を更新する" : "共有AIを有効にする") : "AIの利用条件を確認する") { preparationTask = Task { await prepare() } }.buttonStyle(.borderedProminent).disabled(busy || checking || store.isTransitioning || store.isConsentUpdating)
                        }
                        if let message, message != ShareAIStatus.read(store: store).detail { Text(message).bibleTextStyle(.body) }
                        if let error = store.aiPolicyError { Text(error).bibleTextStyle(.body) }
                    }
                }
            }
            .navigationTitle("共有AIの設定").navigationBarTitleDisplayMode(.inline).bibleCanvas()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { preparationTask?.cancel(); dismiss() } } }
            .sheet(item: $intent, onDismiss: { updateReady() }) { GroundedConsentView(intent: $0).environmentObject(store) }
            .task(id: store.account?.id) { await refresh() }
            .onDisappear { preparationTask?.cancel() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { updateReady() } }
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in if accessReady { updateReady() } }
            .onChange(of: store.sessionEpoch) { _, _ in intent = nil; accessReady = false }
        }
    }
    private func updateReady() {
        guard store.aiPolicyError == nil, let owner = store.account?.id, store.aiPolicy?.shareAiEnabled == true, store.aiPolicy?.shareAiConsent == true, store.aiPolicy?.permits(.groundedGeneration) == true else { accessReady = false; extensionReadConfirmed = false; return }
        do { let access = try ShareInbox.verifiedAIAccess(expectedOwner: owner); accessReady = SharePreparationReadiness.isSaved(policy: store.aiPolicy, owner: owner, access: access); extensionReadConfirmed = (try? ShareInbox.extensionHasReadCurrentAccess(expectedOwner: owner)) == true }
        catch ShareAIAccessReadError.missing, ShareAIAccessReadError.expired { accessReady = false; extensionReadConfirmed = false; message = nil }
        catch { accessReady = false; extensionReadConfirmed = false; message = SharePreparationFailure.message(for: error) }
    }
    private func refresh() async {
        guard store.account != nil else { return }
        checking = true; defer { checking = false }
        await store.loadAIPolicy(); updateReady()
    }
    private func prepare() async {
        guard !busy else { return }; busy = true; message = nil
        defer { busy = false }
        let epoch = store.sessionEpoch
        await store.loadAIPolicy()
        guard !Task.isCancelled, epoch == store.sessionEpoch, let owner = store.account, let policy = store.aiPolicy else {
            message = "準備を始められませんでした。通信とログインを確かめて、もう一度お試しください。"; return
        }
        guard policy.shareAiEnabled == true, policy.allowedAnswerModes.contains(.groundedGeneration) else {
            message = "今はこの機能を利用できません。しばらくしてから、もう一度お試しください。"; return
        }
        if policy.permits(.groundedGeneration) {
            do { try await store.enableShareAI(expectedEpoch: epoch); updateReady() }
            catch { if epoch == store.sessionEpoch { message = SharePreparationFailure.message(for: error) } }
        } else { intent = GroundedConsentIntent(ownerID: owner.id, sessionEpoch: epoch, policy: policy) }
    }
}
