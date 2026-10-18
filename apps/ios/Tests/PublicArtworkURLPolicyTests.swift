import XCTest
@testable import CompanionCore

final class PublicArtworkURLPolicyTests: XCTestCase {
    func testClevelandProxyOnlyAcceptsItsOfficialImageSourceAndKnownParameters() throws {
        let source = "https://piction.clevelandart.org/cma/ump.di?e=" + String(repeating: "A", count: 64) + "&s=24247294&se=116628280&v=3&f=1937.577_o2.jpg"
        func proxy(_ raw: String) -> URL {
            var value = URLComponents(string: "https://www.clevelandart.org/_next/image")!
            value.queryItems = [URLQueryItem(name: "url", value: raw), URLQueryItem(name: "w", value: "1920"), URLQueryItem(name: "q", value: "75")]
            return value.url!
        }
        XCTAssertTrue(PublicArtworkURLPolicy.allows(proxy(source)))
        for raw in [source.replacingOccurrences(of: "piction.clevelandart.org", with: "127.0.0.1"), source + "&redirect=https://evil.com", source + "&v=4", source.replacingOccurrences(of: "1937.577_o2.jpg", with: "https://evil.com/a.jpg"), source.replacingOccurrences(of: "/cma/ump.di", with: "/redirect"), "https://piction.clevelandart.org/cma/ump.di"] {
            XCTAssertFalse(PublicArtworkURLPolicy.allows(proxy(raw)), raw)
        }
        XCTAssertFalse(PublicArtworkURLPolicy.allows(URL(string: proxy(source).absoluteString + "&q=75")!))
        XCTAssertFalse(PublicArtworkURLPolicy.allows(URL(string: proxy(source).absoluteString.replacingOccurrences(of: "w=1920", with: "w=99999"))!))
    }
    func testOnlyReviewedMuseumImageHostsAreAllowed() {
        for host in ["api.nga.gov", "images.metmuseum.org", "openaccess-cdn.clevelandart.org"] {
            XCTAssertTrue(PublicArtworkURLPolicy.allows(URL(string: "https://\(host)/image.jpg")!))
        }
        for raw in [
            "http://images.metmuseum.org/a.jpg", "https://images.metmuseum.org.evil.com/a.jpg",
            "https://evil.images.metmuseum.org/a.jpg", "https://images.metmuseum.org@127.0.0.1/a.jpg",
            "https://user:password@images.metmuseum.org/a.jpg", "https://127.0.0.1/a.jpg",
            "https://[::1]/a.jpg", "https://images.metmuseum.org:8443/a.jpg",
            "https://images.metmuseum.org/a.jpg?redirect=http://127.0.0.1",
            "https://images.metmuseum.org/a.jpg#fragment", "file:///tmp/image.jpg",
            "https://images.metmuseum.org./a.jpg"
        ] {
            XCTAssertFalse(PublicArtworkURLPolicy.allows(URL(string: raw)!), raw)
        }
    }
}
