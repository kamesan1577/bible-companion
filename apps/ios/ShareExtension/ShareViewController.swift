import UIKit
import SwiftUI
import UniformTypeIdentifiers
import CompanionCore

/// The extension displays public references in place; it never launches the containing app.
@MainActor final class ShareViewController: UIViewController {
    private let model = SharedPreviewModel()
    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: SharedPreviewView(model: model, close: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) }))
        addChild(host); view.addSubview(host.view); host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor), host.view.topAnchor.constraint(equalTo: view.topAnchor), host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
        host.didMove(toParent: self)
        Task {
            do {
                var parts: [String] = []
                let inputs = extensionContext?.inputItems as? [NSExtensionItem] ?? []
                for input in inputs {
                    if let text = input.attributedContentText?.string { parts.append(text) }
                    for provider in (input.attachments ?? []).prefix(5) {
                        let type = provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) ? UTType.url.identifier : UTType.plainText.identifier
                        if provider.hasItemConformingToTypeIdentifier(type), let value = try await load(provider, type: type) { parts.append(value) }
                    }
                }
                var seen = Set<String>()
                let text = parts.filter { seen.insert($0).inserted }.joined(separator: "\n")
                guard !text.isEmpty, text.utf16.count <= 20_000 else { model.error = "章節やURLを短く共有してください。"; model.loading = false; return }
                model.sharedText = text
                if let parsed = try? SharedImportParser.parse(text) { model.labels = parsed.ranges.map(\.label) }
                do { try ShareInbox.enqueue(text) } catch { model.storageNotice = "アプリへの引き継ぎは利用できません。この画面で資料を確認できます。" }
                await model.refresh()
            } catch { model.error = "共有内容を読み取れませんでした。もう一度共有してください。"; model.loading = false }
        }
    }
    private func load(_ provider: NSItemProvider, type: String) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type, options: nil) { value, error in
                if let error { continuation.resume(throwing: error) }
                else if let url = value as? URL { continuation.resume(returning: url.absoluteString) }
                else { continuation.resume(returning: value as? String) }
            }
        }
    }
}
@MainActor private final class SharedPreviewModel: ObservableObject {
    struct Preview: Decodable { let items: [Item]; let notice: String; let translation: String? }
    struct Item: Decodable, Identifiable {
        let passage: Passage; let text: String; let citations: [Citation]
        var id: Passage { passage }
    }
    @Published var loading = true
    @Published var preview: Preview?
    @Published var error: String?
    @Published var labels: [String] = []
    @Published var storageNotice: String?
    var sharedText = ""
    func refresh() async {
        guard !sharedText.isEmpty else { return }
        loading = true; error = nil
        defer { loading = false }
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String, let base = URL(string: raw), base.scheme == "https", base.host != nil else { error = "資料の接続先が未設定です。"; return }
        do {
            var request = URLRequest(url: base.appendingPathComponent("public/reading-preview"))
            request.httpMethod = "POST"; request.timeoutInterval = 15
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["sharedText": sharedText])
            let config = URLSessionConfiguration.ephemeral
            config.httpShouldSetCookies = false; config.urlCache = nil
            let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 2_000_000 else { error = "資料を読み込めませんでした。章節を確認して再試行してください。"; return }
            preview = try JSONDecoder().decode(Preview.self, from: data)
        } catch { self.error = "接続できません。共有した章節は保持しています。通信が戻ったら再試行してください。" }
    }
}
private struct SharedPreviewView: View {
    @ObservedObject var model: SharedPreviewModel
    let close: () -> Void
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BibleTheme.Space.page) {
                    if model.loading { ProgressView("確認済みの資料を読み込んでいます") }
                    if let preview = model.preview {
                        Text(preview.notice).bibleTextStyle(.caption).foregroundStyle(.secondary)
                        ForEach(preview.items) { item in
                            Text(item.passage.label).bibleTextStyle(.heading)
                            Text(item.text).textSelection(.enabled)
                            ForEach(Array(item.citations.enumerated()), id: \.offset) { _, citation in Text(citation.title).bibleTextStyle(.caption).foregroundStyle(.secondary) }
                        }
                        Text(preview.translation ?? "訳は未確認です").bibleTextStyle(.caption).foregroundStyle(.secondary)
                    } else { ForEach(model.labels, id: \.self) { Text($0).bibleTextStyle(.heading) } }
                    if let error = model.error { Text(error); Button("再試行") { Task { await model.refresh() } }.disabled(model.sharedText.isEmpty || model.loading) }
                    if let notice = model.storageNotice { Text(notice).bibleTextStyle(.caption).foregroundStyle(.secondary) }
                }.padding(BibleTheme.Space.page).frame(maxWidth: .infinity, alignment: .leading)
            }.bibleCanvas().navigationTitle("聖書コンパニオン").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("閉じる", action: close) } }
        }
    }
}
