import SwiftUI
import UIKit
import CompanionCore

@MainActor final class PublicReadingModel: ObservableObject {
    @Published var reading: ReadingResponse?
    @Published var error: String?
    @Published var loading = false
    private var generation = UUID()
#if DEBUG
    static var fixtureClient: APIClient?
#endif
    func load(_ passage: Passage, translation: String?) async {
        let current = UUID(); generation = current; reading = nil; error = nil; loading = true
        defer { if generation == current { loading = false } }
        do {
            let raw = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String ?? "https://unconfigured.invalid"
            let client: APIClient
#if DEBUG
            if let fixture = Self.fixtureClient { client = fixture }
            else { client = try APIClient(baseURL: URL(string: raw) ?? URL(string: "https://unconfigured.invalid")!) }
#else
            client = try APIClient(baseURL: URL(string: raw) ?? URL(string: "https://unconfigured.invalid")!)
#endif
            struct Input: Encodable, Sendable { let passage: Passage; let translation: String? }
            let result: ReadingResponse = try await client.post("/public/reading", body: Input(passage: passage, translation: translation))
            try Task.checkCancellation()
            guard generation == current else { return }
            guard result.passage == passage, result.translation == translation,
                  !result.spoilerAllowed, result.overview.modelInvoked == false else { throw NetworkFailure.invalidResponse }
            reading = result
        } catch { if generation == current, !Task.isCancelled { self.error = "公開資料を読み込めませんでした。端末に収録した説明と索引は引き続き読めます。" } }
    }
}

struct ExternalProviderPicker: View {
    @Binding var provider: ExternalQuestionProvider
    @State private var failure: String?
    var body: some View {
        Picker("質問を送るサービス", selection: $provider) {
            ForEach(ExternalQuestionProvider.allCases) { Text($0.title).tag($0) }
        }.accessibilityIdentifier("external-provider-picker")
        Text(provider.deliveryNotice).bibleTextStyle(.caption)
        Text("聖句・共有した原文・入力した質問だけを渡します。アプリのログイン情報や、以前の会話は渡しません。").bibleTextStyle(.caption)
        if let failure { Text(failure).bibleTextStyle(.caption) }
        Color.clear.frame(height: 0)
            .onAppear { do { provider = try ShareInbox.externalProvider() } catch { failure = "サービス選択の共有保存先を読めません。表示中の選択を使います。" } }
            .onChange(of: provider) { _, value in
                do { try ShareInbox.setExternalProvider(value); failure = nil }
                catch { failure = "選択を他の画面へ保存できませんでした。この画面では選択中のサービスへ渡します。" }
            }
    }
}

struct ExternalQuestionSettings: View {
    @Binding var provider: ExternalQuestionProvider
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form { Section("質問の送信先") { ExternalProviderPicker(provider: $provider) } }
                .navigationTitle("外部サービス").bibleCanvas()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } } }
        }
    }
}

enum UnifiedReadingSection: String, CaseIterable, Identifiable {
    case explanation = "解説", maps = "地図", people = "人物", art = "絵画"
    var id: String { rawValue }
}

struct UnifiedReadingView: View {
    let passage: Passage
    let translation: String?
    let sharedText: String
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.dynamicTypeSize) private var typeSize
    @StateObject private var model = PublicReadingModel()
    @State private var section = UnifiedReadingSection.explanation
    @State private var visit: LocalReadingVisit?
    @State private var ownerKnown = false
    @State private var revoked = false
    @State private var notice: String?
    @State private var retry = 0
    var body: some View {
        Group {
            if revoked { BibleStateView(title: "表示するアカウントが変わりました", message: "下書きは別のアカウントへ渡しません。この画面を閉じて、箇所を開き直してください。") }
            else {
                ZStack {
                    ForEach(UnifiedReadingSection.allCases) { page in
                        ScrollView {
                            BibleReadingColumn {
                                if page == .explanation {
                                    StaticCommentaryView(passage: passage)
                                    if let reading = model.reading {
                                        DisclosureGroup("聖書本文と出典を確かめる") {
                                            Text(reading.overview.noticeJa ?? "収録された公開資料です。独自AIの回答ではありません。").bibleTextStyle(.caption)
                                            Text(reading.overview.text).bibleTextStyle(.body).textSelection(.enabled)
                                            CitationList(citations: reading.overview.citations)
                                        }
                                    }
                                } else if page == .maps || page == .people {
                                    let cards = page == .maps ? model.reading?.places ?? [] : model.reading?.people ?? []
                                    ForEach(cards.filter { $0.isDisplayable(reading: passage) }) { MaterialCardView(card: $0, reading: passage) }
                                    OfflineEntityPane(passage: passage, kind: page == .maps ? "place" : "person", coveredMaterialCardIDs: cards.map(\.id))
                                } else {
                                    let cards = model.reading?.artworks.filter { $0.isDisplayable(reading: passage) } ?? []
                                    ForEach(cards) { MaterialCardView(card: $0, reading: passage) }
                                    if cards.isEmpty && !model.loading { Text(model.reading == nil ? "公開資料に接続すると、この箇所の絵画を確認できます。" : "この箇所に対応する確認済みの絵画資料はありません。").bibleTextStyle(.body) }
                                }
                                if model.loading { ProgressView("公開資料を確認しています") }
                                if let error = model.error { Text(error).bibleTextStyle(.caption); Button("公開資料を読み直す") { retry += 1 } }
                            }
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .opacity(section == page ? 1 : 0).allowsHitTesting(section == page).accessibilityHidden(section != page)
                        .accessibilityIdentifier("reading-page-\(page.rawValue)")
                        .simultaneousGesture(DragGesture(minimumDistance: BibleTheme.Layout.minimumTouchTarget).onEnded { value in
                            guard !voiceOver, value.startLocation.x > 44, abs(value.translation.width) > 88, abs(value.translation.width) > abs(value.translation.height) * 2 else { return }
                            changeSection(value.translation.width < 0 ? 1 : -1)
                        })
                    }
                }
                .safeAreaInset(edge: .top) {
                    VStack(spacing: BibleTheme.Space.sm) {
                        SharedScriptureHeader(passage: passage, translation: translation, text: sharedText.isEmpty ? nil : sharedText)
                        Group {
                            if typeSize.isAccessibilitySize { sectionPicker.pickerStyle(.menu) }
                            else { sectionPicker.pickerStyle(.segmented) }
                        }.padding(.horizontal, BibleTheme.Space.page)
                    }.bibleCanvas()
                }
                .overlay(alignment: .bottom) { if let notice { Text(notice).bibleTextStyle(.caption).padding().background(.regularMaterial) } }
                .safeAreaInset(edge: .bottom) { ExternalQuestionComposer(passage: passage, translation: translation, sharedText: sharedText) }
            }
        }
        .bibleCanvas().navigationTitle(passage.reference).navigationBarTitleDisplayMode(.inline)
        .task(id: passage) { prepareLocalState(); await model.load(passage, translation: translation) }
        .task(id: retry) { if retry > 0 { await model.load(passage, translation: translation) } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { checkOwner() } }
    }
    private var sectionPicker: some View { Picker("表示内容", selection: $section) { ForEach(UnifiedReadingSection.allCases) { Text($0.rawValue).tag($0) } } }
    private func changeSection(_ delta: Int) {
        guard let index = UnifiedReadingSection.allCases.firstIndex(of: section) else { return }
        section = UnifiedReadingSection.allCases[min(max(index + delta, 0), UnifiedReadingSection.allCases.count - 1)]
    }
    private func prepareLocalState() {
        do {
            let owner = try ShareInbox.activeReadingOwner(); ownerKnown = true
            let value = LocalReadingVisit(ownerID: owner, passage: passage, translation: translation, sharedText: sharedText)
            visit = value; try ShareInbox.saveReadingVisit(value)
        } catch { notice = "端末内の保存先を確認できません。入力はこの画面に残し、選択中の外部サービスへ渡せます。" }
    }
    private func checkOwner() {
        guard ownerKnown else { return }
        do {
            if try ShareInbox.activeReadingOwner() != visit?.ownerID { revoked = true }
        } catch { revoked = true }
    }
}

private struct ReadingContextKey: Hashable { let passage: Passage?; let translation: String?; let sharedText: String }

struct ExternalQuestionComposer: View {
    let passage: Passage?
    let translation: String?
    let sharedText: String
    @Environment(\.scenePhase) private var scenePhase
    @State private var provider = ExternalQuestionProvider.chatGPT
    @State private var draft = ""
    @State private var visit: LocalReadingVisit?
    @State private var ownerKnown = false
    @State private var revoked = false
    @State private var notice: String?
    @State private var showSettings = false
    @State private var lastOpen = Date.distantPast
    @FocusState private var focused: Bool
    private var request: ExternalQuestionHandoff? {
        guard let passage, !revoked else { return nil }
        return try? ExternalQuestionHandoff(provider: provider, question: draft, passage: passage, translation: translation, sharedText: sharedText)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: BibleTheme.Space.sm) {
            HStack {
                Text("質問先：\(provider.title)").bibleTextStyle(.caption)
                Spacer()
                Button { focused = false; showSettings = true } label: { Label("送信先の設定", systemImage: "slider.horizontal.3") }.labelStyle(.iconOnly).accessibilityIdentifier("external-provider-settings")
            }
            TextField(passage == nil ? "箇所を開くと質問できます" : "この箇所について質問", text: $draft, axis: .vertical)
                .lineLimit(1...4).textFieldStyle(.plain).padding(BibleTheme.Space.md)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16)).focused($focused)
                .accessibilityIdentifier("external-question-input").disabled(passage == nil || revoked)
            if draft.utf16.count > 2000 { Text("質問は2000文字以内にしてください。入力は切り詰めず残しています。").bibleTextStyle(.caption) }
            if let notice { Text(notice).bibleTextStyle(.caption).accessibilityIdentifier("external-handoff-status") }
            if let request {
                Link(destination: request.url) { Label(request.buttonTitle, systemImage: "arrow.up.right.square").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).accessibilityIdentifier("external-question-send")
                    .environment(\.openURL, OpenURLAction { url in
                        guard !revoked, Date().timeIntervalSince(lastOpen) > 1 else { return .discarded }
                        checkOwner(); guard !revoked else { return .discarded }
                        lastOpen = Date()
                        UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: request.prompt]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(600)])
                        notice = request.requiresPaste ? "全文をコピーしました。\(provider.title)の入力欄に貼り付けて送信してください。ログインが必要な場合があります。" : "\(provider.title)へ渡します。開いた先で内容を確認してください。回答が始まる場合があります。"
                        return .systemAction(url)
                    })
            } else { Label("\(provider.title)へ質問", systemImage: "arrow.up.right.square").frame(maxWidth: .infinity).foregroundStyle(.secondary).padding(.vertical, BibleTheme.Space.sm) }
            if !focused { Text(provider.deliveryNotice).bibleTextStyle(.caption) }
        }.padding(.horizontal, BibleTheme.Space.page).padding(.vertical, BibleTheme.Space.sm).background(.regularMaterial)
        .task(id: ReadingContextKey(passage: passage, translation: translation, sharedText: sharedText)) { prepareLocalState() }
        .onChange(of: draft) { _, text in
            guard let visit, !revoked else { return }
            do { try ShareInbox.saveExternalDraft(text, for: visit) } catch { notice = "下書きを端末に保存できません。この画面の入力は残しています。" }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { checkOwner(); provider = (try? ShareInbox.externalProvider()) ?? provider } }
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("キーボードを閉じる") { focused = false } } }
        .sheet(isPresented: $showSettings) { ExternalQuestionSettings(provider: $provider) }
    }
    private func prepareLocalState() {
        visit = nil; draft = ""; ownerKnown = false; revoked = false
        guard let passage else { return }
        do {
            let owner = try ShareInbox.activeReadingOwner(); ownerKnown = true
            let value = LocalReadingVisit(ownerID: owner, passage: passage, translation: translation, sharedText: sharedText)
            visit = value
            draft = try ShareInbox.externalDraft(for: value)
            provider = try ShareInbox.externalProvider()
        } catch { notice = "端末内の保存先を確認できません。入力はこの画面に残し、選択中の外部サービスへ渡せます。" }
    }
    private func checkOwner() {
        guard ownerKnown else { return }
        do {
            if try ShareInbox.activeReadingOwner() != visit?.ownerID { revoked = true; draft = ""; focused = false }
        } catch { revoked = true; draft = ""; focused = false }
    }
}
