import SwiftUI
import CompanionCore

@MainActor final class QuestionModel: ObservableObject {
    @Published var draft = ""
    @Published var sourceOnly = false
    @Published var answerMode: AnswerMode = .reviewedClaimSelection
    @Published private(set) var aiPolicy: AIPolicy?
    @Published private(set) var policyError: String?
    @Published var spoilerAllowed = false
    @Published private(set) var transcript = ChatTranscript()
    @Published private(set) var preview = ""
    @Published private(set) var loadingHistory = false
    @Published private(set) var historyCursor: String?
    private var submittedStandard = false
    private var lastQuestion: String?
    @Published private(set) var answer: AnswerResult?
    @Published private(set) var status = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRunning = false
    @Published private(set) var statusAttempt: UUID?
    var isCheckingStatus: Bool { statusAttempt != nil }
    @Published private(set) var needsStatusCheck = false
    @Published private(set) var requestID: String?
    @Published private(set) var conversation: Conversation?
    private var conversationID: String?
    private var task: Task<Void, Never>?
    private var gate = RequestGate()
    private var policyGate = RequestGate()
    private var currentScope: QuestionScope?
    let ownerID: String
    let client: APIClient
    let item: ImportRecord
    let rangeIndex: Int
    private var resumeInvalid = false
    init(ownerID: String, client: APIClient, item: ImportRecord, rangeIndex: Int, conversation: Conversation? = nil) {
        self.ownerID = ownerID; self.client = client; self.item = item; self.rangeIndex = rangeIndex
        if let conversation {
            guard conversation.resumeRangeIndex(in: item) == rangeIndex else { resumeInvalid = true; return }
            conversationID = conversation.id; spoilerAllowed = conversation.spoilerAllowed
            self.conversation = conversation
            transcript.restore(conversation.messages ?? []); historyCursor = conversation.nextMessageCursor
            currentScope = try? QuestionScope(reading: item.ranges[rangeIndex], target: conversation.passage, spoilerAllowed: conversation.spoilerAllowed)
        }
    }
    func loadPolicy() async {
        let generation = policyGate.invalidate(); aiPolicy = nil; policyError = nil
        do { let value: AIPolicy = try await client.get("/v1/me/ai-policy"); guard !Task.isCancelled, policyGate.accepts(generation) else { return }; aiPolicy = value; if let selected = value.defaultAnswerMode { answerMode = selected }; policyError = nil }
        catch { if !Task.isCancelled, policyGate.accepts(generation) { aiPolicy = nil; policyError = "今はAIに質問できるか確認できません。通信を確かめて再確認してください。聖書の説明は引き続き読めます。" } }
    }
    func loadHistory(older: Bool = false) async {
        guard let conversationID, !isRunning, !loadingHistory else { return }
        loadingHistory = true; errorMessage = nil
        let generation = gate.invalidate()
        defer { if gate.accepts(generation) { loadingHistory = false } }
        do {
            let page: Conversation = try await client.get("/v1/conversations/\(conversationID)", query: older ? historyCursor.map { [URLQueryItem(name: "beforeMessageId", value: $0)] } ?? [] : [])
            guard gate.accepts(generation), page.id == conversationID else { return }
            conversation = page; if older { transcript.prepend(page.messages ?? []) } else { transcript.restore(page.messages ?? []) }; historyCursor = page.nextMessageCursor
        } catch {
            if gate.accepts(generation) { errorMessage = "保存した会話を読み込めませんでした。再読み込みで確認できます。" }
        }
    }
    func retry(target: Passage) { guard let lastQuestion else { return }; if let requestID { transcript.discardUnanswered(id: requestID) }; draft = lastQuestion; send(target: target, standard: submittedStandard) }
    func clearPrivateState() { close(); transcript.clear(); preview = ""; answer = nil; draft = ""; errorMessage = nil; lastQuestion = nil; conversation = nil; conversationID = nil; loadingHistory = false }
    var canUseSelectedMode: Bool { sourceOnly || aiPolicy?.permits(answerMode) == true }
    func send(target: Passage, standard: Bool = false) {
        guard canUseSelectedMode, !resumeInvalid, item.ranges.indices.contains(rangeIndex), !isRunning, !loadingHistory, !isCheckingStatus, !needsStatusCheck, !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, draft.utf16.count <= 2000,
              let scope = try? QuestionScope(reading: item.ranges[rangeIndex], target: target, spoilerAllowed: spoilerAllowed) else { return }
        do {
            if try PendingQuestionStore.read(owner: ownerID) != nil { errorMessage = "前の質問の返事を待っています。設定の「返事を待っている質問を確認する」で結果を確認してください。"; return }
        } catch { errorMessage = "送信済みの質問を確認できません。端末のロックを解除してください。"; return }
        // No automatic retry. Every explicit new question gets a unique request ID.
        let submittedQuestion = draft.trimmingCharacters(in: .whitespacesAndNewlines); let submittedMode = sourceOnly
        let submittedAnswerMode: AnswerMode = sourceOnly ? .reviewedClaimSelection : answerMode
        let request = UUID().uuidString; requestID = request; needsStatusCheck = false; errorMessage = nil; isRunning = true; preview = ""; status = AnswerProgress.preparing.label
        submittedStandard = standard; lastQuestion = submittedQuestion
        transcript.submit(id: request, question: submittedQuestion, standard: standard)
        let generation = gate.invalidate()
        task = Task {
            defer { if gate.accepts(generation) { isRunning = false; preview = "" } }
            do {
                try Task.checkCancellation()
                guard gate.accepts(generation) else { return }
                if conversationID == nil || currentScope != scope {
                    struct Create: Encodable, Sendable { let importId: String; let rangeIndex: Int; let passage: Passage; let spoilerAllowed: Bool }
                    let conversation: Conversation = try await client.post("/v1/conversations", body: Create(importId: item.id, rangeIndex: rangeIndex, passage: target, spoilerAllowed: scope.spoilerAllowed))
                    guard gate.accepts(generation) else { return }
                    conversationID = conversation.id; currentScope = scope
                    self.conversation = conversation
                }
                guard let conversationID else { throw NetworkFailure.invalidResponse }
                try Task.checkCancellation()
                guard gate.accepts(generation) else { return }
                let pending = PendingQuestion(ownerID: ownerID, requestID: request, conversationID: conversationID, question: submittedQuestion, sourceOnly: submittedMode, passageLabel: scope.target.label, createdAt: Date(), answerMode: submittedAnswerMode, standardExplanation: standard)
                try PendingQuestionStore.save(pending)
                needsStatusCheck = true
                try Task.checkCancellation()
                guard gate.accepts(generation) else { return }
                draft = ""
                let update: @Sendable (AnswerUpdate) -> Void = { [weak self] update in
                    Task { @MainActor in
                        guard let self, self.gate.accepts(generation), self.isRunning else { return }
                        switch update { case .progress(let stage): self.status = stage.label; case .preview(let text): self.preview = text; self.status = AnswerProgress.receiving.label }
                    }
                }
                let result: RequestResult
                if standard { result = try await client.postAnswer("/v1/conversations/\(conversationID)/explanation", body: ["requestId": request], requestID: request, update: update) }
                else { result = try await client.postAnswer("/v1/conversations/\(conversationID)/questions", body: pending.body, requestID: request, update: update) }
                guard gate.accepts(generation) else { return }
                accept(result)
            } catch {
                if gate.accepts(generation) {
                    if case NetworkFailure.server(_, let code) = error, ["ai_not_connected", "ai_consent_required", "grounded_consent_required", "answer_mode_disabled", "model_unconnected", "budget_unverified", "standard_explanation_pending", "standard_explanation_unavailable"].contains(code) {
                        do { try PendingQuestionStore.remove(owner: ownerID, request: request); needsStatusCheck = false }
                        catch { needsStatusCheck = true }
                        if ["grounded_consent_required", "answer_mode_disabled"].contains(code) { aiPolicy = nil; policyGate.invalidate() }
                    }
                    let failure = (error as? PartialAnswerFailure)?.underlying ?? (error as? NetworkFailure) ?? .invalidResponse
                    let partial = (error as? PartialAnswerFailure)?.text ?? preview
                    if !PartialAnswerFailure.mayRetain(failure) { transcript.clear(); answer = nil }
                    transcript.interrupt(id: request, text: partial, standard: standard, failure: failure)
                    errorMessage = PartialAnswerFailure.diagnostic(failure) + " 再送前に届いた回答を確認してください。"
                    status = needsStatusCheck ? "状態の確認が必要です" : "内容を保持しています。設定や送信方法を確認して再試行できます。"
                }
            }
        }
    }
    func checkStatus() async {
        guard let requestID, !isRunning, !isCheckingStatus else { return }
        let attempt = UUID(); statusAttempt = attempt
        defer { if statusAttempt == attempt { statusAttempt = nil } }
        let generation = gate.invalidate()
        do { let result: RequestResult = try await client.get("/v1/requests/\(requestID)"); guard gate.accepts(generation) else { return }; accept(result) }
        catch {
            guard gate.accepts(generation) else { return }
            if error as? NetworkFailure == .unauthenticated { answer = nil; transcript.clear() }
            if case NetworkFailure.server(_, let code) = error, ["source_policy_changed", "conversation_policy_changed", "conversation_changed"].contains(code) { answer = nil; transcript.clear() }
            if case NetworkFailure.server(status: 404, code: "not_found") = error {
                status = "まだ処理が見つかりません。重複を避けるため、新しい質問は送信せず、設定から同じ識別子で再確認してください。"
            } else { errorMessage = (error as? NetworkFailure)?.userMessage ?? "状態を確認できませんでした。" }
        }
    }
    func cancel() {
        if let requestID { transcript.interrupt(id: requestID, text: preview, standard: submittedStandard, failure: .cancelled) }
        gate.invalidate(); task?.cancel(); task = nil; isRunning = false; preview = ""
        status = "中止しました。処理や利用量が発生している場合があります。"
        guard let requestID else { return }
        Task {
            do { let _: JSONValue = try await client.delete("/v1/requests/\(requestID)"); if self.requestID == requestID { needsStatusCheck = false; try PendingQuestionStore.remove(owner: ownerID, request: requestID) } }
            catch { if self.requestID == requestID { errorMessage = "待つのをやめましたが、回答づくりが続いている可能性があります。「届いた回答を確認」で結果を確かめてください。" } }
        }
    }
    func scopeChanged() { if isRunning { cancel() }; gate.invalidate(); transcript.clear(); historyCursor = nil; preview = ""; answer = nil; conversation = nil; conversationID = nil; currentScope = nil; requestID = nil; needsStatusCheck = false; status = "" }
    func close() { policyGate.invalidate(); if isRunning { cancel() } else { gate.invalidate() } }
    private func accept(_ result: RequestResult) {
        errorMessage = nil
        if ["complete", "failed", "cancelled"].contains(result.status) {
            do { try PendingQuestionStore.remove(owner: ownerID, request: result.requestId) }
            catch { errorMessage = "端末の送信待ち情報を消去できませんでした。設定から状態を再確認してください。" }
        }
        switch result.status {
        case "complete": needsStatusCheck = false; answer = result.result; if let answer = result.result { transcript.complete(id: result.requestId, answer: answer, standard: submittedStandard) }; status = result.result == nil ? "資料の版・権利・表示範囲が変わり、この回答は表示できません。" : "回答を確認しました"
        case "cancelled": needsStatusCheck = false; status = "中止されています。利用量が発生している場合があります。"
        case "failed": needsStatusCheck = false; status = "処理に失敗しました。内容を確認して新しい質問として再試行できます。"; errorMessage = status
        default: status = "回答を作っています。「届いた回答を確認」を押すと、返事が届いたか確認できます。"
        }
    }
}
