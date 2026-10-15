import SwiftUI
import CompanionCore

/// Original shared text only; a missing translation is never replaced with WEB.
struct SharedScriptureHeader: View {
    let passage: Passage
    let translation: String?
    let text: String?
    var compact = false
    @State private var expanded = false
    private var bodyText: String? {
        guard let text else { return nil }
        let lines = text.components(separatedBy: .newlines).filter {
            let value = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return !value.hasPrefix("https://") && !value.hasPrefix("http://")
        }.joined(separator: "\n")
        return lines.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : lines
    }
    var body: some View {
        VStack(alignment: .leading, spacing: BibleTheme.Space.xs) {
            HStack {
                Text("\(passage.label) · \(translation ?? "訳名なし")").bibleTextStyle(.caption)
                Spacer()
                if !compact, bodyText != nil {
                    Button { expanded.toggle() } label: { Text("本文").bibleTextStyle(.caption) }.accessibilityLabel(expanded ? "折り畳む" : "本文を展開").frame(minWidth: BibleTheme.Layout.minimumTouchTarget, minHeight: BibleTheme.Layout.minimumTouchTarget)
                }
            }
            if let bodyText {
                if expanded && !compact {
                    ScrollView { Text(bodyText).bibleTextStyle(.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: BibleTheme.Layout.minimumTouchTarget * 3)
                } else { Text(bodyText).bibleTextStyle(.caption).lineLimit(compact ? 1 : 2).accessibilityLabel("共有本文：\(bodyText)") }
            } else { Text("共有に本文が含まれていません。本文付きで共有すると、ここに表示します。").bibleTextStyle(.caption).lineLimit(compact ? 1 : 2).bibleForeground(.textSecondary) }
        }.padding(.horizontal, BibleTheme.Space.page).padding(.vertical, BibleTheme.Space.sm).bibleCanvas().accessibilityIdentifier("shared-scripture-header")
    }
}
