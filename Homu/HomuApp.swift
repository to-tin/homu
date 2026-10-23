import MapboxMaps
import SwiftUI

@main
struct HomuApp: App {
    @StateObject private var tripMonitor: TripMonitor
    @Environment(\.scenePhase) private var scenePhase

    init() {
        _tripMonitor = StateObject(
            wrappedValue: TripMonitor(arrivalHandler: try? TripArrivalHandler.live())
        )

        if let accessToken = Bundle.main.object(forInfoDictionaryKey: "MBXAccessToken") as? String,
           !accessToken.isEmpty {
            MapboxOptions.accessToken = accessToken
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(tripMonitor)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await tripMonitor.refreshTripState() }
        }
    }
}
