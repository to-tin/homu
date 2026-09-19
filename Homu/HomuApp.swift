import MapboxMaps
import SwiftUI

@main
struct HomuApp: App {
    @StateObject private var tripMonitor = TripMonitor()

    init() {
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
    }
}
