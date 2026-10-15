import SwiftUI
import MapKit
import CompanionCore

struct PlaceMapView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.colorScheme) private var colorScheme
    let cardID: String
    let reading: Passage
    private var currentCard: MaterialCard? {
        guard store.selectedPassage == reading, store.cachedSnapshot == nil else { return nil }
        return store.reading?.places.first { $0.id == cardID && $0.isDisplayable(reading: reading) }
    }
    var body: some View {
        ScrollView {
            BibleReadingColumn {
                if let card = currentCard, let location = card.mapLocation(reading: reading) {
                    BibleSectionHeader(title: card.title, subtitle: "地名の参考位置")
                    Text("現代の地図に古代遺跡・地名の代表点を示しています。出来事が起きた正確な場所や、当時の道・海岸線・移動経路を示すものではありません。").bibleTextStyle(.body)
                    let coordinate = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
                    Map(initialPosition: .camera(MapCamera(centerCoordinate: coordinate, distance: 50_000)), interactionModes: [.pan, .zoom]) {
                        Marker("\(card.title)（概略位置）", coordinate: coordinate)
                            .tint(BibleTheme.color(.accent, scheme: colorScheme))
                    }
                    .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
                    .mapControls { MapScaleView() }
                    .aspectRatio(1, contentMode: .fit)
                    .accessibilityLabel("\(card.title)付近の概略地図。現代の地図上の代表位置です。")
                    Text(location.explanation).bibleTextStyle(.body)
                    Text("地図上の目安（参考地点）: 緯度 \(location.latitude.formatted(.number.precision(.fractionLength(5))))、経度 \(location.longitude.formatted(.number.precision(.fractionLength(5))))").bibleTextStyle(.caption)
                    Text(card.summary).bibleTextStyle(.body).textSelection(.enabled)
                    if let modernName = card.details["modernName"].string { Text("現在の地名: \(modernName)").bibleTextStyle(.caption) }
                    Text("地図の背景には通信が必要な場合があります。表示されない場合も、この説明・地図上の目安・出典を確認できます。現在地は取得していません。").bibleTextStyle(.caption).bibleForeground(.textSecondary)
                    BibleSectionHeader(title: "位置情報の出典と権利")
                    ForEach(card.provenance) { source in
                        if let url = source.safeURL { Link(source.title, destination: url) }
                        if let attribution = source.attribution { Text(attribution).bibleTextStyle(.caption) }
                        if let url = source.safeLicenseURL { Link("ライセンス: \(source.license)", destination: url) }
                        else { Text(source.license).bibleTextStyle(.caption) }
                    }
                } else {
                    BibleStateView(title: "この箇所の地図を表示できません", message: "この箇所に結びつく場所の説明が見つかりません。読書画面に戻り、資料をもう一度開いてください。", systemImage: BibleTheme.Symbol.map)
                }
            }
        }
        .bibleCanvas().navigationTitle("地図").navigationBarTitleDisplayMode(.inline)
    }
}
