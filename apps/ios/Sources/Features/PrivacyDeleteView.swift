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
                Text("この操作では、アカウントに保存されている対象データを削除します。サービス提供者のバックアップから消える時期は確認できません。すでに使われたAI利用量は取り消されません。").bibleTextStyle(.caption)
                Text("削除を送信すると、この端末の個人データも消してログアウトします。通信が途切れて結果を確認できない場合もログアウトします。その場合、削除が完了したかは、ログインし直して対象データが残っていないことを確認してください。").bibleTextStyle(.caption)
            }
            Section("最終確認") {
                TextField("確認のため「削除」と入力してください", text: $typedConfirmation).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button(intent.kind.title, role: .destructive) { showConfirmation = true }
                    .disabled(!intent.permits(ownerID: store.account?.id, epoch: store.sessionEpoch, typedConfirmation: typedConfirmation) || store.isTransitioning || store.isDeleting)
            }
            if needsReauthentication {
                Section {
                    Text("安全のため、直近5分以内にログインしている必要があります。ログインを更新したら、この画面で削除する対象をもう一度読み、確認文字を入力して削除をやり直してください。").bibleTextStyle(.body)
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
            catch { if store.sessionEpoch == intent.sessionEpoch { message = "削除が完了したか確認できませんでした。端末からはログアウトしています。読書データを削除した場合はログインし直して履歴を確認し、残っているデータがあれば削除をもう一度行ってください。アカウントを削除した場合は、削除を自動で再送していません。" } }
        }
    }
}
