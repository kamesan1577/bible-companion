import SwiftUI
import MapKit
import CompanionCore

/// Supplements the reviewed material cards; it does not replace their cards or maps.
struct OfflineEntityPane: View {
    let passage: Passage
    let kind: String
    var ask: ((String) -> Void)? = nil
    var coveredMaterialCardIDs: [String] = []
    @State private var result: EntityIndexResult?
    @State private var includeFuture = false
    @State private var message: String?
    private var additions: [IndexedOccurrence] {
        result?.occurrences.filter { item in
            Set(item.profile?.profile.materialCardIDs ?? []).isDisjoint(with: coveredMaterialCardIDs)
        } ?? []
    }
    var body: some View {
        VStack(alignment: .leading, spacing: BibleTheme.Space.section) {
            if let result {
                if !additions.isEmpty {
                    BibleSectionHeader(title: coveredMaterialCardIDs.isEmpty ? (kind == "person" ? "この箇所に関係する人物" : "この箇所に関係する場所") : (kind == "person" ? "ほかの人物・関連する名前" : "ほかの場所"))
                }
                ForEach(additions) { item in
                    BibleReadingSurface {
                        VStack(alignment: .leading, spacing: BibleTheme.Space.lg) {
                            BibleSectionHeader(title: item.entity.displayName, subtitle: item.profile?.profile.subtitleJa ?? (item.directlyNamed ? "本文に名前が登場" : "この箇所の関連候補"))
                            if let profile = item.profile {
                                Text(profile.profile.summaryJa).bibleTextStyle(.body)
                                if profile.profile.coordinate?.count == 2 {
                                    NavigationLink("地図で概略位置を確認") { EntityProfileMap(resolved: profile, passage: passage) }
                                        .accessibilityIdentifier("entity-map-" + item.id)
                                }
                                NavigationLink(kind == "person" ? "この人物について" : "この場所について") { EntityProfileDetail(initial: profile, passage: passage) }
                                    .accessibilityIdentifier("entity-detail-" + item.id)
                            } else {
                                Text("この人物・場所の日本語の説明は、まだ収録していません。").bibleTextStyle(.body)
                                if let point = item.entity.coordinate, point.count == 2 {
                                    NavigationLink("現代の地図で候補地を見る") { UnreviewedIndexedPlaceMap(entity: item.entity) }
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
                    Text("KJVの節番号をもとにした人物・場所の参考一覧です。関連候補と本文に名前がある場合を区別しています。").bibleTextStyle(.caption)
                    Text(result.attribution).bibleTextStyle(.caption)
                    if let url = result.sourceURL { Link("Theographic Bible Metadata · CC BY-SA 4.0", destination: url) }
                }
            } else if let message { Text(message).bibleTextStyle(.body) }
            else { ProgressView("人物・場所の情報を準備しています") }
        }.task(id: passage.label + kind + String(includeFuture)) {
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
                BibleSectionHeader(title: value.profile.nameJa, subtitle: value.profile.subtitleJa)
                EntityProfileContent(resolved: value)
                Toggle("先の補足説明も見る", isOn: $includeFuture)
            }
        }.bibleCanvas().navigationTitle(initial.profile.nameJa).navigationBarTitleDisplayMode(.inline)
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
                BibleSectionHeader(title: resolved.profile.nameJa, subtitle: "地名の参考位置")
                Text("現代の地図に古代遺跡・地名の代表点を示しています。出来事が起きた正確な場所や、当時の道・海岸線・移動経路を示すものではありません。").bibleTextStyle(.body)
                if let point = resolved.profile.coordinate, point.count == 2 {
                    let coordinate = CLLocationCoordinate2D(latitude: point[0], longitude: point[1])
                    Map(initialPosition: .camera(MapCamera(centerCoordinate: coordinate, distance: 50_000)), interactionModes: [.pan, .zoom]) {
                        Marker("\(resolved.profile.nameJa)（概略位置）", coordinate: coordinate).tint(BibleTheme.color(.accent, scheme: scheme))
                    }
                    .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
                    .mapControls { MapScaleView() }
                    .aspectRatio(1, contentMode: .fit)
                    .accessibilityLabel("\(resolved.profile.nameJa)付近の概略地図。現代の地図上の代表位置です。")
                    NavigationLink("この場所について") { EntityProfileDetail(initial: resolved, passage: passage) }
                    if let note = resolved.profile.locationNoteJa { Text(note).bibleTextStyle(.body) }
                    Text("地図上の目安（参考地点）: 緯度 \(point[0].formatted(.number.precision(.fractionLength(5))))、経度 \(point[1].formatted(.number.precision(.fractionLength(5))))").bibleTextStyle(.caption)
                }
                Text("地図の背景には通信が必要な場合があります。現在地は取得していません。").bibleTextStyle(.caption).bibleForeground(.textSecondary)
                BibleSectionHeader(title: "位置情報の出典と権利")
                ForEach(resolved.sources) { source in
                    if let url = source.safeURL { Link(source.title, destination: url) }
                    Text(source.license + " · " + source.attribution).bibleTextStyle(.caption)
                    if let url = URL(string: source.licenseURL), url.scheme == "https" { Link("利用条件", destination: url) }
                }
            }
        }.bibleCanvas().navigationTitle("地図").navigationBarTitleDisplayMode(.inline)
    }
}
private struct UnreviewedIndexedPlaceMap: View {
    let entity: IndexedEntity
    var body: some View {
        VStack {
            if let position = entity.coordinate, position.count == 2 {
                let point = CLLocationCoordinate2D(latitude: position[0], longitude: position[1])
                Map(initialPosition: .camera(MapCamera(centerCoordinate: point, distance: 50000))) { Marker("\(entity.displayName)（同定候補）", coordinate: point).tint(.orange) }
                Text("現代の地図上の同定候補です。背景の地図には通信が必要です。").bibleTextStyle(.caption).padding()
            }
        }.navigationTitle(entity.displayName)
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
            if let wikipedia = resolved.profile.wikipedia, let url = wikipedia.safeURL {
                Link(wikipedia.labelJa, destination: url).accessibilityIdentifier("wikipedia-" + resolved.profile.id)
                Text(wikipedia.title).bibleTextStyle(.caption).bibleForeground(.textSecondary)
                if !wikipedia.noteJa.isEmpty { Text(wikipedia.noteJa).bibleTextStyle(.caption).bibleForeground(.textSecondary) }
                Text("外部記事には、この箇所より先の内容が含まれることがあります。").bibleTextStyle(.caption).bibleForeground(.textSecondary)
            }
            DisclosureGroup("この説明の出典") {
                Text("AIによる日本語編集。出典本文と照合していますが、専門家の校閲はありません。端末に保存した説明を表示しています。").bibleTextStyle(.caption)
                ForEach(resolved.sources) { source in
                    if let url = source.safeURL { Link(source.title, destination: url) }
                    Text(source.license + " · " + source.attribution).bibleTextStyle(.caption)
                    if let url = URL(string: source.licenseURL), url.scheme == "https" { Link("利用条件", destination: url) }
                }
                Text("出典の外部ページには、選んだ箇所より先の内容が含まれる場合があります。").bibleTextStyle(.caption)
                Text("資料上の識別ID: " + resolved.profile.id).bibleTextStyle(.caption)
            }
        }
    }
}
