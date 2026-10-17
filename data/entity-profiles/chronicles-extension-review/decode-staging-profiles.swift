import Foundation
extension Bundle { static var module: Bundle { .main } }
var reports: [[String: Any]] = []
for path in CommandLine.arguments.dropFirst() {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let profiles = root["profiles"] as! [[String: Any]]
    var errors: [[String: String]] = []
    var hiddenLinks: [[String: String]] = []
    for p in profiles {
        do { let profile = try JSONDecoder().decode(EntityProfile.self, from: JSONSerialization.data(withJSONObject: p)); if let link = profile.wikipedia, link.safeURL == nil { hiddenLinks.append(["id": profile.id, "url": link.url, "kind": link.kind]) } }
        catch { errors.append(["id": p["id"] as? String ?? "unknown", "error": String(describing: error)]) }
    }
    var catalogDecoded = false
    do { _ = try JSONDecoder().decode(EntityProfileCatalog.self, from: data); catalogDecoded = true } catch { }
    reports.append(["path": path, "profiles": profiles.count, "profileDecodeErrors": errors, "wikipediaLinksRejectedByAppSafetyRules": hiddenLinks, "catalogDecoded": catalogDecoded, "semanticApproval": false])
}
let output = try JSONSerialization.data(withJSONObject: reports, options: [.prettyPrinted, .sortedKeys])
print(String(data: output, encoding: .utf8)!)
