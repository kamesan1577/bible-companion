#if DEBUG
import SwiftUI
import CompanionCore

/// Fixture rendering only. This entire entry point is absent from Release builds.
struct SimulatorQA: View {
    @EnvironmentObject private var store: AppStore
    @State private var ready = false
    @State private var externalOpenResult = ""
    @State private var composeSession = UUID().uuidString
    @State private var client: APIClient
    private let item: ImportRecord
    init() {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [SimulatorQAProtocol.self]
        _client = State(initialValue: try! APIClient(baseURL: URL(string: "https://fixture.example.org")!, configuration: config))
        let normal = try! JSONDecoder().decode(ImportRecord.self, from: Data(#"{"id":"00000000-0000-4000-8000-000000000123","idempotencyKey":"00000000-0000-4000-8000-000000000123","ranges":[{"book":"ACT","start":{"chapter":23,"verse":1},"end":{"chapter":23,"verse":1}}],"translation":"JCB","createdAt":0}"#.utf8))
        if ProcessInfo.processInfo.arguments.contains("--qa-screen=conversation") {
            let raw = String(data: try! JSONEncoder().encode(normal), encoding: .utf8)!
            let object = try! JSONSerialization.jsonObject(with: Data(raw.utf8)) as! [String: Any]
            var changed = object
            changed["ranges"] = [["book":"ACT", "start":["chapter":24,"verse":23],"end":["chapter":24,"verse":24]]]
            item = try! JSONDecoder().decode(ImportRecord.self, from: JSONSerialization.data(withJSONObject: changed))
        } else { item = normal }

    }
    private var snapshotScreen: String? {
        ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--qa-screen=") }).map { String($0.dropFirst("--qa-screen=".count)) }
    }
    @ViewBuilder private func snapshot(_ screen: String) -> some View {
        switch screen {
        case "home", "initial", "reading", "entity-pilot-reading", "entity-acts-early", "entity-acts-late", "entity-existing-map", "entity-rom-early", "entity-rom-jacob", "entity-rom-late", "entity-lev-early", "entity-lev-sinai", "entity-lev-jacob", "entity-num-hoshea", "entity-num-gilead", "entity-jos-bohan", "entity-jos-alias", "entity-jos-burial", "entity-jdg-dan", "entity-jdg-luz", "entity-rut-early", "entity-1sa-jacob", "entity-1sa-ahimelech", "entity-2sa-dual", "entity-2ki-jacob", "entity-2ki-adrammelech", "entity-1ch-israel", "entity-1ch-israel-six", "entity-1ch-ephraim", "entity-1ch-jabesh", "entity-1ch-baalah", "entity-2ch-uncovered", "entity-2ch-joash", "entity-1ch-azaziah", "entity-ezr-adaiah", "entity-ezr-hezekiah", "entity-neh-athaiah", "entity-neh-aija", "entity-neh-beeroth", "entity-ezr-held-elnathan", "entity-neh-hanun-early", "entity-neh-hanan-early", "entity-neh-harhur", "entity-neh-hodevah", "entity-neh-joiada-early", "entity-neh-meremoth-early", "entity-neh-sanballat-early": ReadingView()
        case "entity-ui-baseline": Baseline018ReadingView()
        case "romans-opening", "romans-doxology":
            let passage = screen == "romans-opening" ? Passage(book: "ROM", start: Verse(chapter: 1, verse: 1), end: Verse(chapter: 1, verse: 1)) : Passage(book: "ROM", start: Verse(chapter: 16, verse: 25), end: Verse(chapter: 16, verse: 27))
            ScrollView { BibleReadingColumn { StaticCommentaryView(passage: passage) } }.navigationTitle(passage.label).bibleCanvas()
        case "proverbs-final", "ecclesiastes-final", "song-final", "isaiah-final":
            let choices: [String: Passage] = [
                "proverbs-final": Passage(book: "PRO", start: Verse(chapter: 18, verse: 22), end: Verse(chapter: 18, verse: 24)),
                "ecclesiastes-final": Passage(book: "ECC", start: Verse(chapter: 3, verse: 11), end: Verse(chapter: 3, verse: 11)),
                "song-final": Passage(book: "SNG", start: Verse(chapter: 5, verse: 6), end: Verse(chapter: 5, verse: 8)),
                "isaiah-final": Passage(book: "ISA", start: Verse(chapter: 65, verse: 17), end: Verse(chapter: 65, verse: 20))]
            if let passage = choices[screen] {
                ScrollView { BibleReadingColumn { StaticCommentaryView(passage: passage) } }.navigationTitle(passage.label).bibleCanvas()
            }
        case "settings": SettingsView()
        case "setup": AISetupView()
        case "guide": FirstRunGuide()
        case "share-conversation": SharedConversationQA(client: client)
        case "conversation":
            let conversation = try! JSONDecoder().decode(Conversation.self, from: SimulatorQAProtocol.conversationData(passage: item.ranges[0]))
            QuestionView(ownerID: item.id, client: client, item: item, rangeIndex: 0, target: item.ranges[0], conversation: conversation)
        case "question": QuestionView(ownerID: item.id, client: client, item: item, rangeIndex: 0, target: item.ranges[0])
        case "consent":
            if let owner = store.account, let policy = store.aiPolicy {
                GroundedConsentView(intent: GroundedConsentIntent(ownerID: owner.id, sessionEpoch: store.sessionEpoch, policy: policy))
            }
        default: Text("未定義の検証画面です").bibleTextStyle(.body)
        }
    }
    private var navigationContent: some View {
        NavigationStack {
            if let snapshotScreen {
                if ready { snapshot(snapshotScreen) }
                else { ProgressView("固定データを読み込んでいます") }
            } else {
            List {
                Button("QA: main ChatGPT HTTPS") {
                    UIApplication.shared.open(URL(string: "https://chatgpt.com/")!, options: [:]) { success in
                        externalOpenResult = success ? "main-open=true" : "main-open=false"
                    }
                }
                Text(externalOpenResult).accessibilityIdentifier("main-external-open-result")
                Text("Simulator固定データ · 通信・実認証なし").bibleTextStyle(.caption)
                ShareLink("質問する共有拡張を開く", item: (ProcessInfo.processInfo.arguments.contains("--qa-chatgpt-long") ? String(repeating: "長い検証本文", count: 1400) : "検証用の共有本文：上訴についての質問を試します。") + "\nhttps://www.bible.com/bible/83/ACT.26.32.JCB?bible-compose-fixture=1&session=\(composeSession)")
                ShareLink("Crash Acts28:15", item: URL(string: "https://bible.com/bible/83/act.28.15.JCB")!)
                ShareLink("Crash Acts27:2", item: URL(string: "https://bible.com/bible/83/act.27.2.JCB")!)
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
                ShareLink("使徒18章を共有する", item: URL(string: "https://www.bible.com/bible/83/ACT.18.24-28.JCB")!)
                ShareLink("民数記26章を共有する", item: URL(string: "https://www.bible.com/bible/83/NUM.26.29.JCB")!)
                ShareLink("ヨシュア記15章を共有する", item: URL(string: "https://www.bible.com/bible/83/JOS.15.49.JCB")!)
                ShareLink("士師記18章を共有する", item: URL(string: "https://www.bible.com/bible/83/JDG.18.29.JCB")!)
                ShareLink("ルツ記1章を共有する", item: URL(string: "https://www.bible.com/bible/83/RUT.1.1-2.JCB")!)
                ShareLink("サムエル記上1章を共有する", item: URL(string: "https://www.bible.com/bible/83/1SA.1.1-2.JCB")!)
                ShareLink("列王記上1章を共有する", item: URL(string: "https://www.bible.com/bible/83/1KI.1.3-5.JCB")!)
                ShareLink("歴代誌上1章を共有する", item: URL(string: "https://www.bible.com/bible/83/1CH.1.34.JCB")!)
                ShareLink("実際の共有拡張を開く", item: URL(string: "https://www.bible.com/bible/83/ACT.23.1.JCB")!)
            }.navigationTitle("描画確認").bibleCanvas()
            }
        }
    }
    var body: some View {
        Group {
            if snapshotScreen == "configured-home", ready { RootView() }
            else { navigationContent }
        }
        .sheet(isPresented: Binding(get: { snapshotScreen != "configured-home" && store.showAISetup }, set: { store.showAISetup = $0 })) { AISetupView().environmentObject(store) }
        .task { try? PendingQuestionStore.clear(); await client.setToken("simulator-fixture-only"); store.configureSimulatorQA(client: client); await store.loadAIPolicy()
            if ProcessInfo.processInfo.arguments.contains("--qa-handoff-owner") { try? ShareInbox.setOwner(store.account?.id) }
            if ProcessInfo.processInfo.arguments.contains("--qa-clear-access") { try? ShareInbox.clearAIAccess() }
            if ProcessInfo.processInfo.arguments.contains("--qa-expiring-access"), let owner = store.account?.id {
                try? ShareInbox.setOwner(owner)
                try? ShareInbox.saveAIAccess(ShareAIAccess(token: "bcs1_" + String(repeating: "a", count: 64), ownerID: owner, expiresAt: Date().addingTimeInterval(3).timeIntervalSince1970))
            }
            ready = true }
    }
}
final class SimulatorQAProtocol: URLProtocol, @unchecked Sendable {
    private let stopLock = NSLock()
    private var stopped = false
    private var active: Bool { stopLock.lock(); defer { stopLock.unlock() }; return !stopped }
    static func conversationData(passage: Passage) -> Data {
        let initial: [String: Any] = ["answer":"フェリクスはパウロの拘留を少し緩め、のちに妻ドルシラとパウロの話を聞きました。", "status":"answered", "citations":[],"modelId":"fixture-no-provider","modelInvoked":false,"mode":"grounded-generation","warnings":[],"usage":[:],"timing":[:],"standardExplanation":true]
        let range = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(passage))
        return try! JSONSerialization.data(withJSONObject: ["id":"00000000-0000-4000-8000-000000000123","importId":"00000000-0000-4000-8000-000000000123","passage":range,"readingBoundary":range,"spoilerAllowed":false,"createdAt":0,"messages":[["id":"00000000-0000-4000-8000-000000000124","role":"assistant","content":initial,"createdAt":0]]])
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock(); private var value = 0
        func next() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
    }
    private static let standardCounter = Counter()
    private var delayedResponse: DispatchWorkItem?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, url.host == "fixture.example.org" else { client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return }
        var policy = #"{"allowedAnswerModes":["grounded-generation"],"defaultAnswerMode":"grounded-generation","groundedPolicyVersion":"fixture-v1","groundedNoticeJa":"固定データ","workersAiConsent":true,"shareAiEnabled":false,"shareAiConsent":false,"groundedConsent":{"accepted":true,"policyVersion":"fixture-v1"}}"#
        if ProcessInfo.processInfo.arguments.contains("--qa-share-enabled") { policy = policy.replacingOccurrences(of: "\"shareAiEnabled\":false", with: "\"shareAiEnabled\":true").replacingOccurrences(of: "\"shareAiConsent\":false", with: "\"shareAiConsent\":true") }
        var bodyData = request.httpBody ?? Data()
        if bodyData.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }; var bytes = [UInt8](repeating: 0, count: 1024)
            while bodyData.count < 20000 { let n = stream.read(&bytes, maxLength: bytes.count); if n <= 0 { break }; bodyData.append(contentsOf: bytes.prefix(n)) }
        }
        let fields = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] ?? [:]
        let passage: [String: Any] = ["book":"ACT","start":["chapter":23,"verse":1],"end":["chapter":23,"verse":1]]
        var ok = url.path == "/v1/me/ai-policy"
        var data = Data((ok ? policy : #"{"error":{"code":"fixture_no_mutation","message":"描画確認では外部に送信しません"}}"#).utf8)
        if request.httpMethod == "POST", url.path == "/v1/me/share-access", ProcessInfo.processInfo.arguments.contains("--qa-share-success") {
            ok = true
            data = try! JSONEncoder().encode(ShareAIAccess(token: "bcs1_" + String(repeating: "a", count: 64), ownerID: "00000000-0000-4000-8000-000000000123", expiresAt: Date().addingTimeInterval(3600).timeIntervalSince1970))
            if ProcessInfo.processInfo.arguments.contains("--qa-share-slow") {
                let responseData = data
                let work = DispatchWorkItem { [weak self] in self?.complete(data: responseData, url: url, ok: true) }
                delayedResponse = work
                DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: work)
                return
            }
        } else if request.httpMethod == "POST", url.path == "/v1/conversations" {
            ok = true
            data = try! JSONSerialization.data(withJSONObject: ["id":"00000000-0000-4000-8000-000000000123","importId":"00000000-0000-4000-8000-000000000123","passage":passage,"readingBoundary":passage,"spoilerAllowed":false,"createdAt":0])
        } else if request.httpMethod == "POST", (url.path.hasSuffix("/questions") || url.path.hasSuffix("/explanation")) {
            ok = true
            let answer = url.path.hasSuffix("/explanation") ? "固定標準解説\(Self.standardCounter.next())" : "固定データ: " + (fields["question"] as? String ?? "送信")
            data = try! JSONSerialization.data(withJSONObject: ["requestId":fields["requestId"] ?? "00000000-0000-4000-8000-000000000123","status":"complete","result":["answer":answer,"status":"answered","citations":[],"modelId":"fixture-no-provider","modelInvoked":false,"mode":"grounded-generation","warnings":[],"usage":[:],"timing":[:]]])
        }
        if request.httpMethod == "GET", url.path.hasPrefix("/v1/conversations/") {
            ok = true
            data = Self.conversationData(passage: Passage(book: "ACT", start: Verse(chapter: 24, verse: 23), end: Verse(chapter: 24, verse: 24)))
        }
        if request.httpMethod == "DELETE", (url.path.hasPrefix("/v1/requests/") || url.path.hasPrefix("/share/requests/")) { ok = true; data = Data("{\"status\":\"cancelled\"}".utf8) }
        if ok, request.value(forHTTPHeaderField: "Accept") == "text/event-stream", url.path.hasSuffix("/questions"), ProcessInfo.processInfo.arguments.contains(where: { $0 == "--qa-screen=conversation" || $0 == "--qa-screen=share-conversation" }) {
            let question = fields["question"] as? String ?? ""
            let answer = question.contains("wife") ? "ドルシラはフェリクスの妻です。" : "フェリクスはローマの総督で、パウロの訴えを審理した人物です。"
            var object = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
            var result = object["result"] as! [String: Any]; result["answer"] = answer; object["result"] = result
            let complete = String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url:url,statusCode:200,httpVersion:"HTTP/1.1",headerFields:["Content-Type":"text/event-stream"])!,cacheStoragePolicy:.notAllowed)
            @Sendable func event(_ type: String, _ json: String) -> Data { Data(("event: " + type + "\ndata: " + json + "\n\n").utf8) }
            client?.urlProtocol(self, didLoad:event("progress", "{\"stage\":\"generating\"}"))
            let preview = String(data: try! JSONSerialization.data(withJSONObject:["stage":"receiving","text":answer]),encoding:.utf8)!
            DispatchQueue.global().asyncAfter(deadline:.now()+0.5) { [self] in if active { client?.urlProtocol(self,didLoad:event("preview",preview)) } }
            DispatchQueue.global().asyncAfter(deadline:.now()+6) { [self] in
                guard active else { return }
                if !question.contains("fail") { client?.urlProtocol(self,didLoad:event("complete",complete)) }
                client?.urlProtocolDidFinishLoading(self)
            }
            return
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: ok ? 200 : 409, httpVersion: "HTTP/1.1", headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    private func complete(data: Data, url: URL, ok: Bool) {
        guard active else { return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url:url,statusCode:ok ? 200 : 409,httpVersion:"HTTP/1.1",headerFields:["Content-Type":"application/json"])!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:data);client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { delayedResponse?.cancel(); delayedResponse = nil; stopLock.lock(); stopped = true; stopLock.unlock() }
}
private struct SharedConversationQA: View {
    let client: APIClient
    @StateObject private var model = SharedPreviewModel()
    var body: some View {
        SharedPreviewView(model: model, close: {})
            .task {
                let conversation = try! JSONDecoder().decode(Conversation.self, from: SimulatorQAProtocol.conversationData(passage: Passage(book: "ACT", start: Verse(chapter: 24, verse: 23), end: Verse(chapter: 24, verse: 24))))
                model.configureQA(client: client, initial: conversation.messages![0].visibleAnswer!)
            }
    }
}
#endif
