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
                        Text("読書中の箇所から、質問したい章と節を選びます。章をまたぐ場合も指定できます。").bibleTextStyle(.body)
                    }
                    endpoint(isStart: true, selection: selection)
                    endpoint(isStart: false, selection: selection)
                    Section {
                        if selection.isValid {
                            BibleSectionHeader(title: selection.passage.label, subtitle: "この章節について質問します")
                        } else {
                            BibleStateView(title: "開始と終わりを確認してください", message: "終わりの章節を、開始と同じ位置か後にしてください。", systemImage: BibleTheme.Symbol.error)
                        }
                        BibleScopeNotice(text: "先の出来事を含めない設定は、元の読書箇所の\(selection.reading.end.label)までのままです。")
                        Text(ReferenceSystem.fallbackNotice).bibleTextStyle(.caption)
                    }
                } else { BibleStateView(title: "質問する箇所を選べません", message: "読書画面に戻り、読みたい箇所を選び直してください。") }
            }
            .navigationTitle("質問する箇所").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("この箇所に決める") { if let selection, selection.isValid { onSelect(selection.passage); dismiss() } }.disabled(selection?.isValid != true) }
            }
        }
    }
    private func endpoint(isStart: Bool, selection: PassageSelection) -> some View {
        Section(isStart ? "最初の章節" : "最後の章節") {
            Picker("章", selection: Binding(get: { isStart ? self.selection?.start.chapter ?? 1 : self.selection?.end.chapter ?? 1 }, set: { self.selection?.selectChapter($0, isStart: isStart) })) {
                ForEach(Array(selection.chapters), id: \.self) { Text("\($0)章").tag($0) }
            }
            Picker("節", selection: Binding(get: { isStart ? self.selection?.start.verse ?? 1 : self.selection?.end.verse ?? 1 }, set: { self.selection?.selectVerse($0, isStart: isStart) })) {
                ForEach(Array(selection.verses(in: isStart ? selection.start.chapter : selection.end.chapter) ?? 1...1), id: \.self) { Text("\($0)節").tag($0) }
            }
        }
    }
}
