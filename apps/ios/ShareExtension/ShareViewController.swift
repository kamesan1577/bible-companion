import UIKit
import SwiftUI
import UniformTypeIdentifiers
import CompanionCore

/// The extension displays public references in place; it never launches the containing app.
@MainActor final class ShareViewController: UIViewController {
    private let model = SharedPreviewModel()
    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: SharedPreviewView(model: model, close: { [weak self] in self?.view.endEditing(true); self?.extensionContext?.completeRequest(returningItems: nil) }))
        addChild(host); view.addSubview(host.view); host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor), host.view.topAnchor.constraint(equalTo: view.topAnchor), host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
        host.didMove(toParent: self)
        Task {
            var parts: [String] = []
            do {
                let inputs = extensionContext?.inputItems as? [NSExtensionItem] ?? []
                for input in inputs {
                    if let text = input.attributedContentText?.string { parts.append(text) }
                    for provider in (input.attachments ?? []).prefix(5) {
                        let type = provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) ? UTType.url.identifier : UTType.plainText.identifier
                        if provider.hasItemConformingToTypeIdentifier(type), let value = try await load(provider, type: type) { parts.append(value) }
                    }
                }
                let text = SharedTextContent.combine(parts)
                guard !text.isEmpty, text.utf16.count <= 20_000 else {
                    model.sharedText = String(text.prefix(20_000))
                    model.shareTextWasTruncated = !text.isEmpty
                    model.shareParseFailed = true
                    model.error = "共有内容から章節を確認できませんでした。YouVersionで節と本文を選び直してから、もう一度共有してください。受け取った内容は下で端末内表示できます。"
                    model.loading = false
                    return
                }
                model.sharedText = text
#if DEBUG && targetEnvironment(simulator)
                if text.contains("bible-compose-fixture=1") { await configureShareComposeFixture(model) }
#endif
                if let parsed = try? SharedImportParser.parse(text) { model.translation = parsed.translation; model.labels = parsed.ranges.map(\.label); model.items = parsed.ranges.enumerated().map { .init(conversationId: "local-\($0.offset)", passage: $0.element) } }
                else { model.shareParseFailed = true }

#if DEBUG && targetEnvironment(simulator)
                if text.contains("bible-compose-fixture=1") {
                    model.loading = false
                }
                else { model.loading = false }
#else
                model.loading = false
#endif
            } catch {
                let partial = parts.joined(separator: "\n")
                model.sharedText = String(partial.prefix(20_000))
                model.shareTextWasTruncated = partial.utf16.count > 20_000
                model.shareParseFailed = true
                model.error = "共有内容を完全に読み取れませんでした。YouVersionで節と本文を選び直してから、もう一度共有してください。受け取れた部分は下で端末内表示できます。"
                model.loading = false
            }
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
