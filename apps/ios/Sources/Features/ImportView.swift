import SwiftUI
import CompanionCore

struct ImportView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var ranges: [Passage] = []
    @State private var translation = ""
    @State private var translationConfirmed = false
    @State private var accountConfirmed = false
    @State private var share: PendingShare?
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var isParsing = false
    @State private var parseGeneration = UUID()
    @State private var parseTask: Task<Void, Never>?
    @State private var idempotencyKey = UUID().uuidString
    @State private var manualBook = "ACT"
    @State private var startChapter = 18
    @State private var startVerse = 24
    @State private var endChapter = 19
    @State private var endVerse = 7
    var body: some View {
        NavigationStack {
            Form {
                if store.account == nil {
                    Section { BibleStateView(title: "ログインが必要です", message: store.pendingShares.isEmpty ? "ログイン後、章節を入力して自分の履歴に保存できます。" : "共有された内容は端末で待機しています。ログイン後、保存先のアカウントと章節を確認します。")
                        Button(store.isAuthenticating ? "ログイン中" : "パスキーでログイン") { store.signIn() }.disabled(!store.endpointConfigured || store.isAuthenticating || store.isTransitioning || store.restoreNeedsRetry || store.localCleanupRequired)
                        if store.isTransitioning { ProgressView("保存したログインを確認しています") }
                        if store.isAuthenticating { Button("ログインを中止") { store.cancelSignIn() } }
                        if store.restoreNeedsRetry { Button("保存したログインを再確認") { Task { await store.restore() } }.disabled(store.isTransitioning) }
                        if store.localCleanupRequired { Text("この画面を閉じ、設定の「端末内データの削除を再試行」で前回の削除を完了してください。").bibleTextStyle(.caption) }
                        if let error = store.errorMessage { Text(error).bibleTextStyle(.caption).bibleForeground(.textSecondary) }
                        if !store.endpointConfigured { Text("接続先が未設定です。HTTPSサーバーを設定したビルドが必要です。").bibleTextStyle(.caption) }
                    }
                }
                if !store.pendingShares.isEmpty {
                    Section("共有された箇所") {
                        ForEach(store.pendingShares) { pending in
                            Button { choose(pending) } label: {
                                VStack(alignment: .leading, spacing: BibleTheme.Space.xs) { Text(pending.text).lineLimit(2); Text(pending.createdAt, style: .date).bibleTextStyle(.caption) }
                            }
                        }
                        Text("共有内容は24時間を過ぎると取り込めなくなり、次回アプリや共有機能が確認するときに端末から消去されます。").bibleTextStyle(.caption)
                    }
                }
                if let notice = store.shareNotice { Section { Text(notice).bibleTextStyle(.body); Button("共有内容を再確認") { store.refreshInbox() } } }
                Section("URL・章節・共有テキスト") {
                    TextEditor(text: $text).frame(minHeight: BibleTheme.Layout.minimumTouchTarget * 3).accessibilityLabel("共有テキスト")
                    Button(isParsing ? "確認中" : "章節を確認する") { parse() }.disabled(text.isEmpty || isParsing || isSaving)
                    Text("本文は履歴へ保存しません。保存するのは章節と訳の情報です。").bibleTextStyle(.caption).bibleForeground(.textSecondary)
                }
                Section("手動で章節を指定") {
                    Picker("書", selection: $manualBook) { ForEach(Canon.books) { Text($0.ja).tag($0.id) } }
                    Stepper("開始 \(startChapter)章", value: $startChapter, in: 1...150)
                    Stepper("開始 \(startVerse)節", value: $startVerse, in: 1...176)
                    Stepper("終了 \(endChapter)章", value: $endChapter, in: 1...150)
                    Stepper("終了 \(endVerse)節", value: $endVerse, in: 1...176)
                    Button("この範囲を使う") {
                        invalidateParse()
                        let value = Passage(book: manualBook, start: Verse(chapter: startChapter, verse: startVerse), end: Verse(chapter: endChapter, verse: endVerse))
                        guard value.isValid else { errorMessage = "存在する章節を、開始から終了の順で指定してください。"; return }
                        ranges = [value]; idempotencyKey = UUID().uuidString; errorMessage = nil
                    }
                }
                if !ranges.isEmpty {
                    Section("保存する箇所") {
                        ForEach(ranges, id: \.self) { Text($0.label).bibleTextStyle(.body) }
                        TextField("訳名（例：JCB）", text: $translation).textInputAutocapitalization(.characters).autocorrectionDisabled()
                        Toggle(translation.isEmpty ? "訳が不明のまま保存する" : "この訳名を確認しました", isOn: $translationConfirmed)
                        if let owner = store.account, let share, share.requiresAccountConfirmation(currentOwner: owner.id) {
                            Toggle("\(owner.display_name)の履歴へ取り込む", isOn: $accountConfirmed)
                            Text("この共有は現在のログインと紐づいていません。保存先を確認してください。").bibleTextStyle(.caption)
                        }
                    }
                }
                if let errorMessage { Section { Text(errorMessage).bibleTextStyle(.body).bibleForeground(.danger) } }
                if let share { Section { Button("この共有を破棄", role: .destructive) { do { try store.removeShare(share); self.share = nil; text = ""; ranges = [] } catch { errorMessage = "削除できませんでした。" } }.disabled(isSaving) } }
            }
            .disabled(isSaving)
            .bibleCanvas().navigationTitle("箇所を取り込む").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() }.disabled(isSaving) }
                ToolbarItem(placement: .confirmationAction) { Button(isSaving ? "保存中" : "保存") { save() }.disabled(!canSave) }
            }
            .interactiveDismissDisabled(isSaving)
            .onDisappear { invalidateParse() }
            .onChange(of: text) { _, _ in invalidateParse(); ranges = []; translationConfirmed = false; idempotencyKey = UUID().uuidString }
            .onChange(of: translation) { _, _ in translationConfirmed = false; idempotencyKey = UUID().uuidString }
        }
    }
    private var canSave: Bool {
        guard let owner = store.account, !isSaving, !isParsing, !ranges.isEmpty, ranges.allSatisfy(\.isValid), translationConfirmed else { return false }
        return share?.requiresAccountConfirmation(currentOwner: owner.id) != true || accountConfirmed
    }
    private func choose(_ pending: PendingShare) { invalidateParse(); share = pending; text = pending.text; ranges = []; accountConfirmed = false; translationConfirmed = false; errorMessage = nil }
    private func invalidateParse() { parseGeneration = UUID(); parseTask?.cancel(); parseTask = nil; isParsing = false }
    private func parse() {
        invalidateParse()
        errorMessage = nil
        do {
            let parsed = try SharedImportParser.parse(text)
            ranges = parsed.ranges; translation = parsed.translation ?? ""; translationConfirmed = false
            errorMessage = parsed.warnings.isEmpty ? nil : parsed.warnings.joined(separator: "\n")
        } catch {
            guard store.account != nil else { errorMessage = "章節を読み取れませんでした。手動で指定するか、ログイン後に確認してください。"; return }
            isParsing = true
            let submitted = text, generation = parseGeneration, epoch = store.sessionEpoch
            let requestClient = store.client
            parseTask = Task {
                defer { if parseGeneration == generation { isParsing = false } }
                do {
                    struct Input: Encodable, Sendable { let sharedText: String }
                    let parsed: ParsedImport = try await requestClient.post("/v1/imports/parse", body: Input(sharedText: submitted))
                    guard parseGeneration == generation, store.sessionEpoch == epoch, text == submitted, !Task.isCancelled else { return }
                    ranges = parsed.ranges; translation = parsed.translation ?? ""; translationConfirmed = false
                    errorMessage = parsed.warnings.isEmpty ? nil : parsed.warnings.joined(separator: "\n")
                } catch { if parseGeneration == generation, store.sessionEpoch == epoch, !Task.isCancelled { errorMessage = "章節を読み取れませんでした。手動で指定してください。" } }
            }
        }
    }
    private func save() {
        guard canSave else { return }
        let name = translation.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard name.isEmpty || name.range(of: #"^[A-Z0-9-]{1,30}$"#, options: .regularExpression) != nil else { errorMessage = "訳名は30文字以内の英数字・ハイフンで入力してください。"; return }
        isSaving = true; errorMessage = nil
        if let share, let owner = store.account?.id {
            do { idempotencyKey = try ShareInbox.submissionKey(share: share, owner: owner, ranges: ranges, translation: name.isEmpty ? nil : name) }
            catch { isSaving = false; errorMessage = "取り込み識別子を作成できませんでした。"; return }
        }
        let input = ImportInput(idempotencyKey: idempotencyKey, ranges: ranges, translation: name.isEmpty ? nil : name)
        let submittedShare = share, submittedExcerpt = text
        Task { defer { isSaving = false }; do { try await store.saveImport(input, share: submittedShare, transientExcerpt: submittedExcerpt); dismiss() } catch { errorMessage = (error as? NetworkFailure)?.userMessage ?? "保存できませんでした。同じ内容の再試行では重複保存しません。" } }
    }
}
