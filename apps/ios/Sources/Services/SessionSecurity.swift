import AuthenticationServices
import CryptoKit
import Security
import UIKit
import CompanionCore

struct StoredSession: Codable {
    let token: String
    let expiresAt: TimeInterval
    let user: Account
}
enum SessionVault {
    private static let service = "BibleCompanion.session"
    static var cleanupPending: Bool {
        get { UserDefaults.standard.bool(forKey: "localCleanupPending") }
        set { UserDefaults.standard.set(newValue, forKey: "localCleanupPending") }
    }
    static func read() throws -> StoredSession? {
        guard !UserDefaults.standard.bool(forKey: "requiresExplicitLogin") else { return nil }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "current", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else { throw SecurityError.keychain }
        return try JSONDecoder().decode(StoredSession.self, from: data)
    }
    static func save(_ session: StoredSession) throws {
        let data = try JSONEncoder().encode(session)
        try clear()
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "current", kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw SecurityError.keychain }
        UserDefaults.standard.set(false, forKey: "requiresExplicitLogin")
    }
    static func clear() throws {
        UserDefaults.standard.set(true, forKey: "requiresExplicitLogin")
        let result = SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else { throw SecurityError.keychain }
    }
}
enum SecurityError: Error { case keychain, random, callback, presentation, cancelled }

@MainActor final class WebLogin: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var activeAttempt: UUID?
    private var exchangeTask: Task<Void, Never>?
    private var continuation: CheckedContinuation<TokenResponse, Error>?
    private weak var window: UIWindow?
    func login(client: APIClient) async throws -> TokenResponse {
        guard activeAttempt == nil else { throw SecurityError.presentation }
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first(where: \.isKeyWindow) else { throw SecurityError.presentation }
        self.window = window
        let verifier = try randomToken(), state = try randomToken()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        var components = URLComponents(url: client.baseURL, resolvingAgainstBaseURL: false)!
        guard components.host?.hasSuffix(".invalid") != true else { throw NetworkFailure.unconfigured }
        components.path = "/auth/authorize"
        components.queryItems = [URLQueryItem(name: "state", value: state), URLQueryItem(name: "code_challenge", value: challenge), URLQueryItem(name: "code_challenge_method", value: "S256")]
        guard let url = components.url else { throw SecurityError.callback }
        let attempt = UUID()
        activeAttempt = attempt
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let session = ASWebAuthenticationSession(url: url, callback: .customScheme("biblecompanion")) { [weak self] callback, error in
                    Task { @MainActor in
                        guard let self, self.activeAttempt == attempt, self.continuation != nil else { return }
                        guard error == nil, let callback else { self.finish(.failure(SecurityError.cancelled), attempt: attempt); return }
                        guard callback.scheme == "biblecompanion", callback.host == "auth", callback.path == "/callback",
                              let parts = URLComponents(url: callback, resolvingAgainstBaseURL: false),
                              parts.queryItems?.filter({ $0.name == "state" }).count == 1,
                              parts.queryItems?.filter({ $0.name == "code" }).count == 1,
                              parts.queryItems?.first(where: { $0.name == "state" })?.value == state,
                              let code = parts.queryItems?.first(where: { $0.name == "code" })?.value,
                              code.range(of: #"^[A-Za-z0-9_-]{43}$"#, options: .regularExpression) != nil else { self.finish(.failure(SecurityError.callback), attempt: attempt); return }
                        self.exchangeTask = Task { @MainActor in
                        do {
                            struct Exchange: Encodable, Sendable { let code: String; let codeVerifier: String }
                            let token: TokenResponse = try await client.post("/auth/token", body: Exchange(code: code, codeVerifier: verifier), authenticated: false)
                            self.finish(.success(token), attempt: attempt)
                        } catch { self.finish(.failure(error), attempt: attempt) }
                        }
                    }
                }
                self.session = session
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false
                if !session.start() { finish(.failure(SecurityError.presentation), attempt: attempt) }
            }
        }, onCancel: { Task { @MainActor [weak self] in self?.cancel(attempt: attempt) } })
    }
    func cancel() { guard let activeAttempt else { return }; cancel(attempt: activeAttempt) }
    private func cancel(attempt: UUID) {
        guard activeAttempt == attempt else { return }
        session?.cancel(); exchangeTask?.cancel()
        finish(.failure(SecurityError.cancelled), attempt: attempt)
    }
    private func finish(_ result: Result<TokenResponse, Error>, attempt: UUID) {
        guard activeAttempt == attempt else { return }
        let pending = continuation; continuation = nil; session = nil; exchangeTask = nil; activeAttempt = nil
        pending?.resume(with: result)
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { window ?? ASPresentationAnchor() }
    private func randomToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw SecurityError.random }
        return Data(bytes).base64URL
    }
}
private extension Data { var base64URL: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") } }
