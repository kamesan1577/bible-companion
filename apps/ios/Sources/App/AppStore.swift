import SwiftUI
import CompanionCore

@MainActor final class AppStore: ObservableObject {
    @Published private(set) var sessionEpoch = UUID()
    @Published private(set) var restoreNeedsRetry = false
    @Published private(set) var isTransitioning = false
    @Published private(set) var localCleanupRequired = false
    @Published private(set) var exportCleanupRequired = false
    @Published private(set) var isDeleting = false
    @Published var showAISetup = false
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
    private var shareAccessRevision = UUID()
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
    private var standardModels: [String: QuestionModel] = [:]
    func standardModel(item: ImportRecord, passage: Passage, sourceVersion: String) -> QuestionModel? {
        guard let owner = account?.id else { return nil }
        let key = "\(sessionEpoch):\(item.id):\(rangeIndex):\(passage.label):\(sourceVersion)"
        if let model = standardModels[key] { return model }
        if standardModels.count >= 16 { standardModels.values.forEach { $0.close() }; standardModels.removeAll() }
        let model = QuestionModel(ownerID: owner, client: client, item: item, rangeIndex: rangeIndex)
        standardModels[key] = model; return model
    }
    private let loginFlow = WebLogin()
    private let publicCache: PublicReadingCache
    private var gate = RequestGate()
    private var aiPolicyGate = RequestGate()
    private struct ShareIssuance { let id: UUID; let owner: String; let epoch: UUID; let fetch: Task<ShareAIAccess, Error> }
    private var shareIssuance: ShareIssuance?
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
        catch ShareInbox.InboxError.unavailable { shareNotice = "共有した箇所をこの端末に保存できません。アプリを更新してもう一度共有するか、書名・章・節を入力して開いてください。" }
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
                errorMessage = localCleanupRequired ? "ログインの有効期限が切れ、端末内の消去が未完了です。ロック解除後に設定から再試行してください。" : "ログインの有効期限が切れたため、端末内の個人データと待機中の共有を消去しました。アカウントに保存した履歴は、ログインし直すと確認できます。"
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
        guard endpointConfigured else { errorMessage = "アプリの接続設定に問題があります。最新版へ更新して、もう一度お試しください。"; return }
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
        standardModels.values.forEach { $0.close() }; standardModels.removeAll()
        sessionEpoch = UUID(); shareAccessRevision = UUID(); isAuthenticating = false; restoreNeedsRetry = false; consentMutationID = nil; aiPolicyGate.invalidate()
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
        do { try ShareInbox.clear(); shareNotice = nil } catch ShareInbox.InboxError.unavailable { shareNotice = "共有した箇所をこの端末に保存できません。書名・章・節を入力して開くこともできます。" } catch { failed = true }
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
        else if revocationFailed { errorMessage = "この端末からはログアウトしました。通信できなかったため、サービス側のログイン停止を確認できていません。接続が戻ったら、ログイン状況を確認してください。" }
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
            privacyNotice = intent.kind == .account ? "アカウントとサービス側の現在のデータを削除しました。" : "読書データを削除しました。アカウントは残しています。この端末からはログアウトしました。"
            if localCleanupRequired { privacyNotice = (privacyNotice ?? "") + " 端末内の削除が未完了です。設定から再試行してください。" }
            privacyNotice = (privacyNotice ?? "") + " 事業者バックアップの消去時期は未確定です。"
        } catch NetworkFailure.server(status: 403, code: "reauthentication_required") {
            throw NetworkFailure.server(status: 403, code: "reauthentication_required")
        } catch {
            guard sessionEpoch == intent.sessionEpoch else { throw error }
            isTransitioning = false
            await signOut()
            privacyNotice = "サービス側のデータが削除されたか確認できませんでした。この端末からはログアウトしています。ログインし直して記録が残っているか確認してください。削除を自動で繰り返してはいません。"
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
            errorMessage = "この参考説明は読み込み直す必要があります。通信を確かめてから更新してください。"
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
                    errorMessage = "参考説明を端末に保存できませんでした。通信を確かめて読み込み直してください。"
                }
                let result: ReadingResponse = try await requestClient.get("/v1/imports/\(item.id)/reading", query: [URLQueryItem(name: "rangeIndex", value: String(index)), URLQueryItem(name: "spoilers", value: "false")])
                guard gate.accepts(generation), selected?.id == item.id, rangeIndex == index else { return }
                guard result.passage == passage, result.translation == item.translation, !result.spoilerAllowed,
                      result.overview.contentKind == nil || ["curated-reference", "literal-primary-text"].contains(result.overview.contentKind ?? "") else { throw NetworkFailure.invalidResponse }
                do { try await publicCache.store(result) }
                catch OfflineCacheError.ineligible { try? await publicCache.remove(key) }
                catch {
                    guard gate.accepts(generation) else { return }
                    errorMessage = "参考説明は開けましたが、通信せずに読むための保存はできませんでした。"
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
        catch ShareInbox.InboxError.unavailable { shareNotice = "共有した箇所をこの端末に保存できません。アプリを更新してもう一度共有するか、書名・章・節を入力して開いてください。" }
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
        } catch { if sessionEpoch == epoch, account?.id == owner, aiPolicyGate.accepts(generation) { aiPolicyError = "AIを使えるか確認できませんでした。通信を確かめて、もう一度お試しください。" } }
    }
    func consent(_ enabled: Bool, expectedEpoch: UUID) async throws {
        guard sessionEpoch == expectedEpoch, account != nil, !isTransitioning, !isConsentUpdating else { throw NetworkFailure.cancelled }
        let mutation = UUID(); consentMutationID = mutation; shareAccessRevision = UUID(); aiPolicy = nil; aiPolicyGate.invalidate()
        defer { if consentMutationID == mutation { consentMutationID = nil } }
        let requestClient = client
        struct Consent: Codable, Sendable { let workersAi: Bool }
        let response: Consent = try await requestClient.post("/v1/me/consents", body: Consent(workersAi: enabled))
        guard sessionEpoch == expectedEpoch, consentMutationID == mutation, response.workersAi == enabled else { throw NetworkFailure.cancelled }
        consentMutationID = nil
        if !enabled { try? ShareInbox.clearAIAccess() }
        await loadAIPolicy()
    }
    func consentGrounded(_ enabled: Bool, intent: GroundedConsentIntent) async throws {
        guard intent.permits(ownerID: account?.id, epoch: sessionEpoch, currentPolicy: aiPolicy), !isTransitioning, !isConsentUpdating else { throw NetworkFailure.cancelled }
        let mutation = UUID(); consentMutationID = mutation; shareAccessRevision = UUID(); aiPolicy = nil; aiPolicyGate.invalidate()
        defer { if consentMutationID == mutation { consentMutationID = nil } }
        let requestClient = client
        var fields: [String: JSONValue] = ["groundedGeneration": .object(["accepted": .bool(enabled), "policyVersion": .string(intent.policy.groundedPolicyVersion)])]
        if enabled { fields["workersAi"] = .bool(true) }
        let body = JSONValue.object(fields)
        let response: JSONValue = try await requestClient.post("/v1/me/consents", body: body)
        guard sessionEpoch == intent.sessionEpoch, account?.id == intent.ownerID, consentMutationID == mutation, response["workersAi"].bool != nil, (!enabled || response["workersAi"].bool == true) else { throw NetworkFailure.cancelled }
        consentMutationID = nil
        if !enabled { try? ShareInbox.clearAIAccess() }
        await loadAIPolicy()
    }
    func enableShareAI(expectedEpoch: UUID) async throws {
        guard !isConsentUpdating, sessionEpoch == expectedEpoch, let owner = account?.id else { throw NetworkFailure.cancelled }
        let issuance: ShareIssuance
        if let pending = shareIssuance, pending.owner == owner, pending.epoch == expectedEpoch, shareAccessRevision == pending.id {
            issuance = pending
        } else {
            guard aiPolicy?.shareAiEnabled == true, aiPolicy?.permits(.groundedGeneration) == true else { throw NetworkFailure.cancelled }
            do { try ShareInbox.setOwner(owner) }
            catch ShareInbox.InboxError.unavailable { throw ShareAIAccessReadError.appGroupUnavailable }
            let revision = UUID(); shareAccessRevision = revision
            let requestClient = client; let mayRenew = aiPolicy?.shareAiConsent == true
            let fetch = Task<ShareAIAccess, Error> {
                if mayRenew, let old = try? ShareInbox.renewableAIAccess(expectedOwner: owner), old.canRenew() {
                    return try await ShareInbox.currentAIAccess(baseURL: requestClient.baseURL, expectedOwner: owner)
                }
                return try await requestClient.post("/v1/me/share-access", body: ["enabled": true])
            }
            issuance = ShareIssuance(id: revision, owner: owner, epoch: expectedEpoch, fetch: fetch)
            shareIssuance = issuance
        }
        defer { if shareIssuance?.id == issuance.id { shareIssuance = nil } }
        let value = try await issuance.fetch.value
        guard sessionEpoch == expectedEpoch, account?.id == owner, shareAccessRevision == issuance.id,
              !isConsentUpdating, value.isValid(owner: owner) else { throw NetworkFailure.cancelled }
        if let policy = aiPolicy, policy.shareAiEnabled != true || !policy.permits(.groundedGeneration) { throw NetworkFailure.cancelled }
        try Task.checkCancellation()
        try ShareInbox.saveAIAccess(value)
        _ = try ShareInbox.verifiedAIAccess(expectedOwner: owner)
        await loadAIPolicy()
    }
    func refreshShareAI() async {
        guard account != nil, !isTransitioning, !refreshingShareAI, !isConsentUpdating else { return }
        refreshingShareAI = true; defer { refreshingShareAI = false }
        let epoch = sessionEpoch; let revision = shareAccessRevision
        await loadAIPolicy()
        guard sessionEpoch == epoch, shareAccessRevision == revision, !isConsentUpdating else { return }
        guard let policy = aiPolicy else { return }
        if policy.shareAiEnabled != true || policy.shareAiConsent != true { try? ShareInbox.clearAIAccess(); return }
        if let existing = try? ShareInbox.verifiedAIAccess(expectedOwner: account?.id), existing.expiresAt > Date().addingTimeInterval(3600).timeIntervalSince1970 { return }
        do { try await enableShareAI(expectedEpoch: epoch) }
        catch NetworkFailure.cancelled { return }
        catch { shareNotice = SharePreparationFailure.message(for: error) }
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
                else { errorMessage = "ログインが失効したため、端末内の個人データと待機中の共有を消去しました。アカウントに保存した履歴は、ログインし直すと確認できます。" }
            }
        } else { errorMessage = "処理を完了できませんでした。端末のロックと接続を確認して再試行してください。" }
    }
}

#if DEBUG
extension AppStore {
    func configureSimulatorQA(client: APIClient) {
        guard ProcessInfo.processInfo.arguments.contains("--simulator-qa") else { return }
        self.client = client
        selected = try! JSONDecoder().decode(ImportRecord.self, from: Data(#"{"id":"00000000-0000-4000-8000-000000000123","idempotencyKey":"00000000-0000-4000-8000-000000000123","ranges":[{"book":"ACT","start":{"chapter":23,"verse":1},"end":{"chapter":23,"verse":1}}],"translation":"JCB","createdAt":0}"#.utf8))
        reading = try! JSONDecoder().decode(ReadingResponse.self, from: Data(#"{"passage":{"book":"ACT","start":{"chapter":23,"verse":1},"end":{"chapter":23,"verse":1}},"translation":"JCB","spoilerAllowed":false,"sourceVersion":"fixture-v1","overview":{"contentKind":"curated-reference","text":"描画確認用の資料です。","citations":[],"mode":"source-only","modelInvoked":false},"materialNotice":"固定データ","cache":"fixture","people":[],"places":[],"artworks":[]}"#.utf8))
        sourceExcerpt = "共有元の日本語本文・表示確認用。Original Case Remains.\n" + String(repeating: "長い共有本文を折り畳んで保持します。", count: 20)
        account = try! JSONDecoder().decode(Account.self, from: Data(#"{"id":"00000000-0000-4000-8000-000000000123","display_name":"Fixture reader","role":"reader","canDebug":false}"#.utf8))
        if ProcessInfo.processInfo.arguments.contains("--qa-screen=entity-pilot-reading") || ProcessInfo.processInfo.arguments.contains("--qa-screen=entity-ui-baseline") {
            selected = try! JSONDecoder().decode(ImportRecord.self, from: Data(#"{"id":"00000000-0000-4000-8000-000000000123","idempotencyKey":"00000000-0000-4000-8000-000000000123","ranges":[{"book":"ACT","start":{"chapter":18,"verse":24},"end":{"chapter":19,"verse":7}}],"translation":"JCB","createdAt":0}"#.utf8))
            reading = try! JSONDecoder().decode(ReadingResponse.self, from: Data(#"{"passage":{"book":"ACT","start":{"chapter":18,"verse":24},"end":{"chapter":19,"verse":7}},"translation":"JCB","spoilerAllowed":false,"sourceVersion":"source-cards-018-fixture","overview":{"contentKind":"curated-reference","text":"公開ソースに収録された資料カードの表示確認。","citations":[],"mode":"source-only","modelInvoked":false},"materialNotice":"公開ソースの固定資料","cache":"fixture","people":[{"id":"person-apollos-act18-introduction","kind":"person","title":"アポロ：エペソに来る","summary":"アレクサンドリア出身のユダヤ人。雄弁で、聖書に詳しい人物としてエペソに来ます。","passages":[{"book":"ACT","start":{"chapter":18,"verse":24},"end":{"chapter":18,"verse":24}}],"spoilerEnd":{"book":"ACT","chapter":18,"verse":24},"version":"primary-reviewed-2026-10-13.1","reviewed":true,"rightsStatus":"approved","relationship":"direct","provenance":[{"id":"web-act-18-24","title":"World English Bible · Acts 18:24","url":"https://ebible.org/engwebp/ACT18.htm#V24","publisher":"eBible.org","checkedAt":"2026-10-13","license":"public-domain"}],"details":{"identityNote":"このカードは、示した使徒言行録の場面だけを説明します。後の経歴は含めていません。"}},{"id":"person-apollos-act18-learning","kind":"person","title":"アポロ：教えを深める","summary":"熱心にイエスについて教えていましたが、知っていた洗礼はヨハネの洗礼でした。話を聞いたプリスキラとアキラが彼を招き、神の道をより正確に説明します。","passages":[{"book":"ACT","start":{"chapter":18,"verse":25},"end":{"chapter":18,"verse":26}}],"spoilerEnd":{"book":"ACT","chapter":18,"verse":26},"version":"primary-reviewed-2026-10-13.1","reviewed":true,"rightsStatus":"approved","relationship":"direct","provenance":[{"id":"web-act-18-25","title":"World English Bible · Acts 18:25","url":"https://ebible.org/engwebp/ACT18.htm#V25","publisher":"eBible.org","checkedAt":"2026-10-13","license":"public-domain"}],"details":{"identityNote":"本文は、プリスキラとアキラが補った説明の詳しい内容を記していません。"}},{"id":"person-apollos-act18-achaia","kind":"person","title":"アポロ：アカイアへ","summary":"アカイアへ渡る際、仲間たちが現地の弟子たちに受け入れを求める手紙を書きます。到着後は信じた人々を助け、聖書からイエスがキリストであると示します。","passages":[{"book":"ACT","start":{"chapter":18,"verse":27},"end":{"chapter":18,"verse":28}}],"spoilerEnd":{"book":"ACT","chapter":18,"verse":28},"version":"primary-reviewed-2026-10-13.1","reviewed":true,"rightsStatus":"approved","relationship":"direct","provenance":[{"id":"web-act-18-27","title":"World English Bible · Acts 18:27","url":"https://ebible.org/engwebp/ACT18.htm#V27","publisher":"eBible.org","checkedAt":"2026-10-13","license":"public-domain"}],"details":{"identityNote":"このカードは、示した使徒言行録の場面だけを説明します。後の経歴は含めていません。"}},{"id":"person-paul-act19-ephesus","kind":"person","title":"パウロ：エペソで弟子たちに会う","summary":"アポロがコリントにいたころ、パウロは内陸を通ってエペソに来て、何人かの弟子たちに会います。","passages":[{"book":"ACT","start":{"chapter":19,"verse":1},"end":{"chapter":19,"verse":1}}],"spoilerEnd":{"book":"ACT","chapter":19,"verse":1},"version":"primary-reviewed-2026-10-13.1","reviewed":true,"rightsStatus":"approved","relationship":"direct","provenance":[{"id":"web-act-19-1","title":"World English Bible · Acts 19:1","url":"https://ebible.org/engwebp/ACT19.htm#V1","publisher":"eBible.org","checkedAt":"2026-10-13","license":"public-domain"}],"details":{"identityNote":"このカードは、示した使徒言行録の場面だけを説明します。後の経歴は含めていません。"}},{"id":"person-disciples-act19","kind":"person","title":"エペソの約十二人","summary":"パウロにヨハネの洗礼を受けたと答えた人々です。話を聞いて主イエスの名による洗礼を受け、パウロが手を置くと聖霊が臨み、異なる言葉を語り、預言したと記されています。人数は約十二人です。","passages":[{"book":"ACT","start":{"chapter":19,"verse":2},"end":{"chapter":19,"verse":7}}],"spoilerEnd":{"book":"ACT","chapter":19,"verse":7},"version":"primary-reviewed-2026-10-13.1","reviewed":true,"rightsStatus":"approved","relationship":"direct","provenance":[{"id":"web-act-19-2","title":"World English Bible · Acts 19:2","url":"https://ebible.org/engwebp/ACT19.htm#V2","publisher":"eBible.org","checkedAt":"2026-10-13","license":"public-domain"}],"details":{"identityNote":"個々の名前は書かれていません。十二使徒やアポロの弟子たちと同一視する根拠は、この箇所にはありません。"}}],"places":[{"id":"place-corinth","kind":"place","title":"コリント","summary":"ギリシャ本土とペロポネソス半島をつなぐ陸路の要所にある古代都市です。使徒18章の冒頭では、パウロがアテネから到着します。","passages":[{"book":"ACT","start":{"chapter":18,"verse":1},"end":{"chapter":18,"verse":18}},{"book":"ACT","start":{"chapter":19,"verse":1},"end":{"chapter":19,"verse":1}}],"spoilerEnd":{"book":"ACT","chapter":18,"verse":1},"version":"primary-reviewed-2026-10-13.2","reviewed":true,"rightsStatus":"approved","relationship":"direct","provenance":[{"id":"web-act-18-1","title":"World English Bible · Acts 18:1","url":"https://ebible.org/engwebp/ACT18.htm#V1","publisher":"eBible.org","checkedAt":"2026-10-13","license":"public-domain"},{"id":"ascsa-corinth","title":"Corinth","url":"https://www.ascsa.edu.gr/publications/browse-by-series/corinth","publisher":"American School of Classical Studies at Athens","checkedAt":"2026-10-13","license":"citation-only"},{"id":"pleiades-570182","title":"Pleiades · Corinthus/Korinthos","url":"https://pleiades.stoa.org/places/570182","publisher":"Pleiades / Institute for the Study of the Ancient World, New York University","checkedAt":"2026-10-13","license":"cc-by-3.0","licenseUrl":"https://creativecommons.org/licenses/by/3.0/","attribution":"© G. Reger, J. McK. Camp II, Catherine Bouras, Brady Kiesling, R. Talbert, Chris de Lisle, Rosemary Selth, Jeffrey Becker, Sean Gillies, Tom Elliott, DARMC, James Herbst, R. Scott Smith, Greta Hawes. Pleiades, CC BY 3.0. 座標は原資料の代表点を転記。日本語説明は独自作成。"},{"id":"osm-way-224709706","title":"OpenStreetMap · ancient-site geometry","url":"https://www.openstreetmap.org/way/224709706","publisher":"OpenStreetMap contributors","checkedAt":"2026-10-13","license":"odbl-1.0","licenseUrl":"https://opendatacommons.org/licenses/odbl/1-0/","attribution":"© OpenStreetMap contributors. ODbL 1.0. Pleiades が用いた上流の位置資料。"}],"details":{"coordinates":{"latitude":37.90564164345828,"longitude":22.878614390874485,"certainty":"approximate","sourceId":"pleiades-570182","explanation":"古代コリント遺跡の代表点です。現代の市中心部や、本文の出来事の正確な場所を示すものではありません。背景の道路・海岸線は現代のものです。"},"identificationCertainty":"confirmed","modernName":"古代コリント遺跡（ギリシャ）"}},{"id":"place-ephesus","kind":"place","title":"エペソ","summary":"現在のトルコ西部にある古代都市です。古代には海に面していましたが、川が運ぶ土砂によって港や水路の位置が移り変わりました。現在の遺跡の海岸からの距離を、そのまま当時の風景に当てはめることはできません。","passages":[{"book":"ACT","start":{"chapter":18,"verse":19},"end":{"chapter":18,"verse":21}},{"book":"ACT","start":{"chapter":18,"verse":24},"end":{"chapter":18,"verse":26}},{"book":"ACT","start":{"chapter":19,"verse":1},"end":{"chapter":19,"verse":7}}],"spoilerEnd":{"book":"ACT","chapter":18,"verse":19},"version":"primary-reviewed-2026-10-13.2","reviewed":true,"rightsStatus":"approved","relationship":"direct","provenance":[{"id":"oeai-ephesos-2025","title":"130 years of the Austrian excavation at Ephesos","url":"https://www.oeaw.ac.at/en/oeai/media/news-archive/news-detail/130-jahre-oesterreichische-grabung-ephesos","publisher":"Austrian Archaeological Institute, Austrian Academy of Sciences","checkedAt":"2026-10-13","license":"citation-only"},{"id":"web-act-18-19","title":"World English Bible · Acts 18:19","url":"https://ebible.org/engwebp/ACT18.htm#V19","publisher":"eBible.org","checkedAt":"2026-10-13","license":"public-domain"},{"id":"pleiades-599612","title":"Pleiades · Ephesus/Arsinoe(ia)","url":"https://pleiades.stoa.org/places/599612","publisher":"Pleiades / Institute for the Study of the Ancient World, New York University","checkedAt":"2026-10-13","license":"cc-by-3.0","licenseUrl":"https://creativecommons.org/licenses/by/3.0/","attribution":"© C. Foss, G. Reger, Brady Kiesling, Sean Gillies, Jeffrey Becker, H. Kopp, Joel Michael Kent, B. Siewert-Mayer, Phoebe Acheson, R. Talbert, Johan Åhlfeldt, W. Röllig, Adam Rabinowitz, Tom Elliott, DARMC, jfu, Chris de Lisle, Francis Deblauwe, R. Scott Smith, Greta Hawes, Ryan Horne, Eric Kansa. Pleiades, CC BY 3.0. 座標は原資料の代表点を転記。日本語説明は独自作成。"},{"id":"osm-way-244582409","title":"OpenStreetMap · ancient-site geometry","url":"https://www.openstreetmap.org/way/244582409","publisher":"OpenStreetMap contributors","checkedAt":"2026-10-13","license":"odbl-1.0","licenseUrl":"https://opendatacommons.org/licenses/odbl/1-0/","attribution":"© OpenStreetMap contributors. ODbL 1.0. Pleiades が用いた上流の位置資料。"}],"details":{"coordinates":{"latitude":37.940164271971945,"longitude":27.34240298195866,"certainty":"approximate","sourceId":"pleiades-599612","explanation":"エフェソス遺跡の代表点です。現代のセルチュク市中心部や、本文の出来事の正確な場所を示すものではありません。古代の港・海岸線は現在と異なります。"},"identificationCertainty":"confirmed","modernName":"Ephesos／エフェソス遺跡（トルコ）"}}],"artworks":[]}"#.utf8))
            sourceExcerpt = nil
        }
        for (screen, book, chapter, first, last) in [("entity-acts-early", "ACT", 7, 58, 60), ("entity-acts-late", "ACT", 28, 7, 10), ("entity-existing-map", "ACT", 1, 4, 4), ("entity-rom-early", "ROM", 1, 1, 7), ("entity-rom-jacob", "ROM", 9, 13, 13), ("entity-rom-late", "ROM", 16, 1, 5), ("entity-lev-early", "LEV", 1, 1, 2), ("entity-lev-sinai", "LEV", 7, 38, 38), ("entity-lev-jacob", "LEV", 26, 42, 42), ("entity-num-hoshea", "NUM", 13, 8, 8), ("entity-num-gilead", "NUM", 26, 29, 29), ("entity-jos-bohan", "JOS", 15, 6, 6), ("entity-jos-alias", "JOS", 15, 49, 49), ("entity-jos-burial", "JOS", 24, 32, 32), ("entity-jdg-dan", "JDG", 18, 29, 29), ("entity-jdg-luz", "JDG", 1, 26, 26), ("entity-rut-early", "RUT", 1, 1, 2), ("entity-1sa-jacob", "1SA", 12, 8, 8), ("entity-1sa-ahimelech", "1SA", 26, 6, 6), ("entity-2sa-dual", "2SA", 23, 1, 1), ("entity-2ki-jacob", "2KI", 13, 23, 23), ("entity-2ki-adrammelech", "2KI", 19, 37, 37), ("entity-1ch-israel", "1CH", 1, 34, 34), ("entity-1ch-israel-six", "1CH", 2, 1, 1), ("entity-1ch-ephraim", "1CH", 7, 20, 20), ("entity-1ch-jabesh", "1CH", 10, 12, 12), ("entity-1ch-baalah", "1CH", 13, 6, 6), ("entity-2ch-uncovered", "2CH", 3, 4, 4), ("entity-1ch-azaziah", "1CH", 15, 21, 21), ("entity-2ch-joash", "2CH", 22, 11, 11), ("entity-ezr-adaiah", "EZR", 10, 39, 39), ("entity-ezr-hezekiah", "EZR", 2, 16, 16), ("entity-neh-athaiah", "NEH", 11, 4, 4), ("entity-neh-aija", "NEH", 11, 31, 31), ("entity-neh-beeroth", "NEH", 7, 29, 29), ("entity-ezr-held-elnathan", "EZR", 8, 16, 16), ("entity-neh-hanun-early", "NEH", 3, 13, 13), ("entity-neh-hanan-early", "NEH", 8, 7, 7), ("entity-neh-harhur", "NEH", 7, 53, 53), ("entity-neh-hodevah", "NEH", 7, 43, 43), ("entity-neh-joiada-early", "NEH", 12, 10, 10), ("entity-neh-meremoth-early", "NEH", 3, 4, 4), ("entity-neh-sanballat-early", "NEH", 2, 10, 10)] where ProcessInfo.processInfo.arguments.contains("--qa-screen=" + screen) {
            let passage = Passage(book: book, start: Verse(chapter: chapter, verse: first), end: Verse(chapter: chapter, verse: last))
            let encoder = JSONEncoder()
            let range = String(data: try! encoder.encode(passage), encoding: .utf8)!
            selected = try! JSONDecoder().decode(ImportRecord.self, from: Data(("{\"id\":\"00000000-0000-4000-8000-000000000123\",\"idempotencyKey\":\"00000000-0000-4000-8000-000000000123\",\"ranges\":[" + range + "],\"translation\":\"JCB\",\"createdAt\":0}").utf8))
            reading = nil
            sourceExcerpt = nil
        }
        if ProcessInfo.processInfo.arguments.contains("--qa-screen=home") { selected = nil; reading = nil; sourceExcerpt = nil }
        if ProcessInfo.processInfo.arguments.contains("--qa-screen=initial") || ProcessInfo.processInfo.arguments.contains("--qa-screen=configured-home") { selected = nil; reading = nil; sourceExcerpt = nil; account = nil }

    }
}
#endif
