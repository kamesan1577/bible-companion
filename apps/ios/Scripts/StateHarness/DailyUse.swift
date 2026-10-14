// Runs exact app-model source with fake persistence/HTTP boundaries, never Apple SDK stubs.
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import CompanionCore

@MainActor private func waitUntil(_ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(5)
    while !condition() {
        precondition(Date() < deadline, "App-model test timed out")
        try await Task.sleep(for: .milliseconds(5))
    }
}
private func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(name + ".json"))
}
private func api() throws -> APIClient {
    let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [DailyProtocol.self]
    return try APIClient(baseURL: URL(string: "https://example.test")!, configuration: config)
}
@MainActor func runDailyUseChecks(account: Account) async throws {
    RunStateChecks.reset()
    let client = try api(); await client.setToken("synthetic")
    let item = try JSONDecoder().decode(ImportRecord.self, from: fixture("import"))
    let question = QuestionModel(ownerID: account.id, client: client, item: item, rangeIndex: 0)
    question.draft = "範囲の資料"; question.send(target: item.ranges[0])
    try await waitUntil { !question.isRunning }
    precondition(question.needsStatusCheck)
    let requestID = question.requestID
    let first = Task { await question.checkStatus() }
    try await waitUntil { DailyProtocol.state.statusReads == 1 }
    precondition(question.isCheckingStatus)
    await question.checkStatus()
    precondition(DailyProtocol.state.statusReads == 1)
    question.send(target: item.ranges[0]); precondition(question.requestID == requestID)
    DailyProtocol.state.release.signal(); await first.value
    precondition(!question.isCheckingStatus && !question.needsStatusCheck && question.answer == nil)
    print("PASS question status checks serialize and preserve the original request identity")

    let late = Task { await question.checkStatus() }
    try await waitUntil { DailyProtocol.state.statusReads == 2 }
    question.close(); let before = question.status
    DailyProtocol.state.release.signal(); await late.value
    precondition(question.status == before && question.answer == nil && !question.isCheckingStatus)
    print("PASS closing question rejects a late status body")
    DailyProtocol.state.release.signal(); await question.checkStatus()
    precondition(question.answer != nil)
    DailyProtocol.state.release.signal(); await question.checkStatus()
    precondition(question.answer == nil && question.requestID == requestID)
    print("PASS authoritative status rejection clears an earlier answer without changing identity")

    let initial = try JSONDecoder().decode(ComparisonState.self, from: fixture("comparison-start"))
    let ids = Set(initial.trials.array.compactMap { $0["modelId"].string }).sorted()
    let plan = JSONValue.object(["requestId": .string(initial.requestId), "models": .array(ids.map { .object(["modelId": .string($0), "settings": .object([:])]) }), "questions": initial.results?["questions"] ?? .array([]), "saveResults": .bool(true)])
    let comparison = ComparisonModel(ownerID: account.id, client: client)
    comparison.start(plan: plan, hash: String(repeating: "h", count: 43))
    try await waitUntil { !comparison.busy }
    precondition(DailyProtocol.state.stepCount == 2 && comparison.answers.isEmpty && comparison.pending != nil && comparison.state?.results == nil)
    DailyProtocol.state.policyFailure = false
    ComparisonStore.record = nil // Independent fixture scenario; no real ledger is deleted.
    let retained = ComparisonModel(ownerID: account.id, client: client)
    retained.start(plan: plan, hash: String(repeating: "h", count: 43))
    try await waitUntil { !retained.busy }
    precondition(retained.answers.count == 1 && retained.pending != nil)
    retained.clearPresentationForScopeChange()
    precondition(retained.answers.isEmpty && retained.pending != nil && retained.state?.results == nil && ComparisonStore.record != nil)
    print("PASS comparison policy and scope changes clear bodies without losing recovery identity")
    DailyProtocol.state.completeRemaining = true
    retained.resume(); try await waitUntil { !retained.busy }
    precondition(retained.pending == nil && retained.state?.isTerminal == true && retained.answers.count == 1)
    precondition(retained.presentationPlan == plan)
    print("PASS resumed comparison keeps its original result scope after terminal ledger removal")

    RunStateChecks.reset()
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let cache = PublicReadingCache(directory: root, marker: HarnessCacheMarker())
    var object = try JSONSerialization.jsonObject(with: fixture("reading")) as! [String: Any]
    object["checkedAt"] = Date().timeIntervalSince1970
    let reading = try JSONDecoder().decode(ReadingResponse.self, from: JSONSerialization.data(withJSONObject: object))
    try await cache.store(reading)
    SessionVault.session = StoredSession(token: "synthetic", expiresAt: Date().addingTimeInterval(600).timeIntervalSince1970, user: account)
    let store = AppStore(apiClient: try api(), readingCache: cache)
    await store.restore(); store.select(item)
    try await waitUntil { !store.isRevalidatingSource }
    precondition(store.cachedSnapshot != nil && store.reading != nil)
    let intent = DeletionIntent(ownerID: account.id, sessionEpoch: store.sessionEpoch, kind: .readingData)
    do { try await store.deletePrivateData(intent, typedConfirmation: "削除"); preconditionFailure("Expected recent-auth rejection") }
    catch { precondition(error as? NetworkFailure == .server(status: 403, code: "reauthentication_required")) }
    precondition(store.account?.id == account.id && store.cachedSnapshot == nil && store.reading == nil)
    store.loadReading(); try await waitUntil { !store.isRevalidatingSource }
    precondition(store.cachedSnapshot != nil) // Authorized cache survives; only cancelled display was removed.
    store.cancelReading()
    print("PASS rejected deletion cannot leave cache visible without expiry; offline reopening still works")
}
private final class HarnessCacheMarker: PublicCacheValidationMarker, @unchecked Sendable {
    private let lock = NSLock(); private var required = false
    func requiresValidation() -> Bool { lock.withLock { required } }
    func setRequired(_ value: Bool) { lock.withLock { required = value } }
}
private final class DailyState: @unchecked Sendable {
    private let lock = NSLock()
    let release = DispatchSemaphore(value: 0)
    private var reads = 0, steps = 0, policy = true, complete = false
    var completeRemaining: Bool { get { lock.withLock { complete } } set { lock.withLock { complete = newValue } } }
    var statusReads: Int { lock.withLock { reads } }
    var stepCount: Int { lock.withLock { steps } }
    var policyFailure: Bool { get { lock.withLock { policy } } set { lock.withLock { policy = newValue } } }
    func response(_ request: URLRequest) throws -> (Int, Data) {
        let path = request.url!.path
        if path == "/v1/content-manifest" { throw URLError(.notConnectedToInternet) }
        if path == "/v1/me/reading-data" { return (403, Data(#"{"error":{"code":"reauthentication_required"}}"#.utf8)) }
        if path == "/v1/me" { return (200, Data(#"{"user":{"id":"11111111-1111-4111-8111-111111111111","display_name":"Test","role":"owner"}}"#.utf8)) }
        if path == "/v1/conversations" { return (200, try fixture("conversation")) }
        if path.hasSuffix("/questions") {
            let body = try JSONDecoder().decode(JSONValue.self, from: request.httpBody!)
            return (200, try JSONEncoder().encode(JSONValue.object(["requestId": body["requestId"], "status": .string("running"), "result": .null])))
        }
        if path.hasPrefix("/v1/requests/") {
            let index = lock.withLock { reads += 1; return reads }
            release.wait()
            if index == 4 { return (401, Data("{}".utf8)) }
            let result = try JSONDecoder().decode(JSONValue.self, from: fixture("question-result"))
            return (200, try JSONEncoder().encode(JSONValue.object(["requestId": .string(request.url!.lastPathComponent), "status": .string("complete"), "result": index == 1 ? .null : result["result"]])))
        }
        if path == "/v1/developer/comparisons" { return (202, try currentComparison("comparison-start", nested: false)) }
        if request.httpMethod == "GET", path.hasPrefix("/v1/developer/comparisons/") {
            let data = try currentComparison("comparison-step", nested: true)
            let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            return (200, try JSONSerialization.data(withJSONObject: object["state"]!))
        }
        if path.hasSuffix("/steps") {
            lock.withLock { steps += 1 }
            let body = try JSONDecoder().decode(JSONValue.self, from: request.httpBody!)
            if body["trialIndex"] == .number(0) { return (200, try currentComparison("comparison-step", nested: true)) }
            if completeRemaining {
                var object = try JSONSerialization.jsonObject(with: currentComparison("comparison-step", nested: true)) as! [String: Any]
                var state = object["state"] as! [String: Any]
                state["status"] = "complete"; state["phase"] = "terminal"; state["completedCount"] = 2; state["nextTrialIndex"] = NSNull()
                object["state"] = state; object["trialIndex"] = 1
                return (200, try JSONSerialization.data(withJSONObject: object))
            }
            return (policyFailure ? 409 : 503, Data((policyFailure ? #"{"error":{"code":"source_policy_changed"}}"# : #"{"error":{"code":"temporary_failure"}}"#).utf8))
        }
        return (200, Data(#"{"items":[],"nextCursor":null}"#.utf8))
    }
    private func currentComparison(_ name: String, nested: Bool) throws -> Data {
        var object = try JSONSerialization.jsonObject(with: fixture(name)) as! [String: Any]
        if nested { var state = object["state"] as! [String: Any]; state["expiresAt"] = Date().addingTimeInterval(900).timeIntervalSince1970; object["state"] = state }
        else { object["expiresAt"] = Date().addingTimeInterval(900).timeIntervalSince1970 }
        return try JSONSerialization.data(withJSONObject: object)
    }
}
private final class DailyProtocol: URLProtocol {
    static let state = DailyState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.state.response(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
