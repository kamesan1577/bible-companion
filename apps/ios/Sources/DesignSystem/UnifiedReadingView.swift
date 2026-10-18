import SwiftUI
import UIKit
import CompanionCore

@MainActor final class PublicReadingModel: ObservableObject {
    @Published var reading: ReadingResponse?
    @Published var error: String?
    @Published var loading = false
    @Published private(set) var requestedPassage: Passage?
    @Published private(set) var requestedTranslation: String?
    private var generation = UUID()
#if DEBUG
    static var fixtureClient: APIClient?
#endif
    func load(_ passage: Passage, translation: String?) async {
        let current = UUID(); generation = current; requestedPassage = passage; requestedTranslation = translation; reading = nil; error = nil; loading = true
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

private struct EntitySelection: Hashable {
    let passage: Passage
    let kind: String
    let includeFuture: Bool
    var revision = 0
}
@MainActor private final class ReadingLocalInventory: ObservableObject {
    struct EntityState {
        let key: EntitySelection
        var result: EntityIndexResult?
        var failure: String?
    }
    @Published private(set) var editsPassage: Passage?
    @Published private(set) var edits: [CommentaryEdit]?
    @Published private(set) var editsFailure: String?
    @Published private(set) var people: EntityState?
    @Published private(set) var places: EntityState?
    private var editGeneration = UUID()
    private var entityGenerations: [String: UUID] = [:]
    func loadEdits(_ passage: Passage) async {
        let generation = UUID(); editGeneration = generation
        editsPassage = passage; edits = nil; editsFailure = nil
        do {
            let values = try await StaticCommentary.shared.edits(for: passage)
            try Task.checkCancellation()
            guard editGeneration == generation else { return }
            var seen = Set<String>(); edits = values.filter { seen.insert($0.id).inserted }
        } catch { if editGeneration == generation, !Task.isCancelled { editsFailure = "解説の件数を確認できませんでした。" } }
    }
    func loadEntities(_ key: EntitySelection) async {
        let generation = UUID(); entityGenerations[key.kind] = generation
        set(EntityState(key: key))
        do {
            let result = try await BundledEntityIndex.shared.lookup(key.passage, kind: key.kind, includeFuture: key.includeFuture)
            try Task.checkCancellation()
            guard entityGenerations[key.kind] == generation else { return }
            set(EntityState(key: key, result: result))
        } catch {
            if entityGenerations[key.kind] == generation, !Task.isCancelled { set(EntityState(key: key, failure: "人物・場所の情報を表示できませんでした。")) }
        }
    }
    func state(_ key: EntitySelection) -> EntityState? {
        let value = key.kind == "person" ? people : places
        return value?.key == key ? value : nil
    }
    private func set(_ value: EntityState) { if value.key.kind == "person" { people = value } else { places = value } }
}

private enum ReadingBadgeState {
    case loading, unavailable, count(Int)
    var text: String { switch self { case .loading: "…"; case .unavailable: "—"; case .count(let n): ReadingContentProjection.badgeText(n) } }
    var spoken: String { switch self { case .loading: "件数を確認中"; case .unavailable: "件数を確認できません"; case .count(let n): "\(n)件" } }
    var isPositive: Bool { if case .count(let n) = self { n > 0 } else { false } }
}

struct UnifiedReadingView: View {
    let passage: Passage
    let translation: String?
    let sharedText: String
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.dynamicTypeSize) private var typeSize
    @StateObject private var model = PublicReadingModel()
    @StateObject private var local = ReadingLocalInventory()
    @State private var peopleFuture = false
    @State private var placesFuture = false
    @State private var futureScope: Passage?
    @Environment(\.colorScheme) private var scheme
    private var reading: ReadingResponse? { model.requestedPassage == passage && model.requestedTranslation == translation ? model.reading : nil }
    private var personKey: EntitySelection { EntitySelection(passage: passage, kind: "person", includeFuture: futureScope == passage && peopleFuture, revision: retry) }
    private var placeKey: EntitySelection { EntitySelection(passage: passage, kind: "place", includeFuture: futureScope == passage && placesFuture, revision: retry) }
    private func cards(_ page: UnifiedReadingSection) -> [MaterialCard] {
        let values = page == .maps ? reading?.places ?? [] : page == .people ? reading?.people ?? [] : reading?.artworks ?? []
        return ReadingContentProjection.materials(values, kind: page == .maps ? "place" : page == .people ? "person" : "artwork", passage: passage)
    }
    private func badge(_ page: UnifiedReadingSection) -> ReadingBadgeState {
        let matchingPublic = model.requestedPassage == passage && model.requestedTranslation == translation
        guard let reading else { return matchingPublic && model.error != nil ? .unavailable : .loading }
        if page == .art { return .count(cards(page).count) }
        if page == .explanation {
            guard local.editsPassage == passage, let edits = local.edits else { return local.editsPassage == passage && local.editsFailure != nil ? .unavailable : .loading }
            return .count(ReadingContentProjection.explanationCount(edits: edits, publicText: reading.overview.citations.isEmpty ? "" : reading.overview.text))
        }
        let key = page == .maps ? placeKey : personKey
        guard let state = local.state(key), let result = state.result else { return local.state(key)?.failure != nil ? .unavailable : .loading }
        let visible = cards(page)
        return .count(visible.count + ReadingContentProjection.additions(result, covered: visible.map(\.id)).count)
    }
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
                    let page = section
                        ScrollView {
                            BibleReadingColumn {
                                if page == .explanation {
                                    StaticCommentaryView(passage: passage, usesPreparedEdits: true, preparedEdits: local.editsPassage == passage ? local.edits : nil, preparedFailure: local.editsPassage == passage ? local.editsFailure : nil)
                                    if let reading {
                                        DisclosureGroup("聖書本文と出典を確かめる") {
                                            Text(reading.overview.noticeJa ?? "収録された公開資料です。独自AIの回答ではありません。").bibleTextStyle(.caption)
                                            Text(reading.overview.text).bibleTextStyle(.body).textSelection(.enabled)
                                            CitationList(citations: reading.overview.citations)
                                        }
                                    }
                                } else if page == .maps || page == .people {
                                    let visible = cards(page)
                                    ForEach(visible) { MaterialCardView(card: $0, reading: passage) }
                                    let state = local.state(page == .maps ? placeKey : personKey)
                                    OfflineEntityPane(passage: passage, kind: page == .maps ? "place" : "person", coveredMaterialCardIDs: visible.map(\.id), usesPreparedResult: true, preparedResult: state?.result, preparedFailure: state?.failure, futureSelection: futureBinding(page))
                                } else {
                                    let cards = cards(page)
                                    ForEach(cards) { MaterialCardView(card: $0, reading: passage) }
                                    if cards.isEmpty && !model.loading { Text(reading == nil ? "公開資料に接続すると、この箇所の絵画を確認できます。" : "この箇所に対応する確認済みの絵画資料はありません。").bibleTextStyle(.body) }
                                }
                                if local.editsFailure != nil || local.state(personKey)?.failure != nil || local.state(placeKey)?.failure != nil { Button("件数を確認し直す") { retry += 1 } }
                                if model.loading { ProgressView("公開資料を確認しています") }
                                if let error = model.error { Text(error).bibleTextStyle(.caption); Button("公開資料を読み直す") { retry += 1 } }
                            }
                        }
                        .id(section)
                        .scrollDismissesKeyboard(.interactively)
                        .accessibilityIdentifier("reading-page-\(page.rawValue)")
                        .simultaneousGesture(DragGesture(minimumDistance: BibleTheme.Layout.minimumTouchTarget).onEnded { value in
                            guard !voiceOver, value.startLocation.x > 44, abs(value.translation.width) > 88, abs(value.translation.width) > abs(value.translation.height) * 2 else { return }
                            changeSection(value.translation.width < 0 ? 1 : -1)
                        })
                }
                .safeAreaInset(edge: .top) {
                    VStack(spacing: BibleTheme.Space.sm) {
                        SharedScriptureHeader(passage: passage, translation: translation, text: sharedText.isEmpty ? nil : sharedText)
                        sectionPicker.padding(.horizontal, BibleTheme.Space.page)
                    }.bibleCanvas()
                }
                .overlay(alignment: .bottom) { if let notice { Text(notice).bibleTextStyle(.caption).padding().background(.regularMaterial) } }
                .safeAreaInset(edge: .bottom) { ExternalQuestionComposer(passage: passage, translation: translation, sharedText: sharedText) }
            }
        }
        .bibleCanvas().navigationTitle(passage.reference).navigationBarTitleDisplayMode(.inline)
        .task(id: ReadingContextKey(passage: passage, translation: translation, sharedText: sharedText)) { prepareLocalState(); await model.load(passage, translation: translation) }
        .task(id: passage.label + ":" + String(retry)) { await local.loadEdits(passage) }
        .task(id: personKey) { await local.loadEntities(personKey) }
        .task(id: placeKey) { await local.loadEntities(placeKey) }
        .task(id: retry) { if retry > 0 { await model.load(passage, translation: translation) } }
        .onChange(of: passage) { _, _ in futureScope = passage; peopleFuture = false; placesFuture = false; section = .explanation }
        .onChange(of: scenePhase) { _, phase in if phase == .active { checkOwner() } }
    }
    private func futureBinding(_ page: UnifiedReadingSection) -> Binding<Bool> {
        Binding(get: { futureScope == passage && (page == .maps ? placesFuture : peopleFuture) }, set: { value in
            if futureScope != passage { peopleFuture = false; placesFuture = false; futureScope = passage }
            if page == .maps { placesFuture = value } else { peopleFuture = value }
        })
    }
    private var sectionPicker: some View {
        Group {
            if typeSize.isAccessibilitySize {
                Picker("表示内容", selection: $section) {
                    ForEach(UnifiedReadingSection.allCases) { page in Text("\(page.rawValue) · \(badge(page).spoken)").tag(page) }
                }.pickerStyle(.menu)
            } else {
                HStack(spacing: 2) {
                    ForEach(UnifiedReadingSection.allCases) { page in
                        let value = badge(page)
                        Button { section = page } label: {
                            Text(page.rawValue).font(.subheadline.weight(.semibold)).lineLimit(1).offset(y: 4)
                                .frame(maxWidth: .infinity).frame(minHeight: 48)
                                .background(section == page ? (scheme == .dark ? BibleTheme.color(.textPrimary, scheme: scheme).opacity(0.24) : BibleTheme.color(.surface, scheme: scheme)) : .clear, in: Capsule())
                                .overlay(alignment: .topTrailing) {
                                    Text(value.text).font(.system(size: 10, weight: value.isPositive ? .bold : .medium, design: .rounded))
                                        .monospacedDigit().fixedSize().padding(.horizontal, 4).frame(minWidth: 17, minHeight: 16)
                                        .foregroundStyle(value.isPositive ? BibleTheme.color(.canvas, scheme: scheme) : BibleTheme.color(.textSecondary, scheme: scheme))
                                        .background(value.isPositive ? BibleTheme.color(.accent, scheme: scheme) : .clear, in: Capsule())
                                        .padding(.trailing, 3).padding(.top, 1).accessibilityHidden(true)
                                }
                        }.buttonStyle(.plain).bibleForeground(.textPrimary)
                            .accessibilityLabel(page.rawValue).accessibilityValue(value.spoken)
                            .accessibilityAddTraits(section == page ? [.isSelected] : [])
                            .accessibilityHint(page == .explanation ? "日本語解説カードと公開本文資料の件数。英語注解と辞典の検索は含みません。" : page == .maps ? "地図タブの場所の資料・名前の件数。地図座標の数ではありません。" : page == .people ? "人物タブの資料・名前の件数。重複は除いています。" : "この箇所で閲覧できる作品数。画像の取得はタブを開いた後です。")
                    }
                }.padding(3).background(Color.secondary.opacity(0.12), in: Capsule())
            }
        }.accessibilityIdentifier("reading-section-tabs")
    }
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
    @Environment(\.colorScheme) private var scheme
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
                if focused { Button { focused = false } label: { Image(systemName: "keyboard.chevron.compact.down") }.accessibilityLabel("キーボードを閉じる").frame(minWidth: 44, minHeight: 44) }
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
        .tint(BibleTheme.color(.accent, scheme: scheme))
        .task(id: ReadingContextKey(passage: passage, translation: translation, sharedText: sharedText)) { prepareLocalState() }
        .onChange(of: draft) { _, text in
            guard let visit, !revoked else { return }
            do { try ShareInbox.saveExternalDraft(text, for: visit) } catch { notice = "下書きを端末に保存できません。この画面の入力は残しています。" }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { checkOwner(); provider = (try? ShareInbox.externalProvider()) ?? provider } }
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
