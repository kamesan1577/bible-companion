import Foundation
extension Bundle { static var module: Bundle { .main } }
var results: [[String: Any]] = []
for path in CommandLine.arguments.dropFirst() {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let catalog = try JSONDecoder().decode(EntityProfileCatalog.self, from: data)
    let book = path.contains("1CH") ? "1CH" : "2CH"
    var errors: [String] = []
    var checked = 0
    for edge in catalog.occurrences ?? [] {
        let coordinate = Verse(chapter: edge.chapter, verse: edge.verse)
        let passage = Passage(book: book, start: coordinate, end: coordinate)
        guard let resolved = catalog.resolve(id: edge.entityID, passage: passage, includeFuture: false) else {
            errors.append("Unresolved \(edge.entityID) at \(coordinate.label)"); continue
        }
        checked += 1
        let sourceIDs = Set(resolved.sources.map(\.id))
        for fact in resolved.facts {
            if coordinate < fact.knownBy { errors.append("Future fact \(edge.entityID)") }
            if !Set(fact.sourceIds).isSubset(of: sourceIDs) { errors.append("Visible fact source missing \(edge.entityID) at \(coordinate.label)") }
        }
        if resolved.sources.contains(where: { $0.knownBy.map { coordinate < $0 } ?? false }) { errors.append("Future source \(edge.entityID)") }
        if let link = resolved.wikipedia {
            if link.safeURL == nil { errors.append("Unsafe Wikipedia link \(edge.entityID)") }
            if link.knownBy.map({ coordinate < $0 }) ?? false { errors.append("Future Wikipedia link \(edge.entityID)") }
        }
    }
    results.append(["book": book, "occurrences": catalog.occurrences?.count ?? 0,
                    "resolved": checked, "errors": errors, "semanticApproval": false])
}
print(String(data: try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
