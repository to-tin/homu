import CoreLocation
import MapboxMaps
import SwiftUI

private let tokyo = CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671)

struct ContentView: View {
    @State private var query = ""

    var body: some View {
        if hasMapboxAccessToken {
            map
        } else {
            missingTokenView
        }
    }

    private var hasMapboxAccessToken: Bool {
        guard let token = Bundle.main.object(forInfoDictionaryKey: "MBXAccessToken") as? String else {
            return false
        }

        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedToken.hasPrefix("pk.") && trimmedToken.count > 3
    }

    private var map: some View {
        Map(initialViewport: .camera(center: tokyo, zoom: 5))
        .mapStyle(.light)
        .ornamentOptions(OrnamentOptions(
            scaleBar: ScaleBarViewOptions(visibility: .hidden),
            attributionButton: AttributionButtonOptions(margins: CGPoint(x: -1000, y: -1000))
        ))
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            SearchBar(query: $query)
                .padding(.horizontal, 16)
                .padding(.top, 8)
        }
    }

    private var missingTokenView: some View {
        ContentUnavailableView {
            Label("Mapbox Token Required", systemImage: "map")
        } description: {
            Text("Add your public Mapbox token to Config/Local.xcconfig, then rebuild the app.")
        }
    }
}

private struct SearchBar: View {
    @Binding var query: String

    private var placeholder: String {
        Locale.current.language.languageCode?.identifier == "ja" ? "駅を検索" : "Search stations"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $query)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 10, y: 2)
    }
}
