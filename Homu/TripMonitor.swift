import Combine
import CoreLocation
import Foundation
import UIKit
import UserNotifications

private let tripNotificationCategory = "TRIP_PROGRESS"

struct ActiveTrip: Codable, Identifiable, Sendable {
    let id: UUID
    let destination: LocationSelection
    let startedAt: Date
}

@MainActor
protocol TripMonitoring: AnyObject {
    var activeTrip: ActiveTrip? { get }

    func startTrip(to destination: LocationSelection) async throws

    @discardableResult
    func endTrip() -> Bool
}

@MainActor
struct TripCancellationHandler {
    private let tripMonitor: any TripMonitoring

    init(tripMonitor: any TripMonitoring) {
        self.tripMonitor = tripMonitor
    }

    /// The future cancel button can invoke this method directly.
    @discardableResult
    func cancelTrip() -> Bool {
        tripMonitor.endTrip()
    }
}

@MainActor
final class TripMonitor: NSObject, ObservableObject, TripMonitoring {
    @Published private(set) var activeTrip: ActiveTrip?

    private enum Proximity: String, CaseIterable {
        case near
        case arrived

        var radius: CLLocationDistance {
            switch self {
            case .near: 1_000
            case .arrived: 150
            }
        }
    }

    private static let persistedTripKey = "active-trip"
    private let locationManager: CLLocationManager
    private let notificationCenter: UNUserNotificationCenter
    private let defaults: UserDefaults

    init(
        locationManager: CLLocationManager = CLLocationManager(),
        notificationCenter: UNUserNotificationCenter = .current(),
        defaults: UserDefaults = .standard
    ) {
        self.locationManager = locationManager
        self.notificationCenter = notificationCenter
        self.defaults = defaults

        if let data = defaults.data(forKey: Self.persistedTripKey) {
            activeTrip = try? JSONDecoder().decode(ActiveTrip.self, from: data)
        }

        super.init()
        locationManager.delegate = self
        notificationCenter.delegate = self
    }

    func startTrip(to destination: LocationSelection) async throws {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            throw TripMonitorError.regionMonitoringUnavailable
        }

        let notificationAccess = try await notificationCenter.requestAuthorization(
            options: [.alert, .sound]
        )
        guard notificationAccess else {
            throw TripMonitorError.notificationPermissionDenied
        }

        switch locationManager.authorizationStatus {
        case .denied, .restricted:
            throw TripMonitorError.locationPermissionDenied
        case .notDetermined, .authorizedWhenInUse:
            locationManager.requestAlwaysAuthorization()
        case .authorizedAlways:
            break
        @unknown default:
            throw TripMonitorError.locationPermissionDenied
        }

        endTrip()

        let trip = ActiveTrip(id: UUID(), destination: destination, startedAt: .now)
        activeTrip = trip
        persist(trip)

        do {
            try await scheduleNotifications(for: trip)
        } catch {
            endTrip()
            throw error
        }
    }

    @discardableResult
    func endTrip() -> Bool {
        guard let trip = activeTrip else { return false }

        let identifiers = Proximity.allCases.map { notificationID(for: $0, tripID: trip.id) }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
        notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiers)
        defaults.removeObject(forKey: Self.persistedTripKey)
        activeTrip = nil
        return true
    }

    private func scheduleNotifications(for trip: ActiveTrip) async throws {
        for proximity in Proximity.allCases {
            let region = CLCircularRegion(
                center: trip.destination.coordinate,
                radius: proximity.radius,
                identifier: notificationID(for: proximity, tripID: trip.id)
            )
            region.notifyOnEntry = true
            region.notifyOnExit = false

            let content = UNMutableNotificationContent()
            content.categoryIdentifier = tripNotificationCategory
            content.sound = .default
            content.threadIdentifier = "active-trip"

            switch proximity {
            case .near:
                content.title = L10n.stationApproachingTitle
                content.body = L10n.stationIsNear(trip.destination.name)
            case .arrived:
                content.title = L10n.arrivedTitle
                content.body = L10n.arrived(at: trip.destination.name)
            }

            let request = UNNotificationRequest(
                identifier: region.identifier,
                content: content,
                trigger: UNLocationNotificationTrigger(region: region, repeats: false)
            )
            try await notificationCenter.add(request)
        }
    }

    private func notificationID(for proximity: Proximity, tripID: UUID) -> String {
        "trip.\(tripID.uuidString).\(proximity.rawValue)"
    }

    private func persist(_ trip: ActiveTrip) {
        guard let data = try? JSONEncoder().encode(trip) else { return }
        defaults.set(data, forKey: Self.persistedTripKey)
    }
}

extension TripMonitor: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus == .denied ||
                manager.authorizationStatus == .restricted else {
            return
        }

        Task { @MainActor in
            endTrip()
        }
    }
}

extension TripMonitor: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let isTripNotification = notification.request.content.categoryIdentifier == tripNotificationCategory

        if isTripNotification {
            Task { @MainActor in
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }

        completionHandler([.banner, .sound])
    }
}

enum TripMonitorError: LocalizedError {
    case locationPermissionDenied
    case notificationPermissionDenied
    case regionMonitoringUnavailable

    var errorDescription: String? {
        switch self {
        case .locationPermissionDenied:
            L10n.alwaysOnLocationRequired
        case .notificationPermissionDenied:
            L10n.notificationAccessRequired
        case .regionMonitoringUnavailable:
            L10n.locationAlertsUnavailable
        }
    }
}
