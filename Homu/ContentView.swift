import CoreLocation
import MapboxMaps
import SwiftUI

private let tokyo = CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671)

private let mockStations = [
    "Shibuya", "Shinjuku", "Tokyo", "Akihabara", "Ikebukuro",
    "Ueno", "Ginza", "Roppongi", "Harajuku", "Ebisu",
    "Meguro", "Nakano", "Kichijoji", "Asakusa", "Odaiba"
]

private let savedStations: Set<String> = ["Shibuya", "Tokyo", "Harajuku"]

struct ContentView: View {
    @State private var query = ""
    @State private var isSearchActive = false
    @FocusState private var searchFocused: Bool

    private var placeholder: String {
        Locale.current.language.languageCode?.identifier == "ja" ? "駅を検索" : "Search stations"
    }

    private var results: [String] {
        guard !query.isEmpty else { return [] }
        return mockStations.filter { $0.lowercased().contains(query.lowercased()) }
    }

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
        ZStack {
            MapReader { proxy in
                Map(initialViewport: .camera(center: tokyo, zoom: 5))
                    .mapStyle(.light)
                    .onStyleLoaded { _ in
                        guard let map = proxy.map else { return }
                        try? map.setLayerProperty(for: "background", property: "background-color", value: "#EAF2FB")
                        try? map.setLayerProperty(for: "water", property: "fill-color", value: "#A9CEEC")
                    }
                    .ornamentOptions(OrnamentOptions(
                        scaleBar: ScaleBarViewOptions(visibility: .hidden),
                        logo: LogoViewOptions(margins: CGPoint(x: -1000, y: -1000)),
                        attributionButton: AttributionButtonOptions(margins: CGPoint(x: -1000, y: -1000))
                    ))
                    .ignoresSafeArea()
            }

            if isSearchActive {
                Color.white.ignoresSafeArea().transition(.opacity)
            }

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .frame(width: 16, alignment: .leading)
                        ZStack(alignment: .leading) {
                            if query.isEmpty && !searchFocused {
                                Typewriter(sequences: ["Shibuya", "駅を検索", "Tokyo Station", "Harajuku"])
                                    .foregroundStyle(.secondary)
                                    .allowsHitTesting(false)
                            }
                            TextField("", text: $query)
                                .textFieldStyle(.plain)
                                .foregroundStyle(.secondary)
                                .tint(.secondary)
                                .focused($searchFocused)
                                .disabled(!isSearchActive)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.white, in: Capsule())
                    .overlay(
                        Capsule().strokeBorder(.primary.opacity(isSearchActive ? 0.08 : 0), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(isSearchActive ? 0 : 0.12), radius: 10, y: 2)
                    .contentShape(Capsule())
                    .onTapGesture { activate() }

                    if isSearchActive {
                        Button(action: deactivate) {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 36, height: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                if isSearchActive {
                    ResultsList(items: results, onPick: pick)
                        .transition(.opacity)
                }

                Spacer(minLength: 0)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.88), value: isSearchActive)
    }

    private var missingTokenView: some View {
        ContentUnavailableView {
            Label("Mapbox Token Required", systemImage: "map")
        } description: {
            Text("Add your public Mapbox token to Config/Local.xcconfig, then rebuild the app.")
        }
    }

    private func activate() {
        isSearchActive = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { searchFocused = true }
    }

    private func deactivate() {
        searchFocused = false
        query = ""
        isSearchActive = false
    }

    private func pick(_ station: String) {
        query = station
        deactivate()
    }
}

private struct Typewriter: View {
    let sequences: [String]
    var typingSpeed: Double = 0.06
    var deleteSpeed: Double = 0.03
    var pause: Double = 1.0

    @State private var displayed = ""
    @State private var cursorOn = true

    var body: some View {
        HStack(spacing: 2) {
            Text(displayed)
            Rectangle()
                .fill(.secondary)
                .frame(width: 2, height: 16)
                .opacity(cursorOn ? 1 : 0)
        }
        .task { await run() }
        .onAppear {
            withAnimation(.linear(duration: 0.5).repeatForever(autoreverses: true)) {
                cursorOn = false
            }
        }
    }

    private func run() async {
        var i = 0
        while !Task.isCancelled {
            let word = sequences[i % sequences.count]
            for c in word {
                displayed.append(c)
                try? await Task.sleep(nanoseconds: UInt64(typingSpeed * 1_000_000_000))
            }
            try? await Task.sleep(nanoseconds: UInt64(pause * 1_000_000_000))
            while !displayed.isEmpty {
                displayed.removeLast()
                try? await Task.sleep(nanoseconds: UInt64(deleteSpeed * 1_000_000_000))
            }
            i += 1
        }
    }
}

private struct ResultsList: View {
    let items: [String]
    let onPick: (String) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(items, id: \.self) { item in
                    Button {
                        onPick(item)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "bookmark.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                                .opacity(savedStations.contains(item) ? 1 : 0)
                                .frame(width: 16, alignment: .leading)
                            Text(item).foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.leading, 30)
                        .padding(.trailing, 20)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 56)
                }
            }
            .padding(.top, 12)
        }
    }
}
