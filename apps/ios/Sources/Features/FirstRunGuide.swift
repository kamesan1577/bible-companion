import SwiftUI
import CompanionCore

struct FirstRunGuide: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @State private var step = 0
    @State private var showPreparation = false
    @State private var provider = ExternalQuestionProvider.chatGPT
    var onPrepare: (() -> Void)? = nil
    private let titles = ["① 最初に準備する", "② YouVersionで節を選んで共有", "③ 質問を入力して送信する"]
    private let instructions = ["設定で質問を送る外部サービスを1つ選びます。解説を読むだけならログインは不要です。", "YouVersionで読みたい節を選び、共有ボタンを押します。共有先から「聖書コンパニオン」を選んでください。", "共有画面で解説を読み、そのまま質問を入力できます。選んだ外部サービスを開いて質問を続けます。"]
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BibleTheme.Space.page) {
                    HStack { ForEach(0..<3) { index in Capsule().fill(index == step ? Color.accentColor : Color.secondary.opacity(0.2)).frame(height: 5) } }.accessibilityLabel("手順\(step + 1)、全3手順")
                    Text(titles[step]).bibleTextStyle(.heading)
                    illustration
                    Text(instructions[step]).bibleTextStyle(.body)
                    if step == 0 {
                        Button("初回準備を始める") { if let onPrepare { onPrepare() } else { showPreparation = true } }
                            .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                        Text("ChatGPTは質問付きリンク、Claude・Geminiは全文をコピーして開き、貼り付けて送信します。").bibleTextStyle(.caption)
                    }
                    if step == 1 { Text("共有先の一覧にない場合は、「その他」や編集メニューから追加してください。共有を始めてもアプリ本体へ移動する必要はありません。").bibleTextStyle(.caption) }
                    if step == 2 { Text("原文が共有されていない場合はその旨を伝え、訳文を推測で補いません。外部サービスのログインが必要な場合があります。").bibleTextStyle(.caption) }
                    Button(step == 2 ? "ガイドを閉じる" : "次へ") { if step < 2 { step += 1 } else { dismiss() } }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                    if step == 2 { NavigationLink("まずサンプルを読んでみる") { SampleReadingPreview() } }
                    if step > 0 { Button("戻る") { step -= 1 } }
                }.padding(BibleTheme.Space.page)
            }.bibleCanvas().navigationTitle("使い方")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { dismiss() } } }
        }
        .sheet(isPresented: $showPreparation) { ExternalQuestionSettings(provider: $provider) }
    }
    private var illustration: some View {
        BibleReadingSurface {
            VStack(alignment: .leading, spacing: BibleTheme.Space.md) {
                Text(step == 0 ? "聖書コンパニオン · 準備のイメージ" : (step == 2 ? "共有画面" : "YouVersion · 操作のイメージ")).bibleTextStyle(.caption)
                if step == 0 {
                    Label("送信先を1つ選ぶ", systemImage: "slider.horizontal.3")
                    Label("送る情報と利用条件を確認", systemImage: "checkmark.shield")
                    Label("共通の4タブで解説を読む", systemImage: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                } else if step == 1 {
                    Text("使徒の働き 18章").bibleTextStyle(.body)
                    Text("24節　…").padding().frame(maxWidth: .infinity, alignment: .leading).background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: BibleTheme.Radius.inset))
                    Label("節を選んで共有", systemImage: "square.and.arrow.up").foregroundStyle(Color.accentColor)
                } else {
                    Label("聖書コンパニオン", systemImage: "book.closed.fill").padding().frame(maxWidth: .infinity).background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: BibleTheme.Radius.inset))
                    Label("質問を入力", systemImage: "text.bubble").foregroundStyle(Color.accentColor)
                    Text("選んだ外部サービスで質問を続ける").padding().frame(maxWidth: .infinity, alignment: .leading).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: BibleTheme.Radius.inset))
                }
            }.padding(BibleTheme.Space.md)
        }
    }
}

struct SampleReadingPreview: View {
    @EnvironmentObject private var store: AppStore
    @State private var preview: Preview?
    @State private var message: String?
    private struct Preview: Decodable { let items: [Item] }
    private struct Item: Decodable { let passage: Passage; let text: String; let citations: [Citation] }
    var body: some View {
        ScrollView {
            BibleReadingColumn {
                Text("使徒の働き 18:24–28").bibleTextStyle(.heading)
                Text("サンプル · 読書履歴には保存されません。").bibleTextStyle(.caption)
                if let preview {
                    ForEach(Array(preview.items.enumerated()), id: \.offset) { _, item in
                        Text(item.text).bibleTextStyle(.body).textSelection(.enabled)
                        CitationList(citations: item.citations)
                    }
                } else if let message { Text(message); Button("再読み込み") { Task { await load() } } }
                else { ProgressView("サンプルを読み込んでいます") }
                Text("次はYouVersionで読んだ節を共有してください。").bibleTextStyle(.body)
            }
        }.bibleCanvas().navigationTitle("サンプル").task { await load() }
    }
    private func load() async {
        message = nil
        do { preview = try await store.client.post("/public/reading-preview", body: ["sharedText": "使徒の働き 18:24-28"]) }
        catch { message = "通信が必要です。接続して、もう一度お試しください。" }
    }
}
