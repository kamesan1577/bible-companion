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
    @State private var isLoading = true
    @State private var confirmReplay = false
    var body: some View {
        ScrollView {
            BibleReadingColumn {
                if isLoading {
                    BibleStateView(title: "送信済みの質問を確認しています", message: "端末に保存された質問を調べています。")
                } else if let pending {
                    BibleSectionHeader(title: "送信済みの質問", subtitle: pending.passageLabel)
                    Text(pending.question).bibleTextStyle(.body)
                    Text(pending.sourceOnly ? "選んだ箇所の参考資料を表示" : "AIが本文と参考資料をもとに回答").bibleTextStyle(.caption)
                    if !pending.sourceOnly { AnswerQualityNotice(mode: pending.answerMode.rawValue) }
                    Text(pending.createdAt, format: .dateTime.month().day().hour().minute()).bibleTextStyle(.caption)
                    Text("回答がまだ届かなくても、最初の質問が処理中かもしれません。まず状況を確認してください。再確認するときも同じ質問を使い、二重に処理されないようにします。").bibleTextStyle(.body)
                    Button(busy ? "確認しています…" : "処理状況を確認") { check() }.buttonStyle(.bordered).disabled(busy)
                    Button("この質問の処理を中止", role: .cancel) { cancel() }.disabled(busy)
                } else if recoveryID != nil {
                    BibleStateView(title: "質問の状態を読み取れません", message: "保存した質問情報は端末に残っています。新しい質問は送らず、元の処理を中止して整理できます。")
                    Button("元の処理を中止して整理", role: .cancel) { cancelRecovered() }.disabled(busy)
                } else if answer == nil && message == nil {
                    BibleStateView(title: "確認中の質問はありません", message: "回答が届かなかった質問があるときは、この画面から処理状況を確認できます。")
                }
                if busy { BibleLoadingView(title: "処理状況を確認しています", message: "確認が終わるまで、新しい質問は送信しません。") }
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
        .task {
            isLoading = true
            do { pending = try PendingQuestionStore.read(owner: ownerID) }
            catch { recoveryID = try? PendingQuestionStore.recoveryRequestID(owner: ownerID); message = "保存した質問を読み取れませんでした。質問情報は端末に残しています。端末のロックを解除するか、アプリを更新してから、もう一度お試しください。" }
            isLoading = false
        }
        .confirmationDialog("この質問をもう一度確認しますか？", isPresented: $confirmReplay, titleVisibility: .visible) {
            Button("再確認する") { replay() }
        } message: { Text("同じ質問の状況を確認します。すでに処理が始まっていれば、重ねて処理されません。まだ届いていなければ、最初の質問として受け付けます。") }
    }
    private func cancelRecovered() {
        guard let request = recoveryID, !busy else { return }; busy = true
        Task { await perform {
            let _: JSONValue = try await client.delete("/v1/requests/\(request)")
            try PendingQuestionStore.removeRecovered(owner: ownerID, request: request)
            recoveryID = nil; message = "元の処理を中止し、保存した質問情報を整理しました。"
        } }
    }
    private func check() {
        guard let pending, !busy else { return }; busy = true
        Task { await perform {
            let result: RequestResult = try await client.get("/v1/requests/\(pending.requestID)")
            try accept(result)
        } }
    }
    private func replay() {
        guard let pending, !busy else { return }; busy = true
        Task { await perform {
            let result: RequestResult
            if pending.standardExplanation { result = try await client.post("/v1/conversations/\(pending.conversationID)/explanation", body: ["requestId": pending.requestID]) }
            else { result = try await client.post("/v1/conversations/\(pending.conversationID)/questions", body: pending.body) }
            try accept(result)
        } }
    }
    private func cancel() {
        guard let pending else { return }
        Task { await perform {
            let _: JSONValue = try await client.delete("/v1/requests/\(pending.requestID)")
            try PendingQuestionStore.remove(owner: ownerID, request: pending.requestID)
            self.pending = nil; message = "中止を受け付けました。中止前に処理が始まっていた場合、利用回数に反映されることがあります。"
        } }
    }
    private func accept(_ result: RequestResult) throws {
        if ["complete", "failed", "cancelled"].contains(result.status) {
            try PendingQuestionStore.remove(owner: ownerID, request: result.requestId); pending = nil
        }
        answer = result.result
        switch result.status {
        case "complete": message = result.result == nil ? "回答に使う資料が変更されたため、表示できません。読書画面から新しい質問を送れます。" : "回答を確認しました。"
        case "failed": message = "質問の処理は完了しませんでした。読書画面から新しい質問として、もう一度お試しください。"
        case "cancelled": message = "この質問の処理は中止されています。必要なら読書画面から新しい質問を送れます。"
        default: message = "まだ処理中です。少し待ってから、もう一度状況を確認してください。"
        }
    }
    private func perform(_ action: () async throws -> Void) async {
        busy = true; defer { busy = false }
        do { try await action() }
        catch NetworkFailure.server(status: 404, code: "not_found") { message = "まだ質問を確認できません。最初の送信が遅れていることもあるため、同じ質問のまま再確認してください。" }
        catch { message = (error as? NetworkFailure)?.userMessage ?? "処理状況を確認できませんでした。通信状態を確かめて、もう一度お試しください。" }
    }
}
