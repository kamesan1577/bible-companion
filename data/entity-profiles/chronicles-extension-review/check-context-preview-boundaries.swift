import Foundation
extension Bundle { static var module: Bundle { .main } }
let input = CommandLine.arguments[1]
let catalog = try JSONDecoder().decode(EntityProfileCatalog.self, from: Data(contentsOf: URL(fileURLWithPath: input)))
func resolve(_ id: String, _ c: Int, _ v: Int) -> ResolvedEntityProfile? {
    let at = Verse(chapter: c, verse: v)
    return catalog.resolve(id: id, passage: Passage(book: "1CH", start: at, end: at), includeFuture: false)
}
func text(_ p: ResolvedEntityProfile) -> String {
    ([p.nameJa, p.profile.summaryJa, p.profile.identityNoteJa] + p.facts.map(\.textJa)).joined(separator: "\n")
}
var failures: [String] = []
func check(_ value: Bool, _ name: String) { if !value { failures.append(name) } }
let israelEarly = resolve("person:israel_682", 1, 34)!
check(israelEarly.profile.identityType == "individual-context-variant", "Israel ancestor context selected")
check(!text(israelEarly).contains("ヤコブ"), "No later Jacob-name explanation at1:34")
let six = text(resolve("person:israel_682", 2, 1)!)
check(!six.contains("ヨセフ") && !six.contains("ベニヤミン") && !six.contains("アシェル"), "Second-six names hidden at2:1")
let twelve = text(resolve("person:israel_682", 2, 2)!)
check(twelve.contains("ヨセフ") && twelve.contains("アシェル"), "Second-six names visible at2:2")
let gad = resolve("person:gad_1262", 2, 2)!
check(gad.nameJa == "ガド" && !text(gad).contains("ガド族"), "Gad personal context does not show tribal base")
let ephraimEarly = text(resolve("person:ephraim_1206", 7, 20)!)
check(!ephraimEarly.contains("殺") && !ephraimEarly.contains("嘆"), "Ephraim later events hidden at7:20")
check(text(resolve("person:ephraim_1206", 7, 21)!).contains("殺"), "Ephraim event visible at7:21")
check(!text(resolve("person:ephraim_1206", 7, 21)!).contains("嘆"), "Ephraim mourning still hidden at7:21")
check(text(resolve("person:ephraim_1206", 7, 22)!).contains("嘆"), "Ephraim mourning visible at7:22")
check(resolve("person:israel_682", 1, 43) == nil, "Unadopted collective base remains held")
let out: [String: Any] = ["checks": 10, "failures": failures, "allPassed": failures.isEmpty,
                          "scope": "Native context selection and explicit first-use boundaries only; no UI or whole-content approval"]
print(String(data: try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
if !failures.isEmpty { exit(1) }
