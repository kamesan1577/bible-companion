import SwiftUI
import CompanionCore

struct ScriptureView: View {
    @StateObject private var model: ScriptureModel
    @Environment(\.scenePhase) private var scenePhase
    init(client: APIClient, importID: String, rangeIndex: Int, passage: Passage) {
        _model = StateObject(wrappedValue: ScriptureModel(client: client, importID: importID, rangeIndex: rangeIndex, passage: passage))
    }
    var body: some View {
        ScrollView {
            BibleReadingColumn {
                BibleSectionHeader(title: model.passage.label, subtitle: "参考本文 · World English Bible（英語）")
                Text("ここに表示するのは日本語訳やJCBではなく、英語の参考本文です。出典の節番号を保ち、対応する本文がない節を別の節で補うことはありません。この本文は端末には保存されません。").bibleTextStyle(.caption)
                if let page = model.page {
                    Text(page.noticeJa).bibleTextStyle(.caption)
                    if page.available {
                        if page.items.isEmpty { BibleStateView(title: "このページに本文がありません", message: "選んだ範囲の出典から表示できる英語本文を確認できません。節を別の本文で補うことはありません。別の箇所を選ぶか、再読み込みしてください。") }
                        ForEach(page.items) { item in
                            BibleReadingSurface {
                                VStack(alignment: .leading, spacing: BibleTheme.Space.sm) {
                                    Text(item.position.label).bibleTextStyle(.verseReference).accessibilityLabel("\(model.passage.bookName)、\(item.chapter)章\(item.verse)節")
                                    Text(item.text).bibleTextStyle(.body).textSelection(.enabled)
                                }
                            }
                        }
                        if !page.omissions.isEmpty {
                            DisclosureGroup("本文を表示できない箇所（\(page.omissions.count)）") {
                                ForEach(Array(page.omissions.enumerated()), id: \.offset) { _, omission in
                                    Text("\(omission.position.label) · \(omission.reason == "source_text_empty" ? "出典に本文がありません" : "出典にこの節番号がありません")").bibleTextStyle(.caption)
                                }
                            }
                        }
                        Text("節番号のない表題などは含めていません。英語本文の出典を確認しても、日本語解説の編集・解釈まで確認したことにはなりません。").bibleTextStyle(.caption)
                        Text("\(model.pageNumber)ページ目").bibleTextStyle(.caption)
                        if model.pageNumber > 1 { Button("前のページ") { Task { await model.previous() } } }
                        if page.nextCursor != nil { Button("次のページ") { Task { await model.next() } } }
                        if let corpus = page.corpus { DisclosureGroup("本文の版と利用情報") { Text("\(corpus.edition) · \(corpus.version)").bibleTextStyle(.caption); Text("公開利用できる英語本文です。日本語解説の編集確認には使っていません。").bibleTextStyle(.caption) } }
                    } else { BibleStateView(title: "英語の参考本文を表示できません", message: "提供元からこの範囲の本文を取得できませんでした。本文が存在しないという意味ではありません。接続を確認して、再読み込みしてください。") }
                }
                if model.loading { BibleLoadingView(title: "英語原文を確認しています", message: "資料の版と表示できる範囲を確認しています。") }
                if model.errorMessage != nil { BibleStateView(title: "英語本文を読み込めません", message: "本文を取得できませんでした。接続を確認して、もう一度お試しください。"); Button("最初から再読み込み") { Task { await model.loadFirst() } } }
            }
        }
        .bibleCanvas().navigationTitle("英語の参考本文").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("再読み込み", systemImage: "arrow.clockwise") { Task { await model.loadFirst() } }.disabled(model.loading) } }
        .task { await model.loadFirst() }.onDisappear { model.clear() }
        .onChange(of: scenePhase) { _, phase in if phase == .background { model.clear() } else if phase == .active { Task { await model.loadFirst() } } }
    }
}
