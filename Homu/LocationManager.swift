import Combine
import CoreLocation

@MainActor
protocol LocationProviding: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    var currentLocation: CLLocation? { get }
    var locationPublisher: AnyPublisher<CLLocation?, Never> { get }

    func requestAccess()
    func refreshLocation()
}

@MainActor
final class LocationManager: NSObject, ObservableObject, LocationProviding {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var currentLocation: CLLocation?

    private let manager: CLLocationManager

    var locationPublisher: AnyPublisher<CLLocation?, Never> {
        $currentLocation.eraseToAnyPublisher()
    }

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        authorizationStatus = manager.authorizationStatus
        currentLocation = nil

        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestAccess() {
        switch authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            refreshLocation()
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    func refreshLocation() {
        guard authorizationStatus == .authorizedAlways ||
            authorizationStatus == .authorizedWhenInUse else {
            return
        }

        manager.requestLocation()
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus

            if authorizationStatus == .authorizedAlways ||
                authorizationStatus == .authorizedWhenInUse {
                refreshLocation()
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }

        Task { @MainActor in
            currentLocation = location
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        // A later refresh can retry transient Core Location failures.
    }
}
