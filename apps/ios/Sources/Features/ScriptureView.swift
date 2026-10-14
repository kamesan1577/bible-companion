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
                Text("日本語訳・JCB本文ではありません。資料原文の節番号を保持し、対応しない箇所を別の節へ置き換えません。端末へのオフライン保存は行いません。").bibleTextStyle(.caption)
                if let page = model.page {
                    Text(page.noticeJa).bibleTextStyle(.caption)
                    if page.available {
                        if page.items.isEmpty { BibleStateView(title: "表示できる本文はありません", message: "この範囲に対応する出典の本文がありません。欠落した節を補って表示することはありません。") }
                        ForEach(page.items) { item in
                            BibleReadingSurface {
                                VStack(alignment: .leading, spacing: BibleTheme.Space.sm) {
                                    Text(item.position.label).bibleTextStyle(.verseReference).accessibilityLabel("\(model.passage.bookName)、\(item.chapter)章\(item.verse)節")
                                    Text(item.text).bibleTextStyle(.body).textSelection(.enabled)
                                }
                            }
                        }
                        if !page.omissions.isEmpty {
                            DisclosureGroup("本文が空または対応する番号がない箇所（\(page.omissions.count)）") {
                                ForEach(Array(page.omissions.enumerated()), id: \.offset) { _, omission in
                                    Text("\(omission.position.label) · \(omission.reason == "source_text_empty" ? "出典の本文が空です" : "出典に対応する節番号がありません")").bibleTextStyle(.caption)
                                }
                            }
                        }
                        Text("節番号のない表題等は含めていません。出典の確認は、日本語解説の編集・解釈の確認を意味しません。").bibleTextStyle(.caption)
                        Text("\(model.pageNumber)ページ目").bibleTextStyle(.caption)
                        if model.pageNumber > 1 { Button("前のページ") { Task { await model.previous() } } }
                        if page.nextCursor != nil { Button("次のページ") { Task { await model.next() } } }
                        if let corpus = page.corpus { DisclosureGroup("出典の版") { Text("\(corpus.edition) · \(corpus.version)").bibleTextStyle(.caption); Text("公開利用可能な英語原文。解説の編集確認は未実施です。").bibleTextStyle(.caption) } }
                    } else { BibleStateView(title: "参考本文は利用できません", message: "サーバーに利用可能な英語原文がまだありません。本文が存在しないという意味ではありません。") }
                }
                if model.loading { BibleLoadingView(title: "英語原文を確認しています", message: "資料の版と表示できる範囲を確認しています。") }
                if let error = model.errorMessage { BibleStateView(title: "読み込めません", message: error); Button("最初から再読み込み") { Task { await model.loadFirst() } } }
            }
        }
        .bibleCanvas().navigationTitle("英語の参考本文").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("再読み込み", systemImage: "arrow.clockwise") { Task { await model.loadFirst() } }.disabled(model.loading) } }
        .task { await model.loadFirst() }.onDisappear { model.clear() }
        .onChange(of: scenePhase) { _, phase in if phase == .background { model.clear() } else if phase == .active { Task { await model.loadFirst() } } }
    }
}
