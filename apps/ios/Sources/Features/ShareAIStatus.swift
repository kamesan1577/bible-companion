import SwiftUI
import CompanionCore

/// Reads the saved capability; never creates consent or renews access.
@MainActor struct ShareAIStatus {
    let title: String
    let detail: String
    let ready: Bool
    var expiresAt: Date? = nil
    var needsRenewal = false

    static func read(store: AppStore, at date: Date = Date()) -> Self {
        guard let owner = store.account?.id else {
            return Self(title: "共有AIは未設定", detail: "ログインと利用条件の確認から始めます。", ready: false)
        }
        guard store.aiPolicyError == nil, let policy = store.aiPolicy else {
            return Self(title: "利用状態を確認できません", detail: "設定を開いて、接続と利用条件を確認してください。", ready: false)
        }
        guard policy.shareAiEnabled == true, policy.allowedAnswerModes.contains(.groundedGeneration) else {
            return Self(title: "共有AIは現在利用できません", detail: "章や人物の収録済みの説明は、そのまま読めます。", ready: false)
        }
        do {
            let access = try ShareInbox.verifiedAIAccess(expectedOwner: owner)
            guard SharePreparationReadiness.isSaved(policy: policy, owner: owner, access: access, at: date) else {
                return Self(title: "共有AIの設定が必要です", detail: "現在の利用条件を確認してください。", ready: false)
            }
            return Self(title: "共有AIを使えます", detail: "YouVersionで節を選び、共有から「聖書コンパニオン」を開いてください。解説の表示には通信が必要です。", ready: true, expiresAt: Date(timeIntervalSince1970: access.expiresAt))
        } catch ShareAIAccessReadError.missing {
            return Self(title: "共有AIは未設定", detail: "利用条件を確認して、共有画面で使う設定を保存します。", ready: false)
        } catch ShareAIAccessReadError.expired {
            return Self(title: "共有AIの期限が切れています", detail: "設定を更新すると、再び共有画面で使えます。", ready: false, needsRenewal: true)
        } catch {
            return Self(title: "共有AIを確認できません", detail: SharePreparationFailure.message(for: error), ready: false)
        }
    }
}

struct ShareAIStatusLabel: View {
    let status: ShareAIStatus
    var body: some View {
        VStack(alignment: .leading, spacing: BibleTheme.Space.sm) {
            Label(status.title, systemImage: status.ready ? "checkmark.circle.fill" : "info.circle")
                .bibleTextStyle(.body).bibleForeground(.textPrimary)
            if let expiry = status.expiresAt {
                Text("有効期限：\(expiry.formatted(date: .abbreviated, time: .shortened))")
                    .bibleTextStyle(.caption).bibleForeground(.textSecondary)
            }
            Text(status.detail).bibleTextStyle(.caption).bibleForeground(.textSecondary)
        }
    }
}
