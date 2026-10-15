import SwiftUI
import MapKit
import CompanionCore

struct OfflineEntityPane: View {
    let passage: Passage
    let kind: String
    var ask: ((String) -> Void)? = nil
    @State private var result: EntityIndexResult?
    @State private var includeFuture = false
    @State private var loading = false
    @State private var message: String?
    var body: some View {
        VStack(alignment: .leading, spacing: BibleTheme.Space.md) {
            if let result {
                Text(kind == "person" ? "登場人物・存在" : "この箇所の場所").bibleTextStyle(.heading)
                if kind == "place" { OfflineLocationPlot(entities: result.occurrences.map(\.entity)) }
                if result.occurrences.isEmpty {
                    Text(kind == "person" ? "この節には人物の索引がありません。章全体を選ぶと、周辺の登場人物を確認できます。" : "この節には場所の索引がありません。章全体を選ぶと、周辺の場所を確認できます。").bibleTextStyle(.body)
                }
                ForEach(result.occurrences) { item in
                    DisclosureGroup {
                        Text("索引ID: \(item.entity.id)").bibleTextStyle(.caption).textSelection(.enabled)
                        Text("同じ名前でも別の索引IDは別人・別地点として扱います。索引の関連だけでは、この節での本人特定や役割を断定できません。").bibleTextStyle(.caption).bibleForeground(.textSecondary)
                        if let ask { Button("この\(kind == "person" ? "人物" : "場所")について質問") { ask("\(item.entity.displayName)について、この箇所との関係をやさしく説明してください。") } }
                        if !item.sameBookVerses.isEmpty {
                            Text("同じ書のほかの登場箇所").bibleTextStyle(.caption)
                            Text(item.sameBookVerses.prefix(20).map(\.reference).joined(separator: "、")).bibleTextStyle(.body)
                            if item.sameBookVerses.count > 20 { Text("ほか\(item.sameBookVerses.count - 20)箇所").bibleTextStyle(.caption) }
                        }
                        if let coordinate = item.entity.coordinate, coordinate.count == 2 {
                            Text("同定候補 · 緯度\(coordinate[0].formatted(.number.precision(.fractionLength(3))))、経度\(coordinate[1].formatted(.number.precision(.fractionLength(3))))").bibleTextStyle(.caption)
                            NavigationLink("現代の地図で候補地を見る") { IndexedPlaceMap(entity: item.entity) }
                        }
                    } label: {
                        VStack(alignment: .leading) {
                            Text(item.entity.displayName).bibleTextStyle(.body)
                            if result.occurrences.filter({ $0.entity.displayName == item.entity.displayName }).count > 1 {
                                Text("同名を区別 · \(item.entity.id)").bibleTextStyle(.caption)
                            }
                            Text(item.directlyNamed ? "本文に名前が登場" : "この箇所に関連する\(kind == "person" ? "人物" : "場所")").bibleTextStyle(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Toggle("先の登場箇所も見る", isOn: $includeFuture)
                Text(includeFuture ? "同じ書の未読の箇所も表示しています。" : "ネタバレ防止：選んだ箇所までの登場箇所だけを表示します。").bibleTextStyle(.caption).foregroundStyle(.secondary)
                DisclosureGroup("索引の出典とライセンス") {
                    Text("英語KJVの節区分に基づく索引です。各訳との対応は未確認です。関連人物・場所は索引データ上の関連で、本文に名前がある場合と分けて表示します。日本語名がないものは英語名で表示します。").bibleTextStyle(.caption)
                    Text(result.attribution).bibleTextStyle(.caption)
                    if let url = result.sourceURL { Link("Theographic Bible Metadata · CC BY-SA 4.0", destination: url) }
                    Text("地理の位置は同定候補です。当時の正確な位置を保証するピンではありません。").bibleTextStyle(.caption)
                }
            } else if let message { Text(message) }
            else { ProgressView("索引を開いています") }
        }.task(id: passage.label + kind + String(includeFuture)) {
            loading = true; defer { loading = false }
            do { result = try await BundledEntityIndex.shared.lookup(passage, kind: kind, includeFuture: includeFuture) }
            catch { message = "索引を開けませんでした。アプリの更新を確認してください。" }
        }
    }
}
private struct OfflineLocationPlot: View {
    let entities: [IndexedEntity]
    private var located: [IndexedEntity] { entities.filter { $0.coordinate?.count == 2 } }
    var body: some View {
        if !located.isEmpty {
            GeometryReader { geometry in
                let latitudes = located.compactMap { $0.coordinate?.first }, longitudes = located.compactMap { $0.coordinate?.last }
                let minLat = (latitudes.min() ?? 0) - 0.2, maxLat = (latitudes.max() ?? 1) + 0.2
                let minLon = (longitudes.min() ?? 0) - 0.2, maxLon = (longitudes.max() ?? 1) + 0.2
                ZStack {
                    RoundedRectangle(cornerRadius: 18).fill(Color.secondary.opacity(0.07))
                    Text("N ↑").font(.caption).position(x: 28, y: 20)
                    ForEach(located) { entity in
                        if let coordinate = entity.coordinate {
                            VStack(spacing: 3) { Image(systemName: "mappin.circle.fill").foregroundStyle(.orange); Text(entity.displayName).font(.caption).lineLimit(1) }
                                .position(x: 45 + (coordinate[1] - minLon) / (maxLon - minLon) * max(1, geometry.size.width - 90), y: 40 + (maxLat - coordinate[0]) / (maxLat - minLat) * 130)
                        }
                    }
                    Text("候補地の位置図 · オフライン").font(.caption2).foregroundStyle(.secondary).position(x: geometry.size.width / 2, y: 200)
                }
            }.frame(height: 220).accessibilityLabel("同定候補地の相対位置。地図タイルは使わないオフライン位置図です。")
        }
    }
}
private struct IndexedPlaceMap: View {
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
