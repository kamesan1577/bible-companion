import Foundation
import CryptoKit
import ImageIO

/// Public-domain image transport is independent from private API sessions.
/// This explicit allowlist must grow only with reviewed source provenance.
enum PublicArtworkLoader {
    static let allowedHosts: Set<String> = ["api.nga.gov"]
    static let maximumBytes = 8_000_000
    static func load(_ url: URL) async throws -> Data {
        guard url.scheme == "https", let host = url.host?.lowercased(), allowedHosts.contains(host),
              url.user == nil, url.password == nil, url.fragment == nil, url.port == nil || url.port == 443 else { throw URLError(.unsupportedURL) }
        let cacheURL = try? cacheFile(for: url)
        if let cacheURL, let size = try? cacheURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size > 0, size <= maximumBytes, let cached = try? Data(contentsOf: cacheURL), validImage(cached) { return cached }
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
        guard validImage(data) else { throw URLError(.cannotDecodeContentData) }
        if let cacheURL { try? data.write(to: cacheURL, options: [.atomic, .completeFileProtection]) }
        return data
    }
    private static func validImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(source) > 0
    }
    private static func cacheFile(for url: URL) throws -> URL {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("PublicArtworkCache", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var excluded = directory; var values = URLResourceValues(); values.isExcludedFromBackup = true; try excluded.setResourceValues(values)
        let key = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(key + ".image")
    }
}
private final class RejectArtworkRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
