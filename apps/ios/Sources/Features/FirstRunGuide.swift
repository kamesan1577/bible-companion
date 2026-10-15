import SwiftUI
import CompanionCore

struct FirstRunGuide: View {
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    private let titles = ["① 読みたい節を選ぶ", "② 共有ボタンを押す", "③ 聖書コンパニオンを選ぶ"]
    private let instructions = ["YouVersionで、気になる節をタップ。複数の節も選べます。", "選んだ節のメニューから、四角に上矢印の共有ボタンを押します。", "共有先の「聖書コンパニオン」をタップ。解説がその場で開きます。"]
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BibleTheme.Space.page) {
                    HStack { ForEach(0..<3) { index in Capsule().fill(index == step ? Color.accentColor : Color.secondary.opacity(0.2)).frame(height: 5) } }.accessibilityLabel("手順\(step + 1)、全3手順")
                    Text(titles[step]).bibleTextStyle(.heading)
                    illustration
                    Text(instructions[step]).bibleTextStyle(.body)
                    if step == 2 { Text("一覧にないときは「その他」→「編集」→聖書コンパニオンを「よく使う項目」に追加。右の三本線を上へ動かすと、次から先頭に出ます。初回だけメインアプリでログインし、「共有画面のAIを有効にする」を押してください。設定後は共有画面で解説と追加質問を利用できます。").bibleTextStyle(.caption) }
                    Button(step == 2 ? "わかった、読み始める" : "次へ") { if step < 2 { step += 1 } else { dismiss() } }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                    NavigationLink("まずサンプルを読んでみる") { SampleReadingPreview() }
                    if step > 0 { Button("戻る") { step -= 1 } }
                }.padding(BibleTheme.Space.page)
            }.bibleCanvas().navigationTitle("使い方")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { dismiss() } } }
        }
    }
    private var illustration: some View {
        BibleReadingSurface {
            VStack(alignment: .leading, spacing: BibleTheme.Space.md) {
                Text(step == 2 ? "共有先" : "YouVersion · 操作のイメージ").bibleTextStyle(.caption)
                if step == 0 {
                    Text("使徒の働き 18章").bibleTextStyle(.body)
                    Text("24節　…").padding().frame(maxWidth: .infinity, alignment: .leading).background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: BibleTheme.Radius.inset))
                    Label("ここをタップして選ぶ", systemImage: "hand.tap.fill").foregroundStyle(Color.accentColor)
                } else if step == 1 {
                    HStack { Label("コピー", systemImage: "doc.on.doc"); Spacer(); Label("共有", systemImage: "square.and.arrow.up").padding().background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: BibleTheme.Radius.inset)) }
                    Label("このマークを押す", systemImage: "arrow.up").foregroundStyle(Color.accentColor)
                } else {
                    Label("聖書コンパニオン", systemImage: "book.closed.fill").padding().frame(maxWidth: .infinity).background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: BibleTheme.Radius.inset))
                    Label("これを選ぶ → 解説が開く", systemImage: "hand.tap.fill").foregroundStyle(Color.accentColor)
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
                Text("サンプル · 履歴に保存せず、解説を試せます。").bibleTextStyle(.caption)
                if let preview {
                    ForEach(Array(preview.items.enumerated()), id: \.offset) { _, item in
                        Text(item.text).bibleTextStyle(.body).textSelection(.enabled)
                        CitationList(citations: item.citations)
                    }
                } else if let message { Text(message); Button("再読み込み") { Task { await load() } } }
                else { ProgressView("解説を開いています") }
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
