import Foundation

public enum SharePreparationFailure {
    public static func message(for error: Error) -> String {
        guard let issue = error as? ShareAIAccessReadError else {
            if let failure = error as? NetworkFailure { return failure.userMessage }
            return "設定を保存できませんでした。iPhoneのロックを解除してから、もう一度お試しください。質問は送っていません。"
        }
        switch issue {
        case .appGroupUnavailable: return "アプリと共有画面の間で設定を渡せません。同意を繰り返す必要はありません。最新版に更新してから、もう一度お試しください。"
        case .protectedDataUnavailable: return "iPhoneのロックを解除してアプリを開き直してください。その後、YouVersionから同じ箇所をもう一度共有してください。"
        case .missing: return "共有画面で使う設定がまだ保存されていません。準備画面から保存してください。"
        case .expired: return "共有画面で使うログインの期限が切れています。準備画面から更新してください。同意済みの場合は、再び同意する必要はありません。"
        case .ownerMismatch: return "アプリと共有画面のログインが一致しません。今使っているアカウントで準備をやり直してください。ほかの人の記録へは送信していません。"
        case .corrupted, .readFailed: return "保存した設定を読み取れません。iPhoneのロックを解除してアプリを開き直し、準備をやり直してください。読書の記録は削除していません。"
        case .writeFailed: return "設定を保存した後の確認ができませんでした。iPhoneのロックを解除して、もう一度お試しください。準備はまだ完了していません。"
        }
    }
}
