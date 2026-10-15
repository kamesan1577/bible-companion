import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import CompanionCore

final class TransportTests: XCTestCase, @unchecked Sendable {
    private func client(status: Int = 200, payload: String = "{\"ok\":true}", inspect: (@Sendable (URLRequest) -> Void)? = nil) throws -> APIClient {
        StubProtocol.handler = { request in
            inspect?(request)
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!, Data(payload.utf8))
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return try APIClient(baseURL: URL(string: "https://example.com")!, configuration: config)
    }
    func testAuthenticatedGETUsesBearerAndEncodedQuery() async throws {
        let api = try client { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-session")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "a&owner=other")
        }
        XCTAssertEqual(api.baseURL.host, "example.com") // Immutable endpoint is synchronously readable across the module boundary.
        await api.setToken("test-session")
        let value: JSONValue = try await api.get("/v1/imports", query: [URLQueryItem(name: "before", value: "a&owner=other")])
        XCTAssertEqual(value["ok"].bool, true)
    }
    func testAuthExchangeNeverIncludesExistingBearer() async throws {
        let api = try client { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertEqual(request.httpMethod, "POST")
        }
        await api.setToken("old-session")
        let _: JSONValue = try await api.post("/auth/token", body: JSONValue.object(["code": .string("one-use")]), authenticated: false)
    }
    func testDeletionCarriesExplicitConfirmationAndBearer() async throws {
        let api = try client { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer session")
            XCTAssertEqual(request.url?.path, "/v1/me/reading-data")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        }
        await api.setToken("session")
        let intent = DeletionIntent(ownerID: UUID().uuidString, sessionEpoch: UUID(), kind: .readingData)
        let _: JSONValue = try await api.delete(intent.kind.path, body: intent.body)
    }
    func test401IsSessionFailure() async throws {
        let api = try client(status: 401); await api.setToken("expired")
        do { let _: JSONValue = try await api.get("/v1/me"); XCTFail() }
        catch { XCTAssertEqual(error as? NetworkFailure, .unauthenticated) }
    }
    func testShare401EnvelopeCannotReachServerCodeBranch() async throws {
        for code in ["share_access_required", "share_access_expired", "session_expired"] {
            let api = try client(status: 401, payload: "{\"error\":{\"code\":\"\(code)\",\"message\":\"not forwarded\"}}")
            await api.setToken("bcs1_" + String(repeating: "a", count: 64))
            do { let _: JSONValue = try await api.post("/share/start", body: ["sharedText": "John 1:1"]); XCTFail("401 accepted") }
            catch { XCTAssertEqual(error as? NetworkFailure, .unauthenticated) }
        }
    }
    func testNon401ShareFailureRetainsServerCode() async throws {
        let api = try client(status: 409, payload: "{\"error\":{\"code\":\"share_access_changed\"}}")
        await api.setToken("session")
        do { let _: JSONValue = try await api.post("/v1/me/share-access", body: ["enabled": true]); XCTFail("409 accepted") }
        catch { XCTAssertEqual(error as? NetworkFailure, .server(status: 409, code: "share_access_changed")) }
    }
    func testRateLimitCopyDoesNotClaimDailyBudgetExhaustion() {
        let rate = NetworkFailure.server(status: 429, code: "rate_limited").userMessage
        let budget = NetworkFailure.server(status: 429, code: "daily_budget_exceeded").userMessage
        XCTAssertTrue(rate.contains("時間をおいて")); XCTAssertFalse(rate.contains("リセット"))
        XCTAssertTrue(budget.contains("再開できる時刻")); XCTAssertNotEqual(rate, budget)
    }
    func testOversizedComparisonDoesNotPromiseResetWillFixIt() {
        let message = NetworkFailure.server(status: 429, code: "comparison_budget_exceeded").userMessage
        XCTAssertTrue(message.contains("質問を減らす")); XCTAssertFalse(message.contains("トークン"))
        XCTAssertTrue(message.contains("設定は自動で変更していません"))
    }
    func testBudgetVerificationDoesNotDiagnoseExpiryOrDailyExhaustion() {
        let message = NetworkFailure.server(status: 503, code: "budget_unverified").userMessage
        XCTAssertTrue(message.contains("管理者に確認を依頼"))
        XCTAssertTrue(message.contains("上限に達したことを意味しません"))
        XCTAssertFalse(message.contains("CLI"))
        XCTAssertFalse(message.contains("期限が切れました"))
        XCTAssertFalse(message.contains("リセット時刻"))
    }
    func testOwnerBudgetRecoveryUsesPlainLanguageWithoutClaimingActionWasDone() {
        let message = AIAvailabilityExplanation.catalogReason("BUDGET_UNVERIFIED")
        XCTAssertTrue(message.contains("管理者向けの手順")); XCTAssertTrue(message.contains("状態を再確認"))
        XCTAssertFalse(message.contains("CLI")); XCTAssertFalse(message.contains("Free"))
    }
    func testConnectionAndModelTermsHaveDistinctRecovery() {
        let connection = NetworkFailure.server(status: 503, code: "ai_not_connected").userMessage
        let terms = NetworkFailure.server(status: 503, code: "model_terms_unreviewed").userMessage
        XCTAssertTrue(connection.contains("管理者")); XCTAssertFalse(connection.contains("CLI"))
        XCTAssertTrue(terms.contains("ご自身の同意とは別")); XCTAssertNotEqual(connection, terms)
        XCTAssertTrue(AIAvailabilityExplanation.catalogReason("MODEL_TERMS_UNREVIEWED").contains("この画面では同意できません"))
    }
    func testKnownCatalogReasonsDoNotLeakRawMachineCodes() {
        for code in ["CONNECTION_NOT_VERIFIED", "MODEL_UNCONNECTED", "MODEL_TERMS_UNREVIEWED", "BUDGET_UNVERIFIED", "BUDGET_EXCEEDED", "PAID_APPROVAL_REQUIRED", "MODEL_DISABLED"] {
            XCTAssertFalse(AIAvailabilityExplanation.catalogReason(code).contains(code), code)
        }
        XCTAssertTrue(AIAvailabilityExplanation.catalogReason("PAID_APPROVAL_REQUIRED").contains("管理者が有料利用を許可していない"))
    }
    func testRequestBudgetTooLargeDoesNotPromiseResetFixesIt() {
        let message = NetworkFailure.server(status: 429, code: "budget_exceeded").userMessage
        XCTAssertTrue(message.contains("質問を短くする")); XCTAssertFalse(message.contains("トークン"))
    }
    func testUnknownReasonsDoNotLeakMachineCodesOrInventDiagnosis() {
        XCTAssertFalse(AIAvailabilityExplanation.catalogReason("NEW_REASON_v2").contains("NEW_REASON_v2"))
        XCTAssertTrue(AIAvailabilityExplanation.catalogReason(nil).contains("確認できませんでした"))
        let message = NetworkFailure.server(status: 429, code: "new_quota_reason").userMessage
        XCTAssertFalse(message.contains("new_quota_reason")); XCTAssertFalse(message.contains("リセット"))
    }
    func testExpiredAndStaleComparisonsHaveDifferentRecovery() {
        let expired = NetworkFailure.server(status: 409, code: "comparison_expired").userMessage
        let stale = NetworkFailure.server(status: 409, code: "plan_changed").userMessage
        XCTAssertTrue(expired.contains("有効時間が過ぎました")); XCTAssertTrue(expired.contains("内容をもう一度確認"))
        XCTAssertTrue(expired.contains("使われた分は戻らないことがあります"))
        XCTAssertTrue(stale.contains("内容を見直し")); XCTAssertFalse(stale.contains("有効時間が過ぎました"))
        XCTAssertTrue(stale.contains("自動では開始しません"))
    }
    func testTerminalExpiredFixtureUsesReadableRecovery() throws {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: Self.self)
        #endif
        let state = try JSONDecoder().decode(ComparisonState.self, from: Data(contentsOf: XCTUnwrap(bundle.url(forResource: "comparison-expired", withExtension: "json"))))
        XCTAssertTrue(state.terminalMessage.contains("有効時間が過ぎました"))
        XCTAssertFalse(state.terminalMessage.contains("comparison_expired"))
    }
    func testQuotaFailurePreservesMachineCode() async throws {
        let api = try client(status: 429, payload: "{\"error\":{\"code\":\"daily_budget_exceeded\",\"message\":\"quota\"}}")
        await api.setToken("session")
        do { let _: JSONValue = try await api.get("/v1/usage"); XCTFail() }
        catch { XCTAssertEqual(error as? NetworkFailure, .server(status: 429, code: "daily_budget_exceeded")) }
    }
    func testMalformedSuccessIsNotAValidAnswer() async throws {
        let api = try client(payload: "not-json"); await api.setToken("session")
        do { let _: JSONValue = try await api.get("/v1/me"); XCTFail() }
        catch { XCTAssertEqual(error as? NetworkFailure, .invalidResponse) }
    }
    func testRevokedTokenCannotDispatchAnotherRequest() async throws {
        let api = try client(); await api.setToken("session"); await api.setToken(nil)
        do { let _: JSONValue = try await api.get("/v1/me"); XCTFail() }
        catch { XCTAssertEqual(error as? NetworkFailure, .unauthenticated) }
    }
}
private final class StubProtocol: URLProtocol {
    // XCTest methods in this suite are serial; no real network is used.
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
