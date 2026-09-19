import CoreLocation
import MapboxMaps
import SwiftUI

private let homuMapBackground = Color(red: 234.0 / 255.0, green: 242.0 / 255.0, blue: 251.0 / 255.0)
private let homuWaterBlue = Color(red: 169.0 / 255.0, green: 206.0 / 255.0, blue: 236.0 / 255.0)
private let homuPinRed = Color(red: 174.0 / 255.0, green: 88.0 / 255.0, blue: 84.0 / 255.0)

struct ContentView: View {
    @EnvironmentObject private var tripMonitor: TripMonitor
    @StateObject private var searchModel = StationSearchViewModel()
    @State private var isSearchActive = false
    @State private var pendingTripDestination: LocationSelection?
    @State private var viewport: Viewport = .followPuck(
        zoom: 13,
        bearing: .constant(0)
    )
    @State private var tripErrorMessage = ""
    @State private var isTripErrorPresented = false
    @FocusState private var searchFocused: Bool

    private var displayedTripDestination: LocationSelection? {
        tripMonitor.activeTrip?.destination ?? pendingTripDestination
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
                Map(viewport: $viewport) {
                    Puck2D(bearing: .heading)
                        .showsAccuracyRing(true)

                    if let destination = displayedTripDestination {
                        MapViewAnnotation(coordinate: destination.coordinate) {
                            SelectedDestinationPin(destinationName: destination.name)
                                .id(destination.id)
                        }
                        .allowOverlap(true)
                        .variableAnchors([
                            ViewAnnotationAnchorConfig(anchor: .bottom)
                        ])
                    }
                }
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
                if let destination = displayedTripDestination {
                    TripInProgressBanner(destinationName: destination.name)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    HStack(spacing: 8) {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                                .frame(width: 16, alignment: .leading)
                            ZStack(alignment: .leading) {
                                if searchModel.query.isEmpty && !searchFocused {
                                    Typewriter(sequences: ["Search stations", "駅を検索"])
                                        .foregroundStyle(.secondary)
                                        .allowsHitTesting(false)
                                }
                                TextField("", text: $searchModel.query)
                                    .textFieldStyle(.plain)
                                    .foregroundStyle(.secondary)
                                    .tint(.secondary)
                                    .focused($searchFocused)
                                    .disabled(!isSearchActive)
                                    .accessibilityLabel("Search stations")
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
                        ResultsList(
                            query: searchModel.query,
                            recentDestinations: searchModel.recentDestinations,
                            stations: searchModel.stationResults,
                            isUsingCurrentLocation: searchModel.isUsingCurrentLocation,
                            isLoading: searchModel.isLoading,
                            errorMessage: searchModel.errorMessage,
                            onPick: pick
                        )
                        .transition(.opacity)
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.88), value: isSearchActive)
        .animation(.spring(response: 0.45, dampingFraction: 0.9), value: displayedTripDestination?.id)
        .onAppear {
            searchModel.locationManager.requestAccess()
        }
        .onChange(of: searchModel.query) {
            searchModel.queryDidChange()
        }
        .alert("Unable to Start Trip", isPresented: $isTripErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(tripErrorMessage)
        }
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
        searchModel.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { searchFocused = true }
    }

    private func deactivate() {
        searchFocused = false
        isSearchActive = false
        searchModel.deactivate(clearQuery: true)
    }

    private func pick(_ station: LocationSelection) {
        searchFocused = false
        isSearchActive = false
        searchModel.select(station)
        searchModel.deactivate(clearQuery: false)
        pendingTripDestination = station

        Task {
            do {
                try await tripMonitor.startTrip(to: station)
                pendingTripDestination = nil
            } catch {
                pendingTripDestination = nil
                tripErrorMessage = error.localizedDescription
                isTripErrorPresented = true
            }
        }
    }
}

private struct TripInProgressBanner: View {
    let destinationName: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "tram.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(homuWaterBlue.opacity(0.55), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Trip In Progress")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(destinationName)
                    .font(.caption)
                    .foregroundStyle(.secondary.opacity(0.8))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(homuMapBackground.opacity(0.97), in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(homuWaterBlue.opacity(0.9), lineWidth: 1)
        }
        .shadow(
            color: homuWaterBlue.opacity(isPulsing ? 0.42 : 0.2),
            radius: isPulsing ? 12 : 7,
            y: 2
        )
        .scaleEffect(reduceMotion ? 1 : (isPulsing ? 1.008 : 0.995))
        .opacity(reduceMotion ? 1 : (isPulsing ? 1 : 0.94))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
        .onDisappear {
            isPulsing = false
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Trip in progress to \(destinationName)")
    }
}

private struct SelectedDestinationPin: View {
    let destinationName: String

    var body: some View {
        Image(systemName: "mappin.circle.fill")
            .font(.system(size: 34, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(homuPinRed, Color.white)
            .padding(8)
            .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            .accessibilityLabel("Selected station: \(destinationName)")
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
    let query: String
    let recentDestinations: [LocationSelection]
    let stations: [LocationSelection]
    let isUsingCurrentLocation: Bool
    let isLoading: Bool
    let errorMessage: String?
    let onPick: (LocationSelection) -> Void

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleStations: [LocationSelection] {
        stations
    }

    private var hasResults: Bool {
        let hasRecentDestinations = normalizedQuery.isEmpty && !recentDestinations.isEmpty
        return hasRecentDestinations || !visibleStations.isEmpty
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if normalizedQuery.isEmpty && !recentDestinations.isEmpty {
                    sectionHeader("Recent Destinations")
                    ForEach(recentDestinations) { destination in
                        resultRow(destination, systemImage: "clock.arrow.circlepath")
                    }
                }

                if !visibleStations.isEmpty {
                    sectionHeader(stationSectionTitle)
                    ForEach(visibleStations) { station in
                        resultRow(station, systemImage: "tram.fill")
                    }
                }

                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.vertical, 24)
                } else if let errorMessage, !hasResults {
                    statusMessage(errorMessage)
                } else if !hasResults {
                    statusMessage(normalizedQuery.isEmpty ? "No Tokyo stations found." : "No stations match your search.")
                }
            }
            .padding(.top, 12)
        }
    }

    private var stationSectionTitle: String {
        if normalizedQuery.isEmpty && isUsingCurrentLocation {
            return "Closest Tokyo Stations"
        }

        return "Tokyo Stations"
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    @ViewBuilder
    private func resultRow(_ destination: LocationSelection, systemImage: String) -> some View {
        Button {
            onPick(destination)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, alignment: .leading)
                Text(destination.name)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.leading, 30)
            .padding(.trailing, 20)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        Divider().padding(.leading, 56)
    }

    private func statusMessage(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
    }
}
