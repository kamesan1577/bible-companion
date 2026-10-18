import SwiftUI
import CompanionCore

struct CitationList: View {
    let citations: [Citation]
    var body: some View {
        if !citations.isEmpty {
            VStack(alignment: .leading, spacing: BibleTheme.Space.md) {
                BibleSectionHeader(title: "出典")
                ForEach(citations) { citation in
                    VStack(alignment: .leading, spacing: BibleTheme.Space.xs) {
                        Text(citation.kindLabel).bibleTextStyle(.caption).bibleForeground(.textSecondary)
                        if citation.materialProvenance == nil, let url = citation.safeURL { Link(destination: url) { Label(citation.title, systemImage: BibleTheme.Symbol.source) } }
                        else { Text(citation.title) }
                        Text("\(citation.passage.label) · \(citation.license) · \(citation.version)").bibleTextStyle(.caption).bibleForeground(.textSecondary)
                        if let provenance = citation.materialProvenance {
                            DisclosureGroup("出典と利用条件") {
                                Text("\(provenance.kindLabel) · \(provenance.kind == "reviewed-material-summary" ? "収録済み要約" : "この内容の確認は終わっていません") · 版 \(provenance.materialVersion)").bibleTextStyle(.caption)
                                Text("以下は要約の根拠となった資料です。AIの説明全体の正確さを保証するものではありません。").bibleTextStyle(.caption)
                                ForEach(Array(provenance.references.enumerated()), id: \.offset) { _, reference in
                                    VStack(alignment: .leading, spacing: BibleTheme.Space.xs) {
                                        if let url = reference.safeURL { Link(reference.title, destination: url) } else { Text(reference.title) }
                                        Text("\(reference.publisher) · \(reference.license)").bibleTextStyle(.caption)
                                        if let attribution = reference.attribution { Text(attribution).bibleTextStyle(.caption) }
                                        if let url = reference.safeLicenseURL { Link("利用条件を読む", destination: url) }
                                        if let checked = reference.checkedAt { Text("出典確認: \(checked)").bibleTextStyle(.caption).bibleForeground(.textSecondary) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
