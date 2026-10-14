import Foundation

public struct PlaceLocation: Sendable {
    public let latitude: Double
    public let longitude: Double
    public let explanation: String
    public let source: MaterialCard.Provenance
}
public extension MaterialCard {
    func mapLocation(reading: Passage) -> PlaceLocation? {
        guard kind == "place", isDisplayable(reading: reading), reading.isValid,
              passages.contains(where: { $0.isValid && $0.book == reading.book && $0.start <= reading.end && reading.start <= $0.end }),
              case .number(let latitude) = details["coordinates"]["latitude"],
              case .number(let longitude) = details["coordinates"]["longitude"],
              latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude), (-180...180).contains(longitude),
              details["coordinates"]["certainty"].string == "approximate",
              let sourceID = details["coordinates"]["sourceId"].string,
              let source = provenance.first(where: { $0.id == sourceID }), source.safeURL != nil,
              ["cc-by-3.0", "odbl-1.0", "public-domain"].contains(source.license),
              let explanation = details["coordinates"]["explanation"].string, !explanation.isEmpty, explanation.utf16.count <= 2000 else { return nil }
        let licensed = provenance.filter { ["cc-by-3.0", "odbl-1.0"].contains($0.license) }
        guard licensed.allSatisfy({ $0.safeLicenseURL != nil && !($0.attribution ?? "").isEmpty }) else { return nil }
        return PlaceLocation(latitude: latitude, longitude: longitude, explanation: explanation, source: source)
    }
}
