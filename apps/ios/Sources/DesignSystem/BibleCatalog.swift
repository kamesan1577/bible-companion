#if DEBUG
import SwiftUI

/// Developer-only reference gallery. It is not a fourth production tab.
struct BibleDesignCatalog: View {
    @State private var selected = "解説"
    private let categories = ["解説", "地図", "人物", "絵画"]

    var body: some View {
        NavigationStack {
            ScrollView {
                BibleReadingColumn {
                    VStack(alignment: .leading, spacing: BibleTheme.Space.md) {
                        Text("使徒の働き").bibleTextStyle(.heading)
                        Text("18:24–19:7").bibleTextStyle(.verseReference)
                        BibleRangeBadge(text: "選択全体・12節")
                        BibleScopeNotice(text: "19:7まで。先の展開は含めません。")
                    }
                    Picker("表示内容", selection: $selected) {
                        ForEach(categories, id: \.self) { Text($0).tag($0) }
                    }.pickerStyle(.segmented)
                    BibleReadingSurface {
                        VStack(alignment: .leading, spacing: BibleTheme.Space.lg) {
                            BibleSectionHeader(title: "二つの出会いを、つなげて読む", subtitle: "選択範囲の解説・聖句本文ではありません")
                            Text("章の区切りを越えても、選んだ範囲は一つのまま。本文、補足、出典を同じ読書の流れで確かめられます。")
                                .bibleTextStyle(.body).bibleForeground(.textPrimary)
                        }
                    }
                    BibleLoadingView()
                    BibleStateView(title: "この範囲の資料はありません", message: "別の資料が見つかったようには表示せず、現在の範囲を保ちます。")
                    BibleStateView(title: "読み込めませんでした", message: "選んだ範囲は保存されています。接続を確認して、もう一度試してください。", systemImage: BibleTheme.Symbol.error)
                    Button {} label: {
                        BibleActionLabel(title: "この範囲について質問", systemImage: BibleTheme.Symbol.question)
                    }.buttonStyle(.bordered)
                }
            }
            .bibleCanvas()
            .navigationTitle("デザイン見本")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview("Light") { BibleDesignCatalog().preferredColorScheme(.light) }
#Preview("Dark") { BibleDesignCatalog().preferredColorScheme(.dark) }
#Preview("Accessibility") { BibleDesignCatalog().environment(\.dynamicTypeSize, .accessibility5) }
// Contrast and reduced-effects environment values are read-only in the Apple SDK.
// Verify these variants using the Simulator's Accessibility settings.
#endif
