import SwiftUI

@main struct BibleCompanionApp: App {
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            Group {
#if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--simulator-qa") { SimulatorQA() }
                else { RootView() }
#else
                RootView()
#endif
            }.environmentObject(store)
                .task { await store.restore(); await store.refreshShareAI() }
                .onChange(of: scenePhase) { _, phase in if phase == .active { store.enteredForeground() } }
        }
    }
}
struct RootView: View {
    @AppStorage("hasSeenVisualShareGuideV2") private var hasSeenGuide = false
    @State private var showGuide = false
    @EnvironmentObject private var store: AppStore
    var body: some View {
        TabView(selection: $store.selectedTab) {
            Tab("読書", systemImage: BibleTheme.Symbol.reading, value: 0) { NavigationStack { ReadingView() } }
            Tab("履歴", systemImage: BibleTheme.Symbol.history, value: 1) { NavigationStack { HistoryView() } }
            Tab("設定", systemImage: BibleTheme.Symbol.settings, value: 2) { NavigationStack { SettingsView() } }
        }
        .onAppear { if !hasSeenGuide { showGuide = true } }
        .sheet(isPresented: $showGuide, onDismiss: { hasSeenGuide = true }) { FirstRunGuide() }
        .disabled(store.isDeleting)
        .overlay { if store.isDeleting { BibleLoadingView(title: "削除結果を確認しています", message: "完了を確認するまでお待ちください。") } }
        .id(store.sessionEpoch)
        .bibleCanvas()
        .alert("削除結果", isPresented: Binding(get: { store.privacyNotice != nil }, set: { if !$0 { store.privacyNotice = nil } })) { Button("確認") { store.privacyNotice = nil } } message: { Text(store.privacyNotice ?? "") }
        .sheet(isPresented: $store.showImport) {
            if store.pendingShares.count == 1, let share = store.pendingShares.first { QuickShareView(share: share).environmentObject(store) }
            else { ImportView().environmentObject(store) }
        }
        .sheet(isPresented: $store.showQuestion) {
            if let item = store.selected, let target = store.questionTarget, let ownerID = store.account?.id {
                QuestionView(ownerID: ownerID, client: store.client, item: item, rangeIndex: store.rangeIndex, target: target, conversation: store.questionConversation)
            }
        }
    }
}
