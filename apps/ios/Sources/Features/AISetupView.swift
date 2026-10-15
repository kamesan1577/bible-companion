import SwiftUI
import CompanionCore

/// A single preparation flow, reachable without changing the selected reading.
struct AISetupView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var intent: GroundedConsentIntent?
    @State private var busy = false
    @State private var message: String?
    @State private var accessReady = false
    @State private var extensionReadConfirmed = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("YouVersionで選んだ箇所の解説を、そのまま共有画面で読めるようにします。").bibleTextStyle(.body)
                    Text("準備が終わっても、今読んでいる箇所は変わりません。").bibleTextStyle(.caption)
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
                    Section("設定を保存しました") {
                        Label("次にYouVersionから共有してください", systemImage: "checkmark.circle.fill")
                        Text("この画面を閉じ、YouVersionで節を選んで共有ボタンを押し、「聖書コンパニオン」を選んでください。").bibleTextStyle(.body)
                        if extensionReadConfirmed {
                            Text("共有画面で、この設定を受け取れたことも確認できました。").bibleTextStyle(.caption)
                        } else {
                            Text("次にYouVersionから共有してください。共有画面が設定を受け取れたかは、まだ確認していません。同意を繰り返す必要はありません。").bibleTextStyle(.caption)
                        }
                        Button("読んでいた画面に戻る") { dismiss() }.buttonStyle(.borderedProminent)
                    }
                } else {
                    Section("AIの使い方を確認する") {
                        Text("送る情報と保存先を確認してから、解説を使えるようにします。").bibleTextStyle(.body)
                        if let policy = store.aiPolicy, policy.shareAiEnabled != true {
                            Text("現在、YouVersionの共有画面ではAI解説を使えません。このアプリで読書を続けられます。しばらくしてから、下のボタンで再確認してください。").bibleTextStyle(.body)
                            if policy.permits(.groundedGeneration) {
                                Button("このアプリの読書へ戻る") { dismiss() }
                            } else if policy.allowedAnswerModes.contains(.groundedGeneration), let owner = store.account {
                                Button("このアプリでAI解説を使う") { intent = GroundedConsentIntent(ownerID: owner.id, sessionEpoch: store.sessionEpoch, policy: policy) }
                            }
                            Button("使えるか再確認する") { Task { await refresh() } }.disabled(busy)
                        } else {
                            Button(busy ? "準備しています" : (store.aiPolicy?.permits(.groundedGeneration) == true ? "共有から解説を読めるようにする" : "説明を読んで準備する")) { Task { await prepare() } }.buttonStyle(.borderedProminent).disabled(busy || store.isTransitioning || store.isConsentUpdating)
                        }
                        if let message { Text(message).bibleTextStyle(.body) }
                        if let error = store.aiPolicyError { Text(error).bibleTextStyle(.body) }
                    }
                }
            }
            .navigationTitle("YouVersionから解説を読む準備").navigationBarTitleDisplayMode(.inline).bibleCanvas()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() }.disabled(busy) } }
            .sheet(item: $intent, onDismiss: { updateReady() }) { GroundedConsentView(intent: $0).environmentObject(store) }
            .task(id: store.account?.id) { await refresh() }
            .onChange(of: store.sessionEpoch) { _, _ in intent = nil; accessReady = false }
        }
    }
    private func updateReady() {
        guard let owner = store.account?.id, store.aiPolicy?.shareAiEnabled == true, store.aiPolicy?.shareAiConsent == true, store.aiPolicy?.permits(.groundedGeneration) == true else { accessReady = false; extensionReadConfirmed = false; return }
        do { let access = try ShareInbox.verifiedAIAccess(expectedOwner: owner); accessReady = SharePreparationReadiness.isSaved(policy: store.aiPolicy, owner: owner, access: access); extensionReadConfirmed = (try? ShareInbox.extensionHasReadCurrentAccess(expectedOwner: owner)) == true }
        catch { accessReady = false; extensionReadConfirmed = false; message = SharePreparationFailure.message(for: error) }
    }
    private func refresh() async {
        guard store.account != nil else { return }
        await store.loadAIPolicy(); updateReady()
    }
    private func prepare() async {
        guard !busy else { return }; busy = true; message = nil
        defer { busy = false }
        let epoch = store.sessionEpoch
        await store.loadAIPolicy()
        guard epoch == store.sessionEpoch, let owner = store.account, let policy = store.aiPolicy else {
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
