import Foundation
import CryptoKit
import ImageIO
import CompanionCore

/// Public-domain image transport is independent from private API sessions.
/// This explicit allowlist must grow only with reviewed source provenance.
enum PublicArtworkLoader {
    static let maximumBytes = 8_000_000
    static func load(_ url: URL) async throws -> Data {
#if DEBUG
        await MainActor.run { ArtworkLoadProbe.shared.started += 1 }
#endif
        guard PublicArtworkURLPolicy.allows(url) else { throw URLError(.unsupportedURL) }
#if DEBUG && targetEnvironment(simulator)
        if let fixture = try ArtworkCatalogQA.imageFixture(for: url) {
            guard fixture.count <= maximumBytes, validImage(fixture) else { throw URLError(.cannotDecodeContentData) }
            return fixture
        }
#endif
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

#if DEBUG
import Combine
@MainActor final class ArtworkLoadProbe: ObservableObject {
    static let shared = ArtworkLoadProbe()
    @Published var started = 0
}
#endif

#if DEBUG && targetEnvironment(simulator)
enum ArtworkCatalogQA {
    /// Actual, hash-pinned museum bytes prepared only by the Simulator harness.
    /// Missing/corrupt registered fixtures fail; they never silently fall back to live HTTP.
    static func imageFixture(for url: URL) throws -> Data? {
        guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: ShareInbox.groupID) else { return nil }
        let directory = group.appendingPathComponent("HarnessPublicArtworkFixtures", isDirectory: true)
        let manifest = directory.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifest.path) else { return nil }
        guard let manifestSize = try manifest.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              manifestSize <= 8192 else { throw URLError(.dataLengthExceedsMaximum) }
        let hashes = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: manifest))
        let key = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined() + ".image"
        guard let expected = hashes[key] else { return nil }
        let fixture = directory.appendingPathComponent(key)
        guard let size = try fixture.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0, size <= PublicArtworkLoader.maximumBytes else { throw URLError(.dataLengthExceedsMaximum) }
        let data = try Data(contentsOf: fixture)
        guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == expected else { throw URLError(.cannotDecodeContentData) }
        return data
    }
    static var selected: MaterialCard? {
        guard let raw = ProcessInfo.processInfo.environment["BIBLE_QA_ARTWORK"], let data = Data(base64Encoded: raw) else { return nil }
        return try? JSONDecoder().decode(MaterialCard.self, from: data)
    }
    static var shareURL: URL? {
        guard let card = selected, let passage = card.passages.last,
              let raw = ProcessInfo.processInfo.environment["BIBLE_QA_ARTWORK"] else { return nil }
        var parts = URLComponents(string: "https://www.bible.com/bible/83/\(passage.book).\(passage.end.chapter).\(passage.end.verse).JCB")!
        parts.queryItems = [URLQueryItem(name: "bible-compose-fixture", value: "1"), URLQueryItem(name: "bible-artwork-data", value: raw)]
        return parts.url
    }
    static func projected(_ input: Any?, encodedCard: String? = nil) -> [[String: Any]] {
        guard let input, let data = try? JSONSerialization.data(withJSONObject: input),
              let passage = try? JSONDecoder().decode(Passage.self, from: data) else { return [] }
        let selectedCard = encodedCard.flatMap { Data(base64Encoded: $0) }.flatMap { try? JSONDecoder().decode(MaterialCard.self, from: $0) } ?? selected
        let cards = selectedCard.map { [$0] } ?? []
        let visible = ReadingContentProjection.materials(cards, kind: "artwork", passage: passage)
        guard let encoded = try? JSONEncoder().encode(visible) else { return [] }
        return (try? JSONSerialization.jsonObject(with: encoded)) as? [[String: Any]] ?? []
    }
}
#endif
