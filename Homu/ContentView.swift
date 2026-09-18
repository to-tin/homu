import CoreLocation
import MapKit
import SwiftUI

struct ContentView: View {
    @StateObject private var locationManager = LocationManager()
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)

    var body: some View {
        Map(position: $cameraPosition) {
            UserAnnotation()
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .mapStyle(.standard(elevation: .realistic))
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            if locationManager.authorizationStatus == .denied ||
                locationManager.authorizationStatus == .restricted {
                permissionMessage
            }
        }
        .task {
            locationManager.requestAccess()
        }
    }

    private var permissionMessage: some View {
        Text("Location access is off. Enable it in Settings to see your position on the map.")
            .font(.callout)
            .multilineTextAlignment(.center)
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding()
    }
}
