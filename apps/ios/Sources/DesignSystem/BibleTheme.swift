import SwiftUI

/// A restrained physical reading surface. Navigation materials belong to iOS.
enum BibleTheme {
    enum TypeStyle {
        case title, heading, body, caption, verseReference

        var font: Font {
            switch self {
            case .title: return .largeTitle.weight(.semibold)
            case .heading: return .title2.weight(.semibold)
            case .body: return .body
            case .caption: return .subheadline
            case .verseReference: return .title.weight(.semibold)
            }
        }
    }

    enum Symbol {
        static let reading = "book"
        static let history = "clock.arrow.circlepath"
        static let settings = "slider.horizontal.3"
        static let question = "text.bubble"
        static let range = "text.line.first.and.arrowtriangle.forward"
        static let scope = "checkmark.shield"
        static let unavailable = "tray"
        static let error = "exclamationmark.triangle"
        static let source = "link"
        static let map = "map"
        static let people = "person.2"
        static let art = "photo.artframe"
    }
}

private struct BibleTextStyle: ViewModifier {
    let style: BibleTheme.TypeStyle
    @ScaledMetric(relativeTo: .body) private var bodyLeading = BibleTheme.Space.sm

    func body(content: Content) -> some View {
        content
            .font(style.font)
            .lineSpacing(style == .body ? bodyLeading : 0)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct BibleForeground: ViewModifier {
    let role: BibleTheme.ColorRole
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.foregroundStyle(BibleTheme.color(role, scheme: scheme, increasedContrast: contrast == .increased))
    }
}

private struct BibleCanvas: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background(BibleTheme.color(.canvas, scheme: scheme).ignoresSafeArea())
            .tint(BibleTheme.color(.accent, scheme: scheme))
    }
}

extension View {
    func bibleTextStyle(_ style: BibleTheme.TypeStyle) -> some View {
        modifier(BibleTextStyle(style: style))
    }
    func bibleForeground(_ role: BibleTheme.ColorRole) -> some View {
        modifier(BibleForeground(role: role))
    }
    func bibleCanvas() -> some View { modifier(BibleCanvas()) }
}

private struct BibleDeveloperTint: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View { content.tint(BibleTheme.color(.danger, scheme: scheme)) }
}
extension View { func bibleDeveloperTint() -> some View { modifier(BibleDeveloperTint()) } }
