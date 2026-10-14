import Foundation

/// Public-domain image transport is independent from private API sessions.
/// This explicit allowlist must grow only with reviewed source provenance.
enum PublicArtworkLoader {
    static let allowedHosts: Set<String> = ["api.nga.gov"]
    static let maximumBytes = 8_000_000
    static func load(_ url: URL) async throws -> Data {
        guard url.scheme == "https", let host = url.host?.lowercased(), allowedHosts.contains(host),
              url.user == nil, url.password == nil, url.fragment == nil, url.port == nil || url.port == 443 else { throw URLError(.unsupportedURL) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData; configuration.timeoutIntervalForRequest = 20; configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration, delegate: RejectArtworkRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url); request.setValue("image/*", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, http.url == url,
              http.mimeType?.hasPrefix("image/") == true, response.expectedContentLength <= maximumBytes else { throw URLError(.badServerResponse) }
        var data = Data(); data.reserveCapacity(Int(max(0, min(response.expectedContentLength, Int64(maximumBytes)))))
        for try await byte in bytes {
            guard data.count < maximumBytes else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
            if data.count.isMultiple(of: 4096) { try Task.checkCancellation() }
        }
        try Task.checkCancellation()
        return data
    }
}
private final class RejectArtworkRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
