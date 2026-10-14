#if DEBUG
import SwiftUI
import CompanionCore

/// Fixture rendering only. This entire entry point is absent from Release builds.
struct SimulatorQA: View {
    @State private var ready = false
    private let client: APIClient
    private let item: ImportRecord
    init() {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [SimulatorQAProtocol.self]
        client = try! APIClient(baseURL: URL(string: "https://fixture.example.org")!, configuration: config)
        item = try! JSONDecoder().decode(ImportRecord.self, from: Data(#"{"id":"00000000-0000-4000-8000-000000000123","idempotencyKey":"00000000-0000-4000-8000-000000000123","ranges":[{"book":"ACT","start":{"chapter":23,"verse":1},"end":{"chapter":23,"verse":1}}],"translation":"JCB","createdAt":0}"#.utf8))
    }
    var body: some View {
        NavigationStack {
            List {
                Text("Simulator固定データ · 通信・実認証なし").bibleTextStyle(.caption)
                if ready {
                    NavigationLink("質問画面") { QuestionView(ownerID: item.id, client: client, item: item, rangeIndex: 0, target: item.ranges[0]) }
                }
                NavigationLink("使徒23:1の人物") { ScrollView { OfflineEntityPane(passage: item.ranges[0], kind: "person").padding() }.navigationTitle("人物") }
                NavigationLink("使徒23:1の地名") { ScrollView { OfflineEntityPane(passage: item.ranges[0], kind: "place").padding() }.navigationTitle("地名") }
                NavigationLink("使い方") { FirstRunGuide() }
                ShareLink("実際の共有拡張を開く", item: URL(string: "https://www.bible.com/bible/83/ACT.23.1.JCB")!)
            }.navigationTitle("描画確認").bibleCanvas()
        }.task { await client.setToken("simulator-fixture-only"); ready = true }
    }
}
private final class SimulatorQAProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, url.host == "fixture.example.org" else { client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return }
        let policy = #"{"allowedAnswerModes":["grounded-generation"],"defaultAnswerMode":"grounded-generation","groundedPolicyVersion":"fixture-v1","groundedNoticeJa":"固定データ","workersAiConsent":true,"shareAiEnabled":false,"shareAiConsent":false,"groundedConsent":{"accepted":true,"policyVersion":"fixture-v1"}}"#
        let ok = url.path == "/v1/me/ai-policy"
        let data = Data((ok ? policy : #"{"error":{"code":"fixture_no_mutation","message":"描画確認では送信しません"}}"#).utf8)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: ok ? 200 : 409, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
