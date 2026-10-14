import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import CompanionCore

final class BoundedTransportTests: XCTestCase, @unchecked Sendable {
    private func transfer(limit: Int, length: Int?, chunks: [Data], stall: Bool = false, cancelBeforeStart: Bool = false) async throws -> Data {
        ChunkProtocol.recipe = .init(contentLength: length, chunks: chunks, stall: stall)
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [ChunkProtocol.self]
        let job = Task { try await BoundedTransfer(maximumBytes: limit).run(URLRequest(url: URL(string: "https://example.com/fixture")!), configuration: configuration) }
        if cancelBeforeStart { job.cancel() }
        else if stall { try await Task.sleep(for: .milliseconds(20)); job.cancel() }
        return try await job.value.0
    }
    func testExactCapAccepted() async throws {
        let data = try await transfer(limit: 1000, length: 1000, chunks: [Data(repeating: 1, count: 500), Data(repeating: 2, count: 500)])
        XCTAssertEqual(data.count, 1000)
    }
    func testCapPlusOneRejectedIncrementally() async {
        do { _ = try await transfer(limit: 1000, length: nil, chunks: [Data(repeating: 1, count: 500), Data(repeating: 2, count: 501)]); XCTFail() }
        catch { XCTAssertEqual(error as? NetworkFailure, .invalidResponse) }
    }
    func testDeclaredOversizeRejectedBeforeBody() async {
        do { _ = try await transfer(limit: 1000, length: 10_000_000, chunks: []); XCTFail() }
        catch { XCTAssertEqual(error as? NetworkFailure, .invalidResponse) }
    }
    func testUnknownLengthOverTenMegabytesRejected() async {
        let chunk = Data(repeating: 7, count: 1_000_000)
        do { _ = try await transfer(limit: 4_000_000, length: nil, chunks: Array(repeating: chunk, count: 11)); XCTFail() }
        catch { XCTAssertEqual(error as? NetworkFailure, .invalidResponse) }
    }
    func testCancelBeforeStartResumesOnce() async {
        do { _ = try await transfer(limit: 1000, length: nil, chunks: [], stall: true, cancelBeforeStart: true); XCTFail() }
        catch { XCTAssertEqual((error as? URLError)?.code, .cancelled) }
    }
    func testCancelDuringBodyResumesOnce() async {
        do { _ = try await transfer(limit: 1000, length: nil, chunks: [Data(repeating: 1, count: 100)], stall: true); XCTFail() }
        catch { XCTAssertEqual((error as? URLError)?.code, .cancelled) }
    }
    func testLateDuplicateCompletionDoesNotResumeAgain() async throws {
        ChunkProtocol.recipe = .init(contentLength: 1, chunks: [Data([1])], stall: false)
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [ChunkProtocol.self]
        let transfer = BoundedTransfer(maximumBytes: 1000)
        let request = URLRequest(url: URL(string: "https://example.com/fixture")!)
        let result = try await transfer.run(request, configuration: configuration)
        XCTAssertEqual(result.0, Data([1]))
        let session = URLSession(configuration: .ephemeral); defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: request)
        transfer.urlSession(session, task: task, didCompleteWithError: URLError(.cancelled))
        transfer.urlSession(session, task: task, didCompleteWithError: nil)
    }
}
private final class ChunkProtocol: URLProtocol {
    struct Recipe: Sendable { let contentLength: Int?; let chunks: [Data]; let stall: Bool }
    nonisolated(unsafe) static var recipe = Recipe(contentLength: nil, chunks: [], stall: false)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let recipe = Self.recipe
        let headers = recipe.contentLength.map { ["Content-Length": String($0)] } ?? [:]
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in recipe.chunks { client?.urlProtocol(self, didLoad: chunk) }
        if !recipe.stall { client?.urlProtocolDidFinishLoading(self) }
    }
    override func stopLoading() {}
}
