import Foundation

/// Presentation state for an unauthenticated Share Extension request.
/// The state carries no credentials and requests no network action.
public struct ShareAuthRecoveryState: Equatable, Sendable {
    public enum AutomaticAction: Equatable, Sendable { case none }

    public let requiresAppRecheck: Bool
    public let setupMessage: String
    public let canRetryShareStart: Bool
    public let pendingRequest: String?
    public let error: String?
    public let automaticAction: AutomaticAction

    public static func unauthenticated(pendingRequest: String?) -> Self {
        let suffix = pendingRequest == nil
            ? ""
            : " 処理中の質問がある場合は、回答を確認できるまで同じ質問を再送しないでください。"
        return Self(
            requiresAppRecheck: true,
            setupMessage: "ログイン状態を確認できず、共有AIの要求を認証できませんでした。初回同意が原因とは限りません。共有画面を閉じてアプリを一度開き、ログイン状態を確認してからYouVersionで共有し直してください。" + suffix,
            canRetryShareStart: false,
            pendingRequest: pendingRequest,
            error: nil,
            automaticAction: .none
        )
    }
}
