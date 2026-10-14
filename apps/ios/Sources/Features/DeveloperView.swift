import SwiftUI
import CompanionCore

struct DeveloperView: View {
    @EnvironmentObject private var store: AppStore
    let client: APIClient
    @StateObject private var comparison: ComparisonModel
    init(ownerID: String, client: APIClient) { self.client = client; _comparison = StateObject(wrappedValue: ComparisonModel(ownerID: ownerID, client: client)) }
    @State private var catalog: JSONValue = .null
    @State private var first = ""
    @State private var second = ""
    @State private var firstMode: AnswerMode = .reviewedClaimSelection
    @State private var secondMode: AnswerMode = .reviewedClaimSelection
    @State private var questions = ""
    @State private var maxTokens = 512
    @State private var temperature = 0.2
    @State private var timeoutMs = 15000
    @State private var saveResults = false
    @State private var planDraft = ComparisonPlanDraft()
    private var pendingPlan: JSONValue? { planDraft.plan }
    private var estimate: JSONValue? { planDraft.estimate }
    private var jobID: String? { comparison.pending?.requestID ?? (comparison.state?.isTerminal == false ? comparison.state?.requestId : nil) }
    private var operationBusy: Bool { busy || comparison.busy }
    @State private var busy = false
    @State private var viewActive = false
    @State private var operationGeneration = UUID()
    @State private var message: String?
    @State private var confirmRun = false
    private var models: [JSONValue] { catalog["models"].array }
    private var enabledModels: [JSONValue] { models.filter { $0["enabled"].bool == true } }
    private var selectedModels: [JSONValue] { models.filter { [first, second].contains($0["id"].string ?? "") } }
    private var bounds: ModelSettingsBounds? { try? ModelSettingsBounds(models: selectedModels) }
    private var modesPermitted: Bool { store.aiPolicy?.permits(firstMode) == true && store.aiPolicy?.permits(secondMode) == true }
    private var duplicateConfiguration: Bool { first == second && firstMode == secondMode }
    private var validSettings: Bool { bounds?.accepts(tokens: maxTokens, temperature: temperature, timeout: timeoutMs) == true }
    private var tokenChoices: [Int] { guard let bounds else { return [] }; return Array(Set([bounds.outputTokens.lowerBound, bounds.outputTokens.upperBound, 128, 256, 512, 1024, 2048].filter(bounds.outputTokens.contains))).sorted() }
    private var formContent: some View {
        Form {
            if store.account?.canDebug != true {
                BibleStateView(title: "開発用アカウント専用です", message: "このアカウントではモデルの設定を変更できません。")
            } else {
                modelSection
                comparisonSection
                if let message { Section { Text(message).bibleTextStyle(.body) } }
            }
        }
    }
    private var lifecycleContent: some View {
        formContent
        .id(store.sessionEpoch)
        .bibleCanvas().navigationTitle("開発者用デバッグ").bibleDeveloperTint()
        .task { guard store.account?.canDebug == true else { return }; viewActive = true; comparison.restore(); await store.loadAIPolicy(); await perform { epoch, operation in let value: JSONValue = try await client.get("/v1/developer/models"); guard isCurrent(epoch), operationGeneration == operation else { return }; catalog = value } }
        .confirmationDialog("この内容で比較しますか？", isPresented: $confirmRun, titleVisibility: .visible) { Button("比較を開始") { runComparison() } } message: {
            Text("対象：\(frozenPassageLabel)。2つの設定へ\(pendingPlan?["questions"].array.count ?? 0)問を送信します。回答方法: \(pendingPlan.map(modeLabels) ?? "未確認")。予約枠は\(estimate?["reservedBudgetUnits"].display ?? "未確認")です。\(pendingPlan?["saveResults"].bool == true ? "結果は自分のアカウントに保存します。" : "結果本文は保存せず、この画面でのみ確認します。")")
        }
        .onDisappear { viewActive = false; operationGeneration = UUID(); busy = false; comparison.pause(); invalidatePlan() }
    }
    var body: some View {
        lifecycleContent
        .onChange(of: store.selectedPassage) { _, _ in invalidatePlan(); comparison.clearPresentationForScopeChange() }
        .onChange(of: first) { _, _ in clampSettings(); invalidatePlan() }.onChange(of: second) { _, _ in clampSettings(); invalidatePlan() }
        .onChange(of: firstMode) { _, _ in invalidatePlan() }.onChange(of: secondMode) { _, _ in invalidatePlan() }
        .onChange(of: store.aiPolicy?.groundedPolicyVersion) { _, _ in invalidatePlan() }.onChange(of: store.aiPolicy?.workersAiConsent) { _, _ in invalidatePlan() }.onChange(of: store.aiPolicy?.groundedConsent.accepted) { _, _ in invalidatePlan() }
        .onChange(of: store.aiPolicy?.allowedAnswerModes) { _, _ in invalidatePlan() }
        .onChange(of: store.aiPolicy?.groundedConsent.policyVersion) { _, _ in invalidatePlan() }
        .onChange(of: questions) { _, _ in invalidatePlan() }.onChange(of: saveResults) { _, _ in invalidatePlan() }
        .onChange(of: maxTokens) { _, _ in invalidatePlan() }.onChange(of: temperature) { _, _ in invalidatePlan() }.onChange(of: timeoutMs) { _, _ in invalidatePlan() }
    }
    private var modelSection: some View {
Section("モデル") {
                    ForEach(models, id: \.self) { model in
                        DisclosureGroup {
                            DeveloperModelDetails(model: model)
                        } label: {
                            VStack(alignment: .leading, spacing: BibleTheme.Space.xs) {
                                Text(model["displayName"].string ?? "モデル")
                                Text(model["enabled"].bool == true ? "選択可能（送信前に利用枠を確認）" : AIAvailabilityExplanation.catalogReason(model["disabledReason"].string)).bibleTextStyle(.caption).bibleForeground(.textSecondary)
                            }
                        }
                    }
                    Text("候補一覧は接続済みを意味しません。選択可能でも、質問や比較ごとの利用枠確認が必要です。有料・未検証モデルへの自動切り替えはありません。").bibleTextStyle(.caption)
                    modelPicker("通常のモデル / 比較A", selection: $first)
                    Picker("最大出力トークン", selection: $maxTokens) { ForEach(tokenChoices, id: \.self) { Text(String($0)).tag($0) } }.disabled(operationBusy || jobID != nil)
                    Stepper("Temperature \(temperature, specifier: "%.1f")", value: $temperature, in: bounds?.temperature ?? 0...0, step: 0.1).disabled(operationBusy || jobID != nil)
                    Stepper("タイムアウト \(timeoutMs / 1000)秒", value: $timeoutMs, in: bounds?.timeoutMilliseconds ?? 15000...15000, step: 1000).disabled(operationBusy || jobID != nil || bounds == nil)
                    Button("以後の回答に適用") { setPreference() }.disabled(first.isEmpty || operationBusy || !validSettings)
                    Button("既定のモデルへ戻す") { Task { await perform { epoch, operation in try await client.empty("/v1/developer/model-preference", method: "DELETE"); guard isCurrent(epoch), operationGeneration == operation else { return }; message = "既定値へ戻しました。過去の回答は変わりません。" } } }.disabled(operationBusy)
                    Text("回答は完了したJSONで受け取ります。未検証の推論パラメーターは送信しません。").bibleTextStyle(.caption)
                }
    }
    private var comparisonSection: some View {
Section("2つの設定を比較") {
                    if let frozen = comparison.pending { Text("実行中の対象: \(passageLabel(frozen.plan))") } else if jobID != nil { Text("実行中の比較の対象は保存した計画に従います。") } else if let passage = store.selectedPassage { Text("次の比較の対象: \(passage.label)") } else { Text("先に読書画面で箇所を選んでください。") }
                    Picker("比較Aの回答方法", selection: $firstMode) { ForEach(AnswerMode.allCases) { mode in Text(mode.label).tag(mode).disabled(store.aiPolicy?.allowedAnswerModes.contains(mode) != true) } }.disabled(operationBusy || jobID != nil)
                    modelPicker("比較B", selection: $second)
                    Picker("比較Bの回答方法", selection: $secondMode) { ForEach(AnswerMode.allCases) { mode in Text(mode.label).tag(mode).disabled(store.aiPolicy?.allowedAnswerModes.contains(mode) != true) } }.disabled(operationBusy || jobID != nil)
                    if firstMode == .groundedGeneration || secondMode == .groundedGeneration { Text(store.aiPolicy?.groundedNoticeJa ?? AnswerMode.groundedWarning).bibleTextStyle(.caption) }
                    if !modesPermitted { Text(store.aiPolicyError ?? "選んだ回答方法の許可と同意状況を設定で確認してください。別の方法への自動切り替えはしません。").bibleTextStyle(.caption) }
                    Button("回答方法の利用条件を再確認") { Task { await store.loadAIPolicy() } }.disabled(operationBusy)
                    TextField("比較する質問（1行1問・最大10問）", text: $questions, axis: .vertical).lineLimit(3...10).disabled(operationBusy || jobID != nil)
                    Toggle("比較結果を自分のアカウントへ保存する", isOn: $saveResults).disabled(operationBusy || jobID != nil)
                    Button("比較内容と概算を確認") { planComparison() }.disabled(operationBusy || first.isEmpty || second.isEmpty || duplicateConfiguration || !modesPermitted || store.selectedPassage == nil || questionLines.isEmpty || questionLines.count > 10 || jobID != nil || comparison.storageBlocked || !validSettings)
                    Text("質問をCloudflare Workers AIへ送ります。最大2設定×10問を順番に実行。自動再試行はしません。").bibleTextStyle(.caption)
                    if let estimate {
                        LabeledContent("呼び出し回数", value: estimate["trialCount"].display)
                        LabeledContent("概算予約枠", value: estimate["reservedBudgetUnits"].display)
                        Text(estimate["budgetBoundVerified"].bool == true ? "予約上限は検証済みです。" : "予約量は推定です。無料枠の停止条件と残量を確認してください。").bibleTextStyle(.caption)
                        ForEach(estimate["reservationWarnings"].array, id: \.self) { Text($0.string ?? "予算上の注意事項があります。").bibleTextStyle(.caption) }
                        Button("この内容で比較する") { confirmRun = true }.disabled(operationBusy || pendingPlan == nil)
                    }
                    if let pending = comparison.pending {
                        Text("再開する比較の回答方法: \(modeLabels(pending.plan))").bibleTextStyle(.caption)
                        if pending.plan["models"].array.contains(where: { $0["answerMode"].string == AnswerMode.groundedGeneration.rawValue }) { AnswerQualityNotice(mode: AnswerMode.groundedGeneration.rawValue) }
                    }
                    if jobID != nil {
                        if let state = comparison.state { Text("\(state.completedCount) / \(state.trialCount) 試行完了・\(ComparisonDisplay.phase(state.phase))").bibleTextStyle(.caption) }
                        Button("比較の状態を確認") { comparison.check() }.disabled(operationBusy)
                        if comparison.pending != nil && (comparison.state == nil || comparison.state?.phase == "preparing") {
                            Button("同じ識別子で開始状態を再確認") { comparison.startOrRecover() }.disabled(operationBusy)
                        }
                        if comparison.pending != nil && comparison.state?.phase == "ready" {
                            Button("確認済みの次の試行から再開") { comparison.resume() }.disabled(operationBusy)
                        }
                        Button("比較を中止", role: .cancel) { comparison.cancel() }
                        Text("再開時も元の比較内容・識別子・試行番号を使い、同じ推論の重複実行を防ぎます。状態を再確認すると、未保存の回答本文は画面から消去され、復元できません。").bibleTextStyle(.caption)
                    }
                    if comparison.storageBlocked { Button("保存した比較情報を再確認") { comparison.restore() }.disabled(operationBusy) }
                    if comparison.recoveryID != nil { Button("元の比較を中止して整理", role: .cancel) { comparison.cancelRecovered() }.disabled(operationBusy) }
                    if operationBusy { ProgressView("比較の処理を確認しています") }
                    if let notice = comparison.message { Text(notice).bibleTextStyle(.body) }
                    ForEach(comparison.answers) { trial in
                        DisclosureGroup("試行 \(trial.id + 1)・\(trial.answer.modelId)") {
                            if let plan = comparison.presentationPlan { Text("この結果の対象: \(resultPassageLabel(plan, trial: trial.id))").bibleTextStyle(.caption) }
                            AnswerQualityNotice(mode: trial.answer.mode)
                            AnswerBudgetNotice(policy: trial.answer.budgetPolicy)
                            Text(trial.answer.answer).bibleTextStyle(.body).textSelection(.enabled)
                            Text(trial.answer.referenceSystem?.noticeJa ?? ReferenceSystem.fallbackNotice).bibleTextStyle(.caption)
                            CitationList(citations: trial.answer.citations)
                        }
                    }
                    if let saved = comparison.state?.results, saved != .null {
                        DisclosureGroup("保存された比較の詳細") { Text(saved.display).bibleTextStyle(.caption).textSelection(.enabled) }
                    }
                }
    }
    private var frozenPassageLabel: String { pendingPlan.map(passageLabel) ?? "未確認" }
    private func passageLabel(_ plan: JSONValue) -> String {
        guard let value = plan["questions"].array.first?["passage"], let data = try? JSONEncoder().encode(value), let passage = try? JSONDecoder().decode(Passage.self, from: data) else { return "未確認" }
        return passage.label
    }
    private func resultPassageLabel(_ plan: JSONValue, trial: Int) -> String {
        let count = plan["models"].array.count
        guard count > 0, plan["questions"].array.indices.contains(trial / count), let data = try? JSONEncoder().encode(plan["questions"].array[trial / count]["passage"]), let passage = try? JSONDecoder().decode(Passage.self, from: data) else { return "未確認" }
        return passage.label
    }
    private var questionLines: [String] { questions.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
    private var settings: JSONValue { .object(["maxOutputTokens": .number(Double(maxTokens)), "temperature": .number(temperature), "timeoutMs": .number(Double(timeoutMs)), "stream": .bool(false)]) }
    private func modelPicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) { Text("選んでください").tag(""); ForEach(enabledModels, id: \.self) { model in Text(model["displayName"].string ?? "モデル").tag(model["id"].string ?? "") } }.disabled(operationBusy || jobID != nil)
    }
    private func clampSettings() {
        guard let bounds else { return }
        maxTokens = min(max(maxTokens, bounds.outputTokens.lowerBound), bounds.outputTokens.upperBound)
        temperature = min(max(temperature, bounds.temperature.lowerBound), bounds.temperature.upperBound)
        timeoutMs = min(max(timeoutMs, bounds.timeoutMilliseconds.lowerBound), bounds.timeoutMilliseconds.upperBound)
    }
    private func invalidatePlan() { planDraft.invalidate() }
    private func setPreference() {
        guard validSettings else { return }
        let preference = JSONValue.object(["modelId": .string(first), "settings": settings])
        Task { await perform { epoch, operation in let _: JSONValue = try await client.put("/v1/developer/model-preference", body: preference); guard isCurrent(epoch), operationGeneration == operation else { return }; message = "以後の回答に適用しました。過去の回答は変わりません。" } }
    }
    private func modeLabels(_ plan: JSONValue) -> String { plan["models"].array.map { AnswerMode(rawValue: $0["answerMode"].string ?? "reviewed-claim-selection")?.label ?? "未対応の回答方法" }.joined(separator: " / ") }
    private func planComparison() {
        guard modesPermitted, !duplicateConfiguration else { message = "回答方法の許可と同意状況を再確認してください。"; return }
        guard let passage = store.selectedPassage, questionLines.allSatisfy({ $0.utf16.count <= 2000 }), let data = try? JSONEncoder().encode(passage), let passageJSON = try? JSONDecoder().decode(JSONValue.self, from: data) else { message = "章節と各質問の長さを確認してください。"; return }
        let plan = JSONValue.object(["requestId": .string(UUID().uuidString), "models": .array([(first, firstMode), (second, secondMode)].map { .object(["modelId": .string($0.0), "settings": settings, "answerMode": .string($0.1.rawValue)]) }), "questions": .array(questionLines.map { .object(["passage": passageJSON, "question": .string($0), "spoilerAllowed": .bool(false)]) }), "saveResults": .bool(saveResults)])
        let generation = planDraft.begin()
        Task { await perform { epoch, operation in let response: JSONValue = try await client.post("/v1/developer/comparisons/plan", body: plan); guard isCurrent(epoch), operationGeneration == operation else { return }; planDraft.accept(plan: plan, estimate: response, generation: generation) } }
    }
    private func runComparison() {
        guard let pendingPlan, let hash = estimate?["confirmationHash"].string else { return }
        comparison.start(plan: pendingPlan, hash: hash)
        planDraft.invalidate()
    }
    private func isCurrent(_ epoch: UUID) -> Bool { viewActive && !Task.isCancelled && store.sessionEpoch == epoch && store.account?.id == comparison.ownerID && !store.isTransitioning }
    private func perform(_ action: (UUID, UUID) async throws -> Void) async {
        let epoch = store.sessionEpoch
        guard !busy, isCurrent(epoch) else { return }
        let operation = UUID(); operationGeneration = operation; busy = true; message = nil
        defer { if operationGeneration == operation { busy = false } }
        do { try Task.checkCancellation(); try await action(epoch, operation) }
        catch { if isCurrent(epoch), operationGeneration == operation { message = (error as? NetworkFailure)?.userMessage ?? "確認できませんでした。再実行前に状態を確認してください。" } }
    }
}

private struct DeveloperModelDetails: View {
    let model: JSONValue
    var body: some View {
        VStack(alignment: .leading) {

                            LabeledContent("接続", value: model["connectionStatus"].display)
                            LabeledContent("実行検証", value: model["runtimeValidation"].display)
                            LabeledContent("利用区分", value: model["billingTier"].display)
                            LabeledContent("モデル規約の確認", value: model["termsReview"]["status"].string == "reviewed" ? "サーバーで確認済み" : "未確認・利用不可")
                            Text("この画面では規約への同意や有料利用の承認は行いません。").bibleTextStyle(.caption)
                            LabeledContent("予算方式", value: model["budgetReadiness"]["budgetMode"].string == "free-provider-hard-stop" ? "無料枠・事業者側停止" : (model["budgetReadiness"]["budgetMode"].string == "strict-proof" ? "上限の検証資料を必須とする方式" : "未確認"))
                            LabeledContent("予算の準備", value: model["budgetReadiness"]["ready"].bool == true ? "方式の準備を確認済み" : AIAvailabilityExplanation.catalogReason(model["budgetReadiness"]["reason"].string))
                            Text(model["budgetReadiness"]["budgetBoundVerified"].bool == true ? "予約上限の検証資料があります。" : (model["budgetReadiness"]["ready"].bool == true ? "予約量は推定です。厳密な上限が証明されたことを意味しません。" : "予約上限の検証状況は未確認です。")).bibleTextStyle(.caption)
                            if model["budgetReadiness"]["preparedRequestBudgetRequired"].bool == true { Text("この表示はモデルを選択するための準備状況です。実際の質問文・出典・出力上限から、送信ごとに利用枠を確認します。").bibleTextStyle(.caption) }
                            ForEach(model["budgetReadiness"]["warnings"].array, id: \.self) { Text($0.string == "EXACT_REQUEST_BUDGET_CHECK_REQUIRED" ? "実際のリクエストごとに利用枠の確認が必要です。" : ($0.string ?? "予算上の注意事項を確認してください。")).bibleTextStyle(.caption) }
                            LabeledContent("文脈上限", value: model["contextWindowTokens"].display)
                            LabeledContent("推論制御", value: model["reasoningControl"].display)
                            LabeledContent("出力上限", value: "\(model["settingsSchema"]["maxOutputTokens"]["minimum"].display)–\(model["settingsSchema"]["maxOutputTokens"]["maximum"].display)")
                            Text("カタログにある機能と、このアプリで検証済みの実行方法は別です。未検証パラメーターは送信しません。").bibleTextStyle(.caption)
                            if let raw = model["officialUrl"].string, let url = URL(string: raw), url.scheme == "https", url.user == nil, url.password == nil { Link("公式モデル情報", destination: url) }

        }
    }
}
