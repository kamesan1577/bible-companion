import SwiftUI
import CompanionCore

@MainActor final class HistoryPageModel<Item: Decodable & Identifiable & Sendable>: ObservableObject {
    @Published private(set) var items: [Item] = []
    @Published private(set) var hasLoadedSuccessfully = false
    @Published private(set) var nextCursor: String?
    @Published private(set) var loading = false
    @Published private(set) var errorMessage: String?
    private let client: APIClient
    private let path: String
    private var gate = RequestGate()
    init(client: APIClient, path: String) { self.client = client; self.path = path }
    func load(more: Bool = false) async {
        guard !loading else { return }
        let cursor = more ? nextCursor : nil
        if more && cursor == nil { return }
        let generation = gate.invalidate(); loading = true; errorMessage = nil
        defer { if gate.accepts(generation) { loading = false } }
        do {
            let query = cursor.map { [URLQueryItem(name: "before", value: $0)] } ?? []
            let page: CursorPage<Item> = try await client.get(path, query: query)
            guard gate.accepts(generation) else { return }
            guard page.items.count <= 50, page.nextCursor.map({ !$0.isEmpty && $0.utf8.count <= 4096 && $0 != cursor }) ?? true else { throw NetworkFailure.invalidResponse }
            let existing = Set(items.map(\.id))
            items = more ? items + page.items.filter { !existing.contains($0.id) } : page.items
            nextCursor = page.nextCursor; hasLoadedSuccessfully = true
        } catch { if gate.accepts(generation) { if error as? NetworkFailure == .unauthenticated { items = []; nextCursor = nil }; errorMessage = (error as? NetworkFailure)?.userMessage ?? "履歴を読み込めませんでした。" } }
    }
    func cancel() { gate.invalidate(); loading = false }
}

@MainActor final class ConversationHistoryModel: ObservableObject {
    @Published private(set) var window = MessageWindow()
    @Published private(set) var item: ImportRecord?
    @Published private(set) var loading = false
    @Published private(set) var errorMessage: String?
    let id: String
    let client: APIClient
    private var gate = RequestGate()
    init(id: String, client: APIClient) { self.id = id; self.client = client }
    func load(older: Bool = false) async {
        guard !loading else { return }
        let cursor = older ? window.nextCursor : nil
        if older && cursor == nil { return }
        let generation = gate.invalidate(); loading = true; errorMessage = nil
        if !older { window.clear(); item = nil }
        defer { if gate.accepts(generation) { loading = false } }
        do {
            let query = cursor.map { [URLQueryItem(name: "beforeMessageId", value: $0)] } ?? []
            let page: Conversation = try await client.get("/v1/conversations/\(id)", query: query)
            guard gate.accepts(generation) else { return }
            if !older {
                let record: ImportRecord = try await client.get("/v1/imports/\(page.importId)")
                guard gate.accepts(generation) else { return }
                guard page.resumeRangeIndex(in: record) != nil else { throw NetworkFailure.invalidResponse }
                item = record
            }
            try window.apply(page, expectedID: id, older: older)
        } catch {
            guard gate.accepts(generation) else { return }
            if case NetworkFailure.server(_, let code) = error, ["conversation_changed", "conversation_policy_changed", "source_policy_changed"].contains(code) { window.clear(); item = nil; errorMessage = "会話の範囲か出典の状態が変わりました。最新から読み込み直してください。"; return }
            if error as? NetworkFailure == .unauthenticated { window.clear(); item = nil }
            if case NetworkFailure.server(status: 404, code: _) = error { window.clear(); item = nil }
            errorMessage = (error as? NetworkFailure)?.userMessage ?? "会話を確認できませんでした。再読み込みしてください。"
        }
    }
    func clear() { gate.invalidate(); loading = false; window.clear(); item = nil }
}

@MainActor final class SavedComparisonModel: ObservableObject {
    @Published private(set) var state: ComparisonState?
    @Published private(set) var loading = false
    @Published private(set) var errorMessage: String?
    let id: String
    let client: APIClient
    private var gate = RequestGate()
    init(id: String, client: APIClient) { self.id = id; self.client = client }
    func load() async {
        guard !loading else { return }
        let generation = gate.invalidate(); loading = true; state = nil; errorMessage = nil
        defer { if gate.accepts(generation) { loading = false } }
        do {
            let value: ComparisonState = try await client.get("/v1/developer/comparisons/\(id)")
            guard gate.accepts(generation) else { return }
            guard value.requestId == id, value.saved else { throw NetworkFailure.invalidResponse }
            state = value
        } catch { if gate.accepts(generation) { errorMessage = (error as? NetworkFailure)?.userMessage ?? "比較を確認できませんでした。" } }
    }
    func clear() { gate.invalidate(); state = nil; loading = false }
}
