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
                Text("AIによる解説です。出典と本文を確かめながらお読みください。").bibleTextStyle(.caption).bibleForeground(.textSecondary)
                DisclosureGroup("出典を確かめる") { CitationList(citations: answer.citations) }
                Button("続けて質問する") { store.ask(conversation: model.conversation) }.buttonStyle(.borderedProminent)
            } else if model.isRunning {
                ProgressView("解説を作っています")
                Button("中止") { model.cancel() }
            } else if let error = model.errorMessage {
                Text(error).bibleTextStyle(.body)
                if model.needsStatusCheck { Button("届いた回答を確認") { Task { await model.checkStatus() } } }
                else { Button("もう一度解説する") { explain() } }
                NavigationLink("送信済みの質問を確認") { PendingQuestionView(ownerID: model.ownerID, client: model.client) }
            } else if model.canUseSelectedMode {
                Button("AIで解説を読む") { explain() }.buttonStyle(.borderedProminent)
            } else if let policy = store.aiPolicy, let owner = store.account, policy.allowedAnswerModes.contains(.groundedGeneration) {
                Text("初回だけ、質問と関連資料をCloudflareのAIへ送ることを確認します。").bibleTextStyle(.body)
                Button("確認して解説を読む") { consentIntent = GroundedConsentIntent(ownerID: owner.id, sessionEpoch: store.sessionEpoch, policy: policy) }.buttonStyle(.borderedProminent)
            } else {
                Text(model.policyError ?? "AIの準備状況を確認しています。参考資料は下から読めます。").bibleTextStyle(.body)
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
