import SwiftUI
import CompanionCore

@MainActor final class ComparisonModel: ObservableObject {
    struct TrialAnswer: Identifiable { let id: Int; let answer: AnswerResult }
    @Published private(set) var pending: PendingComparison?
    @Published private(set) var state: ComparisonState?
    @Published private(set) var answers: [TrialAnswer] = []
    @Published private(set) var presentationPlan: JSONValue?
    @Published private(set) var busy = false
    @Published private(set) var storageBlocked = false
    @Published private(set) var recoveryID: String?
    @Published private(set) var message: String?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    let ownerID: String
    let client: APIClient
    init(ownerID: String, client: APIClient) { self.ownerID = ownerID; self.client = client }
    func restore() {
        guard !busy else { return }
        do {
            pending = try ComparisonStore.read(owner: ownerID)
            storageBlocked = false; recoveryID = nil
            if pending != nil { message = "確認待ちの比較があります。状態を確認してから再開できます。保存しなかった回答本文は復元できません。" }
            else if state == nil { checkActive() }
        } catch { recoveryID = try? ComparisonStore.recoveryRequestID(owner: ownerID); storageBlocked = true; message = "保存した比較情報を読めません。元の識別子は保持しています。ロック解除またはアプリ更新後に確認してください。" }
    }
    func checkActive() {
        guard !busy else { return }
        launch { generation in
            let response: ActiveComparisonResponse = try await self.client.get("/v1/developer/comparisons/active")
            try Task.checkCancellation()
            guard self.generation == generation else { return }
            if let active = response.comparison {
                guard UUID(uuidString: active.requestId) != nil else { throw NetworkFailure.invalidResponse }
                self.state = active
                self.message = "サーバーに実行中の比較があります。この端末に元の計画がないため、状態確認または中止ができます。"
            }
        }
    }
    func start(plan: JSONValue, hash: String) {
        guard !busy, pending == nil, !storageBlocked, state == nil || state?.isTerminal == true else { return }
        do {
            let frozen = try PendingComparison(ownerID: ownerID, plan: plan, confirmationHash: hash)
            try ComparisonStore.save(frozen); pending = frozen; state = nil; answers = []; presentationPlan = frozen.plan
            startOrRecover(runSteps: true)
        } catch { message = "比較情報を保存できません。未確認の比較を先に確認してください。" }
    }
    func startOrRecover(runSteps: Bool = false) {
        guard let pending, !busy else { return }
        presentationPlan = pending.plan
        launch { generation in
            let state: ComparisonState = try await self.client.post("/v1/developer/comparisons", body: pending.startBody)
            try self.accept(state, pending: pending, generation: generation)
            if runSteps { try await self.advance(pending, generation: generation) }
        }
    }
    func check() {
        guard !busy, let request = pending?.requestID ?? state?.requestId else { return }
        let frozen = pending
        clearBodies()
        launch { generation in
            let state: ComparisonState = try await self.client.get("/v1/developer/comparisons/\(request)")
            if let frozen { try self.accept(state, pending: frozen, generation: generation) }
            else { try Task.checkCancellation(); guard self.generation == generation, state.requestId == request else { return }; self.state = state }
        }
    }
    func resume() {
        guard let pending, !busy else { return }
        clearBodies()
        launch { generation in
            let state: ComparisonState = try await self.client.get("/v1/developer/comparisons/\(pending.requestID)")
            try self.accept(state, pending: pending, generation: generation)
            try await self.advance(pending, generation: generation)
        }
    }
    func cancel() {
        guard let request = pending?.requestID ?? state?.requestId else { return }
        let frozen = pending
        pause()
        launch { generation in
            let _: JSONValue = try await self.client.delete("/v1/developer/comparisons/\(request)")
            let state: ComparisonState = try await self.client.get("/v1/developer/comparisons/\(request)")
            if let frozen { try self.accept(state, pending: frozen, generation: generation) }
            else { try Task.checkCancellation(); guard self.generation == generation, state.requestId == request, state.isTerminal else { throw NetworkFailure.invalidResponse }; self.state = state }
            self.message = "中止を受け付けました。既に実行した分の利用量が発生している場合があります。"
        }
    }
    func cancelRecovered() {
        guard let request = recoveryID, !busy else { return }
        launch { generation in
            let _: JSONValue = try await self.client.delete("/v1/developer/comparisons/\(request)")
            let result: ComparisonState = try await self.client.get("/v1/developer/comparisons/\(request)")
            try Task.checkCancellation()
            guard self.generation == generation, result.requestId == request, result.isTerminal else { throw NetworkFailure.invalidResponse }
            try ComparisonStore.removeRecovered(owner: self.ownerID, requestID: request)
            self.recoveryID = nil; self.storageBlocked = false; self.message = "元の比較を終了し、確認待ち情報を整理しました。"
        }
    }
    func clearPresentationForScopeChange() {
        pause(); clearBodies(); presentationPlan = nil
        if state?.isTerminal == true { state = nil }
    }
    private func clearBodies() { answers = []; state = state?.withoutResultBodies }
    func pause() { generation = UUID(); task?.cancel(); task = nil; busy = false }
    private func advance(_ pending: PendingComparison, generation: UUID) async throws {
        while let state {
            let current = self.pending ?? pending
            guard let index = try current.nextTrial(in: state) else { return }
            try Task.checkCancellation()
            guard self.generation == generation else { throw CancellationError() }
            var sending = self.pending ?? pending; sending.attemptedTrialIndex = index
            try ComparisonStore.save(sending); self.pending = sending
            let step: ComparisonStepResponse = try await client.post("/v1/developer/comparisons/\(pending.requestID)/steps", body: pending.stepBody(index: index))
            guard step.trialIndex == index else { throw NetworkFailure.invalidResponse }
            try Task.checkCancellation(); guard self.generation == generation else { throw CancellationError() }
            try pending.validate(step.state)
            guard try pending.acknowledges(trial: index, in: step.state) else {
                self.state = step.state
                throw NetworkFailure.server(status: 409, code: "trial_acknowledgment_pending")
            }
            var acknowledged = pending; acknowledged.attemptedTrialIndex = nil
            try ComparisonStore.save(acknowledged); self.pending = acknowledged
            try accept(step.state, pending: pending, generation: generation)
            if let answer = step.result, !answers.contains(where: { $0.id == index }) { answers.append(TrialAnswer(id: index, answer: answer)) }
            if step.resultAvailability == "not_saved" { message = "受け付け済みの試行です。保存しなかった回答本文は再取得できません。新しい推論は実行していません。" }
        }
    }
    private func accept(_ state: ComparisonState, pending: PendingComparison, generation: UUID) throws {
        try Task.checkCancellation()
        guard self.generation == generation else { throw CancellationError() }
        try pending.validate(state); presentationPlan = pending.plan
        if state.errorCode == "source_policy_changed" { clearBodies(); self.state = state.withoutResultBodies } else { self.state = state }
        if state.isTerminal {
            try ComparisonStore.remove(owner: ownerID, requestID: pending.requestID); self.pending = nil
            message = state.terminalMessage
        }
    }
    private func launch(_ operation: @escaping @MainActor (UUID) async throws -> Void) {
        let current = UUID(); generation = current; busy = true; message = nil
        task = Task {
            defer { if generation == current { busy = false } }
            do { try await operation(current) }
            catch {
                guard generation == current else { return }
                if case NetworkFailure.server(_, let code) = error, ["source_policy_changed", "conversation_policy_changed"].contains(code) { clearBodies() }
                if error as? NetworkFailure == .unauthenticated { clearBodies() }
                if case NetworkFailure.server(status: 404, code: "not_found") = error {
                    message = "開始処理はまだ見つかりません。同じ識別子で開始状態を確認できます。新しい比較として送信し直しません。"
                } else {
                    if case NetworkFailure.server(_, let code) = error, code == "comparison_budget_exceeded" {
                        message = NetworkFailure.server(status: 429, code: code).userMessage + " 元の比較の中止を確認してから、新しい計画を作ってください。"
                    } else { message = ((error as? NetworkFailure)?.userMessage ?? "処理の完了を確認できませんでした。") + " 自動で繰り返さず、状態確認を待っています。" }
                }
            }
        }
    }
}
