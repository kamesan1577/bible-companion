import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import CompanionCore

@main struct RunStateChecks {
    @MainActor static func reset() {
        SessionVault.cleanupPending = false; SessionVault.session = nil; SessionVault.failRead = false; SessionVault.failClear = false; SessionVault.clears = 0
        PrivateHistoryStore.failRead = false; PrivateHistoryStore.clears = 0
        ShareInbox.owner = nil; ShareInbox.shares = []; ShareInbox.failOwner = false; ShareInbox.unavailable = false; ShareInbox.failClear = false; ShareInbox.clears = 0; ShareInbox.capability = nil; ShareInbox.accessSaveCount = 0; ShareInbox.accessVerifyCount = 0; ShareInbox.accessClears = 0; ShareInbox.failAccessSave = false; ShareInbox.failAccessReadback = false; ShareIssueProtocol.state.reset()
        PendingQuestionStore.clears = 0; PendingQuestionStore.record = nil; ComparisonStore.clears = 0; ComparisonStore.record = nil; ExportFiles.clears = 0; WebLogin.attempts = 0
    }
    @MainActor fileprivate static func waitForHarness(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() {
            precondition(Date() < deadline, "Share-access harness timed out")
            try await Task.sleep(for: .milliseconds(5))
        }
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
        try await runShareAccessChecks(account: account)

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
        var revokeFailure: Error?
        let revoke = Task {
            do { try await consentStore.consent(false, expectedEpoch: intent.sessionEpoch) }
            catch { revokeFailure = error }
        }
        try await RunStateChecks.waitForHarness { ConsentProtocol.state.postCount > 0 || revokeFailure != nil }
        if let revokeFailure { throw revokeFailure }
        precondition(consentStore.isConsentUpdating && consentStore.aiPolicy == nil)
        let reads = ConsentProtocol.state.policyReads
        await consentStore.loadAIPolicy()
        precondition(ConsentProtocol.state.policyReads == reads && consentStore.aiPolicy == nil)
        do { try await consentStore.consentGrounded(false, intent: intent); preconditionFailure("Concurrent mutation accepted") }
        catch { precondition(error as? NetworkFailure == .cancelled) }
        ConsentProtocol.state.release.signal(); await revoke.value
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
        print("21 app-model control-flow checks passed. Fake storage/auth/observation boundaries; NOT Apple SDK or device validation.")
    }
}

@MainActor private func runShareAccessChecks(account: Account) async throws {
    func makeStore() async throws -> AppStore {
        SessionVault.session = StoredSession(token: "synthetic", expiresAt: Date().addingTimeInterval(600).timeIntervalSince1970, user: account)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ShareIssueProtocol.self]
        let client = try APIClient(baseURL: URL(string: "https://example.test")!, configuration: config)
        let store = AppStore(apiClient: client)
        await store.restore(); await store.loadAIPolicy()
        precondition(store.account?.id == account.id && store.aiPolicy?.permits(.groundedGeneration) == true)
        return store
    }

    // A successful but late response must not recreate local access after consent revocation.
    RunStateChecks.reset()
    ShareIssueProtocol.state.configure(holdShareIssue: true)
    let revoked = try await makeStore(); let epoch = revoked.sessionEpoch
    let issuance = Task { try await revoked.enableShareAI(expectedEpoch: epoch) }
    try await RunStateChecks.waitForHarness { ShareIssueProtocol.state.shareIssueCount == 1 }
    await revoked.signOut(revokeRemote: false)
    let otherAccount = try JSONDecoder().decode(Account.self, from: Data(#"{"id":"22222222-2222-4222-8222-222222222222","display_name":"Other","role":"owner"}"#.utf8))
    ShareIssueProtocol.state.configureUserID(otherAccount.id)
    SessionVault.session = StoredSession(token: "other-synthetic", expiresAt: Date().addingTimeInterval(600).timeIntervalSince1970, user: otherAccount)
    await revoked.restore(); await revoked.loadAIPolicy()
    precondition(revoked.account?.id == otherAccount.id && ShareInbox.capability == nil)
    ShareIssueProtocol.state.releaseShareIssue.signal()
    do { try await issuance.value; preconditionFailure("Late share-access response was accepted after revocation") }
    catch { precondition(error as? NetworkFailure == .cancelled) }
    precondition(ShareInbox.accessSaveCount == 0 && ShareInbox.capability == nil)
    do { _ = try ShareInbox.verifiedAIAccess(expectedOwner: account.id); preconditionFailure("Revoked capability became readable") }
    catch { precondition(error as? ShareAIAccessReadError == .missing) }
    print("PASS delayed share-access response cannot save after account/session change")

    // Worker-consent revocation invalidates a pending issuance for the same session.
    RunStateChecks.reset()
    ShareIssueProtocol.state.configure(holdShareIssue: true)
    let workerRevoked = try await makeStore(); let workerEpoch = workerRevoked.sessionEpoch
    let workerIssuance = Task { try await workerRevoked.enableShareAI(expectedEpoch: workerEpoch) }
    try await RunStateChecks.waitForHarness { ShareIssueProtocol.state.shareIssueCount == 1 }
    try await workerRevoked.consent(false, expectedEpoch: workerEpoch)
    precondition(workerRevoked.aiPolicy?.workersAiConsent == false && ShareInbox.capability == nil)
    ShareIssueProtocol.state.releaseShareIssue.signal()
    do { try await workerIssuance.value; preconditionFailure("Late response survived worker-consent revocation") }
    catch { precondition(error as? NetworkFailure == .cancelled) }
    precondition(ShareInbox.accessSaveCount == 0 && ShareInbox.capability == nil)
    print("PASS worker-consent revocation blocks late share capability save")

    // Grounded-consent revocation independently invalidates a pending issuance.
    RunStateChecks.reset()
    ShareIssueProtocol.state.configure(holdShareIssue: true)
    let groundedRevoked = try await makeStore(); let groundedEpoch = groundedRevoked.sessionEpoch
    let groundedIntent = GroundedConsentIntent(ownerID: account.id, sessionEpoch: groundedEpoch, policy: groundedRevoked.aiPolicy!)
    let groundedIssuance = Task { try await groundedRevoked.enableShareAI(expectedEpoch: groundedEpoch) }
    try await RunStateChecks.waitForHarness { ShareIssueProtocol.state.shareIssueCount == 1 }
    try await groundedRevoked.consentGrounded(false, intent: groundedIntent)
    precondition(groundedRevoked.aiPolicy?.permits(.groundedGeneration) == false && ShareInbox.capability == nil)
    ShareIssueProtocol.state.releaseShareIssue.signal()
    do { try await groundedIssuance.value; preconditionFailure("Late response survived grounded-consent revocation") }
    catch { precondition(error as? NetworkFailure == .cancelled) }
    precondition(ShareInbox.accessSaveCount == 0 && ShareInbox.capability == nil)
    print("PASS grounded-consent revocation blocks late share capability save")

    // Normal issuance is accepted only after owner-bound write and verified readback.
    RunStateChecks.reset()
    ShareIssueProtocol.state.configure(holdShareIssue: false)
    let issued = try await makeStore()
    try await issued.enableShareAI(expectedEpoch: issued.sessionEpoch)
    let stored = try ShareInbox.verifiedAIAccess(expectedOwner: account.id)
    precondition(stored.ownerID == account.id && stored.token.hasPrefix("bcs1_"))
    precondition(ShareInbox.accessSaveCount == 1 && ShareInbox.accessVerifyCount >= 2)
    precondition(issued.aiPolicy?.shareAiConsent == true)
    print("PASS share-access issuance verifies owner-bound persisted capability")

    // Simulate the write landing but the immediate readback failing.
    RunStateChecks.reset()
    ShareIssueProtocol.state.configure(holdShareIssue: false)
    ShareInbox.failAccessReadback = true
    let unreadable = try await makeStore()
    do { try await unreadable.enableShareAI(expectedEpoch: unreadable.sessionEpoch); preconditionFailure("Readback failure was treated as success") }
    catch { precondition(error as? ShareAIAccessReadError == .writeFailed) }
    precondition(ShareInbox.accessSaveCount == 1 && ShareInbox.accessVerifyCount == 1)
    do { _ = try ShareInbox.verifiedAIAccess(expectedOwner: account.id); preconditionFailure("Injected readback failure disappeared") }
    catch { precondition(error as? ShareAIAccessReadError == .writeFailed) }
    precondition(unreadable.aiPolicy?.shareAiConsent == false)
    print("PASS share-access write/readback mismatch is a typed non-success")

    // A completed grounded-consent update does not imply the local capability was saved.
    RunStateChecks.reset()
    ShareIssueProtocol.state.configure(holdShareIssue: false)
    let grantedThenSaveFails = try await makeStore()
    let grantIntent = GroundedConsentIntent(ownerID: account.id, sessionEpoch: grantedThenSaveFails.sessionEpoch, policy: grantedThenSaveFails.aiPolicy!)
    try await grantedThenSaveFails.consentGrounded(true, intent: grantIntent)
    precondition(grantedThenSaveFails.aiPolicy?.permits(.groundedGeneration) == true)
    ShareInbox.failAccessSave = true
    do { try await grantedThenSaveFails.enableShareAI(expectedEpoch: grantedThenSaveFails.sessionEpoch); preconditionFailure("Capability save failure was treated as success after consent grant") }
    catch { precondition(error as? ShareAIAccessReadError == .writeFailed) }
    precondition(ShareInbox.accessSaveCount == 1 && ShareInbox.capability == nil)
    precondition(grantedThenSaveFails.aiPolicy?.shareAiConsent == false)
    print("PASS successful grounded-consent update does not mask capability save failure")

    // An expired saved token is replaced when policy still allows sharing.
    RunStateChecks.reset()
    ShareIssueProtocol.state.configure(holdShareIssue: false)
    ShareIssueProtocol.state.configureShareConsent(true)
    let refreshed = try await makeStore()
    ShareInbox.capability = ShareAIAccess(token: "bcs1_" + String(repeating: "b", count: 64), ownerID: account.id, expiresAt: Date().addingTimeInterval(-30).timeIntervalSince1970)
    await refreshed.refreshShareAI()
    let replacement = try ShareInbox.verifiedAIAccess(expectedOwner: account.id)
    precondition(replacement.expiresAt > Date().timeIntervalSince1970 && ShareIssueProtocol.state.shareIssueCount == 1)
    precondition(ShareInbox.accessSaveCount == 1 && refreshed.shareNotice == nil)
    print("PASS expired owner-bound capability is refreshed and verified")
}

private final class ShareIssueState: @unchecked Sendable {
    private let lock = NSLock()
    private var issueCount = 0
    private var holdIssue = false
    private var workers = true
    private var grounded = true
    private var shareConsent = false
    private var userID = "11111111-1111-4111-8111-111111111111"
    let shareIssueStarted = DispatchSemaphore(value: 0)
    let releaseShareIssue = DispatchSemaphore(value: 0)
    var shareIssueCount: Int { lock.withLock { issueCount } }
    func reset() { lock.withLock { issueCount = 0; holdIssue = false; workers = true; grounded = true; shareConsent = false; userID = "11111111-1111-4111-8111-111111111111" } }
    func configure(holdShareIssue: Bool) { lock.withLock { holdIssue = holdShareIssue } }
    func configureShareConsent(_ value: Bool) { lock.withLock { shareConsent = value } }
    func configureUserID(_ value: String) { lock.withLock { userID = value } }
    func response(_ request: URLRequest) throws -> Data {
        let path = request.url?.path ?? ""
        if path == "/v1/me" {
            let id = lock.withLock { userID }
            return Data("{\"user\":{\"id\":\"\(id)\",\"display_name\":\"Test\",\"role\":\"owner\"}}".utf8)
        }
        if path == "/v1/imports" { return Data(#"{"items":[],"nextCursor":null}"#.utf8) }
        if path == "/v1/me/ai-policy" {
            return lock.withLock {
                let accepted = grounded ? "true" : "false"
                let version = grounded ? "\"v1\"" : "null"
                return Data("{\"allowedAnswerModes\":[\"reviewed-claim-selection\",\"grounded-generation\"],\"defaultAnswerMode\":\"grounded-generation\",\"groundedPolicyVersion\":\"v1\",\"groundedNoticeJa\":\"notice\",\"workersAiConsent\":\(workers),\"shareAiEnabled\":true,\"shareAiConsent\":\(shareConsent),\"groundedConsent\":{\"accepted\":\(accepted),\"policyVersion\":\(version)}}".utf8)
            }
        }
        if path == "/v1/me/consents" {
            let body = try JSONDecoder().decode(JSONValue.self, from: requestBodyData(request))
            return lock.withLock {
                if body["workersAi"].bool == false { workers = false; grounded = false; shareConsent = false }
                if let consent = body["groundedGeneration"]["accepted"].bool { grounded = consent }
                return Data("{\"workersAi\":\(workers)}".utf8)
            }
        }
        if path == "/v1/me/share-access" {
            let (shouldHold, owner) = lock.withLock { () -> (Bool, String) in issueCount += 1; return (holdIssue, userID) }
            shareIssueStarted.signal()
            if shouldHold { releaseShareIssue.wait() }
            let token = "bcs1_" + String(repeating: "a", count: 64)
            let expires = Date().addingTimeInterval(300).timeIntervalSince1970
            lock.withLock { shareConsent = true }
            return Data("{\"token\":\"\(token)\",\"ownerId\":\"\(owner)\",\"expiresAt\":\(expires)}".utf8)
        }
        return Data(#"{"items":[],"nextCursor":null}"#.utf8)
    }
}
private final class ShareIssueProtocol: URLProtocol, @unchecked Sendable {
    static let state = ShareIssueState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        // Never block URLSession's protocol queue while a test holds the fake POST.
        DispatchQueue.global().async { [self] in
            do {
                let data = try Self.state.response(self.request)
                self.client?.urlProtocol(self, didReceive: HTTPURLResponse(url: self.request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: data); self.client?.urlProtocolDidFinishLoading(self)
            } catch { self.client?.urlProtocol(self, didFailWithError: error) }
        }
    }
    override func stopLoading() {}
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
            let parsed = try JSONDecoder().decode(JSONValue.self, from: requestBodyData(request))
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

func requestBodyData(_ request: URLRequest) throws -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open(); defer { stream.close() }
    var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count < 0 { throw stream.streamError ?? NetworkFailure.invalidResponse }
        if count == 0 { break }
        data.append(buffer, count: count)
    }
    return data
}
private final class ConsentProtocol: URLProtocol, @unchecked Sendable {
    static let state = ConsentState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        DispatchQueue.global().async { [self] in
            do {
                let data = try Self.state.response(request)
                client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
            } catch { client?.urlProtocol(self, didFailWithError: error) }
        }
    }
    override func stopLoading() {}
}
