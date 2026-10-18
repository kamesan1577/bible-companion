import SwiftUI
import CompanionCore

/// Home keeps its existing discovery artwork; all opened passages use the same reader as Share.
struct ReadingView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var visits: [LocalReadingVisit] = []
    @State private var opening: LocalReadingVisit?
    @State private var showReader = false
    @State private var initialised = false
    @State private var notice: String?
    var body: some View {
        ScrollView {
            BibleReadingColumn {
                ReadingDiscoveryCard()
                BibleReadingSurface {
                    VStack(alignment: .leading, spacing: BibleTheme.Space.md) {
                        BibleSectionHeader(title: "最近開いた箇所", subtitle: "この端末の本体・共有画面で共通")
                        if let recent = visits.first {
                            Button { open(recent) } label: { BibleActionLabel(title: recent.passage.label, systemImage: "clock.arrow.circlepath") }
                                .accessibilityIdentifier("recent-reading")
                            Text(recent.translation ?? "訳名なし").bibleTextStyle(.caption)
                        } else { Text("共有した箇所、または本体で開いた箇所がここに表示されます。").bibleTextStyle(.body) }
                        if let notice { Text(notice).bibleTextStyle(.caption) }
                    }
                }
                NavigationLink { StaticCommentaryBrowser() } label: { BibleActionLabel(title: "書名・章から説明を探す", systemImage: "books.vertical") }
                    .buttonStyle(.glass).accessibilityIdentifier("browse-chapters")
                if !store.pendingShares.isEmpty { Button("YouVersionから受け取った箇所を開く") { store.showImport = true } }
                if store.account != nil { Button("書名・章・節を入力する") { store.showImport = true } }
            }
        }
        .bibleCanvas().navigationTitle("読書").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { ExternalQuestionComposer(passage: visits.first?.passage, translation: visits.first?.translation, sharedText: visits.first?.sharedText ?? "") }
        .navigationDestination(isPresented: $showReader) {
            if let value = opening { UnifiedReadingView(passage: value.passage, translation: value.translation, sharedText: value.sharedText) }
        }
        .task {
            refresh()
            if !initialised { initialised = true; if store.selectedPassage != nil { openSelected() } }
        }
        .onChange(of: store.selectedPassage) { _, value in if value != nil { openSelected() } }
        .onChange(of: store.account?.id) { _, _ in refresh() }
        .onChange(of: scenePhase) { _, value in if value == .active { refresh() } }
        .onChange(of: showReader) { _, value in if !value { refresh() } }
    }
    private func refresh() {
        do { visits = try ShareInbox.readingVisits(owner: store.account?.id); notice = nil }
        catch { visits = []; notice = "端末内の最近の箇所を確認できません。記録は削除していません。" }
    }
    private func open(_ visit: LocalReadingVisit) { opening = visit; showReader = true }
    private func openSelected() {
        guard let passage = store.selectedPassage else { return }
        open(LocalReadingVisit(ownerID: store.account?.id, passage: passage, translation: store.selected?.translation, sharedText: store.sourceExcerpt ?? ""))
    }
}
