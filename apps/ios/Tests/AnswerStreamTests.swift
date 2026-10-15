import XCTest
@testable import CompanionCore

final class AnswerStreamTests: XCTestCase, @unchecked Sendable {
    func testSplitUTF8CRLFAndTerminal() throws {
        let wire = ": heartbeat\r\n\r\nevent: preview\r\ndata: {\"text\":\"フェリクスは総督です。\"}\r\n\r\nevent: complete\r\ndata: {}\r\n\r\n"
        var parser = AnswerEventParser(); var events: [(String, Data)] = []
        for byte in wire.utf8 { events += try parser.append(Data([byte])) }
        try parser.finish()
        XCTAssertEqual(events.map { $0.0 }, ["preview", "complete"])
        XCTAssertEqual(String(data: events[0].1, encoding: .utf8), "{\"text\":\"フェリクスは総督です。\"}")
        XCTAssertThrowsError(try parser.append(Data("event: progress\ndata: {}\n\n".utf8)))
    }
    func testInterruptedOrMalformedStreamNeverCompletes() throws {
        for text in ["event: progress\ndata: {\"stage\":\"receiving\"}\n\n", "event: complete\ndata: {}\n", "event: complete\ndata: {}"] {
            var parser = AnswerEventParser(); _ = try parser.append(Data(text.utf8)); XCTAssertThrowsError(try parser.finish())
        }
        var parser = AnswerEventParser()
        XCTAssertThrowsError(try parser.append(Data("event: unknown\ndata: {}\n\n".utf8)))
    }
    func testFailureIsTerminalAndDoesNotBecomeAnswer() throws {
        let receiver = AnswerStreamReceiver(update: { _ in })
        try receiver.receive(Data("event: failure\ndata: {\"status\":401,\"code\":\"session_expired\"}\n\n".utf8))
        try receiver.parser.finish(); XCTAssertEqual(receiver.failure, .unauthenticated); XCTAssertNil(receiver.result)
    }
    func testRetryDoesNotDuplicateUnansweredUserTurn() {
        var transcript = ChatTranscript()
        transcript.submit(id: "cancelled", question: "誰？", standard: false)
        transcript.discardUnanswered(id: "cancelled")
        transcript.submit(id: "retry", question: "誰？", standard: false)
        XCTAssertEqual(transcript.entries.map(\.text), ["誰？"])
        XCTAssertEqual(transcript.entries.first?.id, "retry:user")
    }
    func testTranscriptPreservesInitialAndDeduplicatesRecoveredRequest() throws {
        let answer = try JSONDecoder().decode(AnswerResult.self, from: Data(#"{"answer":"フェリクスは総督です。","status":"answered","citations":[],"modelId":"fixture","modelInvoked":false,"mode":"grounded-generation","warnings":[],"usage":{},"timing":{}}"#.utf8))
        var transcript = ChatTranscript()
        transcript.complete(id: "initial", answer: answer, standard: true)
        transcript.submit(id: "one", question: "誰やねんペリクスって", standard: false)
        transcript.complete(id: "one", answer: answer, standard: false)
        transcript.complete(id: "one", answer: answer, standard: false)
        transcript.submit(id: "two", question: "ペリクスってだれは", standard: false)
        XCTAssertEqual(transcript.entries.count, 4)
        XCTAssertEqual(transcript.entries.map(\.role), ["assistant", "user", "assistant", "user"])
        XCTAssertTrue(transcript.entries[0].standard)
        var differentOwner = ChatTranscript(); XCTAssertTrue(differentOwner.entries.isEmpty)
        transcript.clear(); XCTAssertTrue(transcript.entries.isEmpty)
        differentOwner.submit(id: "other", question: "別アカウント", standard: false)
        XCTAssertEqual(differentOwner.entries.count, 1); XCTAssertTrue(transcript.entries.isEmpty)
    }
}

private final class StreamingProtocol: URLProtocol, @unchecked Sendable {
    // Serial XCTest methods, synthetic transport only. Control the EOF independently of preview receipt.
    nonisolated(unsafe) static var started: (@Sendable (StreamingProtocol) -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!,statusCode:200,httpVersion:"HTTP/1.1",headerFields:["Content-Type":"text/event-stream"])!,cacheStoragePolicy:.notAllowed)
        Self.started?(self)
    }
    func emit(_ value: String, finish: Bool = false) {
        for byte in value.utf8 { client?.urlProtocol(self,didLoad:Data([byte])) }
        if finish { client?.urlProtocolDidFinishLoading(self) }
    }
    override func stopLoading() {}
}
private final class StreamHandle: @unchecked Sendable {
    private let lock=NSLock(); private var value:StreamingProtocol?
    func store(_ value:StreamingProtocol){lock.lock();self.value=value;lock.unlock()}
    func emit(_ text:String, finish:Bool=true){lock.lock();let value=self.value;lock.unlock();value?.emit(text,finish:finish)}
}
extension AnswerStreamTests {
    private func streamingAPI() throws -> APIClient {
        let config=URLSessionConfiguration.ephemeral; config.protocolClasses=[StreamingProtocol.self]
        return try APIClient(baseURL:URL(string:"https://example.test")!,configuration:config)
    }
    private var completedWire: String { "event: complete\ndata: {\"requestId\":\"request\",\"status\":\"complete\",\"result\":null}\n\n" }
    func testTransportReceivesPreviewBeforeEOFAndChecksRequestIdentity() async throws {
        let handle=StreamHandle(), preview=expectation(description:"real preview before EOF")
        StreamingProtocol.started={ transport in
            XCTAssertEqual(transport.request.value(forHTTPHeaderField:"Accept"),"text/event-stream")
            XCTAssertEqual(transport.request.value(forHTTPHeaderField:"Authorization"),"Bearer alice")
            handle.store(transport); transport.emit("event: preview\ndata: {\"text\":\"総督\"}\n\n")
        }
        let api=try streamingAPI(); await api.setToken("alice")
        let task=Task { try await api.postAnswer("/v1/conversations/id/questions",body:["question":"誰？"],requestID:"request") { if case .preview(let text)=$0 { XCTAssertEqual(text,"総督");preview.fulfill() } } }
        await fulfillment(of:[preview],timeout:3)
        handle.emit(completedWire)
        let result=try await task.value; XCTAssertEqual(result.requestId,"request")
    }
    func testAccountSwitchRejectsLateStreamResult() async throws {
        let handle=StreamHandle(), received=expectation(description:"old owner response started")
        StreamingProtocol.started={ transport in handle.store(transport);received.fulfill() }
        let api=try streamingAPI();await api.setToken("alice")
        let task=Task { try await api.postAnswer("/v1/conversations/id/questions",body:["question":"private"],requestID:"request",update:{_ in}) }
        await fulfillment(of:[received],timeout:3);await api.setToken("bob");handle.emit(completedWire)
        do { _=try await task.value;XCTFail("old owner result accepted") } catch { XCTAssertEqual(error as? NetworkFailure,.unauthenticated) }
    }
    func testCancelledStreamAndMismatchedRequestAreRejected() async throws {
        let received=expectation(description:"started")
        StreamingProtocol.started={ _ in received.fulfill() }
        let api=try streamingAPI();await api.setToken("alice")
        let task=Task { try await api.postAnswer("/v1/conversations/id/questions",body:["question":"private"],requestID:"request",update:{_ in}) }
        await fulfillment(of:[received],timeout:3);task.cancel()
        do { _=try await task.value;XCTFail("cancelled stream accepted") } catch { XCTAssertEqual(error as? NetworkFailure,.cancelled) }
        let wire=completedWire
        StreamingProtocol.started={ $0.emit(wire,finish:true) }
        do { _=try await api.postAnswer("/v1/conversations/id/questions",body:["question":"private"],requestID:"different",update:{_ in});XCTFail("wrong request accepted") } catch { XCTAssertEqual(error as? NetworkFailure,.invalidResponse) }
    }
}
