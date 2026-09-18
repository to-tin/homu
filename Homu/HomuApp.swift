import SwiftUI

@main
struct HomuApp: App {
    @StateObject private var tripMonitor = TripMonitor()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(tripMonitor)
        }
    }
}
