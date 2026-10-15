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
    var body: some View {
        NavigationStack {
            List {
                Text("Simulator固定データ · 通信・実認証なし").bibleTextStyle(.caption)
                if ready {
                    NavigationLink("読書画面") { ReadingView() }
                    NavigationLink("質問画面") { QuestionView(ownerID: item.id, client: client, item: item, rangeIndex: 0, target: item.ranges[0]) }
                }
                NavigationLink("使徒23:1の人物") { ScrollView { OfflineEntityPane(passage: item.ranges[0], kind: "person").padding() }.navigationTitle("人物") }
                NavigationLink("使徒23:1の地名") { ScrollView { OfflineEntityPane(passage: item.ranges[0], kind: "place").padding() }.navigationTitle("地名") }
                NavigationLink("使い方") { FirstRunGuide() }
                ShareLink("実際の共有拡張を開く", item: URL(string: "https://www.bible.com/bible/83/ACT.23.1.JCB")!)
            }.navigationTitle("描画確認").bibleCanvas()
        }.task { await client.setToken("simulator-fixture-only"); store.configureSimulatorQA(client: client); ready = true }
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
        let policy = #"{"allowedAnswerModes":["grounded-generation"],"defaultAnswerMode":"grounded-generation","groundedPolicyVersion":"fixture-v1","groundedNoticeJa":"固定データ","workersAiConsent":true,"shareAiEnabled":false,"shareAiConsent":false,"groundedConsent":{"accepted":true,"policyVersion":"fixture-v1"}}"#
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
