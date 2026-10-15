import SwiftUI
import UIKit
import CompanionCore

@MainActor final class ExportModel: ObservableObject {
    @Published private(set) var busy = false
    @Published private(set) var progress = ""
    @Published private(set) var message: String?
    @Published private(set) var file: URL?
    @Published private(set) var cleanupRequired = false
    private var task: Task<Void, Never>?
    private var assembler: PrivateExportAssembler?
    private var attempt = UUID()
    let ownerID: String
    let client: APIClient
    init(ownerID: String, client: APIClient) { self.ownerID = ownerID; self.client = client }
    func start() {
        guard !busy, file == nil, !cleanupRequired else { return }
        do {
            guard try PendingQuestionStore.read(owner: ownerID) == nil, try ComparisonStore.read(owner: ownerID) == nil else {
                message = "送信結果を確認中の質問または比較があります。重複を防ぐため、先に履歴で処理結果を確認してください。"; return
            }
        } catch { message = "送信結果を確認中の質問や比較があるか調べられません。端末のロックを解除してから、もう一度お試しください。"; return }
        let generation = UUID(); attempt = generation
        busy = true; message = nil; progress = "書き出す記録を確認しています"
        task = Task {
            var writer: PrivateExportAssembler?
            defer { if attempt == generation { busy = false } }
            do {
                try Task.checkCancellation()
                guard attempt == generation else { throw CancellationError() }
                try ExportFiles.cleanup()
                let snapshot: ExportSnapshot = try await client.post("/v1/me/export/snapshots", body: JSONValue.object([:]))
                try Task.checkCancellation()
                let output = try PrivateExportAssembler(snapshot: snapshot, ownerID: ownerID, directory: ExportFiles.directory())
                writer = output; assembler = output
                var pageCount = 0
                while let next = try await output.nextRequest() {
                    try Task.checkCancellation()
                    guard attempt == generation else { throw CancellationError() }
                    progress = "\(Self.sectionName(next.section))を書き出し用に準備しています（\(pageCount)ページ完了）"
                    var query = [URLQueryItem(name: "snapshotId", value: snapshot.snapshotId), URLQueryItem(name: "section", value: next.section)]
                    if let cursor = next.cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
                    let page: ExportPage = try await client.get("/v1/me/export/pages", query: query)
                    try Task.checkCancellation(); try await output.append(page); pageCount += 1
                }
                let url = try await output.finish()
                try Task.checkCancellation()
                guard attempt == generation else { throw CancellationError() }
                file = url; progress = "書き出しの準備ができました"
            } catch {
                var cleanupFailed = false
                do { if let writer { try await writer.discard() } else if attempt == generation { try ExportFiles.cleanup() } } catch { cleanupFailed = true }
                guard attempt == generation else { return }
                assembler = cleanupFailed ? writer : nil; file = nil; cleanupRequired = cleanupFailed
                if cleanupFailed { message = "端末内の作業用ファイルを削除できませんでした。端末のロックを解除して「端末内の作業用ファイルを削除」を押してください。"; return }
                switch error {
                case NetworkFailure.server(status: 409, code: "export_changed"):
                    message = "書き出し中に履歴または資料が更新されたため、ファイルを作り直す必要があります。不完全なファイルは削除しました。質問や比較の処理が終わってから「記録を書き出す」を押してください。"
                case NetworkFailure.server(status: 413, code: "export_entity_too_large"):
                    message = "1件の記録がファイルにできる大きさを超えたため、内容を省かず書き出しを中止して削除しました。記録を変更せず、ファイルも共有していません。"
                case ExportFailure.expired:
                    message = "書き出しの準備に使える時間が過ぎました。「記録を書き出す」をもう一度押してください。"
                case is CancellationError, NetworkFailure.cancelled:
                    message = "書き出しを中止して削除しました。"
                default:
                    message = "ファイルを最後まで作成できませんでした。不完全なファイルは共有していません。通信状態を確認して「記録を書き出す」を押してください。"
                }
            }
        }
    }
    func clear() {
        let generation = UUID(); attempt = generation
        task?.cancel(); task = nil; file = nil
        let previous = assembler
        busy = true
        Task {
            var failed = false
            do { if let previous { try await previous.discard() } else if attempt == generation { try ExportFiles.cleanup() } } catch { failed = true }
            guard attempt == generation else { return }
            cleanupRequired = failed; assembler = failed ? previous : nil; busy = false
            message = failed ? "端末内の作業用ファイルを削除できませんでした。ロックを解除してから、削除をもう一度お試しください。" : "端末内の作業用ファイルを削除しました。"
        }
    }
    private static func sectionName(_ section: String) -> String {
        ["imports": "読書履歴", "conversations": "会話", "messages": "質問と回答", "comparisons": "保存した比較"][section] ?? "記録"
    }
}
enum ExportFiles {
    static func directory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("PrivateTemporaryExports", isDirectory: true)
    }
    static func cleanup() throws {
        let root = try directory()
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        for file in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) { try FileManager.default.removeItem(at: file) }
    }
}
struct ExportView: View {
    @StateObject private var model: ExportModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showShare = false
    init(ownerID: String, client: APIClient) { _model = StateObject(wrappedValue: ExportModel(ownerID: ownerID, client: client)) }
    var body: some View {
        ScrollView {
            BibleReadingColumn {
                BibleSectionHeader(title: "自分の記録を書き出す", subtitle: "JSONファイル")
                Text("読書履歴、質問、現在表示できる回答、保存した比較、設定をJSONファイルにまとめます。パスキーなどのログイン情報は含みません。準備後に保存・共有先を選ぶ画面が開くので、保存先や送信先を自分で選んでください。").bibleTextStyle(.body)
                Text("質問や比較の送信結果を確認中の場合は、履歴で結果を確認してから始めてください。書き出し中に履歴や資料が更新されると、作成をやり直すことがあります。このファイルからアカウントやログイン情報を復元することはできません。").bibleTextStyle(.caption).bibleForeground(.textSecondary)
                if model.busy {
                    BibleLoadingView(title: model.progress, message: "記録をページごとにこの端末の作業用領域へ準備しています。完了後、共有先を選んで保存してください。")
                    Button("書き出しを中止して削除", role: .cancel) { model.clear() }
                } else if model.cleanupRequired {
                    Button("端末内の作業用ファイルを削除", role: .destructive) { model.clear() }
                } else if model.file != nil {
                    BibleStateView(title: "準備ができました", message: "質問などの個人データを含むファイルができました。保存・共有先を選ぶと、保存または送信できます。", systemImage: "doc")
                    Button("保存・共有先を選ぶ") { showShare = true }.buttonStyle(.glass)
                    Button("ファイルを削除", role: .destructive) { model.clear() }
                } else {
                    Button("記録を書き出す") { model.start() }.buttonStyle(.glass)
                }
                if let message = model.message { Text(message).bibleTextStyle(.body) }
            }
        }
        .bibleCanvas().navigationTitle("記録の書き出し")
        .sheet(isPresented: $showShare, onDismiss: { model.clear() }) {
            if let file = model.file { ExportShareSheet(file: file) { showShare = false } }
        }
        .onDisappear { if !showShare { model.clear() } }
        .onChange(of: scenePhase) { _, phase in if phase == .background && !showShare { model.clear() } }
    }
}
private struct ExportShareSheet: UIViewControllerRepresentable {
    let file: URL
    let completion: @MainActor @Sendable () -> Void
    func makeUIViewController(context: Context) -> ExportActivityHost {
        ExportActivityHost(file: file, completion: completion)
    }
    func updateUIViewController(_ controller: ExportActivityHost, context: Context) {}
}
@MainActor private final class ExportActivityHost: UIViewController, UIAdaptivePresentationControllerDelegate {
    private let file: URL
    private let completion: @MainActor @Sendable () -> Void
    private var presentedActivity = false
    private var completed = false
    init(file: URL, completion: @escaping @MainActor @Sendable () -> Void) {
        self.file = file; self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { return nil }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !presentedActivity, view.window != nil else { return }
        presentedActivity = true
        let activity = UIActivityViewController(activityItems: [file], applicationActivities: nil)
        activity.completionWithItemsHandler = { [weak self] _, _, _, _ in
            Task { @MainActor in self?.finish() }
        }
        if traitCollection.userInterfaceIdiom == .pad {
            activity.modalPresentationStyle = .popover
            if let popover = activity.popoverPresentationController {
                popover.sourceView = view
                popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
        }
        activity.presentationController?.delegate = self
        present(activity, animated: true)
    }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { finish() }
    private func finish() {
        guard !completed else { return }
        completed = true; completion()
    }
}
