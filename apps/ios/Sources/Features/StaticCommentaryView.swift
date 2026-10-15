import SwiftUI
import CompanionCore

struct StaticCommentaryView: View {
    let passage: Passage
    @State private var edits: [CommentaryEdit] = []
    @State private var failure: String?
    @State private var progress: CommentaryProgress?
    var body: some View {
        VStack(alignment: .leading, spacing: BibleTheme.Space.md) {
            BibleSectionHeader(title: "出典に基づく日本語編集", subtitle: "端末に保存された資料")
            if let failure { Text(failure).bibleTextStyle(.caption) }
            else if edits.isEmpty { Text("この選択範囲で先読みせずに表示できる日本語説明は、まだ整備されていません。").bibleTextStyle(.body) }
            ForEach(edits) { edit in
                VStack(alignment: .leading, spacing: BibleTheme.Space.sm) {
                    Text(edit.titleJa).bibleTextStyle(.heading)
                    Text(edit.passage.label).bibleTextStyle(.caption)
                    Text(progress?.sourceComparedEntryIds.contains(edit.id) == true ? "AIによる日本語編集・別のAIが原典とWEBに照合（専門家校閲なし）" : "AI補助の日本語編集・専門家校閲なし").bibleTextStyle(.caption)
                    Text("本文の要約").bibleTextStyle(.caption)
                    Text(edit.summaryJa).bibleTextStyle(.body).textSelection(.enabled)
                    DisclosureGroup("原典の注解と、この範囲の注意") {
                        Text(edit.authorInterpretationJa).bibleTextStyle(.body)
                        if let note = edit.editorialNoteForDisplay { Text(note).bibleTextStyle(.caption) }
                    }
                    Text(edit.sourceUnitIds.map { $0.hasPrefix("mhc:") ? "Matthew Henry’s Complete Commentary · 2.2" : "Jamieson–Fausset–Brown · 3.0" }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.joined(separator: " / ")).bibleTextStyle(.caption)
                }
            }
            NavigationLink("英語の注解原文・出典を読む") { CommentaryOriginalView(passage: passage) }
            NavigationLink("英語の聖書辞典を調べる") { CommentaryDictionaryView() }
            DisclosureGroup("資料の整備状況") {
                Text("歴史的なプロテスタントの注解を根拠にしたAI補助の編集要約です。原文そのもの・専門家監修済みの解説とは区別します。").bibleTextStyle(.caption)

                Text("英語原文の節への直接対応は31,101／31,102。章冒頭の見出し・注は別に収録しています。サムエル記下22:1も章注から読めるため、原典自体の欠落を表す数ではありません。章全体の注・節別の注・日本語説明の整備数を分けます。").bibleTextStyle(.caption)
                Text("使徒8:37・15:34・24:7は手元のWEB本文にないため、日本語の通常説明を補作していません。KJV系の節番号との違いがあります。").bibleTextStyle(.caption)
                if let progress {
                    Text("日本語編集：\(progress.editedRanges)範囲・\(progress.coveredCoordinates)節座標。うち8節以下の具体的説明は\(progress.detailedRanges)範囲・\(progress.detailedCoordinates)節座標、章概説は\(progress.chapterOverviews)件です。全聖書の同粒度の整備と専門家校閲は未完です。").bibleTextStyle(.caption)
                    if !progress.completeActsChapters.isEmpty {
                        Text("使徒の全節座標を短い範囲で収録した章：" + progress.completeActsChapters.map(String.init).joined(separator: "、") + "。節座標の網羅は、解釈の正しさや全節の同じ詳しさを保証しません。").bibleTextStyle(.caption)
                    }
                }
            }
        }.task(id: passage) {
            do { edits = try await StaticCommentary.shared.edits(for: passage); progress = try await StaticCommentary.shared.progress(); failure = nil }
            catch { edits = []; failure = "保存資料を読み込めませんでした。" }
        }
    }
}
private struct CommentaryOriginalView: View {
    let passage: Passage
    @State private var accepted = false
    @State private var originals: [CommentaryOriginal] = []
    @State private var failed = false
    var body: some View {
        ScrollView { BibleReadingColumn {
            Text("英語原文には選択箇所より先の出来事や他の書への言及が含まれます。").bibleTextStyle(.body)
            if !accepted { Button("先の内容を含む英語原文を開く") { accepted = true } }
            else {
                if failed { Text("原文を読み込めませんでした。") }
                ForEach(originals) { item in
                    Text(item.editionId == "MHC-2.2" ? "Matthew Henry’s Complete Commentary" : "Jamieson–Fausset–Brown Commentary").bibleTextStyle(.heading)
                    Text("\(item.editionId) · \(item.sourceLocator) · Public domain").bibleTextStyle(.caption)
                    if item.kind == "chapter-context" {
                        Text("章冒頭の資料（章見出し・章注）。次の範囲は閲覧対象であり、各節の独立した詳細注解を示すものではありません。").bibleTextStyle(.caption)
                    }
                    Text(item.ranges.map(\.label).joined(separator: ", ")).bibleTextStyle(.caption)
                    ForEach(Array(item.originalText.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, paragraph in Text(paragraph).bibleTextStyle(.body).textSelection(.enabled) }
                    ForEach(item.crossReferences ?? []) { reference in
                        Text(reference.noteJa).bibleTextStyle(.caption)
                        NavigationLink("原典が参照する\(reference.passage.label)の英語注解") { CommentaryOriginalView(passage: reference.passage) }
                    }
                }
                Link("MHC 原典・版情報", destination: URL(string: "https://www.crosswire.org/sword/modules/ModInfo.jsp?modName=MHC")!)
                Link("JFB 原典・版情報", destination: URL(string: "https://www.crosswire.org/sword/modules/ModInfo.jsp?modName=JFB")!)
            }
        } }.navigationTitle("注解の英語原文").bibleCanvas().task(id: accepted) {
            guard accepted else { return }
            do { originals = try await StaticCommentary.shared.originals(for: passage) } catch { failed = true }
        }
    }
}

private struct CommentaryDictionaryView: View {
    @State private var accepted = false
    @State private var query = ""
    @State private var results: [CommentaryDictionaryEntry] = []
    @State private var failed = false
    var body: some View {
        ScrollView { BibleReadingColumn {
            Text("Easton’s Bible Dictionary · 1897 · モジュール2.0.1 · Public domain").bibleTextStyle(.caption)
            Text("歴史的なスコットランド長老派の辞典です。英語原文3,963見出しで、日本語説明の整備数には含めません。選択範囲より先の人物・出来事を含みます。").bibleTextStyle(.body)
            if !accepted { Button("先の内容を含む辞典を開く") { accepted = true } }
            else {
                TextField("英語の見出しを検索（例 Paul）", text: $query).textFieldStyle(.roundedBorder).autocorrectionDisabled()
                Text("一致した見出しを最大30件表示します。人物名が同じでも、自動で同一人物とは結びつけません。").bibleTextStyle(.caption)
                if failed { Text("辞典を読み込めませんでした。") }
                ForEach(results) { entry in
                    DisclosureGroup(entry.headword) { Text(entry.originalText).bibleTextStyle(.body).textSelection(.enabled) }
                }
            }
            Link("Easton 原典・版情報", destination: URL(string: "https://www.crosswire.org/sword/modules/ModInfo.jsp?modName=Easton")!)
        } }.navigationTitle("英語の聖書辞典").bibleCanvas().task(id: query) {
            guard accepted else { return }
            do { results = try await StaticCommentary.shared.dictionary(matching: query); failed = false }
            catch { results = []; failed = true }
        }
    }
}

struct StaticCommentaryBrowser: View {
    @State private var book = "ACT"
    @State private var chapter = 1
    private var range: Passage {
        let counts = Canon.verseCounts[book] ?? [1]
        let selected = min(max(chapter, 1), counts.count)
        return Passage(book: book, start: Verse(chapter: selected, verse: 1), end: Verse(chapter: selected, verse: counts[selected - 1]))
    }
    var body: some View {
        Form {
            Section("読む章を選ぶ") {
                Picker("書", selection: $book) { ForEach(Canon.books) { Text($0.ja).tag($0.id) } }.onChange(of: book) { _, _ in chapter = 1 }
                Stepper("\(chapter)章", value: $chapter, in: 1...(Canon.verseCounts[book]?.count ?? 1))
                NavigationLink("\(range.label)の注解を開く") {
                    ScrollView { BibleReadingColumn { StaticCommentaryView(passage: range) } }.navigationTitle(range.label).bibleCanvas()
                }
            }
            Text("保存した日本語説明を章ごとに読めます。整備状況は各章の画面で確認でき、未整備の箇所には英語原文も用意しています。章の途中まで読んでいる場合は、共有した箇所の読書画面をご利用ください。").bibleTextStyle(.caption)
        }.navigationTitle("保存した注解").bibleCanvas()
    }
}
