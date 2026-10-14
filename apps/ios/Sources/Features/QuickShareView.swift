import SwiftUI
import CompanionCore

struct QuickShareView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let share: PendingShare
    @State private var parsed: ParsedImport?
    @State private var error: String?
    @State private var busy = false
    @State private var manual = false
    var body: some View {
        NavigationStack {
            ScrollView {
                BibleReadingColumn {
                    Text("共有した箇所を開く").bibleTextStyle(.heading)
                    if let parsed { ForEach(parsed.ranges, id: \.self) { Text($0.label).bibleTextStyle(.verseReference) } }
                    if let owner = store.account {
                        Text("\(owner.display_name)の読書として保存し、質問できます。共有された聖書本文は履歴に保存しません。").bibleTextStyle(.body)
                        Button(busy ? "開いています" : "このアカウントで開く") { open() }.buttonStyle(.borderedProminent).disabled(parsed == nil || busy || store.isTransitioning)
                    } else {
                        Text("自分だけの質問と読書履歴を保存するため、初回だけログインします。共有した箇所は待機しています。").bibleTextStyle(.body)
                        Button(store.isAuthenticating ? "ログイン中" : "ログインして続ける") { store.signIn() }.buttonStyle(.borderedProminent).disabled(store.isAuthenticating || store.isTransitioning || !store.endpointConfigured)
                    }
                    if let error { Text(error).bibleTextStyle(.body) }
                    if let error = store.errorMessage { Text(error).bibleTextStyle(.body) }
                    Button("章節を修正する") { manual = true }
                }
            }.bibleCanvas().navigationTitle("共有した箇所")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { dismiss() }.disabled(busy) } }
                .task { do { parsed = try SharedImportParser.parse(share.text) } catch { self.error = "章節を読み取れません。下の「章節を修正する」から指定してください。" } }
                .sheet(isPresented: $manual) { ImportView().environmentObject(store) }
                .interactiveDismissDisabled(busy)
        }
    }
    private func open() {
        guard let parsed, let owner = store.account?.id else { return }
        busy = true; error = nil
        Task {
            defer { busy = false }
            do {
                let key = try ShareInbox.submissionKey(share: share, owner: owner, ranges: parsed.ranges, translation: parsed.translation)
                try await store.saveImport(ImportInput(idempotencyKey: key, ranges: parsed.ranges, translation: parsed.translation), share: share, transientExcerpt: share.text)
                dismiss()
            } catch { self.error = "開けませんでした。共有内容は残っています。もう一度お試しください。" }
        }
    }
}
