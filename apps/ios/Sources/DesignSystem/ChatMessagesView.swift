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
            Text("確認できた主張から表示します。出典の確認が必要なため、しばらく表示が止まる場合があります。").bibleTextStyle(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children: .contain)
    }
}
