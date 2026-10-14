import SwiftUI
import CompanionCore

@MainActor final class ScriptureModel: ObservableObject {
    @Published private(set) var page: ScripturePage?
    @Published private(set) var loading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var pageNumber = 0
    private let client: APIClient
    private let importID: String
    private let rangeIndex: Int
    let passage: Passage
    private var history = ScriptureCursorHistory()
    private var gate = RequestGate()
    init(client: APIClient, importID: String, rangeIndex: Int, passage: Passage) {
        self.client = client; self.importID = importID; self.rangeIndex = rangeIndex; self.passage = passage
    }
    func loadFirst() async { await load(cursor: nil, destination: 0, baseline: nil) }
    func next() async {
        guard let page, let request = history.next(cursor: page.nextCursor) else { return }
        await load(cursor: request.cursor, destination: request.destination, baseline: page)
    }
    func previous() async {
        guard let request = history.previous, let page else { return }
        await load(cursor: request.cursor, destination: request.destination, baseline: page)
    }
    private func load(cursor: String?, destination: Int, baseline: ScripturePage?) async {
        guard !loading, passage.isValid, rangeIndex >= 0 else { return }
        let generation = gate.invalidate(); loading = true; errorMessage = nil; page = nil
        defer { if gate.accepts(generation) { loading = false } }
        do {
            var query = [URLQueryItem(name: "rangeIndex", value: String(rangeIndex))]
            if let cursor { query.append(URLQueryItem(name: "after", value: cursor)) }
            let value: ScripturePage = try await client.get("/v1/imports/\(importID)/scripture", query: query)
            guard gate.accepts(generation) else { return }
            try value.validate(expected: passage, previous: baseline, requestedCursor: cursor)
            try history.accept(cursor: cursor, destination: destination, nextCursor: value.nextCursor)
            pageNumber = history.pageNumber; page = value
        } catch {
            guard gate.accepts(generation) else { return }
            history.clear(); pageNumber = 0
            errorMessage = "英語の参考本文を確認できませんでした。資料の版や表示条件が変わった場合は、最初から読み込み直してください。"
        }
    }
    func clear() { gate.invalidate(); loading = false; page = nil; history.clear(); pageNumber = 0 }
}
