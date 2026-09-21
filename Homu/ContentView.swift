import CoreLocation
import MapboxMaps
import SwiftUI

private let homuMapBackground = Color(red: 234.0 / 255.0, green: 242.0 / 255.0, blue: 251.0 / 255.0)
private let homuWaterBlue = Color(red: 169.0 / 255.0, green: 206.0 / 255.0, blue: 236.0 / 255.0)
private let homuPinRed = Color(red: 179.0 / 255.0, green: 34.0 / 255.0, blue: 52.0 / 255.0)
private let homuGrey = Color(red: 142.0 / 255.0, green: 142.0 / 255.0, blue: 147.0 / 255.0)

struct ContentView: View {
    @EnvironmentObject private var tripMonitor: TripMonitor
    @StateObject private var searchModel = StationSearchViewModel()
    @State private var isSearchActive = false
    @State private var pendingTripDestination: LocationSelection?
    @State private var savedStations: [LocationSelection] = []
    @State private var showingSavedOnly = false
    private var savedStationIDs: Set<String> { Set(savedStations.map { String(describing: $0.id) }) }
    @State private var viewport: Viewport = .followPuck(
        zoom: 13,
        bearing: .constant(0)
    )
    @State private var tripErrorMessage = ""
    @State private var isTripErrorPresented = false
    @FocusState private var searchFocused: Bool

    private var displayedTripDestination: LocationSelection? {
        tripMonitor.tripPresentation?.destination ?? pendingTripDestination
    }

    private var displayedTripStatus: TripStatus {
        tripMonitor.tripPresentation?.status ?? .inProgress
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
                        .topImage(UIImage(named: "PuckTop"))
                        .bearingImage(UIImage(named: "PuckBearing"))
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
                        let waterLayers = map.allLayerIdentifiers.filter { $0.id.lowercased().contains("water") }
                        for layer in waterLayers {
                            try? map.setLayerProperty(for: layer.id, property: "fill-color", value: "#A9CEEC")
                            try? map.setLayerProperty(for: layer.id, property: "line-color", value: "#A9CEEC")
                        }
                        try? map.setStyleImportConfigProperty(for: "basemap", config: "colorWater", value: "#A9CEEC")
                    }
                    .ornamentOptions(OrnamentOptions(
                        scaleBar: ScaleBarViewOptions(visibility: .hidden),
                        compass: CompassViewOptions(visibility: .hidden),
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
                    let isArrived = displayedTripStatus == .arrived
                    let arrivedGreen = Color(red: 76.0 / 255.0, green: 175.0 / 255.0, blue: 80.0 / 255.0)
                    HStack(spacing: 8) {
                        HStack(spacing: 14) {
                            Group {
                                if isArrived {
                                    RingingBell()
                                } else {
                                    AnimatedTrain()
                                }
                            }
                                .foregroundColor(isArrived ? arrivedGreen : homuGrey)
                                .frame(width: 16, alignment: .leading)
                            Text(destination.name)
                                .foregroundColor(isArrived ? arrivedGreen : homuGrey)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color.white, in: Capsule())
                        .overlay(Capsule().strokeBorder(homuGrey.opacity(0.25), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 2)

                        if isArrived {
                            Button(action: cancelTrip) {
                                HStack(spacing: 6) {
                                    Text("Here!")
                                        .font(.system(size: 15, weight: .semibold))
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 18)
                                .frame(height: 44)
                                .background(arrivedGreen, in: Capsule())
                                .shadow(color: .black.opacity(0.12), radius: 10, y: 2)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button(action: cancelTrip) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(homuGrey)
                                    .frame(width: 44, height: 44)
                                    .background(Color.white, in: Circle())
                                    .shadow(color: .black.opacity(0.12), radius: 10, y: 2)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    HStack(spacing: 8) {
                        HStack(spacing: 14) {
                            Image("SearchGlass")
                                .renderingMode(.template)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .foregroundColor(homuGrey)
                                .frame(width: 18, height: 18)
                            ZStack(alignment: .leading) {
                                if searchModel.query.isEmpty && !searchFocused {
                                    Typewriter(sequences: [L10n.searchStations])
                                        .foregroundColor(homuGrey)
                                        .allowsHitTesting(false)
                                }
                                TextField("", text: $searchModel.query)
                                    .textFieldStyle(.plain)
                                    .foregroundColor(homuGrey)
                                    .tint(homuGrey)
                                    .focused($searchFocused)
                                    .disabled(!isSearchActive)
                                    .accessibilityLabel(L10n.searchStations)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color.white, in: Capsule())
                        .overlay(
                            Capsule().strokeBorder(homuGrey.opacity(0.25), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(isSearchActive ? 0.06 : 0.12), radius: 10, y: 2)
                        .contentShape(Capsule())
                        .onTapGesture { activate() }

                        if isSearchActive {
                            Button(action: deactivate) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(homuGrey)
                                    .frame(width: 36, height: 36)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                        } else {
                            Button(action: { showingSavedOnly = true; activate() }) {
                                Image("StarFill")
                                    .renderingMode(.template)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .foregroundColor(homuGrey)
                                    .frame(width: 18, height: 18)
                                    .frame(width: 44, height: 44)
                                    .background(Color.white, in: Circle())
                                    .shadow(color: .black.opacity(0.12), radius: 10, y: 2)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .transition(.opacity)
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
                            savedStations: savedStations,
                            savedIDs: savedStationIDs,
                            showSavedOnly: showingSavedOnly,
                            onPick: pick,
                            onToggleSave: { station in
                                let id = String(describing: station.id)
                                if let idx = savedStations.firstIndex(where: { String(describing: $0.id) == id }) {
                                    savedStations.remove(at: idx)
                                } else {
                                    savedStations.append(station)
                                }
                            }
                        )
                        .transition(.opacity)
                    }
                }

                Spacer(minLength: 0)
            }

            if !isSearchActive {
                VStack {
                    Spacer()

                    HStack {
                        Spacer()

                        Button(action: centerOnUser) {
                            ZStack {
                                Circle().fill(.white)
                                Image("NavArrow")
                                    .renderingMode(.template)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .foregroundColor(homuGrey)
                                    .frame(width: 18, height: 18)
                            }
                            .frame(width: 44, height: 44)
                            .shadow(color: .black.opacity(0.12), radius: 10, y: 2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.centerOnUserLocation)
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 18)
                }
                .transition(.opacity)
            }

        }
        .animation(.spring(response: 0.4, dampingFraction: 0.88), value: isSearchActive)
        .animation(.spring(response: 0.45, dampingFraction: 0.9), value: displayedTripDestination?.id)
        .animation(.easeInOut(duration: 0.25), value: tripMonitor.tripPresentation?.status)
        .onAppear {
            searchModel.locationManager.requestAccess()
        }
        .onChange(of: searchModel.query) {
            searchModel.queryDidChange()
            if !searchModel.query.isEmpty { showingSavedOnly = false }
        }
        .onChange(of: displayedTripDestination?.id) { previousDestinationID, destinationID in
            guard previousDestinationID != nil, destinationID == nil else { return }
            resetSearchInput()
        }
        .alert(L10n.unableToStartTrip, isPresented: $isTripErrorPresented) {
            Button(L10n.okay, role: .cancel) {}
        } message: {
            Text(tripErrorMessage)
        }
    }

    private var missingTokenView: some View {
        ContentUnavailableView {
            Label(L10n.mapboxTokenRequired, systemImage: "map")
        } description: {
            Text(L10n.mapboxTokenInstructions)
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
        showingSavedOnly = false
        searchModel.deactivate(clearQuery: true)
    }

    private func cancelTrip() {
        let cancellationHandler = TripCancellationHandler(tripMonitor: tripMonitor)
        cancellationHandler.cancelTrip()
        pendingTripDestination = nil
        resetSearchInput()
    }

    private func centerOnUser() {
        searchModel.locationManager.requestAccess()
        withViewportAnimation(.default(maxDuration: 1)) {
            viewport = .followPuck(
                zoom: 13,
                bearing: .constant(0)
            )
        }
    }

    private func resetSearchInput() {
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

private struct TripStatusBanner: View {
    let destinationName: String
    let status: TripStatus

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    private var statusText: String {
        switch status {
        case .inProgress:
            L10n.tripInProgress
        case .near:
            L10n.stationApproachingTitle
        case .arrived:
            L10n.arrivedTitle
        }
    }

    private var statusSymbol: String {
        switch status {
        case .inProgress:
            "tram.fill"
        case .near:
            "location.fill"
        case .arrived:
            "checkmark"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: statusSymbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(homuGrey)
                .frame(width: 32, height: 32)
                .background(homuWaterBlue.opacity(0.55), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(statusText)
                    .font(.headline)
                    .foregroundColor(homuGrey)
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
        .accessibilityLabel("\(statusText), \(destinationName)")
    }
}

private struct AnimatedTrain: View {
    @State private var offset: CGFloat = -2

    var body: some View {
        Image(systemName: "tram.fill")
            .offset(x: offset)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    offset = 2
                }
            }
    }
}

private struct RingingBell: View {
    @State private var angle: Double = -14

    var body: some View {
        Image(systemName: "bell.fill")
            .rotationEffect(.degrees(angle), anchor: .top)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.18).repeatForever(autoreverses: true)) {
                    angle = 14
                }
            }
    }
}

private struct PhosphorNavArrow: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.95, y: h * 0.05))
        p.addLine(to: CGPoint(x: w * 0.05, y: h * 0.40))
        p.addLine(to: CGPoint(x: w * 0.48, y: h * 0.56))
        p.addLine(to: CGPoint(x: w * 0.66, y: h * 0.95))
        p.closeSubpath()
        return p
    }
}

private struct TablerPin: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let r = w / 2
        let cx = w / 2
        let cy = r
        var p = Path()
        p.move(to: CGPoint(x: cx, y: 0))
        p.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                 startAngle: .degrees(-90), endAngle: .degrees(-180),
                 clockwise: true)
        p.addQuadCurve(to: CGPoint(x: cx, y: h),
                       control: CGPoint(x: cx - r * 0.25, y: h * 0.88))
        p.addQuadCurve(to: CGPoint(x: w, y: cy),
                       control: CGPoint(x: cx + r * 0.25, y: h * 0.88))
        p.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                 startAngle: .degrees(0), endAngle: .degrees(-90),
                 clockwise: true)
        p.closeSubpath()
        return p
    }
}

private struct SelectedDestinationPin: View {
    let destinationName: String

    var body: some View {
        Image("DestinationPin")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 32, height: 42)
            .accessibilityLabel(L10n.selectedStation(destinationName))
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
    let savedStations: [LocationSelection]
    let savedIDs: Set<String>
    let showSavedOnly: Bool
    let onPick: (LocationSelection) -> Void
    let onToggleSave: (LocationSelection) -> Void

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
            VStack(alignment: .leading, spacing: 0) {
                if showSavedOnly && normalizedQuery.isEmpty {
                    if !savedStations.isEmpty {
                        sectionHeader("Saved")
                        ForEach(savedStations) { destination in
                            resultRow(destination, systemImage: "tram.fill")
                        }
                    } else {
                        statusMessage("No saved stations yet")
                    }
                } else {
                if normalizedQuery.isEmpty && !recentDestinations.isEmpty {
                    sectionHeader(L10n.recentDestinations)
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
                    statusMessage(normalizedQuery.isEmpty ? L10n.noTokyoStations : L10n.noMatchingStations)
                }
                }
            }
            .padding(.top, 12)
        }
    }

    private var stationSectionTitle: String {
        if normalizedQuery.isEmpty && isUsingCurrentLocation {
            return L10n.closestTokyoStations
        }

        return L10n.tokyoStations
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundColor(homuGrey)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    @ViewBuilder
    private func resultRow(_ destination: LocationSelection, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Button {
                onPick(destination)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .font(.system(size: 14))
                        .foregroundColor(homuGrey)
                        .frame(width: 16, alignment: .leading)
                    Text(destination.name)
                        .foregroundColor(homuGrey)
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: { onToggleSave(destination) }) {
                let isSaved = savedIDs.contains(String(describing: destination.id))
                Image(isSaved ? "StarFill" : "StarOutline")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(isSaved ? Color(red: 1.0, green: 0.78, blue: 0.0) : homuGrey.opacity(0.4))
                    .frame(width: 18, height: 18)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 34)
        .padding(.trailing, 20)
        .padding(.vertical, 14)
        Rectangle()
            .fill(homuGrey.opacity(0.12))
            .frame(height: 0.33)
            .padding(.leading, 60)
            .padding(.trailing, 58)
    }

    private func statusMessage(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundColor(homuGrey)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
    }
}
