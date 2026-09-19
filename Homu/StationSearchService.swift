import CoreLocation
import Foundation
import MapKit

protocol StationSearching: Sendable {
    func searchStations(
        query: String,
        near location: CLLocation?,
        limit: Int
    ) async throws -> [LocationSelection]
}

struct AppleMapsStationSearchService: StationSearching {
    private static let tokyoStation = CLLocation(
        latitude: 35.681236,
        longitude: 139.767125
    )

    /// Covers central Tokyo and the nearby wards where station suggestions are useful.
    /// `MKLocalSearch.Request.region` is only a ranking hint, so results are also
    /// filtered against this region before they are returned.
    private static let tokyoRegion = MKCoordinateRegion(
        center: tokyoStation.coordinate,
        span: MKCoordinateSpan(latitudeDelta: 0.65, longitudeDelta: 0.85)
    )

    func searchStations(
        query: String,
        near location: CLLocation?,
        limit: Int
    ) async throws -> [LocationSelection] {
        guard limit > 0 else { return [] }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestCenter = location.map { candidate in
            Self.tokyoRegion.contains(candidate.coordinate)
                ? candidate.coordinate
                : Self.tokyoStation.coordinate
        } ?? Self.tokyoStation.coordinate
        let distanceOrigin = location ?? Self.tokyoStation
        var seenIDs = Set<String>()
        var seenNames = Set<String>()
        var candidates: [Candidate] = []

        for region in searchRegions(query: trimmedQuery, center: requestCenter) {
            let response = try await search(query: trimmedQuery, region: region)
            try Task.checkCancellation()

            for mapItem in response.mapItems {
                guard Self.isTokyoRailStation(mapItem, matching: trimmedQuery) else { continue }

                let station = LocationSelection(mapItem: mapItem)
                let normalizedName = Self.normalized(station.name)
                guard !seenIDs.contains(station.id),
                      !seenNames.contains(normalizedName) else {
                    continue
                }
                seenIDs.insert(station.id)
                seenNames.insert(normalizedName)

                let stationLocation = CLLocation(
                    latitude: station.latitude,
                    longitude: station.longitude
                )
                candidates.append(
                    Candidate(
                        station: station,
                        distance: distanceOrigin.distance(from: stationLocation)
                    )
                )
            }

            if candidates.count >= limit {
                break
            }
        }

        return candidates
            .sorted { lhs, rhs in
                if lhs.distance == rhs.distance {
                    return lhs.station.name.localizedCaseInsensitiveCompare(rhs.station.name)
                        == .orderedAscending
                }
                return lhs.distance < rhs.distance
            }
            .prefix(limit)
            .map(\.station)
    }

    private func search(
        query: String,
        region: MKCoordinateRegion
    ) async throws -> MKLocalSearch.Response {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query.isEmpty ? "railway station" : query
        request.region = region
        request.resultTypes = .pointOfInterest
        request.pointOfInterestFilter = MKPointOfInterestFilter(
            including: [.publicTransport]
        )

        return try await MKLocalSearch(request: request).start()
    }

    private func searchRegions(
        query: String,
        center: CLLocationCoordinate2D
    ) -> [MKCoordinateRegion] {
        guard query.isEmpty else {
            return [MKCoordinateRegion(center: center, span: Self.tokyoRegion.span)]
        }

        // Start tightly around the user so MapKit's relevance-ranked response is
        // dominated by nearby stations, then expand only when fewer than requested
        // results were found.
        return [
            MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.10)
            ),
            MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: 0.20, longitudeDelta: 0.26)
            ),
            MKCoordinateRegion(center: center, span: Self.tokyoRegion.span)
        ]
    }

    private static func isTokyoRailStation(
        _ mapItem: MKMapItem,
        matching query: String
    ) -> Bool {
        guard mapItem.pointOfInterestCategory == .publicTransport else {
            return false
        }

        let coordinate = mapItem.placemark.coordinate
        guard CLLocationCoordinate2DIsValid(coordinate),
              tokyoRegion.contains(coordinate),
              let administrativeArea = mapItem.placemark.administrativeArea else {
            return false
        }

        let normalizedArea = administrativeArea
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        guard normalizedArea.contains("tokyo") || normalizedArea.contains("東京") else {
            return false
        }

        let normalizedQuery = normalized(query)
        let normalizedName = normalized(mapItem.name ?? "")
        guard normalizedQuery.isEmpty || normalizedName.contains(normalizedQuery) else {
            return false
        }

        let description = [mapItem.name, mapItem.placemark.title]
            .compactMap { $0 }
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        let railTerms = [
            "station", "railway", "subway", "metro", "tram",
            "駅", "역", "車站", "车站", "bahnhof", "gare", "estacion", "stazione"
        ]

        return railTerms.contains { description.contains($0) }
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

private struct Candidate {
    let station: LocationSelection
    let distance: CLLocationDistance
}

private extension MKCoordinateRegion {
    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let halfLatitudeDelta = span.latitudeDelta / 2
        let halfLongitudeDelta = span.longitudeDelta / 2

        return coordinate.latitude >= center.latitude - halfLatitudeDelta &&
            coordinate.latitude <= center.latitude + halfLatitudeDelta &&
            coordinate.longitude >= center.longitude - halfLongitudeDelta &&
            coordinate.longitude <= center.longitude + halfLongitudeDelta
    }
}
