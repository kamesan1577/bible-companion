import SwiftUI
import CompanionCore

struct ChatMessagesView: View {
    let entries: [ChatEntry]
    var body: some View {
        LazyVStack(alignment: .leading, spacing: BibleTheme.Space.lg) {
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: BibleTheme.Space.sm) {
                    Text(entry.role == "user" ? "あなた" : entry.standard ? "最初の解説" : "聖書コンパニオン")
                        .bibleTextStyle(.caption).foregroundStyle(.secondary)
                    Text(entry.text).bibleTextStyle(.body).textSelection(.enabled)
                    if entry.incomplete == true {
                        Label("未完了の部分回答です。全体の確認と保存は完了していません。", systemImage: "exclamationmark.circle").bibleTextStyle(.caption)
                        if let reason = entry.failureReason { Text(reason).bibleTextStyle(.caption) }
                    }
                    if let answer = entry.answer, !answer.citations.isEmpty {
                        DisclosureGroup("出典を確かめる") {
                            ForEach(answer.citations) { citation in
                                VStack(alignment: .leading) {
                                    Text(citation.title).bibleTextStyle(.caption)
                                    if let url = citation.safeURL { Link("出典を開く", destination: url).bibleTextStyle(.caption) }
                                }
                            }
                        }.bibleTextStyle(.caption)
                    }
                }
                .padding(BibleTheme.Space.md)
                .frame(maxWidth: entry.role == "user" ? 300 : .infinity, alignment: .leading)
                .background(entry.role == "user" ? Color.secondary.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 18))
                .frame(maxWidth: .infinity, alignment: entry.role == "user" ? .trailing : .leading)
                .id(entry.id)
            }
        }
    }
}
struct ChatWaitingView: View {
    let status: String
    let preview: String
    var body: some View {
        VStack(alignment: .leading, spacing: BibleTheme.Space.sm) {
            if !preview.isEmpty {
                Text(preview).bibleTextStyle(.body)
                Text("受信中の回答です。全体の確認が終わるまで確定しません。").bibleTextStyle(.caption).foregroundStyle(.secondary)
            }
            ProgressView(status.isEmpty ? "回答を準備しています" : status).bibleTextStyle(.caption)
            Text("回答が届くまで、そのまま次の質問を入力できます。").bibleTextStyle(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children: .contain)
    }
}

/// Keep icon-only composer controls fully visible above the keyboard at every text size.
/// Input and message text continue to use the user's Dynamic Type setting.
struct ChatComposerIcon: View {
    let systemName: String
    var body: some View {
        Image(systemName: systemName).bibleTextStyle(.title)
            .dynamicTypeSize(.large).frame(width: 44, height: 44)
    }
}

/// Unmodified official OpenAI asset; the separate symbol indicates the external destination.
struct ChatGPTCopyComposerLabel: View {
    var body: some View {
        HStack(spacing: 8) {
            Image("OpenAIBlossom").renderingMode(.original).resizable().scaledToFit().frame(width: 24, height: 24)
            Image(systemName: "arrow.up.right.square").font(.system(size: 14)).foregroundStyle(.primary)
        }.padding(.horizontal, 8).dynamicTypeSize(.large).frame(width: 64, height: 44).accessibilityHidden(true)
    }
}
