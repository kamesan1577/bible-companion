import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Ephemeral transport. Private responses never enter shared URLCache or cookie storage.
public actor APIClient {
    public nonisolated let baseURL: URL
    private let configuration: URLSessionConfiguration
    private var token: String?
    public init(baseURL: URL, configuration suppliedConfiguration: URLSessionConfiguration? = nil) throws {
        guard baseURL.scheme == "https", baseURL.host != nil, baseURL.user == nil, baseURL.password == nil,
              baseURL.query == nil, baseURL.fragment == nil, baseURL.path.isEmpty || baseURL.path == "/" else { throw NetworkFailure.insecureEndpoint }
        self.baseURL = baseURL
        let configuration = (suppliedConfiguration?.copy() as? URLSessionConfiguration) ?? URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 45; configuration.timeoutIntervalForResource = 60
        self.configuration = configuration
    }
    public func setToken(_ value: String?) { token = value }
    public func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await decode(path, method: "GET", body: nil, query: query)
    }
    public func post<B: Encodable & Sendable, T: Decodable & Sendable>(_ path: String, body: B, authenticated: Bool = true) async throws -> T {
        try await decode(path, method: "POST", body: JSONEncoder().encode(body), authenticated: authenticated)
    }
    public func put<B: Encodable & Sendable, T: Decodable & Sendable>(_ path: String, body: B) async throws -> T {
        try await decode(path, method: "PUT", body: JSONEncoder().encode(body))
    }
    public func delete<T: Decodable & Sendable>(_ path: String) async throws -> T { try await decode(path, method: "DELETE", body: nil) }
    public func delete<B: Encodable & Sendable, T: Decodable & Sendable>(_ path: String, body: B) async throws -> T { try await decode(path, method: "DELETE", body: JSONEncoder().encode(body)) }
    public func empty(_ path: String, method: String = "POST") async throws { _ = try await request(path, method: method, body: nil) }
    private func decode<T: Decodable & Sendable>(_ path: String, method: String, body: Data?, query: [URLQueryItem] = [], authenticated: Bool = true) async throws -> T {
        let data = try await request(path, method: method, body: body, query: query, authenticated: authenticated)
        do { return try JSONDecoder().decode(T.self, from: data) } catch { throw NetworkFailure.invalidResponse }
    }
    private func request(_ path: String, method: String, body: Data?, query: [URLQueryItem] = [], authenticated: Bool = true) async throws -> Data {
        guard baseURL.host?.hasSuffix(".invalid") != true else { throw NetworkFailure.unconfigured }
        guard path.hasPrefix("/"), !path.hasPrefix("//"), !path.contains(".."), !path.contains("?"), !path.contains("#") else { throw NetworkFailure.invalidResponse }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { throw NetworkFailure.invalidResponse }
        components.path = path; components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw NetworkFailure.invalidResponse }
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if authenticated { guard let token else { throw NetworkFailure.unauthenticated }; request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        do {
            let (data, response) = try await BoundedTransfer(maximumBytes: 4_000_000).run(request, configuration: configuration)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, http.url?.host == baseURL.host, http.url?.scheme == "https", data.count <= 4_000_000 else { throw NetworkFailure.invalidResponse }
            if http.statusCode == 401 { throw NetworkFailure.unauthenticated }
            guard (200...299).contains(http.statusCode) else {
                let envelope = try? JSONDecoder().decode(JSONValue.self, from: data)
                throw NetworkFailure.server(status: http.statusCode, code: envelope?["error"]["code"].string ?? "server_error")
            }
            return data
        } catch is CancellationError { throw NetworkFailure.cancelled }
        catch let error as URLError { if error.code == .cancelled { throw NetworkFailure.cancelled }; throw NetworkFailure.offline }
    }
}
