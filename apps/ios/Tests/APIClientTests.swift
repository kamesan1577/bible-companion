import XCTest
@testable import CompanionCore

final class APIClientTests: XCTestCase, @unchecked Sendable {
    func testRejectHTTP() { XCTAssertThrowsError(try APIClient(baseURL: URL(string: "http://example.com")!)) }
    func testRejectEmbeddedCredentials() { XCTAssertThrowsError(try APIClient(baseURL: URL(string: "https://person:password@example.com")!)) }
    func testRejectEndpointWithQuery() { XCTAssertThrowsError(try APIClient(baseURL: URL(string: "https://example.com?owner=x")!)) }
    func testRejectEndpointPath() { XCTAssertThrowsError(try APIClient(baseURL: URL(string: "https://example.com/other")!)) }
    func testInvalidPlaceholderDoesNotMakeNetworkCall() async throws {
        let client = try APIClient(baseURL: URL(string: "https://unconfigured.invalid")!)
        do { let _: JSONValue = try await client.get("/v1/me"); XCTFail("Must reject placeholder") }
        catch { XCTAssertEqual(error as? NetworkFailure, .unconfigured) }
    }
    func testMissingBearerDoesNotMakeNetworkCall() async throws {
        let client = try APIClient(baseURL: URL(string: "https://example.com")!)
        do { let _: JSONValue = try await client.get("/v1/me"); XCTFail("Must require session") }
        catch { XCTAssertEqual(error as? NetworkFailure, .unauthenticated) }
    }
    func testRejectPathInjectionBeforeNetworkCall() async throws {
        let client = try APIClient(baseURL: URL(string: "https://example.com")!)
        for path in ["//evil.example/v1/me", "/../auth/token", "/v1/me?owner=other", "/v1/me#fragment"] {
            do { let _: JSONValue = try await client.get(path); XCTFail("Must reject unsafe path") }
            catch { XCTAssertEqual(error as? NetworkFailure, .invalidResponse) }
        }
    }
}
