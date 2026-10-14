import SwiftUI
import CompanionCore

struct PrivacyDeleteView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let intent: DeletionIntent
    @State private var typedConfirmation = ""
    @State private var showConfirmation = false
    @State private var needsReauthentication = false
    @State private var message: String?
    var body: some View {
        Form {
            Section {
                BibleSectionHeader(title: intent.kind.title)
                Text(intent.kind.explanation).bibleTextStyle(.body)
                Text("現在のサーバーデータを削除します。事業者バックアップの消去時期は未確定です。既に発生したAI利用量は取り消されません。").bibleTextStyle(.caption)
                Text("完了後は端末内の個人データも消去してログアウトします。通信結果が不明な場合もログアウトし、削除完了は改めて確認が必要です。").bibleTextStyle(.caption)
            }
            Section("最終確認") {
                TextField("確認のため「削除」と入力", text: $typedConfirmation).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button(intent.kind.title, role: .destructive) { showConfirmation = true }
                    .disabled(!intent.permits(ownerID: store.account?.id, epoch: store.sessionEpoch, typedConfirmation: typedConfirmation) || store.isTransitioning || store.isDeleting)
            }
            if needsReauthentication {
                Section {
                    Text("削除には5分以内のログインが必要です。ログインを更新した後、削除する対象をもう一度確認してください。").bibleTextStyle(.body)
                    Button("ログインを更新する") {
                        Task { await store.signOut(); store.signIn(); dismiss() }
                    }.disabled(store.isTransitioning)
                }
            }
            if let message { Section { Text(message).bibleTextStyle(.body) } }
        }
        .bibleCanvas().navigationTitle("個人データの削除").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("この操作は元に戻せません", isPresented: $showConfirmation, titleVisibility: .visible) {
            Button(intent.kind.title, role: .destructive) { submit() }
            Button("キャンセル", role: .cancel) {}
        } message: { Text(intent.kind.explanation) }
    }
    private func submit() {
        let confirmation = typedConfirmation
        Task {
            do { try await store.deletePrivateData(intent, typedConfirmation: confirmation) }
            catch NetworkFailure.server(status: 403, code: "reauthentication_required") { needsReauthentication = true; typedConfirmation = ""; message = "削除は実行されていません。ログインを更新してください。" }
            catch { if store.sessionEpoch == intent.sessionEpoch { message = "削除結果を確認できませんでした。表示される状態を確認してください。" } }
        }
    }
}
