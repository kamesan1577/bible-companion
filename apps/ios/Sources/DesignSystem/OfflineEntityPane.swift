import SwiftUI
import MapKit
import os
import CompanionCore

/// Supplements the reviewed material cards; it does not replace their cards or maps.
struct OfflineEntityPane: View {
    let passage: Passage
    let kind: String
    var ask: ((String) -> Void)? = nil
    var coveredMaterialCardIDs: [String] = []
    var inlineDetails = false
    @State private var result: EntityIndexResult?
    @State private var includeFuture = false
    @State private var message: String?
    @State private var selectedMapID: String?
    private func toggleMap(_ id: String) {
        selectedMapID = selectedMapID == id ? nil : id
#if DEBUG
        Logger(subsystem: "org.example.BibleCompanion", category: "ShareMap").notice("Map selection changed: \(id, privacy: .public)")
#endif
    }
    private var hasPartialEntityCoverage: Bool { ["1CH", "2CH", "EZR", "NEH"].contains(passage.book) }
    private var additions: [IndexedOccurrence] {
        result?.occurrences.filter { item in
            Set(item.profile?.profile.materialCardIDs ?? []).isDisjoint(with: coveredMaterialCardIDs)
        } ?? []
    }
    var body: some View {
        VStack(alignment: .leading, spacing: BibleTheme.Space.section) {
            if let message, result != nil { Text(message).bibleTextStyle(.caption) }
            if let result {
                if hasPartialEntityCoverage {
                    Text(["EZR", "NEH"].contains(passage.book) ? "この書の人物・地名は、原文と照合したものから順に収録を進めています。説明が出ない名前も、未収録の場合があります。" : "この書の人物・地名は、一部を原文と照合して収録しています。説明が出ない名前も、未収録の場合があります。")
                        .bibleTextStyle(.caption).bibleForeground(.textSecondary)
                }
                if !additions.isEmpty {
                    BibleSectionHeader(title: coveredMaterialCardIDs.isEmpty ? (kind == "person" ? "この箇所に関係する人物・名前" : "この箇所に関係する場所") : (kind == "person" ? "ほかの人物・関連する名前" : "ほかの場所"))
                }
                if additions.isEmpty && coveredMaterialCardIDs.isEmpty {
                    Text(hasPartialEntityCoverage ? "この箇所の説明は、まだ収録していません。人物や地名が登場しないという意味ではありません。" : kind == "person" ? "この箇所に対応する人物の説明はありません。名前のない人物に、推測で名前を付けてはいません。" : "この箇所に対応する地名の説明はありません。同定できない場所には地図の印を置いていません。").bibleTextStyle(.body)
                }
                ForEach(additions) { item in
                    BibleReadingSurface {
                        VStack(alignment: .leading, spacing: BibleTheme.Space.lg) {
                            BibleSectionHeader(title: item.entity.displayName, subtitle: item.profile?.profile.subtitleJa ?? (item.directlyNamed ? "本文に名前が登場" : "この箇所の関連候補"))
                            if let profile = item.profile {
                                if inlineDetails {
                                    EntityProfileContent(resolved: profile).accessibilityIdentifier("entity-inline-detail-" + item.id)
                                    if profile.profile.coordinate?.count == 2 {
                                        Button(selectedMapID == item.id ? "地図を閉じる" : "地図で概略位置を確認") { toggleMap(item.id) }
                                            .buttonStyle(.bordered).frame(minHeight: BibleTheme.Layout.minimumTouchTarget)
                                        .accessibilityIdentifier("share-place-map-" + item.id)
                                        if selectedMapID == item.id { EntityProfileInlineMap(resolved: profile) }
                                    }
                                } else {
                                Text(profile.profile.summaryJa).bibleTextStyle(.body)
                                if profile.profile.coordinate?.count == 2 {
                                    NavigationLink("地図で概略位置を確認") { EntityProfileMap(resolved: profile, passage: passage) }
                                        .accessibilityIdentifier("entity-map-" + item.id)
                                }
                                NavigationLink(profile.profile.detailLinkLabelJa) { EntityProfileDetail(initial: profile, passage: passage) }
                                    .accessibilityIdentifier("entity-detail-" + item.id)
                                }
                            } else {
                                Text("この人物・場所の日本語の説明は、まだ収録していません。").bibleTextStyle(.body)
                                if let point = item.entity.coordinate, point.count == 2 {
                                    NavigationLink("現代の地図で候補地を見る") { UnreviewedIndexedPlaceMap(entity: item.entity, note: item.candidateMapNote ?? item.profile?.profile.locationNoteJa) }
                                }
                            }
                            if item.profile != nil, item.profile?.profile.coordinate == nil,
                               let point = item.entity.coordinate, point.count == 2 {
                                if inlineDetails {
                                    Button(selectedMapID == item.id ? "地図を閉じる" : "従来資料の候補位置を地図で見る") { toggleMap(item.id) }
                                        .buttonStyle(.bordered).frame(minHeight: BibleTheme.Layout.minimumTouchTarget)
                                        .accessibilityIdentifier("share-place-map-" + item.id)
                                    if selectedMapID == item.id { UnreviewedIndexedPlaceMap(entity: item.entity, inline: true, note: item.candidateMapNote ?? item.profile?.profile.locationNoteJa) }
                                } else {
                                    NavigationLink("従来資料の候補位置を地図で見る") { UnreviewedIndexedPlaceMap(entity: item.entity, note: item.candidateMapNote ?? item.profile?.profile.locationNoteJa) }
                                        .accessibilityIdentifier("entity-candidate-map-" + item.id)
                                }
                            }
                            if let ask { Button("この\(kind == "person" ? "人物" : "場所")について質問") { ask("\(item.entity.displayName)について、この箇所との関係をやさしく説明してください。") } }
                            if !item.sameBookVerses.isEmpty {
                                DisclosureGroup("同じ書の参照箇所") {
                                    ForEach(item.sameBookVerses.prefix(20), id: \.self) { reference in
                                        NavigationLink(reference.label) { ScrollView { OfflineEntityPane(passage: reference, kind: kind).padding() }.navigationTitle(reference.label).bibleCanvas() }
                                    }
                                }
                            }
                        }
                    }
                }
                Toggle("先の登場箇所も見る", isOn: $includeFuture)
                Text(includeFuture ? "この書の先の登場箇所と補足説明も表示しています。" : "選んだ箇所までの情報を表示しています。").bibleTextStyle(.caption).bibleForeground(.textSecondary)
                DisclosureGroup("一覧の出典と利用条件") {
                    Text(["ACT", "ROM", "LEV", "NUM", "JOS", "JDG", "RUT", "1SA", "2SA", "1KI", "2KI", "1CH", "2CH", "EZR", "NEH"].contains(passage.book) ? "WEB本文と照合した人物・場所の対応を表示します。名前の明記と、文脈上の指示を区別しています。" : "KJVの節番号をもとにした人物・場所の参考一覧です。関連候補と本文に名前がある場合を区別しています。").bibleTextStyle(.caption)
                    Text(result.attribution).bibleTextStyle(.caption)
                    if let url = result.sourceURL { Link("Theographic Bible Metadata · CC BY-SA 4.0", destination: url) }
                }
            } else if let message { Text(message).bibleTextStyle(.body) }
            else { ProgressView("人物・場所の情報を準備しています") }
        }
        // Share extensions have a smaller memory budget than the containing app.
        // Mount one interactive MapKit map only after an explicit selection, never a map per card.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            if selectedMapID != nil { selectedMapID = nil; message = "端末の空きメモリが少ないため地図を閉じました。場所の説明は引き続き読めます。" }
        }
        .task(id: passage.label + kind + String(includeFuture)) {
            do { result = try await BundledEntityIndex.shared.lookup(passage, kind: kind, includeFuture: includeFuture) }
            catch { message = "人物・場所の情報を表示できませんでした。" }
        }
    }
}

struct EntityProfileDetail: View {
    let initial: ResolvedEntityProfile
    let passage: Passage
    @State private var resolved: ResolvedEntityProfile?
    @State private var includeFuture = false
    private var value: ResolvedEntityProfile { resolved ?? initial }
    var body: some View {
        ScrollView {
            BibleReadingColumn {
                BibleSectionHeader(title: value.nameJa, subtitle: value.profile.subtitleJa)
                EntityProfileContent(resolved: value)
                Toggle("先の補足説明も見る", isOn: $includeFuture)
            }
        }.bibleCanvas().navigationTitle(initial.nameJa).navigationBarTitleDisplayMode(.inline)
        .task(id: String(includeFuture)) {
            if let result = try? await BundledEntityIndex.shared.lookup(passage, kind: initial.profile.kind, includeFuture: includeFuture) {
                resolved = result.occurrences.first(where: { $0.id == initial.profile.id })?.profile
            }
        }
    }
}

/// Uses the same MapKit presentation, scale, pan and zoom as the existing PlaceMapView.
struct EntityProfileMap: View {
    let resolved: ResolvedEntityProfile
    let passage: Passage
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ScrollView {
            BibleReadingColumn {
                BibleSectionHeader(title: resolved.nameJa, subtitle: "地名の参考位置")
                Text("現代の地図に古代遺跡・地名の代表点を示しています。出来事が起きた正確な場所や、当時の道・海岸線・移動経路を示すものではありません。").bibleTextStyle(.body)
                if let point = resolved.profile.coordinate, point.count == 2 {
                    let coordinate = CLLocationCoordinate2D(latitude: point[0], longitude: point[1])
                    Map(initialPosition: .camera(MapCamera(centerCoordinate: coordinate, distance: 50_000)), interactionModes: [.pan, .zoom]) {
                        Marker("\(resolved.nameJa)（概略位置）", coordinate: coordinate).tint(BibleTheme.color(.accent, scheme: scheme))
                    }
                    .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
                    .mapControls { MapScaleView() }
                    .aspectRatio(1, contentMode: .fit)
                    .accessibilityLabel("\(resolved.nameJa)付近の概略地図。現代の地図上の代表位置です。")
                    NavigationLink("この場所について") { EntityProfileDetail(initial: resolved, passage: passage) }
                    if let note = resolved.profile.locationNoteJa { Text(note).bibleTextStyle(.body) }
                    Text("地図上の目安（参考地点）: 緯度 \(point[0].formatted(.number.precision(.fractionLength(5))))、経度 \(point[1].formatted(.number.precision(.fractionLength(5))))").bibleTextStyle(.caption)
                }
                Text("地図の背景には通信が必要な場合があります。現在地は取得していません。").bibleTextStyle(.caption).bibleForeground(.textSecondary)
                BibleSectionHeader(title: "位置情報の出典と権利")
                ForEach(resolved.sources) { source in
                    if let url = source.safeURL { Link(source.readerTitle, destination: url) }
                    Text(source.license + " · " + source.readerAttribution).bibleTextStyle(.caption)
                    if let url = URL(string: source.licenseURL), url.scheme == "https" { Link("利用条件", destination: url) }
                }
            }
        }.bibleCanvas().navigationTitle("地図").navigationBarTitleDisplayMode(.inline)
    }
}
/// Share extensions show the stored explanation and map in their reading surface.
/// No containing-app launch or second navigation controller is needed.
struct EntityProfileInlineMap: View {
    let resolved: ResolvedEntityProfile
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        if let point = resolved.profile.coordinate, point.count == 2 {
            let coordinate = CLLocationCoordinate2D(latitude: point[0], longitude: point[1])
            Text("現代の地図上の代表位置です。出来事の正確な地点や古代の海岸線を示すものではありません。").bibleTextStyle(.caption)
            Map(initialPosition: .camera(MapCamera(centerCoordinate: coordinate, distance: 50_000)), interactionModes: [.pan, .zoom]) {
                Marker("\(resolved.nameJa)（概略位置）", coordinate: coordinate).tint(BibleTheme.color(.accent, scheme: scheme))
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
            .mapControls { MapScaleView() }
            .aspectRatio(1, contentMode: .fit)
            .accessibilityIdentifier("entity-inline-map-" + resolved.profile.id)
            .accessibilityLabel("\(resolved.nameJa)付近の概略地図。現代の地図上の代表位置です。")
            Text("地図の背景には通信が必要な場合があります。現在地は取得していません。").bibleTextStyle(.caption).bibleForeground(.textSecondary)
        }
    }
}

private struct UnreviewedIndexedPlaceMap: View {
    let entity: IndexedEntity
    var inline = false
    var note: String? = nil
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Group {
            if inline { content }
            else {
                ScrollView { BibleReadingColumn { content } }.bibleCanvas()
                    .navigationTitle(entity.displayName).navigationBarTitleDisplayMode(.inline)
            }
        }
    }
    private var content: some View {
        VStack(alignment: .leading, spacing: BibleTheme.Space.sm) {
            Text("従来資料の候補位置").bibleTextStyle(.heading)
            Text("Theographicの既存座標を保持しています。このアプリで独立に位置を確認した地点ではありません。地域・島・海の場合は範囲の目安であり、出来事の場所や境界を示しません。").bibleTextStyle(.caption)
            if let position = entity.coordinate, position.count == 2 {
                let point = CLLocationCoordinate2D(latitude: position[0], longitude: position[1])
                Map(initialPosition: .camera(MapCamera(centerCoordinate: point, distance: 50_000)), interactionModes: [.pan, .zoom]) {
                    Marker("\(entity.displayName)（資料上の候補位置）", coordinate: point).tint(BibleTheme.color(.accent, scheme: scheme))
                }
                .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
                .mapControls { MapScaleView() }
                .aspectRatio(1, contentMode: .fit)
                .accessibilityIdentifier("entity-candidate-map-content-" + entity.id)
            }
            if let note { Text(note).bibleTextStyle(.caption) }
            Text(entity.coordinateStatus == "source-verified-candidate" ? "元資料の状態: VERIFIED。アプリ側の独立照合とは区別しています。" : "元資料の状態: 未確認の座標候補。").bibleTextStyle(.caption)
            Link("Theographic Bible Metadata · CC BY-SA 4.0", destination: URL(string: "https://github.com/robertrouse/theographic-bible-metadata/tree/52e049efb3b95e4f1da52d11a3303fbd2d648922")!)
            Text("Robert Rouse and contributors。現在地は取得していません。背景地図には通信が必要な場合があります。").bibleTextStyle(.caption)
        }
    }
}

struct EntityProfileContent: View {
    let resolved: ResolvedEntityProfile
    var body: some View {
        VStack(alignment: .leading, spacing: BibleTheme.Space.sm) {
            Text(resolved.profile.summaryJa).bibleTextStyle(.body).textSelection(.enabled)
            if let modern = resolved.profile.modernLocationJa {
                Text("現在の場所").bibleTextStyle(.heading)
                Text(modern).bibleTextStyle(.body)
            }
            if let role = resolved.profile.historicalRoleJa {
                Text("当時の役割").bibleTextStyle(.heading)
                Text(role).bibleTextStyle(.body)
            }
            ForEach(Array(resolved.facts.enumerated()), id: \.offset) { _, fact in Text(fact.textJa).bibleTextStyle(.body) }
            if !resolved.profile.identityNoteJa.isEmpty {
                Text(resolved.profile.identityNoteJa).bibleTextStyle(.caption).bibleForeground(.textSecondary)
            }
            if let note = resolved.profile.locationNoteJa { Text(note).bibleTextStyle(.caption) }
            ForEach(resolved.contextNotes, id: \.self) { note in Text(note).bibleTextStyle(.body) }
            if let wikipedia = resolved.wikipedia, let url = wikipedia.safeURL {
                Link(wikipedia.labelJa, destination: url).accessibilityIdentifier("wikipedia-" + resolved.profile.id)
                Text(wikipedia.title).bibleTextStyle(.caption).bibleForeground(.textSecondary)
                if !wikipedia.noteJa.isEmpty { Text(wikipedia.noteJa).bibleTextStyle(.caption).bibleForeground(.textSecondary) }
                Text("外部記事には、この箇所より先の内容が含まれることがあります。").bibleTextStyle(.caption).bibleForeground(.textSecondary)
            }
            DisclosureGroup("この説明の出典") {
                Text("AIによる日本語編集。出典本文と照合していますが、専門家の校閲はありません。端末に保存した説明を表示しています。").bibleTextStyle(.caption)
                ForEach(["primary-text", "geographic-reference", "secondary-reference"], id: \.self) { category in
                    let items = resolved.sources.filter { ($0.category ?? "primary-text") == category }
                    if !items.isEmpty {
                        Text(category == "primary-text" ? "聖書本文の出典" : category == "geographic-reference" ? "地理資料" : "補助資料").bibleTextStyle(.heading)
                        ForEach(items) { source in
                            if let url = source.safeURL { Link(source.readerTitle, destination: url) }
                            Text(source.license + " · " + source.readerAttribution).bibleTextStyle(.caption)
                            if let url = URL(string: source.licenseURL), url.scheme == "https" { Link("利用条件", destination: url) }
                        }
                    }
                }
                Text("出典の外部ページには、選んだ箇所より先の内容が含まれる場合があります。").bibleTextStyle(.caption)
            }
        }
    }
}

// Snapshot identifiers remain in the bundled provenance; readers see the
// Bible edition, passage, attribution and license without internal build IDs.
private extension EntityProfileSource {
    var readerTitle: String { readerCitationText(title) }
    var readerAttribution: String { readerCitationText(attribution) }
    func readerCitationText(_ value: String) -> String {
        guard url.hasPrefix("https://ebible.org/engwebp/") else { return value }
        return value.replacingOccurrences(
            of: #"[,;]?\s*fixed witness\s+webp-usfx-[A-Za-z0-9-]+"#,
            with: "", options: .regularExpression)
    }
}
