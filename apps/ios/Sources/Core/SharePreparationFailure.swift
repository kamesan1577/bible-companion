import Foundation

public enum SharePreparationFailure {
    public static func message(for error: Error) -> String {
        let text = description(for: error)
        if let failure = error as? ShareStorageFailure { return text + " 診断コード：" + failure.diagnosticCode }
        return text
    }
    private static func description(for error: Error) -> String {
        guard let issue = ShareStorageFailure.reason(for: error) else {
            if let failure = error as? NetworkFailure { return failure.userMessage }
            return "設定の保存を確認できませんでした。原因はまだ特定できません。診断情報を確認してください。質問は送っていません。"
        }
        switch issue {
        case .appGroupUnavailable: return "共有設定の保存先をOSから取得できません。署名や共有権限を確認する必要があります。同意やインストールを繰り返さず、診断情報を確認してください。"
        case .protectedDataUnavailable: return "iPhoneのロックを解除してアプリを開き直してください。その後、YouVersionから同じ箇所をもう一度共有してください。"
        case .missing: return "共有画面で使う設定がまだ保存されていません。準備画面から保存してください。"
        case .expired: return "共有画面で使うログインの期限が切れています。準備画面から更新してください。同意済みの場合は、再び同意する必要はありません。"
        case .ownerMismatch: return "アプリと共有画面のログインが一致しません。今使っているアカウントで準備をやり直してください。ほかの人の記録へは送信していません。"
        case .accessDenied: return "共有設定の保存先へのアクセスが拒否されました。ロック中か、署名の共有権限に問題があるかはまだ分かりません。診断情報を確認してください。アプリや読書の記録は削除しないでください。"
        case .storageFull: return "共有設定を保存する空き容量が足りません。iPhoneのストレージを確認してください。アプリや読書の記録を削除する必要はありません。"
        case .coordinationFailed: return "共有設定の読み書きを調整できませんでした。この画面を閉じて一度だけ開き直し、続く場合は診断情報を確認してください。記録は削除していません。"
        case .corrupted: return "共有設定の形式を確認できません。読書の記録は削除せず、診断情報を確認してください。"
        case .readFailed: return "共有設定を読み取れませんでした。原因はまだ特定できません。診断情報を確認してください。読書の記録は削除していません。"
        case .writeFailed: return "共有設定を書き込むか、保存後に読み直す処理に失敗しました。診断情報を確認してください。準備はまだ完了していません。"
        }
    }
}
