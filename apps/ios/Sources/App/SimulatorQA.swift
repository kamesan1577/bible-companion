#if DEBUG
import SwiftUI
import CompanionCore

/// Fixture rendering only. This entire entry point is absent from Release builds.
struct SimulatorQA: View {
    @EnvironmentObject private var store: AppStore
    @State private var ready = false
    @State private var client: APIClient
    private let item: ImportRecord
    init() {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [SimulatorQAProtocol.self]
        _client = State(initialValue: try! APIClient(baseURL: URL(string: "https://fixture.example.org")!, configuration: config))
        item = try! JSONDecoder().decode(ImportRecord.self, from: Data(#"{"id":"00000000-0000-4000-8000-000000000123","idempotencyKey":"00000000-0000-4000-8000-000000000123","ranges":[{"book":"ACT","start":{"chapter":23,"verse":1},"end":{"chapter":23,"verse":1}}],"translation":"JCB","createdAt":0}"#.utf8))
    }
    private var snapshotScreen: String? {
        ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--qa-screen=") }).map { String($0.dropFirst("--qa-screen=".count)) }
    }
    @ViewBuilder private func snapshot(_ screen: String) -> some View {
        switch screen {
        case "initial", "reading": ReadingView()
        case "romans-opening", "romans-doxology":
            let passage = screen == "romans-opening" ? Passage(book: "ROM", start: Verse(chapter: 1, verse: 1), end: Verse(chapter: 1, verse: 1)) : Passage(book: "ROM", start: Verse(chapter: 16, verse: 25), end: Verse(chapter: 16, verse: 27))
            ScrollView { BibleReadingColumn { StaticCommentaryView(passage: passage) } }.navigationTitle(passage.label).bibleCanvas()
        case "settings": SettingsView()
        case "setup": AISetupView()
        case "guide": FirstRunGuide()
        case "question": QuestionView(ownerID: item.id, client: client, item: item, rangeIndex: 0, target: item.ranges[0])
        case "consent":
            if let owner = store.account, let policy = store.aiPolicy {
                GroundedConsentView(intent: GroundedConsentIntent(ownerID: owner.id, sessionEpoch: store.sessionEpoch, policy: policy))
            }
        default: Text("未定義の検証画面です").bibleTextStyle(.body)
        }
    }
    var body: some View {
        NavigationStack {
            if let snapshotScreen {
                if ready { snapshot(snapshotScreen) }
                else { ProgressView("固定データを読み込んでいます") }
            } else {
            List {
                Text("Simulator固定データ · 通信・実認証なし").bibleTextStyle(.caption)
                if ready {
                    NavigationLink("読書画面") { ReadingView() }
                    NavigationLink("使徒23:1の静的解説") { ScrollView { BibleReadingColumn { StaticCommentaryView(passage: item.ranges[0]) } }.navigationTitle("静的解説").bibleCanvas() }
                    NavigationLink("使徒18–23章の静的解説") { ScrollView { BibleReadingColumn { StaticCommentaryView(passage: Passage(book: "ACT", start: Verse(chapter: 18, verse: 1), end: Verse(chapter: 23, verse: 35))) } }.navigationTitle("静的解説の確認").bibleCanvas() }
                    NavigationLink("サムエル記下22:1の資料") { ScrollView { BibleReadingColumn { StaticCommentaryView(passage: Passage(book: "2SA", start: Verse(chapter: 22, verse: 1), end: Verse(chapter: 22, verse: 1))) } }.navigationTitle("章冒頭資料の確認").bibleCanvas() }
                    NavigationLink("質問画面") { QuestionView(ownerID: item.id, client: client, item: item, rangeIndex: 0, target: item.ranges[0]) }
                }
                NavigationLink("使徒23:1の人物") { ScrollView { OfflineEntityPane(passage: item.ranges[0], kind: "person").padding() }.navigationTitle("人物") }
                NavigationLink("使徒23:1の地名") { ScrollView { OfflineEntityPane(passage: item.ranges[0], kind: "place").padding() }.navigationTitle("地名") }
                NavigationLink("使い方") { FirstRunGuide() }
                ShareLink("実際の共有拡張を開く", item: URL(string: "https://www.bible.com/bible/83/ACT.23.1.JCB")!)
            }.navigationTitle("描画確認").bibleCanvas()
            }
        }
        .sheet(isPresented: $store.showAISetup) { AISetupView().environmentObject(store) }
        .task { await client.setToken("simulator-fixture-only"); store.configureSimulatorQA(client: client); await store.loadAIPolicy(); ready = true }
    }
}
private final class SimulatorQAProtocol: URLProtocol, @unchecked Sendable {
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock(); private var value = 0
        func next() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
    }
    private static let standardCounter = Counter()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, url.host == "fixture.example.org" else { client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return }
        var policy = #"{"allowedAnswerModes":["grounded-generation"],"defaultAnswerMode":"grounded-generation","groundedPolicyVersion":"fixture-v1","groundedNoticeJa":"固定データ","workersAiConsent":true,"shareAiEnabled":false,"shareAiConsent":false,"groundedConsent":{"accepted":true,"policyVersion":"fixture-v1"}}"#
        if ProcessInfo.processInfo.arguments.contains("--qa-share-enabled") { policy = policy.replacingOccurrences(of: "\"shareAiEnabled\":false", with: "\"shareAiEnabled\":true") }
        var bodyData = request.httpBody ?? Data()
        if bodyData.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }; var bytes = [UInt8](repeating: 0, count: 1024)
            while bodyData.count < 20000 { let n = stream.read(&bytes, maxLength: bytes.count); if n <= 0 { break }; bodyData.append(contentsOf: bytes.prefix(n)) }
        }
        let fields = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] ?? [:]
        let passage: [String: Any] = ["book":"ACT","start":["chapter":23,"verse":1],"end":["chapter":23,"verse":1]]
        var ok = url.path == "/v1/me/ai-policy"
        var data = Data((ok ? policy : #"{"error":{"code":"fixture_no_mutation","message":"描画確認では外部に送信しません"}}"#).utf8)
        if request.httpMethod == "POST", url.path == "/v1/conversations" {
            ok = true
            data = try! JSONSerialization.data(withJSONObject: ["id":"00000000-0000-4000-8000-000000000123","importId":"00000000-0000-4000-8000-000000000123","passage":passage,"readingBoundary":passage,"spoilerAllowed":false,"createdAt":0])
        } else if request.httpMethod == "POST", (url.path.hasSuffix("/questions") || url.path.hasSuffix("/explanation")) {
            ok = true
            let answer = url.path.hasSuffix("/explanation") ? "固定標準解説\(Self.standardCounter.next())" : "固定データ: " + (fields["question"] as? String ?? "送信")
            data = try! JSONSerialization.data(withJSONObject: ["requestId":fields["requestId"] ?? "00000000-0000-4000-8000-000000000123","status":"complete","result":["answer":answer,"status":"answered","citations":[],"modelId":"fixture-no-provider","modelInvoked":false,"mode":"grounded-generation","warnings":[],"usage":[:],"timing":[:]]])
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: ok ? 200 : 409, httpVersion: "HTTP/1.1", headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
