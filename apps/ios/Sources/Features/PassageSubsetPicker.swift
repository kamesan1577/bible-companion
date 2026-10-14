import SwiftUI
import CompanionCore

struct PassageSubsetPicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selection: PassageSelection?
    let onSelect: (Passage) -> Void
    init(reading: Passage, selected: Passage, onSelect: @escaping (Passage) -> Void) {
        _selection = State(initialValue: try? PassageSelection(reading: reading, selected: selected)); self.onSelect = onSelect
    }
    var body: some View {
        NavigationStack {
            Form {
                if let selection {
                    Section {
                        BibleRangeBadge(text: selection.reading.label)
                        Text("読書範囲の中で、質問する章節を指定します。章をまたぐ範囲も選べます。").bibleTextStyle(.body)
                    }
                    endpoint("開始", isStart: true, selection: selection)
                    endpoint("終わり", isStart: false, selection: selection)
                    Section {
                        if selection.isValid {
                            BibleSectionHeader(title: selection.passage.label, subtitle: "\(selection.passage.verseCount)節を質問の対象にします")
                        } else {
                            BibleStateView(title: "開始と終わりを確認してください", message: "終わりの章節を、開始と同じ位置か後にしてください。", systemImage: BibleTheme.Symbol.error)
                        }
                        BibleScopeNotice(text: "先の情報の上限は、元の読書範囲の\(selection.reading.end.label)のままです。")
                        Text(ReferenceSystem.fallbackNotice).bibleTextStyle(.caption)
                    }
                } else { BibleStateView(title: "範囲を確認できません", message: "読書画面から箇所を選び直してください。") }
            }
            .navigationTitle("質問の範囲").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("選択") { if let selection, selection.isValid { onSelect(selection.passage); dismiss() } }.disabled(selection?.isValid != true) }
            }
        }
    }
    private func endpoint(_ title: String, isStart: Bool, selection: PassageSelection) -> some View {
        Section(title) {
            Picker("章", selection: Binding(get: { isStart ? self.selection?.start.chapter ?? 1 : self.selection?.end.chapter ?? 1 }, set: { self.selection?.selectChapter($0, isStart: isStart) })) {
                ForEach(Array(selection.chapters), id: \.self) { Text("\($0)章").tag($0) }
            }
            Picker("節", selection: Binding(get: { isStart ? self.selection?.start.verse ?? 1 : self.selection?.end.verse ?? 1 }, set: { self.selection?.selectVerse($0, isStart: isStart) })) {
                ForEach(Array(selection.verses(in: isStart ? selection.start.chapter : selection.end.chapter) ?? 1...1), id: \.self) { Text("\($0)節").tag($0) }
            }
        }
    }
}
