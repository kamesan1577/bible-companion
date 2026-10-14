import SwiftUI
import CompanionCore

struct QuestionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: QuestionModel
    @State private var target: Passage
    @State private var confirmSpoilers = false
    @State private var showSubset = false
    private let reading: Passage
    private let isResuming: Bool
    init(ownerID: String, client: APIClient, item: ImportRecord, rangeIndex: Int, target: Passage, conversation: Conversation? = nil) {
        _model = StateObject(wrappedValue: QuestionModel(ownerID: ownerID, client: client, item: item, rangeIndex: rangeIndex, conversation: conversation))
        isResuming = conversation != nil
        _target = State(initialValue: target); reading = item.ranges.indices.contains(rangeIndex) ? item.ranges[rangeIndex] : target
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                BibleReadingColumn {
                    BibleSectionHeader(title: "この箇所について質問", subtitle: target.label)
                    Picker("質問の範囲", selection: $target) {
                        Text("選択箇所全体 \(reading.reference)").tag(reading)
                        if target != reading && !reading.chapterSegments.contains(target) { Text("指定範囲 \(target.reference)").tag(target) }
                        if reading.chapterSegments.count > 1 { ForEach(reading.chapterSegments, id: \.self) { Text($0.reference).tag($0) } }
                    }.pickerStyle(.menu).disabled(model.isRunning || model.needsStatusCheck || isResuming)
                    Button("章節を指定して範囲を絞る") { showSubset = true }.disabled(model.isRunning || model.needsStatusCheck || isResuming)
                    if isResuming { Text("保存した会話の質問対象と読了位置を引き継ぎます。範囲を変える場合は読書画面から新しい会話を始めてください。").bibleTextStyle(.caption) }
                    BibleScopeNotice(text: model.spoilerAllowed ? "先の内容も含める" : "\(reading.end.label)まで · 先の内容を含めない")
                    BibleReadingSurface {
                        VStack(alignment: .leading, spacing: BibleTheme.Space.md) {
                            TextField("気になったことを入力", text: $model.draft, axis: .vertical).lineLimit(3...10).bibleTextStyle(.body).disabled(model.isRunning)
                            Text("\(model.draft.utf16.count) / 2000").bibleTextStyle(.caption).bibleForeground(.textSecondary)
                        }
                    }
                    Toggle("範囲の資料だけを確認する（AIを使わない）", isOn: $model.sourceOnly).disabled(model.isRunning)
                    if model.sourceOnly { Text("入力した質問は会話履歴に保存されますが、表示する資料は選んだ範囲に基づき、質問文に応じて変わりません。質問への回答を生成するモードではありません。").bibleTextStyle(.caption).bibleForeground(.textSecondary) }
                    if !model.sourceOnly {
                        Picker("回答方法", selection: $model.answerMode) { ForEach(AnswerMode.allCases) { mode in Text(mode.label).tag(mode).disabled(model.aiPolicy?.allowedAnswerModes.contains(mode) != true) } }.pickerStyle(.menu).disabled(model.isRunning || model.needsStatusCheck)
                        if model.answerMode == .groundedGeneration { Text(model.aiPolicy?.groundedNoticeJa ?? AnswerMode.groundedWarning).bibleTextStyle(.caption) }
                        if !model.canUseSelectedMode { Text("この回答方法のサーバー許可と送信・生成への同意が必要です。設定で確認してください。自動で別の方法には切り替えません。").bibleTextStyle(.caption) }
                        if let error = model.policyError { Text(error).bibleTextStyle(.caption) }
                        Button("利用条件を再確認") { Task { await model.loadPolicy() } }.disabled(model.isRunning)
                    }
                    if !model.sourceOnly { Text("質問と関連する読書の文脈をCloudflare Workers AIへ送信します。初回は設定で送信への同意が必要です。").bibleTextStyle(.caption).bibleForeground(.textSecondary) }
                    Toggle("先の内容も含める", isOn: Binding(get: { model.spoilerAllowed }, set: { value in if value { confirmSpoilers = true } else { model.spoilerAllowed = false; model.scopeChanged() } })).disabled(model.isRunning || model.needsStatusCheck || isResuming)
                    if model.isRunning {
                        BibleLoadingView(title: model.sourceOnly ? "範囲の資料を確認しています" : "回答を確認しています", message: model.sourceOnly ? "AIは呼び出していません。" : "回答は完成後に表示します。")
                        Button("中止する", role: .cancel) { model.cancel() }.buttonStyle(.bordered)
                    } else {
                        Button { model.send(target: target) } label: { BibleActionLabel(title: model.sourceOnly ? "選んだ範囲の資料を確認" : "質問を送信する", systemImage: BibleTheme.Symbol.question) }.buttonStyle(.glass).disabled(!model.canUseSelectedMode || model.isCheckingStatus || model.needsStatusCheck || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.draft.utf16.count > 2000)
                    }
                    if let error = model.errorMessage { BibleStateView(title: model.sourceOnly ? "資料を確認できません" : "回答を確認できません", message: error, systemImage: BibleTheme.Symbol.error) }
                    if !model.status.isEmpty { Text(model.status).bibleTextStyle(.caption).bibleForeground(.textSecondary) }
                    if model.requestID != nil && !model.isRunning { Button(model.isCheckingStatus ? "状態を確認中" : "送信済みの状態を確認") { Task { await model.checkStatus() } }.disabled(model.isCheckingStatus) }
                    if let answer = model.answer {
                        BibleSectionHeader(title: answer.modelInvoked ? "回答" : "選んだ範囲の資料", subtitle: answer.modelInvoked ? "AIによる説明" : "AI生成ではありません")
                        AnswerQualityNotice(mode: answer.mode)
                        AnswerBudgetNotice(policy: answer.budgetPolicy)
                        Text(answer.answer).bibleTextStyle(.body).textSelection(.enabled)
                        Text(answer.referenceSystem?.noticeJa ?? ReferenceSystem.fallbackNotice).bibleTextStyle(.caption).bibleForeground(.textSecondary)
                        ForEach(answer.warnings, id: \.self) { Text($0).bibleTextStyle(.caption).bibleForeground(.textSecondary) }
                        CitationList(citations: answer.citations)
                        DisclosureGroup("回答の詳細") {
                            Text("モデル: \(answer.modelId)").bibleTextStyle(.caption)
                            Text("サーバー側の処理時間（画面表示までの実測ではありません）: \(answer.timing.display)").bibleTextStyle(.caption)
                        }
                    }
                }
            }
            .bibleCanvas().navigationTitle("質問").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { model.close(); dismiss() } } }
            .sheet(isPresented: $showSubset) { PassageSubsetPicker(reading: reading, selected: target) { target = $0 } }
            .onChange(of: target) { _, _ in model.scopeChanged() }
            .task { await model.loadPolicy() }
            .onDisappear { model.close() }
            .confirmationDialog("この範囲より先の内容も表示しますか？", isPresented: $confirmSpoilers, titleVisibility: .visible) {
                Button("先の内容も含める") { model.spoilerAllowed = true; model.scopeChanged() }
                Button("キャンセル", role: .cancel) {}
            } message: { Text("読了位置より先の出来事や人物の結末を含む場合があります。") }
        }
    }
}
