import SwiftUI
import CompanionCore

@MainActor final class AppStore: ObservableObject {
    @Published private(set) var sessionEpoch = UUID()
    @Published private(set) var restoreNeedsRetry = false
    @Published private(set) var isTransitioning = false
    @Published private(set) var localCleanupRequired = false
    @Published private(set) var exportCleanupRequired = false
    @Published private(set) var isDeleting = false
    @Published var privacyNotice: String?
    @Published private(set) var account: Account?
    @Published private(set) var history: [ImportRecord] = []
    @Published private(set) var historyLoading = false
    @Published private(set) var historyChecked = false
    @Published private(set) var historyError: String?
    @Published private(set) var selected: ImportRecord?
    @Published private(set) var reading: ReadingResponse?
    @Published private(set) var sourceExcerpt: String?
    @Published private(set) var cachedSnapshot: PublicReadingSnapshot?
    @Published private(set) var isRevalidatingSource = false
    @Published private(set) var pendingShares: [PendingShare] = []
    private var importingOwnedShare = false
    private var refreshingShareAI = false
    @Published private(set) var shareNotice: String?
    @Published private(set) var usage: UsageResponse?
    @Published private(set) var consentMutationID: UUID?
    var isConsentUpdating: Bool { consentMutationID != nil }
    @Published private(set) var aiPolicy: AIPolicy?
    @Published private(set) var aiPolicyError: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isAuthenticating = false
    @Published private(set) var isOffline = false
    @Published var errorMessage: String?
    @Published var rangeIndex = 0
    @Published var selectedTab = 0
    @Published var showImport = false
    @Published var showQuestion = false
    @Published var questionTarget: Passage?
    @Published var questionConversation: Conversation?
    @Published private(set) var client: APIClient
    private let loginFlow = WebLogin()
    private let publicCache: PublicReadingCache
    private var gate = RequestGate()
    private var aiPolicyGate = RequestGate()
    private var readingTask: Task<Void, Never>?
    private var cacheExpiryTask: Task<Void, Never>?
    private var authTask: Task<Void, Never>?
    private var nextCursor: String?
    var selectedPassage: Passage? { guard let selected, selected.ranges.indices.contains(rangeIndex) else { return nil }; return selected.ranges[rangeIndex] }
    var endpointConfigured: Bool { client.baseURL.host?.hasSuffix(".invalid") == false }

    init(apiBaseURL: URL? = nil, apiClient: APIClient? = nil, readingCache: PublicReadingCache? = nil) {
        var exportCleanupFailed = false
        do { try ExportFiles.cleanup() } catch { exportCleanupFailed = true }
        let cacheRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        publicCache = readingCache ?? PublicReadingCache(directory: cacheRoot.appendingPathComponent("PublicReadingOverviews", isDirectory: true))
        let configured = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String ?? ""
        let url = apiBaseURL ?? URL(string: configured) ?? URL(string: "https://unconfigured.invalid")!
        client = apiClient ?? (try? APIClient(baseURL: url)) ?? (try! APIClient(baseURL: URL(string: "https://unconfigured.invalid")!))
        exportCleanupRequired = exportCleanupFailed
    }
    func retryExportCleanup() {
        do { try ExportFiles.cleanup(); exportCleanupRequired = false }
        catch { exportCleanupRequired = true; errorMessage = "書き出しの一時ファイルを削除できません。ロック解除後に再試行してください。" }
    }
    private func configureShareOwner(_ owner: String?) throws {
        do { try ShareInbox.setOwner(owner); shareNotice = nil }
        catch ShareInbox.InboxError.unavailable { shareNotice = "共有機能の保存領域を利用できません。章節・テキストの手動入力は使えます。署名時のApp Group設定を確認してください。" }
    }
    func restore() async {
        guard !isTransitioning, !isAuthenticating else { return }
        isTransitioning = true; defer { isTransitioning = false }
        let epoch = sessionEpoch
        restoreNeedsRetry = false
        localCleanupRequired = SessionVault.cleanupPending
        if localCleanupRequired { errorMessage = "前回の端末内データ削除が未完了です。設定から再試行してください。"; return }
        do {
            guard let session = try SessionVault.read() else {
                // A first launch can already have an unbound share from the extension.
                // No authenticated session is not an explicit logout: preserve that queue.
                try SessionVault.clear(); try PrivateHistoryStore.clear(); try configureShareOwner(nil)
                refreshInbox(); return
            }
            guard session.expiresAt > Date().timeIntervalSince1970 else {
                let previous = invalidateLocalSession(); await previous.setToken(nil); refreshInbox()
                errorMessage = localCleanupRequired ? "ログインの有効期限が切れ、端末内の消去が未完了です。ロック解除後に設定から再試行してください。" : "ログインの有効期限が切れたため、端末内の個人データと待機中の共有を消去しました。サーバーの履歴はログイン後に確認できます。"
                return
            }
            // Do not expose a signed-in UI until protected local storage is readable.
            let restoredHistory = try PrivateHistoryStore.read(owner: session.user.id)
            try configureShareOwner(session.user.id)
            let requestClient = client
            await requestClient.setToken(session.token)
            guard sessionEpoch == epoch else { await requestClient.setToken(nil); return }
            account = session.user; history = restoredHistory
            do {
                let response: AccountResponse = try await requestClient.get("/v1/me")
                guard sessionEpoch == epoch, response.user.id == account?.id else { return }
                account = response.user
                await refreshHistory()
            } catch { if sessionEpoch == epoch { handle(error) } }
            refreshInbox()
        } catch {
            guard sessionEpoch == epoch else { return }
            restoreNeedsRetry = true; errorMessage = "保存したログインまたは履歴を読めません。端末のロックを解除して再確認してください。新しいログインは確認が終わるまで開始しません。"
        }
    }
    func signIn() {
        guard endpointConfigured else { errorMessage = "接続先が未設定です。HTTPSサーバーを設定したビルドが必要です。"; return }
        guard !isAuthenticating, !isTransitioning, !localCleanupRequired, !restoreNeedsRetry else { return }
        sessionEpoch = UUID()
        isAuthenticating = true; errorMessage = nil
        let epoch = sessionEpoch; let requestClient = client
        authTask = Task {
            var installingSession = false
            defer { if sessionEpoch == epoch { isAuthenticating = false } }
            do {
                let response = try await loginFlow.login(client: requestClient)
                guard sessionEpoch == epoch, !Task.isCancelled else { return }
                guard response.tokenType == "Bearer", response.expiresAt > Date().timeIntervalSince1970 else { throw NetworkFailure.invalidResponse }
                installingSession = true
                try PrivateHistoryStore.clear()
                try configureShareOwner(response.user.id)
                try SessionVault.save(StoredSession(token: response.accessToken, expiresAt: response.expiresAt, user: response.user))
                await requestClient.setToken(response.accessToken)
                guard sessionEpoch == epoch else { await requestClient.setToken(nil); return }
                try Task.checkCancellation()
                account = response.user; history = []
                if let verified: AccountResponse = try? await requestClient.get("/v1/me"), sessionEpoch == epoch, verified.user.id == response.user.id {
                    account = verified.user
                    try SessionVault.save(StoredSession(token: response.accessToken, expiresAt: response.expiresAt, user: verified.user))
                }
                guard sessionEpoch == epoch else { return }
                await refreshHistory(); refreshInbox()
            } catch {
                guard sessionEpoch == epoch else { return }
                if installingSession {
                    let previous = invalidateLocalSession()
                    Task { await previous.setToken(nil) }
                }
                if error is CancellationError { return }
                if case SecurityError.cancelled = error { return }
                handle(error)
                if localCleanupRequired { errorMessage = "ログインを完了できず、端末内の消去も未完了です。ロック解除後に設定から消去を再試行してください。" }
            }
        }
    }
    func cancelSignIn() { authTask?.cancel(); loginFlow.cancel() }
    /// Synchronous local invalidation is shared by explicit logout and server 401.
    /// No later cleanup task may erase a newly authenticated account.
    private func invalidateLocalSession() -> APIClient {
        sessionEpoch = UUID(); isAuthenticating = false; restoreNeedsRetry = false; consentMutationID = nil; aiPolicyGate.invalidate()
        gate.invalidate(); cancelSignIn(); cancelReading(); showQuestion = false; showImport = false
        account = nil; selected = nil; reading = nil; sourceExcerpt = nil; cachedSnapshot = nil; history = []; historyLoading = false; historyChecked = false; historyError = nil; usage = nil; aiPolicy = nil; aiPolicyError = nil; pendingShares = []; nextCursor = nil
        performLocalCleanup()
        let previous = client
        client = try! APIClient(baseURL: previous.baseURL)
        return previous
    }
    private func performLocalCleanup() {
        SessionVault.cleanupPending = true
        var failed = false
        do { try SessionVault.clear() } catch { failed = true }
        do { try PrivateHistoryStore.clear() } catch { failed = true }
        do { try ShareInbox.clear(); shareNotice = nil } catch ShareInbox.InboxError.unavailable { shareNotice = "共有機能の保存領域を利用できません。章節・テキストは手動で入力できます。" } catch { failed = true }
        do { try PendingQuestionStore.clear() } catch { failed = true }
        do { try ComparisonStore.clear() } catch { failed = true }
        do { try ExportFiles.cleanup(); exportCleanupRequired = false } catch { failed = true; exportCleanupRequired = true }
        localCleanupRequired = failed; SessionVault.cleanupPending = failed
    }
    func signOut(revokeRemote: Bool = true) async {
        guard !isTransitioning else { return }
        isTransitioning = true; defer { isTransitioning = false }
        let previousClient = invalidateLocalSession()
        var revocationFailed = false
        if revokeRemote { do { try await previousClient.empty("/v1/logout") } catch { revocationFailed = true } }
        await previousClient.setToken(nil)
        if localCleanupRequired { errorMessage = "端末内データの削除を完了できませんでした。端末のロックを解除して再試行してください。" }
        else if revocationFailed { errorMessage = "端末からログアウトしました。サーバー側のセッション失効は通信できず未確認です。" }
    }
    func deletePrivateData(_ intent: DeletionIntent, typedConfirmation: String) async throws {
        guard intent.permits(ownerID: account?.id, epoch: sessionEpoch, typedConfirmation: typedConfirmation), !isTransitioning, !isAuthenticating else { throw NetworkFailure.cancelled }
        let requestClient = client
        isDeleting = true; isTransitioning = true
        cancelReading()
        defer { isDeleting = false; isTransitioning = false }
        do {
            let result: DeletionResult = try await requestClient.delete(intent.kind.path, body: intent.body)
            guard sessionEpoch == intent.sessionEpoch, account?.id == intent.ownerID else { throw NetworkFailure.cancelled }
            guard result.confirms(intent.kind) else { throw NetworkFailure.invalidResponse }
            isTransitioning = false
            await signOut(revokeRemote: intent.kind != .account)
            privacyNotice = intent.kind == .account ? "アカウントと現在のサーバーデータを削除しました。" : "読書データを削除しました。アカウントは残しています。この端末からはログアウトしました。"
            if localCleanupRequired { privacyNotice = (privacyNotice ?? "") + " 端末内の削除が未完了です。設定から再試行してください。" }
            privacyNotice = (privacyNotice ?? "") + " 事業者バックアップの消去時期は未確定です。"
        } catch NetworkFailure.server(status: 403, code: "reauthentication_required") {
            throw NetworkFailure.server(status: 403, code: "reauthentication_required")
        } catch {
            guard sessionEpoch == intent.sessionEpoch else { throw error }
            isTransitioning = false
            await signOut()
            privacyNotice = "サーバーでの削除完了を確認できませんでした。安全のため、この端末からログアウトしました。再ログインして状態を確認してください。削除を自動で繰り返してはいません。"
            throw error
        }
    }
    func retryLocalCleanup() {
        performLocalCleanup()
        errorMessage = localCleanupRequired ? "端末内データを消去できません。ロック解除後に再試行してください。" : "この端末のアカウント情報と待機データを消去しました。"
    }
    func refreshHistory(loadMore: Bool = false) async {
        guard let owner = account?.id, !isDeleting, !historyLoading else { return }
        let epoch = sessionEpoch
        historyLoading = true; historyError = nil
        defer { if sessionEpoch == epoch { historyLoading = false } }
        do {
            let query = loadMore ? nextCursor.map { [URLQueryItem(name: "before", value: $0)] } ?? [] : []
            if loadMore && nextCursor == nil { return }
            let page: ImportPage = try await client.get("/v1/imports", query: query)
            guard sessionEpoch == epoch, owner == account?.id, !isDeleting else { return }
            history = loadMore ? history + page.items.filter { item in !history.contains(where: { $0.id == item.id }) } : page.items
            nextCursor = page.nextCursor; isOffline = false; historyChecked = true
            try PrivateHistoryStore.save(history, owner: owner)
        } catch { if sessionEpoch == epoch, owner == account?.id, !isDeleting { historyError = (error as? NetworkFailure)?.userMessage ?? "履歴を確認できませんでした。"; handle(error) } }
    }
    var canLoadMore: Bool { nextCursor != nil }
    func select(_ item: ImportRecord, range: Int = 0) {
        guard !isDeleting, item.ranges.indices.contains(range) else { return }
        if selected?.id != item.id { sourceExcerpt = nil }
        cancelReading(); selected = item; rangeIndex = range; reading = nil; selectedTab = 0; questionTarget = nil; questionConversation = nil
        loadReading()
    }
    func changeRange(_ index: Int) { guard let selected else { return }; select(selected, range: index) }
    private func displayCached(_ snapshot: PublicReadingSnapshot?, generation: UUID) {
        cacheExpiryTask?.cancel()
        cachedSnapshot = snapshot; reading = snapshot?.readingResponse()
        guard let snapshot else { return }
        cacheExpiryTask = Task {
            let delay = max(0, snapshot.expiresAt.timeIntervalSinceNow)
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard gate.accepts(generation), cachedSnapshot?.expiresAt == snapshot.expiresAt else { return }
            cachedSnapshot = nil; reading = nil
            errorMessage = "保存した資料の有効期限が切れました。接続して更新してください。"
        }
    }
    func loadReading() {
        guard !isDeleting, let item = selected, let passage = selectedPassage, account != nil else { return }
        readingTask?.cancel(); cacheExpiryTask?.cancel()
        let generation = gate.invalidate(); let index = rangeIndex; let requestClient = client
        let key = ReadingCacheKey(passage: passage, translation: item.translation)
        isLoading = true; isRevalidatingSource = true; errorMessage = nil; reading = nil; cachedSnapshot = nil
        readingTask = Task {
            var validationAttempt: UUID?
            var receivedManifest = false
            defer { if gate.accepts(generation) { isLoading = false; isRevalidatingSource = false } }
            do {
                do {
                    let snapshot = try await publicCache.load(key)
                    guard gate.accepts(generation) else { return }
                    displayCached(snapshot, generation: generation)
                    if snapshot != nil { isLoading = false }
                } catch {
                    guard gate.accepts(generation) else { return }
                    errorMessage = "保存した資料を読めません。オンラインで確認しています。"
                }
                validationAttempt = try await publicCache.beginValidation()
                guard gate.accepts(generation) else {
                    if let validationAttempt { await publicCache.validationFailedBeforeManifest(validationAttempt) }
                    return
                }
                let manifest: ContentManifest = try await requestClient.get("/v1/content-manifest")
                receivedManifest = true
                if let validationAttempt { await publicCache.manifestReceived(validationAttempt) }
                guard gate.accepts(generation) else { return }
                guard manifest.isFresh() else { throw NetworkFailure.invalidResponse }
                if let snapshot = cachedSnapshot, !snapshot.isAllowed(by: manifest) { displayCached(nil, generation: generation) }
                do {
                    try await publicCache.reconcile(manifest, attempt: validationAttempt)
                    guard gate.accepts(generation) else { return }
                    let refreshed = try await publicCache.load(key)
                    guard gate.accepts(generation) else { return }
                    displayCached(refreshed, generation: generation)
                } catch {
                    guard gate.accepts(generation) else { return }
                    displayCached(nil, generation: generation)
                    errorMessage = "端末内の資料キャッシュを更新できませんでした。接続して再確認するまで保存資料は表示しません。"
                }
                let result: ReadingResponse = try await requestClient.get("/v1/imports/\(item.id)/reading", query: [URLQueryItem(name: "rangeIndex", value: String(index)), URLQueryItem(name: "spoilers", value: "false")])
                guard gate.accepts(generation), selected?.id == item.id, rangeIndex == index else { return }
                guard result.passage == passage, result.translation == item.translation, !result.spoilerAllowed,
                      result.overview.contentKind == nil || ["curated-reference", "literal-primary-text"].contains(result.overview.contentKind ?? "") else { throw NetworkFailure.invalidResponse }
                do { try await publicCache.store(result) }
                catch OfflineCacheError.ineligible { try? await publicCache.remove(key) }
                catch {
                    guard gate.accepts(generation) else { return }
                    errorMessage = "資料は読み込めましたが、この端末へのオフライン保存はできませんでした。"
                }
                guard gate.accepts(generation) else { return }
                cacheExpiryTask?.cancel(); reading = result; cachedSnapshot = nil; isOffline = false
            } catch {
                if let validationAttempt, !receivedManifest { await publicCache.validationFailedBeforeManifest(validationAttempt) }
                guard gate.accepts(generation) else { return }
                if case NetworkFailure.server(_, let code) = error, code == "source_policy_changed" {
                    try? await publicCache.invalidateAfterPolicyChange(key)
                    guard gate.accepts(generation) else { return }
                    displayCached(nil, generation: generation)
                }
                if let snapshot = cachedSnapshot, !snapshot.isUsable() { displayCached(nil, generation: generation) }
                handle(error)
            }
        }
    }
    func cancelReading() { if cachedSnapshot != nil { cachedSnapshot = nil; reading = nil }; readingTask?.cancel(); readingTask = nil; cacheExpiryTask?.cancel(); cacheExpiryTask = nil; gate.invalidate(); isLoading = false; isRevalidatingSource = false }
    func enteredForeground() {
        Task { await refreshShareAI() }
        refreshInbox()
        if account != nil, selected != nil, !isTransitioning, !isAuthenticating { loadReading() }
    }
    func ask(target: Passage? = nil, conversation: Conversation? = nil) { questionTarget = target ?? selectedPassage; questionConversation = target == nil ? (conversation ?? questionConversation) : conversation; showQuestion = true }
    func refreshInbox() {
        do { pendingShares = try ShareInbox.pending().filter { $0.ownerID == nil || $0.ownerID == account?.id }; shareNotice = nil }
        catch ShareInbox.InboxError.unavailable { shareNotice = "共有機能の保存領域を利用できません。章節・テキストの手動入力は使えます。署名時のApp Group設定を確認してください。" }
        catch { shareNotice = "共有内容を読み出せません。端末のロックを解除して再確認してください。読み出せなかった内容は消去していません。" }
        // Only a single share already bound to this same account is automatic.
        // Anonymous shares and shares across accounts still require explicit confirmation.
        guard !importingOwnedShare, !isTransitioning, !isDeleting, !showImport,
              let owner = account?.id, pendingShares.count == 1, let share = pendingShares.first,
              !share.requiresAccountConfirmation(currentOwner: owner),
              let parsed = try? SharedImportParser.parse(share.text), !parsed.ranges.isEmpty,
              parsed.warnings.isEmpty,
              let key = try? ShareInbox.submissionKey(share: share, owner: owner, ranges: parsed.ranges, translation: parsed.translation) else { return }
        importingOwnedShare = true
        Task {
            defer { importingOwnedShare = false }
            do { try await saveImport(ImportInput(idempotencyKey: key, ranges: parsed.ranges, translation: parsed.translation), share: share, transientExcerpt: share.text) }
            catch { shareNotice = "共有した箇所を開けませんでした。共有内容は残っています。もう一度確認してください。" }
        }
    }
    func removeShare(_ share: PendingShare) throws { try ShareInbox.remove(share.id); refreshInbox() }
    func saveImport(_ input: ImportInput, share: PendingShare?, transientExcerpt: String) async throws {
        guard let owner = account?.id, !isTransitioning else { throw NetworkFailure.unauthenticated }
        let epoch = sessionEpoch
        let result: ImportRecord = try await client.post("/v1/imports", body: input)
        guard sessionEpoch == epoch, account?.id == owner, !isTransitioning else { throw NetworkFailure.unauthenticated }
        history.removeAll { $0.id == result.id }; history.insert(result, at: 0)
        try PrivateHistoryStore.save(history, owner: owner)
        if let share { try removeShare(share) }
        select(result); sourceExcerpt = transientExcerpt.isEmpty ? nil : transientExcerpt; showImport = false
    }
    func loadUsage() async {
        guard let owner = account?.id, !isDeleting else { return }
        let epoch = sessionEpoch
        do { let value: UsageResponse = try await client.get("/v1/usage"); guard sessionEpoch == epoch, owner == account?.id, !isDeleting else { return }; usage = value }
        catch { if sessionEpoch == epoch, owner == account?.id { handle(error) } }
    }
    func loadAIPolicy() async {
        guard !isConsentUpdating else { return }
        guard let owner = account?.id, !isTransitioning else { return }
        let epoch = sessionEpoch; let requestClient = client; let generation = aiPolicyGate.invalidate()
        aiPolicy = nil; aiPolicyError = nil
        do {
            let value: AIPolicy = try await requestClient.get("/v1/me/ai-policy")
            guard sessionEpoch == epoch, account?.id == owner, !isTransitioning, !isConsentUpdating, aiPolicyGate.accepts(generation) else { return }
            aiPolicy = value
        } catch { if sessionEpoch == epoch, account?.id == owner, aiPolicyGate.accepts(generation) { aiPolicyError = "AIの回答方法と同意状況を確認できません。再確認してください。" } }
    }
    func consent(_ enabled: Bool, expectedEpoch: UUID) async throws {
        guard sessionEpoch == expectedEpoch, account != nil, !isTransitioning, !isConsentUpdating else { throw NetworkFailure.cancelled }
        let mutation = UUID(); consentMutationID = mutation; aiPolicy = nil; aiPolicyGate.invalidate()
        defer { if consentMutationID == mutation { consentMutationID = nil } }
        let requestClient = client
        struct Consent: Codable, Sendable { let workersAi: Bool }
        let response: Consent = try await requestClient.post("/v1/me/consents", body: Consent(workersAi: enabled))
        guard sessionEpoch == expectedEpoch, consentMutationID == mutation, response.workersAi == enabled else { throw NetworkFailure.cancelled }
        consentMutationID = nil
        await loadAIPolicy()
    }
    func consentGrounded(_ enabled: Bool, intent: GroundedConsentIntent) async throws {
        guard intent.permits(ownerID: account?.id, epoch: sessionEpoch, currentPolicy: aiPolicy), !isTransitioning, !isConsentUpdating else { throw NetworkFailure.cancelled }
        let mutation = UUID(); consentMutationID = mutation; aiPolicy = nil; aiPolicyGate.invalidate()
        defer { if consentMutationID == mutation { consentMutationID = nil } }
        let requestClient = client
        var fields: [String: JSONValue] = ["groundedGeneration": .object(["accepted": .bool(enabled), "policyVersion": .string(intent.policy.groundedPolicyVersion)])]
        if enabled { fields["workersAi"] = .bool(true) }
        let body = JSONValue.object(fields)
        let response: JSONValue = try await requestClient.post("/v1/me/consents", body: body)
        guard sessionEpoch == intent.sessionEpoch, account?.id == intent.ownerID, consentMutationID == mutation, response["workersAi"].bool != nil, (!enabled || response["workersAi"].bool == true) else { throw NetworkFailure.cancelled }
        consentMutationID = nil
        await loadAIPolicy()
    }
    func enableShareAI(expectedEpoch: UUID) async throws {
        guard aiPolicy?.shareAiEnabled == true, sessionEpoch == expectedEpoch, let owner = account?.id else { throw NetworkFailure.cancelled }
        let value: ShareAIAccess = try await client.post("/v1/me/share-access", body: ["enabled": true])
        guard sessionEpoch == expectedEpoch, account?.id == owner, value.isValid(owner: owner) else { throw NetworkFailure.cancelled }
        try ShareInbox.saveAIAccess(value)
        await loadAIPolicy()
    }
    func refreshShareAI() async {
        guard account != nil, !isTransitioning, !refreshingShareAI else { return }
        refreshingShareAI = true; defer { refreshingShareAI = false }
        let epoch = sessionEpoch
        await loadAIPolicy()
        guard sessionEpoch == epoch else { return }
        guard let policy = aiPolicy else { return }
        if policy.shareAiEnabled != true || policy.shareAiConsent != true { try? ShareInbox.clearAIAccess(); return }
        if let existing = try? ShareInbox.aiAccess(), existing.expiresAt > Date().addingTimeInterval(3600).timeIntervalSince1970 { return }
        do { try await enableShareAI(expectedEpoch: epoch) } catch { try? ShareInbox.clearAIAccess() }
    }
    func handle(_ error: Error) {
        // The confirmed destructive transition owns its outcome and full cleanup.
        // A concurrent GET 401 must not rotate the epoch before DELETE acknowledges.
        guard !isDeleting else { return }
        if let failure = error as? NetworkFailure {
            isOffline = failure == .offline
            if failure == .cancelled { return }
            errorMessage = failure.userMessage
            if failure == .unauthenticated {
                let expiredClient = invalidateLocalSession()
                Task { await expiredClient.setToken(nil) }
                if localCleanupRequired { errorMessage = "ログインが失効しました。端末内の消去が未完了です。ロック解除後に設定から再試行してください。" }
                else { errorMessage = "ログインが失効したため、端末内の個人データと待機中の共有を消去しました。サーバーの履歴はログイン後に確認できます。" }
            }
        } else { errorMessage = "処理を完了できませんでした。端末のロックと接続を確認して再試行してください。" }
    }
}

#if DEBUG
extension AppStore {
    func configureSimulatorQA(client: APIClient) {
        guard ProcessInfo.processInfo.arguments.contains("--simulator-qa") else { return }
        self.client = client
        account = try! JSONDecoder().decode(Account.self, from: Data(#"{"id":"00000000-0000-4000-8000-000000000123","display_name":"Fixture reader","role":"reader","canDebug":false}"#.utf8))
    }
}
#endif
