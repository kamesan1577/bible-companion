#if DEBUG
import SwiftUI
import CompanionCore

private enum ReadingSection: String, CaseIterable, Identifiable {
    case explanation = "解説", maps = "地図", people = "人物", art = "絵画"
    var id: String { rawValue }
    var symbol: String { switch self { case .explanation: BibleTheme.Symbol.reading; case .maps: BibleTheme.Symbol.map; case .people: BibleTheme.Symbol.people; case .art: BibleTheme.Symbol.art } }
}
struct Baseline018ReadingView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var section: ReadingSection = .explanation
    @State private var showGuide = false
    @State private var showStandardExplanation = false
    @State private var prepareAfterGuide = false
    var body: some View {
        Group {
            if let passage = store.selectedPassage {
                ZStack {
                    ForEach(ReadingSection.allCases) { page in
                        ScrollView {
                            BibleReadingColumn {
                                if let record = store.selected, record.ranges.count > 1 {
                                    Picker("表示する箇所", selection: Binding(get: { store.rangeIndex }, set: { store.changeRange($0) })) {
                                        ForEach(Array(record.ranges.enumerated()), id: \.offset) { index, range in Text(range.label).tag(index) }
                                    }.pickerStyle(.menu)
                                }
                                if page == .maps || page == .people {
                                    if page == .people { Text("人物の名前は確認できますが、日本語の説明がまだない人物もいます。").bibleTextStyle(.caption) }
                                    Baseline018OfflineEntityPane(passage: passage, kind: page == .maps ? "place" : "person")
                                }
                                if page == .explanation {
                                    StaticCommentaryView(passage: passage)
                                }
                                if store.isLoading && page == .explanation { ProgressView("この箇所に関する説明を開いています") }
                                else if let reading = store.reading { sectionContent(reading, passage: passage, section: page) }
                                else if page == .art {
                                    BibleStateView(title: "絵画を開けません", message: store.errorMessage ?? "再読み込みしてください。", systemImage: BibleTheme.Symbol.error)
                                    Button("再読み込み") { store.loadReading() }
                                }
                            }
                        }
                        .id("\(passage.label)-\(page.rawValue)")
                        .opacity(section == page ? 1 : 0).allowsHitTesting(section == page).accessibilityHidden(section != page)
                        .accessibilityIdentifier("reading-page-\(page.rawValue)")
                        .simultaneousGesture(DragGesture(minimumDistance: BibleTheme.Layout.minimumTouchTarget).onEnded { value in
                            guard !voiceOver, value.startLocation.x > BibleTheme.Layout.minimumTouchTarget, abs(value.translation.width) > BibleTheme.Layout.minimumTouchTarget * 2, abs(value.translation.width) > abs(value.translation.height) * 2 else { return }
                            changeSection(value.translation.width < 0 ? 1 : -1)
                        })
                    }
                }
                .safeAreaInset(edge: .top) {
                    VStack(spacing: BibleTheme.Space.sm) {
                        SharedScriptureHeader(passage: passage, translation: store.selected?.translation, text: store.sourceExcerpt)
                        sectionPicker.padding(.horizontal, BibleTheme.Space.page)
                    }.bibleCanvas()
                }
                .accessibilityAdjustableAction { direction in changeSection(direction == .increment ? 1 : -1) }
            } else {
                ScrollView { BibleReadingColumn {
                    BibleStateView(title: "読みたい箇所を選びましょう", message: "YouVersionの共有メニューから「聖書コンパニオン」を選んでください。", systemImage: BibleTheme.Symbol.reading)
                    NavigationLink("聖書の説明を章から探す") { StaticCommentaryBrowser() }
                    NavigationLink("まずはサンプルを読む") { SampleReadingPreview() }
                    Button("共有の手順を図で見る") { showGuide = true }
                    if store.account == nil { Button("YouVersionから解説を読む準備") { store.showAISetup = true }.buttonStyle(.borderedProminent); signInStatus }
                    else {
                        Button("YouVersionから解説を読む準備") { store.showAISetup = true }.buttonStyle(.borderedProminent)
                        Button("書名・章・節を入力する") { store.showImport = true }
                    }
                    if !store.pendingShares.isEmpty { Button("YouVersionから受け取った箇所を開く") { store.showImport = true } }
                } }
            }
        }
        .bibleCanvas()
        .navigationTitle(store.selectedPassage?.reference ?? "読書")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showGuide, onDismiss: { if prepareAfterGuide { prepareAfterGuide = false; store.showAISetup = true } }) { FirstRunGuide(onPrepare: { prepareAfterGuide = true; showGuide = false }).environmentObject(store) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("YouVersionから解説を読む準備", systemImage: "checklist") { store.showAISetup = true }
                    Button("箇所を追加", systemImage: "plus") { store.showImport = true }
                    Button("再読み込み", systemImage: "arrow.clockwise") { store.loadReading() }.disabled(store.selected == nil)
                    if let selected = store.selected { Label("履歴に保存済み", systemImage: "bookmark.fill"); Text(selected.translation ?? "訳名なし") }
                } label: { Label("読書メニュー", systemImage: "ellipsis") }
            }
        }
        .navigationDestination(isPresented: $showStandardExplanation) {
            if let passage = store.selectedPassage { standardExplanation(passage) }
        }
        .safeAreaInset(edge: .bottom) {
            if store.selectedPassage != nil {
                Menu {
                    Button("AIでこの箇所の解説を読む") {
                        if store.account == nil || store.aiPolicy?.permits(.groundedGeneration) != true { store.showAISetup = true }
                        else { showStandardExplanation = true }
                    }.disabled(store.reading == nil && store.account != nil)
                    Button("この箇所について質問する") {
                        if store.account == nil { store.showAISetup = true }
                        else { store.ask() }
                    }
                    Button("YouVersionから解説を読む準備") { store.showAISetup = true }
                } label: { BibleActionLabel(title: "AIで解説・質問", systemImage: BibleTheme.Symbol.question).frame(maxWidth: .infinity) }
                .buttonStyle(.glass).padding(.horizontal, BibleTheme.Space.page).padding(.vertical, BibleTheme.Space.sm)
            }
        }
    }
    private func changeSection(_ delta: Int) {
        guard let index = ReadingSection.allCases.firstIndex(of: section) else { return }
        section = ReadingSection.allCases[min(max(index + delta, 0), ReadingSection.allCases.count - 1)]
    }
    @ViewBuilder private func standardExplanation(_ passage: Passage) -> some View {
        if let reading = store.reading, let item = store.selected, let model = store.standardModel(item: item, passage: passage, sourceVersion: reading.sourceVersion) {
            ScrollView {
                BibleReadingColumn {
                    ReadingAIExplanation(model: model, passage: passage).id("standard-\(item.id)-\(passage.label)-\(reading.sourceVersion)")
                }
            }
            .safeAreaInset(edge: .top) { SharedScriptureHeader(passage: passage, translation: store.selected?.translation, text: store.sourceExcerpt) }
            .navigationTitle("AIの解説").navigationBarTitleDisplayMode(.inline).bibleCanvas()
        }
    }
    private var signInStatus: some View {
        VStack(alignment: .leading, spacing: BibleTheme.Space.md) {
            if !store.endpointConfigured { Text("アプリの接続設定に問題があります。最新版へ更新して、もう一度お試しください。").bibleTextStyle(.caption) }
            if store.isTransitioning { ProgressView("保存したログインを確認しています") }
            if store.restoreNeedsRetry { Button("保存したログインを再確認") { Task { await store.restore() } }.disabled(store.isTransitioning) }
            if store.isAuthenticating { Button("ログインを中止") { store.cancelSignIn() } }
            if let error = store.errorMessage { Text(error).bibleTextStyle(.caption).bibleForeground(.textSecondary) }
        }
    }
    private func rangeHeader(_ passage: Passage) -> some View {
        VStack(alignment: .leading, spacing: BibleTheme.Space.md) {
            Text(passage.bookName).bibleTextStyle(.heading)
            Text(passage.reference).bibleTextStyle(.verseReference).accessibilityLabel("\(passage.bookName)、\(passage.start.chapter)章\(passage.start.verse)節から\(passage.end.chapter)章\(passage.end.verse)節")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: BibleTheme.Space.md) { scopeBadges(passage) }
                VStack(alignment: .leading, spacing: BibleTheme.Space.sm) { scopeBadges(passage) }
            }
        }
    }
    @ViewBuilder private func scopeBadges(_ passage: Passage) -> some View {
        BibleRangeBadge(text: "選択箇所 · \(passage.verseCount)節")
        BibleScopeNotice(text: "\(passage.end.label)まで · ネタバレ防止")
    }
    @ViewBuilder private var sectionPicker: some View {
        if typeSize.isAccessibilitySize {
            Picker("表示内容", selection: $section) { ForEach(ReadingSection.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu)
        } else {
            Picker("表示内容", selection: $section) { ForEach(ReadingSection.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
        }
    }
    @ViewBuilder private func sectionContent(_ reading: ReadingResponse, passage: Passage, section: ReadingSection) -> some View {
        if section == .explanation {
            DisclosureGroup("聖書本文と出典を確かめる") {
            BibleSectionHeader(title: reading.overview.contentKind == "literal-primary-text" ? "出典の原文を確認する" : "選んだ箇所をつなげて読む", subtitle: reading.overview.contentKind == "literal-primary-text" ? "英語 · World English Bible" : "この箇所の背景")
            Text(reading.overview.noticeJa ?? "保存された参考説明です。AIがその場で書いた回答ではありません。")
                .bibleTextStyle(.caption).bibleForeground(.textSecondary)
            if reading.overview.contentKind == "literal-primary-text" {
                Text("World English Bibleの英語本文です。上にある日本語の説明と読み比べられます。").bibleTextStyle(.body)
                DisclosureGroup("英語原文の抜粋と出典") {
                    Text(reading.overview.text).bibleTextStyle(.body).textSelection(.enabled)
                    Baseline018CitationList(citations: reading.overview.citations)
                }
            } else { Text(reading.overview.text).bibleTextStyle(.body).textSelection(.enabled) }
            Text(reading.overview.referenceSystem?.noticeJa ?? ReferenceSystem.fallbackNotice).bibleTextStyle(.caption).bibleForeground(.textSecondary)
            if passage.chapterSegments.count > 1 {
                Menu("この章について質問する") {
                    ForEach(passage.chapterSegments, id: \.self) { range in
                        Button(range.label) { store.ask(target: range) }
                    }
                }
            }
            if reading.overview.contentKind != "literal-primary-text" { Baseline018CitationList(citations: reading.overview.citations) }
            if let item = store.selected { NavigationLink("英語の参考本文を開く") { ScriptureView(client: store.client, importID: item.id, rangeIndex: store.rangeIndex, passage: passage) } }
            }
        } else {
            let cards = (section == .maps ? reading.places : section == .people ? reading.people : reading.artworks).filter { $0.isDisplayable(reading: passage) }
            if cards.isEmpty && section == .art {
                BibleStateView(title: store.cachedSnapshot != nil ? "接続して\(section.rawValue)を確認" : "この箇所の\(section.rawValue)は未登録です", message: reading.materialNotice, systemImage: section.symbol)
            } else {
                if section == .maps { Text("場所の背景を確認できます。位置が分からない場所は、地図に表示していません。").bibleTextStyle(.caption).bibleForeground(.textSecondary) }
                ForEach(cards) { Baseline018MaterialCardView(card: $0, reading: passage) }
            }
        }
    }
}
struct Baseline018CitationList: View {
    let citations: [Citation]
    var body: some View {
        if !citations.isEmpty {
            VStack(alignment: .leading, spacing: BibleTheme.Space.md) {
                BibleSectionHeader(title: "出典")
                ForEach(citations) { citation in
                    VStack(alignment: .leading, spacing: BibleTheme.Space.xs) {
                        Text(citation.kindLabel).bibleTextStyle(.caption).bibleForeground(.textSecondary)
                        if citation.materialProvenance == nil, let url = citation.safeURL { Link(destination: url) { Label(citation.title, systemImage: BibleTheme.Symbol.source) } }
                        else { Text(citation.title) }
                        Text("\(citation.passage.label) · \(citation.license) · \(citation.version)").bibleTextStyle(.caption).bibleForeground(.textSecondary)
                        if let provenance = citation.materialProvenance {
                            DisclosureGroup("出典と利用条件") {
                                Text("\(provenance.kindLabel) · \(provenance.kind == "reviewed-material-summary" ? "収録済み要約" : "この内容の確認は終わっていません") · 版 \(provenance.materialVersion)").bibleTextStyle(.caption)
                                Text("以下は要約の根拠となった資料です。AIの説明全体の正確さを保証するものではありません。").bibleTextStyle(.caption)
                                ForEach(Array(provenance.references.enumerated()), id: \.offset) { _, reference in
                                    VStack(alignment: .leading, spacing: BibleTheme.Space.xs) {
                                        if let url = reference.safeURL { Link(reference.title, destination: url) } else { Text(reference.title) }
                                        Text("\(reference.publisher) · \(reference.license)").bibleTextStyle(.caption)
                                        if let attribution = reference.attribution { Text(attribution).bibleTextStyle(.caption) }
                                        if let url = reference.safeLicenseURL { Link("利用条件を読む", destination: url) }
                                        if let checked = reference.checkedAt { Text("出典確認: \(checked)").bibleTextStyle(.caption).bibleForeground(.textSecondary) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

#endif
