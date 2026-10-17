#if DEBUG && targetEnvironment(simulator)
import Foundation
import CompanionCore

/// Simulator-only transport selected by an explicit QA share link. Never calls an AI service.
@MainActor func configureShareComposeFixture(_ model: SharedPreviewModel) async {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ShareComposeFixtureProtocol.self]
    let client = try! APIClient(baseURL: URL(string: "https://fixture.example.org")!, configuration: configuration)
    await client.setToken("fixture-only")
    model.configureQA(client: client, restore: true)
}
private final class ShareComposeFixtureProtocol: URLProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    private var active: Bool { lock.lock(); defer { lock.unlock() }; return !stopped }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "fixture.example.org" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        if request.httpMethod == "DELETE" || request.httpMethod == "GET" {
            let object: [String: Any] = request.httpMethod == "DELETE" ? ["status":"cancelled"] : ["requestId":url.lastPathComponent,"status":"failed"]
            let data = try! JSONSerialization.data(withJSONObject: object)
            client?.urlProtocol(self,didReceive:HTTPURLResponse(url:url,statusCode:200,httpVersion:"HTTP/1.1",headerFields:["Content-Type":"application/json"])!,cacheStoragePolicy:.notAllowed)
            client?.urlProtocol(self,didLoad:data);client?.urlProtocolDidFinishLoading(self);return
        }
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream, body.isEmpty {
            stream.open(); defer { stream.close() }; var bytes = [UInt8](repeating: 0, count: 1024)
            while body.count < 20000 { let count = stream.read(&bytes, maxLength: bytes.count); if count <= 0 { break }; body.append(contentsOf: bytes.prefix(count)) }
        }
        let fields = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        let question = fields["question"] as? String ?? ""
        let answer = question.contains("why") ? "エルサレムで裁かれる危険を避けるため、上訴したと考えられます。これは状況からの見立てです。" : "結果だけなら上訴が釈放の妨げに見えます。ただ、その時点では安全な裁判を求める判断だったと考えられます。"
        let result: [String: Any] = ["requestId": fields["requestId"] ?? "fixture", "status":"complete", "result":["answer":answer,"status":"answered","citations":[],"modelId":"fixture-no-provider","modelInvoked":false,"mode":"grounded-generation","warnings":[],"usage":[:],"timing":[:]]]
        let json = String(data: try! JSONSerialization.data(withJSONObject: result), encoding: .utf8)!
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url:url,statusCode:200,httpVersion:"HTTP/1.1",headerFields:["Content-Type":"text/event-stream"])!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self, didLoad: Data("event: progress\ndata: {\"stage\":\"generating\"}\n\n".utf8))
        DispatchQueue.global().asyncAfter(deadline:.now()+3) { [self] in
            guard active else { return }
            if question.contains("fail") { client?.urlProtocol(self,didLoad:Data("event: preview\ndata: {\"text\":\"主がモーセを通して人々へ語りかけています。\"}\n\nevent: failure\ndata: {\"status\":503,\"code\":\"timeout\"}\n\n".utf8)) }
            if !question.contains("fail") { client?.urlProtocol(self,didLoad:Data(("event: complete\ndata: " + json + "\n\n").utf8)) }
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() { lock.lock(); stopped = true; lock.unlock() }
}
#endif
