import SwiftUI
import CompanionCore

struct ReadingAIExplanation: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var model: QuestionModel
    @State private var consentIntent: GroundedConsentIntent?
    let passage: Passage
    init(model: QuestionModel, passage: Passage) {
        self.passage = passage
        _model = StateObject(wrappedValue: model)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: BibleTheme.Space.md) {
            Text("標準解説").bibleTextStyle(.heading)
            if let answer = model.answer {
                Text(answer.answer).bibleTextStyle(.body).textSelection(.enabled)
                Text("AIの解説です。本文と出典もあわせてお確かめください。").bibleTextStyle(.caption).bibleForeground(.textSecondary)
                DisclosureGroup("出典を確かめる") { CitationList(citations: answer.citations) }
                Button("続けて質問する") { store.ask(conversation: model.conversation) }.buttonStyle(.borderedProminent)
            } else if model.isRunning {
                ProgressView("解説を準備しています")
                Button("解説の準備をやめる") { model.cancel() }
            } else if let error = model.errorMessage {
                Text(error).bibleTextStyle(.body)
                if model.needsStatusCheck { Button { Task { await model.checkStatus() } } label: { Text(model.isCheckingStatus ? "確認しています…" : "質問の状況を確認") }.disabled(model.isCheckingStatus || model.isRunning) }
                else { Button("新しい質問としてもう一度頼む") { explain() } }
                NavigationLink("送信済みの質問を確認") { PendingQuestionView(ownerID: model.ownerID, client: model.client) }
            } else if model.canUseSelectedMode {
                Button("AIで解説を読む") { explain() }.buttonStyle(.borderedProminent)
            } else if let policy = store.aiPolicy, let owner = store.account, policy.allowedAnswerModes.contains(.groundedGeneration) {
                Text("初めて解説を読む前に、質問と関連資料をCloudflareのAIへ送ることを確認できます。").bibleTextStyle(.body)
                Button("確認して解説を読む") { consentIntent = GroundedConsentIntent(ownerID: owner.id, sessionEpoch: store.sessionEpoch, policy: policy) }.buttonStyle(.borderedProminent)
            } else {
                Text(model.policyError ?? "AIに解説を頼めるか確認しています。参考資料は下から読めます。").bibleTextStyle(.body)
                Button("再確認") { Task { await prepare() } }
            }
        }
        .task { await prepare() }
        .onChange(of: model.conversation?.id) { _, _ in if store.account?.id == model.ownerID { store.questionConversation = model.conversation } }
        .sheet(item: $consentIntent, onDismiss: { Task { await prepare() } }) { GroundedConsentView(intent: $0).environmentObject(store) }
    }
    private func prepare() async {
        await store.loadAIPolicy(); await model.loadPolicy()
        if model.canUseSelectedMode && model.answer == nil && !model.needsStatusCheck { explain() }
    }
    private func explain() {
        model.draft = "この箇所の出来事と意味を、初めて読む人にも分かる日本語で短く説明してください。"
        model.send(target: passage, standard: true)
    }
}
