import SwiftUI
import CompanionCore

private enum ReadingSection: String, CaseIterable, Identifiable {
    case explanation = "解説", maps = "地図", people = "人物", art = "絵画"
    var id: String { rawValue }
    var symbol: String { switch self { case .explanation: BibleTheme.Symbol.reading; case .maps: BibleTheme.Symbol.map; case .people: BibleTheme.Symbol.people; case .art: BibleTheme.Symbol.art } }
}
struct ReadingView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var section: ReadingSection = .explanation
    var body: some View {
        ScrollView {
            BibleReadingColumn {
                if let passage = store.selectedPassage {
                    rangeHeader(passage)
                    if let record = store.selected, record.ranges.count > 1 {
                        Picker("表示する箇所", selection: Binding(get: { store.rangeIndex }, set: { store.changeRange($0) })) {
                            ForEach(Array(record.ranges.enumerated()), id: \.offset) { index, range in Text(range.label).tag(index) }
                        }.pickerStyle(.menu)
                    }
                    if let excerpt = store.sourceExcerpt {
                        DisclosureGroup("共有したテキスト") {
                            Text(excerpt).bibleTextStyle(.body).textSelection(.enabled)
                            Text("この起動中のみ保持しています。履歴には保存しません。").bibleTextStyle(.caption).bibleForeground(.textSecondary)
                        }
                    }
                    if let cached = store.cachedSnapshot {
                        BibleReadingSurface {
                            VStack(alignment: .leading, spacing: BibleTheme.Space.sm) {
                                Label(store.isRevalidatingSource ? "保存した資料 · 更新を確認中" : store.isOffline ? "保存した資料 · オフラインで閲覧" : "保存した資料 · 更新は未確認", systemImage: "arrow.down.circle")
                                    .bibleTextStyle(.caption)
                                Text("最終確認: \(cached.lastValidatedAt.formatted(date: .abbreviated, time: .shortened))").bibleTextStyle(.caption)
                                Text("公開利用が確認された概要です。保存から24時間以内のみ表示します。地図・人物・絵画は再接続後に確認できます。").bibleTextStyle(.caption).bibleForeground(.textSecondary)
                            }
                        }
                    }
                    sectionPicker
                    if store.isLoading {
                        BibleLoadingView()
                        Button("読み込みを中止") { store.cancelReading() }
                    } else if let reading = store.reading {
                        sectionContent(reading, passage: passage)
                    } else {
                        BibleStateView(title: store.isOffline ? "オフラインです" : "資料を読み込めません", message: store.errorMessage ?? "資料を読み込むと、選んだ箇所の背景を確認できます。", systemImage: BibleTheme.Symbol.error)
                        Button("再読み込み") { store.loadReading() }.buttonStyle(.bordered)
                    }
                } else {
                    BibleSectionHeader(title: "読んだ箇所を、もう少し深く。", subtitle: "YouVersionから共有した章節を、ひとつの文脈のまま。")
                    BibleStateView(title: "最初の箇所を開く", message: "YouVersionの共有メニューから「聖書コンパニオン」を選んでください。ここから章節や共有テキストを入力することもできます。", systemImage: BibleTheme.Symbol.reading)
                    if store.account == nil { signInPrompt }
                    else { Button { store.showImport = true } label: { BibleActionLabel(title: "章節を入力する", systemImage: "plus") }.buttonStyle(.glass) }
                }
                if !store.pendingShares.isEmpty {
                    Button { store.showImport = true } label: { BibleActionLabel(title: "共有された箇所を確認（\(store.pendingShares.count)）", systemImage: "square.and.arrow.down") }.buttonStyle(.glass)
                }
            }
        }
        .bibleCanvas()
        .navigationTitle(store.selectedPassage?.reference ?? "読書")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("箇所を追加", systemImage: "plus") { store.showImport = true }
                    Button("再読み込み", systemImage: "arrow.clockwise") { store.loadReading() }.disabled(store.selected == nil)
                    if let selected = store.selected { Label("履歴に保存済み", systemImage: "bookmark.fill"); Text(selected.translation ?? "訳は未確認") }
                } label: { Label("読書メニュー", systemImage: "ellipsis") }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if store.selectedPassage != nil {
                Button { store.ask() } label: { BibleActionLabel(title: "この箇所について質問", systemImage: BibleTheme.Symbol.question).frame(maxWidth: .infinity) }
                    .buttonStyle(.glass).padding(.horizontal, BibleTheme.Space.page).padding(.vertical, BibleTheme.Space.sm)
            }
        }
    }
    private var signInPrompt: some View {
        VStack(alignment: .leading, spacing: BibleTheme.Space.md) {
            Button { store.signIn() } label: { BibleActionLabel(title: store.isAuthenticating ? "ログイン中" : "パスキーでログイン", systemImage: "person.crop.circle") }.buttonStyle(.glass).disabled(!store.endpointConfigured || store.isAuthenticating || store.isTransitioning || store.restoreNeedsRetry || store.localCleanupRequired)
            if !store.endpointConfigured { Text("接続先が未設定です。HTTPSサーバーを設定したビルドでログインできます。資料やAIモデルへの接続はまだ行っていません。").bibleTextStyle(.caption) }
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
        BibleScopeNotice(text: "\(passage.end.label)まで · 先を含めない")
    }
    @ViewBuilder private var sectionPicker: some View {
        if typeSize.isAccessibilitySize {
            Picker("表示内容", selection: $section) { ForEach(ReadingSection.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu)
        } else {
            Picker("表示内容", selection: $section) { ForEach(ReadingSection.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
        }
    }
    @ViewBuilder private func sectionContent(_ reading: ReadingResponse, passage: Passage) -> some View {
        if section == .explanation {
            BibleSectionHeader(title: reading.overview.contentKind == "literal-primary-text" ? "出典の原文を確認する" : "選んだ箇所をつなげて読む", subtitle: reading.overview.contentKind == "literal-primary-text" ? "英語 · World English Bible" : "資料からの案内")
            Text(reading.overview.noticeJa ?? "出典に基づく資料からの案内です。AI生成ではありません。")
                .bibleTextStyle(.caption).bibleForeground(.textSecondary)
            if reading.overview.contentKind == "literal-primary-text" {
                Text("この箇所の日本語解説はまだありません。出典の英語原文を参考として確認できます。").bibleTextStyle(.body)
                DisclosureGroup("英語原文の抜粋と出典") {
                    Text(reading.overview.text).bibleTextStyle(.body).textSelection(.enabled)
                    CitationList(citations: reading.overview.citations)
                }
            } else { Text(reading.overview.text).bibleTextStyle(.body).textSelection(.enabled) }
            Text(reading.overview.referenceSystem?.noticeJa ?? ReferenceSystem.fallbackNotice).bibleTextStyle(.caption).bibleForeground(.textSecondary)
            if passage.chapterSegments.count > 1 {
                Menu("範囲を絞って質問") {
                    ForEach(passage.chapterSegments, id: \.self) { range in
                        Button(range.label) { store.ask(target: range) }
                    }
                }
            }
            if reading.overview.contentKind != "literal-primary-text" { CitationList(citations: reading.overview.citations) }
            if let item = store.selected { NavigationLink("英語の参考本文を開く") { ScriptureView(client: store.client, importID: item.id, rangeIndex: store.rangeIndex, passage: passage) } }
        } else {
            let cards = (section == .maps ? reading.places : section == .people ? reading.people : reading.artworks).filter { $0.isDisplayable(reading: passage) }
            if cards.isEmpty {
                BibleStateView(title: store.cachedSnapshot != nil ? "接続して\(section.rawValue)を確認" : "この箇所の\(section.rawValue)は未登録です", message: reading.materialNotice, systemImage: section.symbol)
            } else {
                if section == .maps { Text("確認済みの地名と背景です。位置の座標が未確認の場所は、地図上に推測のピンを置きません。").bibleTextStyle(.caption).bibleForeground(.textSecondary) }
                ForEach(cards) { MaterialCardView(card: $0, reading: passage) }
            }
        }
    }
}
struct CitationList: View {
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
                            DisclosureGroup("資料の原出典・著作権表示") {
                                Text("\(provenance.kindLabel) · \(provenance.kind == "reviewed-material-summary" ? "編集確認済み要約" : "確認状態は未確認") · 版 \(provenance.materialVersion)").bibleTextStyle(.caption)
                                Text("以下は要約の根拠となった資料です。AIの説明全体の正確さを保証するものではありません。").bibleTextStyle(.caption)
                                ForEach(Array(provenance.references.enumerated()), id: \.offset) { _, reference in
                                    VStack(alignment: .leading, spacing: BibleTheme.Space.xs) {
                                        if let url = reference.safeURL { Link(reference.title, destination: url) } else { Text(reference.title) }
                                        Text("\(reference.publisher) · \(reference.license)").bibleTextStyle(.caption)
                                        if let attribution = reference.attribution { Text(attribution).bibleTextStyle(.caption) }
                                        if let url = reference.safeLicenseURL { Link("ライセンスを確認", destination: url) }
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
