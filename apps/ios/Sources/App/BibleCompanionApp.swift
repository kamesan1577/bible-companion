import SwiftUI
import CompanionCore

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
                 .task {
#if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--simulator-qa") { return }
#endif
                    await store.restore()
                }
                .onChange(of: scenePhase) { _, phase in
#if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--simulator-qa") { return }
#endif
                    if phase == .active { store.enteredForeground() }
                }
        }
    }
}
struct RootView: View {
    @AppStorage("hasSeenVisualShareGuideV2") private var hasSeenGuide = false
    @State private var showGuide = false
    @State private var prepareAfterGuide = false
    @State private var provider = ExternalQuestionProvider.chatGPT
    @EnvironmentObject private var store: AppStore
    var body: some View {
        TabView(selection: $store.selectedTab) {
            Tab("読書", systemImage: BibleTheme.Symbol.reading, value: 0) { NavigationStack { ReadingView() } }
            Tab("履歴", systemImage: BibleTheme.Symbol.history, value: 1) { NavigationStack { HistoryView() } }
            Tab("設定", systemImage: BibleTheme.Symbol.settings, value: 2) { NavigationStack { SettingsView() } }
        }
        .onAppear { if !hasSeenGuide { showGuide = true } }
        .sheet(isPresented: $showGuide, onDismiss: { hasSeenGuide = true; if prepareAfterGuide { prepareAfterGuide = false; store.showAISetup = true } }) { FirstRunGuide(onPrepare: { prepareAfterGuide = true; showGuide = false }) }
        .disabled(store.isDeleting)
        .overlay { if store.isDeleting { BibleLoadingView(title: "削除結果を確認しています", message: "完了を確認するまでお待ちください。") } }
        .id(store.sessionEpoch)
        .bibleCanvas()
        .alert("削除結果", isPresented: Binding(get: { store.privacyNotice != nil }, set: { if !$0 { store.privacyNotice = nil } })) { Button("確認") { store.privacyNotice = nil } } message: { Text(store.privacyNotice ?? "") }
        .sheet(isPresented: $store.showAISetup) { ExternalQuestionSettings(provider: $provider) }
        .sheet(isPresented: $store.showImport) {
            if store.pendingShares.count == 1, let share = store.pendingShares.first { QuickShareView(share: share).environmentObject(store) }
            else { ImportView().environmentObject(store) }
        }
    }
}
