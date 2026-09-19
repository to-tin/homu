import SwiftUI
import MapboxMaps

@main
struct HomuApp: App {
    init() {
        MapboxOptions.accessToken = Secrets.mapboxAccessToken
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
