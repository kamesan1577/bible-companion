import SwiftUI
import CompanionCore

struct ReadingDiscoveryCard: View {
    var body: some View {
        NavigationLink {
            ReadingDiscoveryDetail()
        } label: {
            BibleReadingSurface {
                VStack(alignment: .leading, spacing: BibleTheme.Space.xl) {
                    HStack {
                        BibleRangeBadge(text: "人物と場所から読む")
                        Spacer()
                        Image(systemName: "arrow.up.right").bibleForeground(.accent)
                    }
                    Image(systemName: "building.columns")
                        .bibleTextStyle(.title).bibleForeground(.accent)
                        .padding(.vertical, BibleTheme.Space.lg).accessibilityHidden(true)
                    Text("アポロと\nエペソの人々").bibleTextStyle(.title).bibleForeground(.textPrimary)
                    Text("聖書に詳しいアポロ。プリスキラとアキラとの出会いを、人物の説明から確かめる。")
                        .bibleTextStyle(.body).bibleForeground(.textSecondary)
                    Divider()
                    HStack {
                        Text("使徒の働き 18:24–28").bibleTextStyle(.caption)
                        Spacer()
                        Label("開く", systemImage: "chevron.right").bibleTextStyle(.body)
                    }.bibleForeground(.accent)
                }
            }
        }.buttonStyle(.plain).accessibilityIdentifier("discovery-card")
    }
}

struct ReadingDiscoveryDetail: View {
    private let passage = Passage(book: "ACT", start: Verse(chapter: 18, verse: 24), end: Verse(chapter: 18, verse: 28))
    var body: some View {
        ScrollView {
            BibleReadingColumn {
                BibleSectionHeader(title: "アポロとエペソの人々", subtitle: passage.label)
                Text("この箇所の人物と場所を、端末に収録された説明で確認できます。説明は使徒18:28までの内容です。読書履歴には追加しません。")
                    .bibleTextStyle(.body)
                OfflineEntityPane(passage: passage, kind: "person")
                OfflineEntityPane(passage: passage, kind: "place")
            }
        }.navigationTitle("人物と場所").navigationBarTitleDisplayMode(.inline).bibleCanvas()
    }
}
