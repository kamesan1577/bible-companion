import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import CompanionCore

@main struct RunStateChecks {
    @MainActor static func reset() {
        SessionVault.cleanupPending = false; SessionVault.session = nil; SessionVault.failRead = false; SessionVault.failClear = false; SessionVault.clears = 0
        PrivateHistoryStore.failRead = false; PrivateHistoryStore.clears = 0
        ShareInbox.owner = nil; ShareInbox.shares = []; ShareInbox.failOwner = false; ShareInbox.unavailable = false; ShareInbox.failClear = false; ShareInbox.clears = 0
        PendingQuestionStore.clears = 0; PendingQuestionStore.record = nil; ComparisonStore.clears = 0; ComparisonStore.record = nil; ExportFiles.clears = 0; WebLogin.attempts = 0
    }
    @MainActor static func main() async throws {
        let account = try JSONDecoder().decode(Account.self, from: Data(#"{"id":"11111111-1111-4111-8111-111111111111","display_name":"Test","role":"owner"}"#.utf8))
        reset()
        let queued = PendingShare(ownerID: nil, text: "ACT 18:24")
        ShareInbox.shares = [queued]
        let firstLaunch = AppStore(apiBaseURL: URL(string: "https://example.test")!); await firstLaunch.restore()
        precondition(firstLaunch.account == nil && firstLaunch.pendingShares.count == 1)
        precondition(ShareInbox.clears == 0 && ShareInbox.shares.first?.id == queued.id)
        print("PASS signed-out launch preserves unbound share")

        reset()
        SessionVault.session = StoredSession(token: "synthetic", expiresAt: Date().addingTimeInterval(600).timeIntervalSince1970, user: account)
        PrivateHistoryStore.failRead = true
        let locked = AppStore(apiBaseURL: URL(string: "https://example.test")!); await locked.restore()
        precondition(locked.account == nil && locked.restoreNeedsRetry && SessionVault.session != nil)
        locked.signIn(); await Task.yield(); precondition(WebLogin.attempts == 0)
        do { let _: JSONValue = try await locked.client.get("/v1/me"); preconditionFailure("No token should have been installed") }
        catch { precondition(error as? NetworkFailure == .unauthenticated) }
        print("PASS unreadable history never publishes authenticated state")

        ShareInbox.failClear = true
        await locked.signOut(revokeRemote: false)
        precondition(locked.account == nil && locked.localCleanupRequired && SessionVault.cleanupPending)
        precondition(PendingQuestionStore.clears > 0 && ComparisonStore.clears > 0)
        ShareInbox.failClear = false; locked.retryLocalCleanup()
        precondition(!locked.localCleanupRequired && !SessionVault.cleanupPending && !locked.restoreNeedsRetry)
        print("PASS explicit restore recovery retains failure flag until cleanup succeeds")

        reset()
        let expired = AppStore(apiBaseURL: URL(string: "https://example.test")!); ShareInbox.failClear = true
        expired.handle(NetworkFailure.unauthenticated)
        precondition(expired.account == nil && expired.localCleanupRequired && SessionVault.cleanupPending)
        precondition(PrivateHistoryStore.clears == 1 && PendingQuestionStore.clears == 1 && ComparisonStore.clears == 1)
        precondition(ExportFiles.clears == 2) // Startup cleanup plus synchronous401 cleanup.
        let restarted = AppStore(apiBaseURL: URL(string: "https://example.test")!); await restarted.restore()
        precondition(restarted.localCleanupRequired && restarted.account == nil)
        print("PASS401 cleanup failure remains blocked across a new store instance")

        reset()
        ShareInbox.shares = [queued]; ShareInbox.failOwner = true
        let ownerLocked = AppStore(apiBaseURL: URL(string: "https://example.test")!); await ownerLocked.restore()
        precondition(ownerLocked.restoreNeedsRetry && ownerLocked.account == nil && ShareInbox.shares.count == 1)
        print("PASS owner-marker I/O failure preserves queued content and blocks bootstrap")

        reset()
        ShareInbox.unavailable = true
        let noGroup = AppStore(apiBaseURL: URL(string: "https://example.test")!); await noGroup.restore()
        precondition(!noGroup.restoreNeedsRetry && !noGroup.localCleanupRequired && noGroup.shareNotice != nil)
        print("PASS missing App Group exposes manual-import fallback")
        reset()
        SessionVault.session = StoredSession(token: "synthetic", expiresAt: Date().addingTimeInterval(600).timeIntervalSince1970, user: account)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ConsentProtocol.self]
        let api = try APIClient(baseURL: URL(string: "https://example.test")!, configuration: config)
        let consentStore = AppStore(apiClient: api)
        await consentStore.restore(); await consentStore.loadAIPolicy()
        let policy = consentStore.aiPolicy!
        let intent = GroundedConsentIntent(ownerID: account.id, sessionEpoch: consentStore.sessionEpoch, policy: policy)
        let revoke = Task { try await consentStore.consent(false, expectedEpoch: intent.sessionEpoch) }
        while ConsentProtocol.state.postCount == 0 { await Task.yield() }
        precondition(consentStore.isConsentUpdating && consentStore.aiPolicy == nil)
        let reads = ConsentProtocol.state.policyReads
        await consentStore.loadAIPolicy()
        precondition(ConsentProtocol.state.policyReads == reads && consentStore.aiPolicy == nil)
        do { try await consentStore.consentGrounded(false, intent: intent); preconditionFailure("Concurrent mutation accepted") }
        catch { precondition(error as? NetworkFailure == .cancelled) }
        ConsentProtocol.state.release.signal(); try await revoke.value
        precondition(!consentStore.isConsentUpdating && consentStore.aiPolicy?.workersAiConsent == false)
        print("PASS consent mutations serialize and policy refresh cannot republish stale grants")

        let revokedPolicy = consentStore.aiPolicy!
        let partialIntent = GroundedConsentIntent(ownerID: account.id, sessionEpoch: consentStore.sessionEpoch, policy: revokedPolicy)
        ConsentProtocol.state.release.signal()
        try await consentStore.consentGrounded(false, intent: partialIntent)
        guard case .object(let partialBody) = ConsentProtocol.state.lastBody else { preconditionFailure("Expected consent body") }
        precondition(partialBody["workersAi"] == nil)
        precondition(consentStore.aiPolicy?.workersAiConsent == false)
        print("PASS grounded revocation omits provider grant and preserves revoked consent")
        try await runDailyUseChecks(account: account)
        print("14 app-model control-flow checks passed. Fake storage/auth/observation boundaries; NOT Apple SDK or device validation.")
    }
}

private final class ConsentState: @unchecked Sendable {
    private let lock = NSLock()
    let release = DispatchSemaphore(value: 0)
    private var posts = 0, reads = 0
    private var body: JSONValue?
    private var workers = true
    var postCount: Int { lock.withLock { posts } }
    var policyReads: Int { lock.withLock { reads } }
    var lastBody: JSONValue? { lock.withLock { body } }
    func response(_ request: URLRequest) throws -> Data {
        if request.url?.path == "/v1/me/consents" {
            let parsed = try JSONDecoder().decode(JSONValue.self, from: request.httpBody ?? Data())
            lock.withLock { posts += 1; body = parsed }
            release.wait()
            return lock.withLock {
                if parsed["workersAi"].bool == false { workers = false }
                return Data("{\"workersAi\":\(workers)}".utf8)
            }
        }
        if request.url?.path == "/v1/me/ai-policy" {
            return lock.withLock {
                reads += 1
                return Data("{\"allowedAnswerModes\":[\"reviewed-claim-selection\",\"grounded-generation\"],\"defaultAnswerMode\":\"reviewed-claim-selection\",\"groundedPolicyVersion\":\"v1\",\"groundedNoticeJa\":\"notice\",\"workersAiConsent\":\(workers),\"groundedConsent\":{\"accepted\":false,\"policyVersion\":null}}".utf8)
            }
        }
        if request.url?.path == "/v1/me" { return Data(#"{"user":{"id":"11111111-1111-4111-8111-111111111111","display_name":"Test","role":"owner"}}"#.utf8) }
        return Data(#"{"items":[],"nextCursor":null}"#.utf8)
    }
}
private final class ConsentProtocol: URLProtocol {
    static let state = ConsentState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let data = try Self.state.response(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
