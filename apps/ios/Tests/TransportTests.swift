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
    func testRateLimitCopyDoesNotClaimDailyBudgetExhaustion() {
        let rate = NetworkFailure.server(status: 429, code: "rate_limited").userMessage
        let budget = NetworkFailure.server(status: 429, code: "daily_budget_exceeded").userMessage
        XCTAssertTrue(rate.contains("時間をおいて")); XCTAssertFalse(rate.contains("リセット"))
        XCTAssertTrue(budget.contains("リセット")); XCTAssertNotEqual(rate, budget)
    }
    func testOversizedComparisonDoesNotPromiseResetWillFixIt() {
        let message = NetworkFailure.server(status: 429, code: "comparison_budget_exceeded").userMessage
        XCTAssertTrue(message.contains("質問数")); XCTAssertTrue(message.contains("最大出力トークン"))
        XCTAssertTrue(message.contains("リセット後も実行できません")); XCTAssertTrue(message.contains("自動で設定は変更しません"))
    }
    func testBudgetVerificationDoesNotDiagnoseExpiryOrDailyExhaustion() {
        let message = NetworkFailure.server(status: 503, code: "budget_unverified").userMessage
        XCTAssertTrue(message.contains("区別はこの応答ではできません"))
        XCTAssertTrue(message.contains("オーナー"))
        XCTAssertTrue(message.contains("日次上限の消費を示すものではありません"))
        XCTAssertFalse(message.contains("期限が切れました"))
        XCTAssertFalse(message.contains("リセット時刻"))
    }
    func testOwnerBudgetRecoveryNamesCLIWithoutClaimingRenewalWasDone() {
        let message = AIAvailabilityExplanation.catalogReason("BUDGET_UNVERIFIED")
        XCTAssertTrue(message.contains("運用CLI")); XCTAssertTrue(message.contains("Free運用では必要に応じて証跡を更新"))
        XCTAssertTrue(message.contains("準備状況を再確認")); XCTAssertFalse(message.contains("更新しました"))
    }
    func testConnectionAndModelTermsHaveDistinctRecovery() {
        let connection = NetworkFailure.server(status: 503, code: "ai_not_connected").userMessage
        let terms = NetworkFailure.server(status: 503, code: "model_terms_unreviewed").userMessage
        XCTAssertTrue(connection.contains("接続状態")); XCTAssertTrue(connection.contains("オーナー"))
        XCTAssertTrue(terms.contains("個人のAI送信への同意とは別")); XCTAssertNotEqual(connection, terms)
        XCTAssertTrue(AIAvailabilityExplanation.catalogReason("MODEL_TERMS_UNREVIEWED").contains("この画面では同意を行いません"))
    }
    func testKnownCatalogReasonsDoNotLeakRawMachineCodes() {
        for code in ["CONNECTION_NOT_VERIFIED", "MODEL_UNCONNECTED", "MODEL_TERMS_UNREVIEWED", "BUDGET_UNVERIFIED", "BUDGET_EXCEEDED", "PAID_APPROVAL_REQUIRED", "MODEL_DISABLED"] {
            XCTAssertFalse(AIAvailabilityExplanation.catalogReason(code).contains(code), code)
        }
        XCTAssertTrue(AIAvailabilityExplanation.catalogReason("PAID_APPROVAL_REQUIRED").contains("Free運用では有効にできません"))
    }
    func testRequestBudgetTooLargeDoesNotPromiseResetFixesIt() {
        let message = NetworkFailure.server(status: 429, code: "budget_exceeded").userMessage
        XCTAssertTrue(message.contains("最大出力トークン")); XCTAssertTrue(message.contains("リセットを待つだけでは解消しません"))
    }
    func testUnknownReasonsRemainExactAndDoNotInventDiagnosis() {
        XCTAssertTrue(AIAvailabilityExplanation.catalogReason("NEW_REASON_v2").contains("NEW_REASON_v2"))
        XCTAssertTrue(AIAvailabilityExplanation.catalogReason(nil).contains("理由を確認できません"))
        let message = NetworkFailure.server(status: 429, code: "new_quota_reason").userMessage
        XCTAssertTrue(message.contains("new_quota_reason")); XCTAssertFalse(message.contains("リセット"))
    }
    func testExpiredAndStaleComparisonsHaveDifferentRecovery() {
        let expired = NetworkFailure.server(status: 409, code: "comparison_expired").userMessage
        let stale = NetworkFailure.server(status: 409, code: "plan_changed").userMessage
        XCTAssertTrue(expired.contains("比較の実行期限")); XCTAssertTrue(expired.contains("新しい計画"))
        XCTAssertTrue(expired.contains("利用量が戻るとは限りません"))
        XCTAssertTrue(stale.contains("計画と利用枠を確認し直して")); XCTAssertFalse(stale.contains("期限が切れました"))
        XCTAssertTrue(stale.contains("自動では実行しません"))
    }
    func testTerminalExpiredFixtureUsesReadableRecovery() throws {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: Self.self)
        #endif
        let state = try JSONDecoder().decode(ComparisonState.self, from: Data(contentsOf: XCTUnwrap(bundle.url(forResource: "comparison-expired", withExtension: "json"))))
        XCTAssertTrue(state.terminalMessage.contains("比較の実行期限"))
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
