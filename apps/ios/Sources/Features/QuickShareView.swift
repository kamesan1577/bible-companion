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
                    Text("共有した箇所を確認").bibleTextStyle(.heading)
                    if let parsed { ForEach(parsed.ranges, id: \.self) { Text($0.label).bibleTextStyle(.verseReference) } }
                    if let owner = store.account {
                        Text("保存すると、選んだ章と節、訳名が\(owner.display_name)の読書履歴に送られます。共有された聖書本文は履歴に保存しません。AIへの質問は、利用できる状態を確認し、送る内容と条件に同意した後に使えます。").bibleTextStyle(.body)
                        Button(busy ? "保存しています" : "このアカウントに保存して開く") { open() }.buttonStyle(.borderedProminent).disabled(parsed == nil || busy || store.isTransitioning)
                    } else {
                        Text("ログインすると、共有した箇所をこのアカウントの読書履歴に保存できます。共有文はこの端末で一時的に待機しています。初めての方は、パスキー認証画面の案内から登録できます。").bibleTextStyle(.body)
                        Button(store.isAuthenticating ? "ログイン中" : "パスキーでログイン") { store.signIn() }.buttonStyle(.borderedProminent).disabled(store.isAuthenticating || store.isTransitioning || !store.endpointConfigured)
                    }
                    if let error { Text(error).bibleTextStyle(.body) }
                    if let error = store.errorMessage { Text(error).bibleTextStyle(.body) }
                    Button("章と節を選び直す") { manual = true }
                }
            }.bibleCanvas().navigationTitle("共有した箇所")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { dismiss() }.disabled(busy) } }
                .task { do { parsed = try SharedImportParser.parse(share.text) } catch { self.error = "章と節を読み取れません。下の「章と節を選び直す」から指定してください。" } }
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
            } catch { self.error = "保存できませんでした。共有文はこの端末に残っています。もう一度お試しください。" }
        }
    }
}
