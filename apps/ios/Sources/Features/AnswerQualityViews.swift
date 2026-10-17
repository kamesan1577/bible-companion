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
                    Text("選んだ聖書の箇所、質問、関連する会話をCloudflare Workers AIへ送り、解説を作ります。出典があっても間違いや未読の出来事を含むことがあります。").bibleTextStyle(.body)
                    if intent.policy.shareAiEnabled == true { Text("YouVersionから開く画面でも解説と質問を使えるよう、共有専用のログイン情報と自動更新用の情報を端末内に保存します。短期の情報は最長24時間で更新し、更新できる期間も元のログイン期限までです。通常のログイン情報はその画面へ渡しません。設定でAIへの送信をやめることもできます。").bibleTextStyle(.caption) }
                    DisclosureGroup("詳しい注意事項") { Text(intent.policy.groundedNoticeJa).bibleTextStyle(.caption) }
                }
                Section {
                    Button("同意して解説を使う") {
                        busy = true
                        Task {
                            defer { busy = false }
                            do { try await store.consentGrounded(true, intent: intent); if intent.policy.shareAiEnabled == true { try await store.enableShareAI(expectedEpoch: intent.sessionEpoch) }; dismiss() }
                            catch { message = SharePreparationFailure.message(for: error) }
                        }
                    }.disabled(busy || !intent.permits(ownerID: store.account?.id, epoch: store.sessionEpoch, currentPolicy: store.aiPolicy))
                    if busy { ProgressView("解説を使う準備をしています") }
                    if let message { Text(message).bibleTextStyle(.body) }
                }
            }
            .bibleCanvas().navigationTitle("AI解説を使う前に").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() }.disabled(busy) } }
            .interactiveDismissDisabled(busy)
        }
    }
}

struct AnswerBudgetNotice: View {
    @EnvironmentObject private var store: AppStore
    let policy: JSONValue?
    var body: some View {
        if store.account?.canDebug == true, let policy, policy != .null {
            DisclosureGroup("開発者専用：利用枠の計算") {
                Text(policy["budgetBoundVerified"].bool == true ? "検証済みの予約上限を使用しました。実際の請求額とは異なります。" : "予約量は推定です。厳密な使用量や請求額を証明する値ではありません。").bibleTextStyle(.caption)
                LabeledContent("予約単位", value: policy["reservedBudgetUnits"].display)
                ForEach(policy["warnings"].array, id: \.self) { Text($0.string ?? "利用枠の注意事項があります。").bibleTextStyle(.caption) }
            }.bibleForeground(.danger)
        }
    }
}
