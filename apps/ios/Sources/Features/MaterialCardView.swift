import SwiftUI
import ImageIO
import CompanionCore

struct MaterialCardView: View {
    let card: MaterialCard
    let reading: Passage
    @State private var entityProfile: ResolvedEntityProfile?
    var body: some View {
        BibleReadingSurface {
            VStack(alignment: .leading, spacing: BibleTheme.Space.lg) {
                BibleSectionHeader(title: card.title, subtitle: card.relationship == "direct" ? "本文に直接関係する資料" : "関連する背景資料")
                if let url = card.publicDomainImageURL { PublicArtworkImage(url: url, title: card.title, id: card.id) }
                if card.mapLocation(reading: reading) != nil { NavigationLink("地図で概略位置を確認") { PlaceMapView(card: card, reading: reading) } }
                Text(card.summary).bibleTextStyle(.body).textSelection(.enabled)
                if let note = card.details["identityNote"].string { Text(note).bibleTextStyle(.caption).bibleForeground(.textSecondary) }
                if let name = card.details["modernName"].string { Text("現在の地名: \(name)").bibleTextStyle(.caption) }
                if let artist = card.details["artist"].string { Text(artist).bibleTextStyle(.caption) }
                if let year = card.details["yearLabel"].string { Text(year).bibleTextStyle(.caption) }
                if let collection = card.details["collection"].string { Text(collection).bibleTextStyle(.caption) }
                if let attribution = card.details["media"]["attribution"].string { Text(attribution).bibleTextStyle(.caption).bibleForeground(.textSecondary) }
                if let entityProfile {
                    NavigationLink(card.kind == "person" ? "この人物について" : "この場所について") { EntityProfileDetail(initial: entityProfile, passage: reading) }
                        .accessibilityIdentifier("entity-detail-" + card.id)
                }
                DisclosureGroup("出典と権利") {
                    VStack(alignment: .leading, spacing: BibleTheme.Space.md) {
                        if let statement = card.details["rightsStatement"].string { Text(statement).bibleTextStyle(.caption) }
                        ForEach(card.provenance) { source in
                            if let url = source.safeURL { Link(source.title, destination: url) }
                            Text("\(source.publisher) · \(source.license) · 情報を確認した日: \(source.checkedAt)").bibleTextStyle(.caption).bibleForeground(.textSecondary)
                            if let attribution = source.attribution { Text(attribution).bibleTextStyle(.caption) }
                            if let url = source.safeLicenseURL { Link("ライセンスを確認", destination: url) }
                        }
                    }
                }
            }
        }.task(id: card.id + reading.label) { entityProfile = try? await BundledEntityIndex.shared.profile(forMaterialCardID: card.id, passage: reading) }
    }
}
private struct PublicArtworkImage: View {
    let url: URL
    let title: String
    let id: String
    @State private var image: UIImage?
    @State private var failed = false
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit().accessibilityLabel(title).accessibilityIdentifier("artwork-image-" + (Bundle.main.bundleURL.pathExtension == "appex" ? "share-" : "main-") + id) }
            else if failed { Label("作品画像を表示できません。下の「出典と権利」から作品を確認できます。", systemImage: BibleTheme.Symbol.art).bibleTextStyle(.caption) }
            else { ProgressView("作品画像を読み込んでいます") }
        }
        .task(id: url) {
            image = nil; failed = false
            do {
                let data = try await PublicArtworkLoader.load(url)
                try Task.checkCancellation()
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1600, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { failed = true; return }
                let decoded = UIImage(cgImage: thumbnail)
                image = decoded
            } catch { if !Task.isCancelled { failed = true } }
        }
    }
}
