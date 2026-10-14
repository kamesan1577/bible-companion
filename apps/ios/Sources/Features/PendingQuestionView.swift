import SwiftUI
import CompanionCore

/// Recovery is explicit. A lost response never mints a replacement request ID.
struct PendingQuestionView: View {
    let ownerID: String
    let client: APIClient
    @State private var pending: PendingQuestion?
    @State private var recoveryID: String?
    @State private var answer: AnswerResult?
    @State private var message: String?
    @State private var busy = false
    @State private var confirmReplay = false
    var body: some View {
        ScrollView {
            BibleReadingColumn {
                if let pending {
                    BibleSectionHeader(title: "送信済みの質問", subtitle: pending.passageLabel)
                    Text(pending.question).bibleTextStyle(.body)
                    Text(pending.sourceOnly ? "選んだ範囲の資料のみ" : pending.answerMode.label).bibleTextStyle(.caption)
                    if !pending.sourceOnly { AnswerQualityNotice(mode: pending.answerMode.rawValue) }
                    Text(pending.createdAt, format: .dateTime.month().day().hour().minute()).bibleTextStyle(.caption)
                    Text("回答が届かなかった場合も、最初の処理が続いている可能性があります。同じ識別子と内容で確認し、二重の生成を避けます。").bibleTextStyle(.body)
                    Button("状態を確認") { check() }.buttonStyle(.bordered).disabled(busy)
                    Button("同じ質問の送信を再確認") { confirmReplay = true }.buttonStyle(.glass).disabled(busy)
                    Button("この質問の処理を中止", role: .cancel) { cancel() }.disabled(busy)
                } else if recoveryID != nil {
                    BibleStateView(title: "送信情報の形式を確認できません", message: "元の識別子を保持しています。新しい質問を送る前に、処理を中止して整理できます。内容の再送はしません。")
                    Button("元の処理を中止して整理", role: .cancel) { cancelRecovered() }.disabled(busy)
                } else if answer == nil && message == nil {
                    BibleStateView(title: "確認待ちの質問はありません", message: "未確認の送信がある場合、ここから状況を確認できます。")
                }
                if busy { BibleLoadingView(title: "処理状況を確認しています", message: "新しい識別子での再送はしていません。") }
                if let message { Text(message).bibleTextStyle(.body) }
                if let answer {
                    AnswerQualityNotice(mode: answer.mode)
                        AnswerBudgetNotice(policy: answer.budgetPolicy)
                    Text(answer.answer).bibleTextStyle(.body).textSelection(.enabled)
                    Text(answer.referenceSystem?.noticeJa ?? ReferenceSystem.fallbackNotice).bibleTextStyle(.caption).bibleForeground(.textSecondary)
                    CitationList(citations: answer.citations)
                }
            }
        }
        .bibleCanvas().navigationTitle("送信済みの質問")
        .task { do { pending = try PendingQuestionStore.read(owner: ownerID) } catch { recoveryID = try? PendingQuestionStore.recoveryRequestID(owner: ownerID); message = "送信情報を読めません。元の情報は保持しています。端末のロックを解除するか、アプリを更新して再確認してください。" } }
        .confirmationDialog("同じ識別子・内容で送信を再確認しますか？", isPresented: $confirmReplay, titleVisibility: .visible) {
            Button("再確認する") { replay() }
        } message: { Text("既に受け付けられた処理は重複実行しません。まだ受け付けられていなければ、最初の質問として処理されます。") }
    }
    private func cancelRecovered() {
        guard let request = recoveryID else { return }
        Task { await perform {
            let _: JSONValue = try await client.delete("/v1/requests/\(request)")
            try PendingQuestionStore.removeRecovered(owner: ownerID, request: request)
            recoveryID = nil; message = "元の処理を中止し、確認待ち情報を整理しました。"
        } }
    }
    private func check() {
        guard let pending else { return }
        Task { await perform {
            let result: RequestResult = try await client.get("/v1/requests/\(pending.requestID)")
            try accept(result)
        } }
    }
    private func replay() {
        guard let pending else { return }
        Task { await perform {
            let result: RequestResult = try await client.post("/v1/conversations/\(pending.conversationID)/questions", body: pending.body)
            try accept(result)
        } }
    }
    private func cancel() {
        guard let pending else { return }
        Task { await perform {
            let _: JSONValue = try await client.delete("/v1/requests/\(pending.requestID)")
            try PendingQuestionStore.remove(owner: ownerID, request: pending.requestID)
            self.pending = nil; message = "中止を受け付けました。既に処理や利用量が発生している場合があります。"
        } }
    }
    private func accept(_ result: RequestResult) throws {
        if ["complete", "failed", "cancelled"].contains(result.status) {
            try PendingQuestionStore.remove(owner: ownerID, request: result.requestId); pending = nil
        }
        answer = result.result
        switch result.status {
        case "complete": message = result.result == nil ? "資料の権利・版・表示範囲が変わり、回答は表示できません。" : "回答を確認しました。"
        case "failed": message = "処理は失敗して終了しました。読書画面から新しい質問として再試行できます。"
        case "cancelled": message = "この質問の処理は中止されています。"
        default: message = "まだ処理中です。しばらくして状態を確認してください。"
        }
    }
    private func perform(_ action: () async throws -> Void) async {
        busy = true; defer { busy = false }
        do { try await action() }
        catch NetworkFailure.server(status: 404, code: "not_found") { message = "処理はまだ見つかりません。最初の送信が遅れている可能性があるため、同じ識別子で再確認してください。" }
        catch { message = (error as? NetworkFailure)?.userMessage ?? "処理状況を確認できませんでした。" }
    }
}
