import SwiftUI

/// Opaque content grouping. Never a custom Liquid Glass substitute.
struct BibleReadingSurface<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    private let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(BibleTheme.Space.lg)
            .background(BibleTheme.color(.surface, scheme: scheme), in: RoundedRectangle(cornerRadius: BibleTheme.Radius.surface, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: BibleTheme.Radius.surface, style: .continuous)
                    .strokeBorder(BibleTheme.color(.border, scheme: scheme, increasedContrast: contrast == .increased), lineWidth: contrast == .increased ? BibleTheme.Layout.emphasizedBorder : BibleTheme.Layout.hairline)
                    .allowsHitTesting(false)
            }
    }
}

struct BibleSectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: BibleTheme.Space.sm) {
            Text(title).bibleTextStyle(.heading).bibleForeground(.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle).bibleTextStyle(.caption).bibleForeground(.textSecondary)
            }
        }
    }
}

/// A label only; the enclosing native Button supplies press, focus, and glass behavior.
struct BibleActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .bibleTextStyle(.body)
            .frame(minHeight: BibleTheme.Layout.minimumTouchTarget)
            .contentShape(Rectangle())
    }
}

struct BibleRangeBadge: View {
    let text: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(text)
            .bibleTextStyle(.caption)
            .bibleForeground(.accent)
            .padding(.horizontal, BibleTheme.Space.sm)
            .padding(.vertical, BibleTheme.Space.xs)
            .background(BibleTheme.color(.inset, scheme: scheme), in: RoundedRectangle(cornerRadius: BibleTheme.Radius.badge, style: .continuous))
    }
}

struct BibleScopeNotice: View {
    let text: String

    var body: some View {
        Label(text, systemImage: BibleTheme.Symbol.scope)
            .bibleTextStyle(.caption)
            .bibleForeground(.textSecondary)
            .accessibilityElement(children: .combine)
    }
}

/// The same quiet structure for empty, unsupported, offline, and failure states.
/// Put a native retry Button outside this container when recovery is available.
struct BibleStateView: View {
    let title: String
    let message: String
    var systemImage: String = BibleTheme.Symbol.unavailable

    var body: some View {
        BibleReadingSurface {
            VStack(alignment: .leading, spacing: BibleTheme.Space.md) {
                Label(title, systemImage: systemImage)
                    .bibleTextStyle(.heading).bibleForeground(.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(message).bibleTextStyle(.body).bibleForeground(.textSecondary)
            }
        }
    }
}

struct BibleLoadingView: View {
    var title: String = "読み込んでいます"
    var message: String = "選んだ範囲を確認しています。"

    var body: some View {
        BibleReadingSurface {
            VStack(alignment: .leading, spacing: BibleTheme.Space.md) {
                ProgressView(title).bibleTextStyle(.body)
                Text(message).bibleTextStyle(.caption).bibleForeground(.textSecondary)
            }
        }
    }
}

/// Reusable reading rhythm without fixing a text-bearing container's height.
struct BibleReadingColumn<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        VStack(alignment: .leading, spacing: BibleTheme.Space.section) { content }
            .frame(maxWidth: BibleTheme.Layout.readingMaxWidth, alignment: .leading)
            .padding(.horizontal, BibleTheme.Space.page)
            .padding(.vertical, BibleTheme.Space.xl)
            .frame(maxWidth: .infinity)
    }
}
