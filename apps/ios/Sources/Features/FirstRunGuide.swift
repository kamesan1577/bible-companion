import SwiftUI

struct FirstRunGuide: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BibleTheme.Space.page) {
                    Text("いつもの聖書から、理解を深める").bibleTextStyle(.heading)
                    Label("聖書アプリの共有から章節やURLを送ります。", systemImage: "square.and.arrow.up")
                    Label("確認済みの資料を読み、気になるところを質問できます。", systemImage: "book")
                    Label("ログインすると、自分の読書履歴を保存できます。", systemImage: "person.crop.circle")
                    Text("資料がない箇所はそのままお知らせします。AIの生成は、接続と同意が確認できた場合に利用できます。").bibleTextStyle(.caption)
                    Button("読み始める") { dismiss() }.buttonStyle(.borderedProminent)
                }.padding(BibleTheme.Space.page)
            }.bibleCanvas().navigationTitle("はじめに")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("スキップ") { dismiss() } } }
        }
    }
}
