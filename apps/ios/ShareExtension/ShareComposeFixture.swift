#if DEBUG && targetEnvironment(simulator)
import Foundation
import CompanionCore

/// Simulator-only transport selected by an explicit QA share link. Never calls an AI service.
@MainActor func configureShareComposeFixture(_ model: SharedPreviewModel, artwork: String? = nil) async {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ShareComposeFixtureProtocol.self]
    if let artwork, artwork.utf8.count <= 12000 { configuration.httpAdditionalHeaders = ["X-Bible-QA-Artwork": artwork] }
    let client = try! APIClient(baseURL: URL(string: "https://fixture.example.org")!, configuration: configuration)
    await client.setToken("fixture-only")
    PublicReadingModel.fixtureClient = client
    model.loading = false
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
        guard url.path == "/public/reading", request.httpMethod == "POST", let passage = fields["passage"] else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return
        }
        let result: [String: Any] = ["passage":passage,"translation":fields["translation"] ?? NSNull(),"spoilerAllowed":false,"sourceVersion":"unified-share-fixture-v1","overview":["contentKind":"curated-reference","text":"公開資料の固定データ。独自AIは呼び出していません。","citations":[],"mode":"source-only","modelInvoked":false],"materialNotice":"固定された公開資料","cache":"fixture","people":[],"places":[],"artworks":ArtworkCatalogQA.projected(passage, encodedCard: request.value(forHTTPHeaderField: "X-Bible-QA-Artwork"))]
        let data = try! JSONSerialization.data(withJSONObject: result)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url:url,statusCode:200,httpVersion:"HTTP/1.1",headerFields:["Content-Type":"application/json"])!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { lock.lock(); stopped = true; lock.unlock() }
}
#endif
