import SwiftUI

private struct BibleStateAnimation<Value: Equatable>: ViewModifier {
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // No spatial motion under Reduce Motion. Callers must not introduce
        // offset, rotation, scale or asymmetric transitions around this modifier.
        content.animation(reduceMotion ? nil : BibleTheme.Motion.animation(reduceMotion: false), value: value)
    }
}

extension View {
    /// Local disclosure/state change only. Native sheets and navigation own their motion.
    func bibleStateAnimation<Value: Equatable>(value: Value) -> some View {
        modifier(BibleStateAnimation(value: value))
    }

    /// Trigger on a deliberate range/tab selection, never on each generated token.
    func bibleSelectionFeedback<Value: Equatable>(trigger: Value) -> some View {
        sensoryFeedback(.selection, trigger: trigger)
    }

    /// Use only after a confirmed user-initiated save; do not imply server success early.
    func bibleSuccessFeedback<Value: Equatable>(trigger: Value) -> some View {
        sensoryFeedback(.success, trigger: trigger)
    }
}
