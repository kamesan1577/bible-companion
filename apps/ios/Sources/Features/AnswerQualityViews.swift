import SwiftUI
import CompanionCore

struct AnswerQualityNotice: View {
    let mode: String
    var body: some View {
        if mode == AnswerMode.groundedGeneration.rawValue {
            BibleScopeNotice(text: AnswerMode.groundedWarning)
        } else if mode == AnswerMode.reviewedClaimSelection.rawValue {
            Text("編集確認済みの説明から選択した内容です。回答の対象範囲と出典を確認してください。").bibleTextStyle(.caption).bibleForeground(.textSecondary)
        }
    }
}
struct GroundedConsentView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let intent: GroundedConsentIntent
    @State private var busy = false
    @State private var message: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("AIで解説を読む") {
                    Text("AIは間違えることがあります。解説は本文と出典を確かめながら読んでください。").bibleTextStyle(.body)
                    Text("質問と関連する読書の文脈をCloudflare Workers AIへ送信し、AIが新しい文章を生成します。引用があることは、説明の正確さや先の内容を含まないことの保証ではありません。").bibleTextStyle(.body)
                    if intent.policy.shareAiEnabled == true { Text("共有画面でも使えるように、解説・質問専用の24時間の認証をこのアプリと共有拡張だけで利用します。通常のログイン認証は共有しません。いつでも設定から停止できます。").bibleTextStyle(.caption) }
                    DisclosureGroup("詳しい注意事項") { Text(intent.policy.groundedNoticeJa).bibleTextStyle(.caption) }
                }
                Section {
                    Button(intent.policy.shareAiEnabled == true ? "同意して、共有画面でもAIを使う" : "同意して解説を読む") {
                        busy = true
                        Task {
                            defer { busy = false }
                            do { try await store.consentGrounded(true, intent: intent); if intent.policy.shareAiEnabled == true { try await store.enableShareAI(expectedEpoch: intent.sessionEpoch) }; dismiss() }
                            catch { message = "同意の更新を確認できませんでした。アカウントと説明の版を再確認してください。自動で再送はしていません。" }
                        }
                    }.disabled(busy || !intent.permits(ownerID: store.account?.id, epoch: store.sessionEpoch, currentPolicy: store.aiPolicy))
                    if busy { ProgressView("同意状況を更新しています") }
                    if let message { Text(message).bibleTextStyle(.body) }
                }
            }
            .bibleCanvas().navigationTitle("生成の注意事項").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() }.disabled(busy) } }
            .interactiveDismissDisabled(busy)
        }
    }
}

struct AnswerBudgetNotice: View {
    let policy: JSONValue?
    var body: some View {
        if let policy, policy != .null {
            DisclosureGroup("利用枠の計算") {
                Text(policy["budgetBoundVerified"].bool == true ? "検証済みの予約上限を使用しました。実際の請求額とは異なります。" : "予約量は推定です。厳密な使用量や請求額を証明する値ではありません。").bibleTextStyle(.caption)
                LabeledContent("予約単位", value: policy["reservedBudgetUnits"].display)
                ForEach(policy["warnings"].array, id: \.self) { Text($0.string ?? "利用枠の注意事項があります。").bibleTextStyle(.caption) }
            }
        }
    }
}
