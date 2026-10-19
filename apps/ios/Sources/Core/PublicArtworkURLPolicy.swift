import Foundation

/// Transport approval is separate from the per-work public-domain rights review.
public enum PublicArtworkURLPolicy {
    public static let allowedHosts: Set<String> = ["api.nga.gov", "images.metmuseum.org", "openaccess-cdn.clevelandart.org"]

    public static func allows(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased(),
              url.user == nil, url.password == nil, url.port == nil || url.port == 443,
              url.fragment == nil else { return false }
        if allowedHosts.contains(host) { return url.query == nil }
        // The museum's image service must never become an arbitrary URL proxy.
        guard host == "www.clevelandart.org", url.path == "/_next/image",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              items.count == 3, Set(items.map(\.name)) == Set(["url", "w", "q"]),
              items.first(where: { $0.name == "w" })?.value == "1920",
              items.first(where: { $0.name == "q" })?.value == "75",
              let raw = items.first(where: { $0.name == "url" })?.value,
              let source = URL(string: raw), source.scheme == "https", source.host == "piction.clevelandart.org",
              source.path == "/cma/ump.di", source.user == nil, source.password == nil,
              source.port == nil, source.fragment == nil,
              let fields = URLComponents(url: source, resolvingAgainstBaseURL: false)?.queryItems,
              fields.count == 5, Set(fields.map(\.name)) == Set(["e", "s", "se", "v", "f"]) else { return false }
        let patterns = ["e": "^[A-Fa-f0-9]{64}$", "s": "^[0-9]{1,12}$", "se": "^[0-9]{1,12}$", "v": "^[0-9]{1,3}$", "f": "^[A-Za-z0-9._\\\\-]+[.]jpg$"]
        return fields.allSatisfy { field in
            guard let value = field.value, let pattern = patterns[field.name] else { return false }
            return value.range(of: pattern, options: .regularExpression) != nil
        }
    }
}
