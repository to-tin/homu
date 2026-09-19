import CoreLocation
import Foundation
import MapKit

struct LocationSelection: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double

    init(id: String, name: String, latitude: Double, longitude: Double) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }

    init(mapItem: MKMapItem) {
        let coordinate = mapItem.placemark.coordinate
        let name = mapItem.name ?? "Unnamed location"

        self.init(
            id: Self.stableID(name: name, coordinate: coordinate),
            name: name,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private static func stableID(name: String, coordinate: CLLocationCoordinate2D) -> String {
        let normalizedName = name
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let latitude = (coordinate.latitude * 100_000).rounded() / 100_000
        let longitude = (coordinate.longitude * 100_000).rounded() / 100_000

        return "\(normalizedName)|\(latitude)|\(longitude)"
    }
}
