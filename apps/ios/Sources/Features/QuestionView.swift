import SwiftUI
import CompanionCore

struct QuestionView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: QuestionModel
    @State private var target: Passage
    @State private var confirmSpoilers = false
    @State private var showScopeInfo = false
    @State private var showSubset = false
    @State private var consentIntent: GroundedConsentIntent?
    private let reading: Passage
    private let isResuming: Bool
    init(ownerID: String, client: APIClient, item: ImportRecord, rangeIndex: Int, target: Passage, conversation: Conversation? = nil) {
        _model = StateObject(wrappedValue: QuestionModel(ownerID: ownerID, client: client, item: item, rangeIndex: rangeIndex, conversation: conversation))
        isResuming = conversation != nil
        _target = State(initialValue: target)
        reading = item.ranges.indices.contains(rangeIndex) ? item.ranges[rangeIndex] : target
    }
    private var canSend: Bool { model.canUseSelectedMode && !model.isRunning && !model.isCheckingStatus && !model.needsStatusCheck && !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.draft.utf16.count <= 2000 }
    var body: some View {
        NavigationStack {
            ScrollView {
                BibleReadingColumn {
                    Text(target.label).bibleTextStyle(.verseReference)
                    HStack {
                        Toggle("ネタバレ防止", isOn: Binding(get: { !model.spoilerAllowed }, set: { prevent in if prevent { model.spoilerAllowed = false; model.scopeChanged() } else { confirmSpoilers = true } })).disabled(model.isRunning || model.needsStatusCheck || isResuming)
                        Button { showScopeInfo = true } label: { Image(systemName: "info.circle") }.accessibilityLabel("ネタバレ防止について")
                    }
                    if !model.canUseSelectedMode {
                        Text("初回だけ、AIへの送信を確認します。").bibleTextStyle(.body)
                        if let policy = store.aiPolicy, let owner = store.account, policy.allowedAnswerModes.contains(.groundedGeneration) {
                            Button("確認して質問する") { consentIntent = GroundedConsentIntent(ownerID: owner.id, sessionEpoch: store.sessionEpoch, policy: policy) }.buttonStyle(.borderedProminent)
                        } else { Text(model.policyError ?? "AIの準備状況を確認しています。").bibleTextStyle(.caption); Button("再確認") { Task { await model.loadPolicy() } } }
                    }
                    if model.answer == nil && !model.isRunning {
                        Text("気になったことを聞いてください。").bibleTextStyle(.body)
                        Button("登場人物は誰？") { model.draft = "この箇所に登場する人物と、その役割を教えてください。" }
                        Button("背景を教えて") { model.draft = "この箇所の背景を、やさしく説明してください。" }
                    }
                    if model.isRunning { ProgressView("回答を考えています"); Button("中止") { model.cancel() } }
                    if let error = model.errorMessage { Text(error).bibleTextStyle(.body) }
                    if model.needsStatusCheck { Button(model.isCheckingStatus ? "確認中" : "送信した回答を確認") { Task { await model.checkStatus() } }.disabled(model.isCheckingStatus || model.isRunning) }
                    if let answer = model.answer {
                        Text(answer.answer).bibleTextStyle(.body).textSelection(.enabled)
                        Text("AIによる回答 · 本文と出典を確かめてください").bibleTextStyle(.caption).bibleForeground(.textSecondary)
                        DisclosureGroup("出典") { CitationList(citations: answer.citations) }
                    }
                    DisclosureGroup("質問する箇所を変更") {
                        Picker("箇所", selection: $target) {
                            Text(reading.reference).tag(reading)
                            if target != reading && !reading.chapterSegments.contains(target) { Text(target.reference).tag(target) }
                            if reading.chapterSegments.count > 1 { ForEach(reading.chapterSegments, id: \.self) { Text($0.reference).tag($0) } }
                        }.pickerStyle(.menu).disabled(model.isRunning || model.needsStatusCheck || isResuming)
                        Button("章節を指定") { showSubset = true }.disabled(model.isRunning || model.needsStatusCheck || isResuming)
                    }
                    if store.account?.canDebug == true {
                        DisclosureGroup {
                            Picker("回答方法", selection: $model.answerMode) { ForEach(AnswerMode.allCases) { Text($0.label).tag($0) } }.disabled(model.isRunning || model.needsStatusCheck)
                            Toggle("AIを呼ばず参考資料を表示", isOn: $model.sourceOnly).disabled(model.isRunning)
                            if let answer = model.answer { Text("モデル: \(answer.modelId)").bibleTextStyle(.caption); AnswerBudgetNotice(policy: answer.budgetPolicy) }
                        } label: { Label("開発者用デバッグ", systemImage: "ladybug.fill").bibleForeground(.danger) }
                    }
                }
            }.bibleCanvas().navigationTitle("質問").navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom) { composer }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("閉じる") { model.close(); dismiss() } }
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("送信") { model.send(target: target) }.disabled(!canSend) }
                }
                .sheet(isPresented: $showSubset) { PassageSubsetPicker(reading: reading, selected: target) { target = $0 } }
                .sheet(item: $consentIntent, onDismiss: { Task { await model.loadPolicy() } }) { GroundedConsentView(intent: $0).environmentObject(store) }
                .onChange(of: target) { _, _ in model.scopeChanged() }
                .task { await store.loadAIPolicy(); await model.loadPolicy() }
                .onDisappear { model.close() }
                .alert("ネタバレ防止", isPresented: $showScopeInfo) { Button("わかった") {} } message: { Text("\(reading.end.label)より先の出来事を回答に含めないようにします。AIが誤って暗示する可能性はあるため、本文も確認してください。") }
                .confirmationDialog("ネタバレ防止をオフにしますか？", isPresented: $confirmSpoilers, titleVisibility: .visible) { Button("オフにする") { model.spoilerAllowed = true; model.scopeChanged() }; Button("キャンセル", role: .cancel) {} }
        }
    }
    private var composer: some View {
        HStack(alignment: .bottom, spacing: BibleTheme.Space.sm) {
            TextField("質問を入力", text: $model.draft, axis: .vertical).lineLimit(1...4).bibleTextStyle(.body).disabled(model.isRunning).submitLabel(.send).onSubmit { if canSend { model.send(target: target) } }
            Button { model.send(target: target) } label: { Image(systemName: "arrow.up.circle.fill").bibleTextStyle(.title).frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("質問を送る").disabled(!canSend)
        }.padding(BibleTheme.Space.md).bibleCanvas()
    }
}
