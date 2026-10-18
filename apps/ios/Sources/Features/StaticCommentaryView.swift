import SwiftUI
import CompanionCore

struct StaticCommentaryView: View {
    var developerDetails = false
    let passage: Passage
    @State private var edits: [CommentaryEdit] = []
    @State private var failure: String?
    @State private var progress: CommentaryProgress?
    var body: some View {
        VStack(alignment: .leading, spacing: BibleTheme.Space.md) {
            BibleSectionHeader(title: "この箇所の説明")
            Text("AIで編集。専門家の校閲なし。").bibleTextStyle(.caption)
            if let failure { Text(failure).bibleTextStyle(.caption) }
            else if edits.isEmpty { Text("この箇所の日本語の説明は、まだありません。下の「英語の注解を読む」から参考にした注解を読めます。先の出来事を含むことがあるため、開く前にお知らせします。").bibleTextStyle(.body) }
            ForEach(edits) { edit in
                VStack(alignment: .leading, spacing: BibleTheme.Space.sm) {
                    Text(edit.titleJa).bibleTextStyle(.heading)
                    Text(edit.passage.label).bibleTextStyle(.caption)
                    Text(edit.summaryJa).bibleTextStyle(.body).textSelection(.enabled)
                    DisclosureGroup("解釈と出典を確かめる") {
                        Text("参考にした注解：" + edit.sourceUnitIds.map { $0.hasPrefix("mhc:") ? "Matthew Henry" : "Jamieson–Fausset–Brown（JFB）" }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.joined(separator: " / ")).bibleTextStyle(.caption)
                        if progress?.sourceComparedEntryIds.contains(edit.id) == true { Text("別のAIによる本文・出典との照合も行っています。専門家の校閲とは異なります。").bibleTextStyle(.caption) }
                        Text(edit.authorInterpretationJa).bibleTextStyle(.body)
                        if let note = edit.editorialNoteForDisplay { Text(note).bibleTextStyle(.caption) }
                    }

                }
            }
            NavigationLink("英語の注解を読む") { CommentaryOriginalView(passage: passage) }
            NavigationLink("英語の聖書辞典で調べる") { CommentaryDictionaryView() }
            DisclosureGroup("この説明について") {
                Text("昔のプロテスタントの注解をもとに、AIを使ってまとめています。聖書本文そのものや、専門家が確認した説明ではありません。著者の解釈と本文を読み比べてください。").bibleTextStyle(.caption)

                Text("選んだ箇所より先の説明は表示しません。一部の節は、聖書の版によって節番号や本文の有無が異なります。").bibleTextStyle(.caption)
                if developerDetails {
                VStack(alignment: .leading) {
                if let progress {
                    Text("開発者専用：日本語編集：\(progress.editedRanges)範囲・\(progress.coveredCoordinates)節座標。うち8節以下の具体的説明は\(progress.detailedRanges)範囲・\(progress.detailedCoordinates)節座標、章概説は\(progress.chapterOverviews)件です。全聖書の同粒度の整備と専門家校閲は未完です。").bibleTextStyle(.caption)
                    if !progress.completeActsChapters.isEmpty {
                        Text("使徒の全節座標を短い範囲で収録した章：" + progress.completeActsChapters.map(String.init).joined(separator: "、") + "。節座標の網羅は、解釈の正しさや全節の同じ詳しさを保証しません。").bibleTextStyle(.caption)
                    }
                }
                }.bibleForeground(.danger)
                }
            }
        }.task(id: passage) {
            do { edits = try await StaticCommentary.shared.edits(for: passage); progress = try await StaticCommentary.shared.progress(); failure = nil }
            catch { edits = []; failure = "説明を開けませんでした。いったん戻って、もう一度お試しください。" }
        }
    }
}
private struct CommentaryOriginalView: View {
    var developerDetails = false
    let passage: Passage
    @State private var accepted = false
    @State private var originals: [CommentaryOriginal] = []
    @State private var failed = false
    var body: some View {
        ScrollView { BibleReadingColumn {
            Text("この英語の注解には、まだ読んでいない出来事や、ほかの書の説明が含まれることがあります。").bibleTextStyle(.body)
            if !accepted { Button("先の内容を含むことを確認して開く") { accepted = true } }
            else {
                if failed { Text("英語の注解を開けませんでした。いったん戻って、もう一度お試しください。") }
                ForEach(originals) { item in
                    Text(item.editionId == "MHC-2.2" ? "Matthew Henry’s Complete Commentary" : "Jamieson–Fausset–Brown Commentary").bibleTextStyle(.heading)
                    Text("著作権の保護期間が終了した、英語の注解です。").bibleTextStyle(.caption)
                    if developerDetails { Text("開発者専用：\(item.editionId) · \(item.sourceLocator)").bibleTextStyle(.caption).bibleForeground(.danger) }
                    if item.kind == "chapter-context" {
                        Text("この章についての説明です。各節を個別に説明した文章ではありません。").bibleTextStyle(.caption)
                    }
                    Text(item.ranges.map(\.label).joined(separator: ", ")).bibleTextStyle(.caption)
                    ForEach(Array(item.originalText.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, paragraph in Text(paragraph).bibleTextStyle(.body).textSelection(.enabled) }
                    ForEach(item.crossReferences ?? []) { reference in
                        Text("著者が参照した箇所です。今選んだ箇所より先の内容を含むことがあります。").bibleTextStyle(.caption)
                        NavigationLink("著者が参照した\(reference.passage.label)の英語注解") { CommentaryOriginalView(passage: reference.passage) }
                    }
                }
                Link("Matthew Henryの注解について", destination: URL(string: "https://www.crosswire.org/sword/modules/ModInfo.jsp?modName=MHC")!)
                Link("Jamieson–Fausset–Brownの注解について", destination: URL(string: "https://www.crosswire.org/sword/modules/ModInfo.jsp?modName=JFB")!)
            }
        } }.navigationTitle("英語の注解").bibleCanvas().task(id: accepted) {
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
            Text("昔のスコットランド長老派の聖書辞典です。英語で人名や地名などを調べられます。まだ読んでいない人物や出来事の説明も含まれます。").bibleTextStyle(.body)
            if !accepted { Button("先の内容を含むことを確認して調べる") { accepted = true } }
            else {
                TextField("英語の見出しを検索（例 Paul）", text: $query).textFieldStyle(.roundedBorder).autocorrectionDisabled()
                Text("一致した項目を最大30件表示します。同じ名前でも、別の人物を指すことがあります。").bibleTextStyle(.caption)
                if failed { Text("辞典を開けませんでした。戻ってから、もう一度お試しください。") }
                ForEach(results) { entry in
                    DisclosureGroup(entry.headword) { Text(entry.originalText).bibleTextStyle(.body).textSelection(.enabled) }
                }
            }
            Link("Easton 出典について", destination: URL(string: "https://www.crosswire.org/sword/modules/ModInfo.jsp?modName=Easton")!)
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
                    UnifiedReadingView(passage: range, translation: nil, sharedText: "")
                }
            }
            Text("書名と章を選ぶと、日本語の説明を読めます。説明がまだない章では、英語の注解を案内します。章の途中まで読んでいるときは、YouVersionから読んだ節だけを共有してください。").bibleTextStyle(.caption)
        }.navigationTitle("章から説明を探す").bibleCanvas()
    }
}
