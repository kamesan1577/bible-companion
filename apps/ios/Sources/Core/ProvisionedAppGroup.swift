import Foundation

/// Resolve only the configured group or its unique signing-team suffix.
/// The OS still decides whether the process may open that App Group container.
public enum ProvisionedAppGroup {
    public static func resolve(configured: String, groups: [String]?) -> String? {
        guard configured.hasPrefix("group."), configured.count < 256 else { return nil }
        guard let groups else { return configured } // Simulator has no embedded profile.
        if groups.contains(configured) { return configured }
        let prefix = configured + "."
        let candidates = Set(groups.filter { group in
            guard group.hasPrefix(prefix) else { return false }
            let suffix = group.dropFirst(prefix.count)
            return suffix.count == 10 && suffix.allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber) }
        })
        return candidates.count == 1 ? candidates.first : nil
    }

    public static func groups(inProfile data: Data) -> [String]? {
        // An installed profile contains its XML payload inside a CMS envelope.
        // This reads only group metadata; it does not validate or grant privileges.
        let start = Data("<?xml".utf8), end = Data("</plist>".utf8)
        guard data.count <= 2_000_000, let opening = data.range(of: start),
              let closing = data.range(of: end, in: opening.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(from: data[opening.lowerBound..<closing.upperBound], format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any] else { return [] }
        return entitlements["com.apple.security.application-groups"] as? [String] ?? []
    }
}
