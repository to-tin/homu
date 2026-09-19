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

enum TripStatus: Equatable, Sendable {
    case inProgress
    case near
    case arrived
}

struct TripPresentation: Sendable {
    let tripID: UUID
    let destination: LocationSelection
    let status: TripStatus
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
    @Published private(set) var tripPresentation: TripPresentation?

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
    private let arrivalHandler: TripArrivalHandler?
    private var completingTripID: UUID?
    private var arrivalBannerTask: Task<Void, Never>?

    init(
        locationManager: CLLocationManager = CLLocationManager(),
        notificationCenter: UNUserNotificationCenter = .current(),
        defaults: UserDefaults = .standard,
        arrivalHandler: TripArrivalHandler? = nil
    ) {
        self.locationManager = locationManager
        self.notificationCenter = notificationCenter
        self.defaults = defaults
        self.arrivalHandler = arrivalHandler

        let restoredTrip = defaults.data(forKey: Self.persistedTripKey).flatMap {
            try? JSONDecoder().decode(ActiveTrip.self, from: $0)
        }
        activeTrip = restoredTrip

        if let restoredTrip {
            tripPresentation = TripPresentation(
                tripID: restoredTrip.id,
                destination: restoredTrip.destination,
                status: .inProgress
            )
        }

        super.init()
        locationManager.delegate = self
        notificationCenter.delegate = self

        if let activeTrip {
            startProximityMonitoring(for: activeTrip)
        }
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
        arrivalBannerTask?.cancel()

        let trip = ActiveTrip(id: UUID(), destination: destination, startedAt: .now)
        activeTrip = trip
        tripPresentation = TripPresentation(
            tripID: trip.id,
            destination: trip.destination,
            status: .inProgress
        )
        persist(trip)

        do {
            try await scheduleNotifications(for: trip)
            startProximityMonitoring(for: trip)
        } catch {
            endTrip()
            throw error
        }
    }

    @discardableResult
    func endTrip() -> Bool {
        guard let trip = activeTrip else { return false }

        finishTrip(
            trip,
            preservingArrivalNotification: false,
            preservingPresentation: false
        )
        return true
    }

    private func finishTrip(
        _ trip: ActiveTrip,
        preservingArrivalNotification: Bool,
        preservingPresentation: Bool
    ) {
        stopProximityMonitoring(for: trip)

        let proximities: [Proximity] = preservingArrivalNotification ? [.near] : Proximity.allCases
        let notificationIdentifiers = proximities.map { notificationID(for: $0, tripID: trip.id) }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: notificationIdentifiers)
        notificationCenter.removeDeliveredNotifications(withIdentifiers: notificationIdentifiers)
        defaults.removeObject(forKey: Self.persistedTripKey)
        activeTrip = nil
        completingTripID = nil

        if !preservingPresentation {
            arrivalBannerTask?.cancel()
            tripPresentation = nil
        }
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

    private func monitoringID(for proximity: Proximity, tripID: UUID) -> String {
        "trip.\(tripID.uuidString).monitor.\(proximity.rawValue)"
    }

    private func monitoringRegion(for proximity: Proximity, trip: ActiveTrip) -> CLCircularRegion {
        let region = CLCircularRegion(
            center: trip.destination.coordinate,
            radius: proximity.radius,
            identifier: monitoringID(for: proximity, tripID: trip.id)
        )
        region.notifyOnEntry = true
        region.notifyOnExit = false
        return region
    }

    private func startProximityMonitoring(for trip: ActiveTrip) {
        for proximity in Proximity.allCases {
            locationManager.startMonitoring(for: monitoringRegion(for: proximity, trip: trip))
        }
    }

    private func stopProximityMonitoring(for trip: ActiveTrip) {
        for proximity in Proximity.allCases {
            locationManager.stopMonitoring(for: monitoringRegion(for: proximity, trip: trip))
        }
    }

    private func markTripAsNearIfActive() {
        guard let trip = activeTrip,
              tripPresentation?.status != .arrived else {
            return
        }

        tripPresentation = TripPresentation(
            tripID: trip.id,
            destination: trip.destination,
            status: .near
        )
    }

    private func handleNotification(identifier: String) async {
        guard let trip = activeTrip else { return }

        if identifier == notificationID(for: .near, tripID: trip.id) {
            markTripAsNearIfActive()
        } else if identifier == notificationID(for: .arrived, tripID: trip.id) {
            await completeTripIfArrived()
        }
    }

    private func completeTripIfArrived() async {
        guard let trip = activeTrip,
              completingTripID != trip.id else {
            return
        }

        completingTripID = trip.id

        if let arrivalHandler {
            _ = try? await arrivalHandler.didArrive(at: trip.destination)
        }

        guard activeTrip?.id == trip.id else { return }
        tripPresentation = TripPresentation(
            tripID: trip.id,
            destination: trip.destination,
            status: .arrived
        )
        finishTrip(
            trip,
            preservingArrivalNotification: true,
            preservingPresentation: true
        )
        scheduleArrivalBannerDismissal(for: trip.id)
    }

    private func scheduleArrivalBannerDismissal(for tripID: UUID) {
        arrivalBannerTask?.cancel()
        arrivalBannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled,
                  let self,
                  self.tripPresentation?.tripID == tripID,
                  self.tripPresentation?.status == .arrived else {
                return
            }

            self.tripPresentation = nil
        }
    }

    private func persist(_ trip: ActiveTrip) {
        guard let data = try? JSONEncoder().encode(trip) else { return }
        defaults.set(data, forKey: Self.persistedTripKey)
    }
}

extension TripMonitor: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedAlways:
                if let activeTrip {
                    startProximityMonitoring(for: activeTrip)
                }
            case .denied, .restricted:
                endTrip()
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        Task { @MainActor in
            guard let activeTrip else { return }

            if region.identifier == monitoringID(for: .near, tripID: activeTrip.id) {
                markTripAsNearIfActive()
            } else if region.identifier == monitoringID(for: .arrived, tripID: activeTrip.id) {
                await completeTripIfArrived()
            }
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
                await handleNotification(identifier: notification.request.identifier)
            }
        }

        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            await handleNotification(identifier: response.notification.request.identifier)
            completionHandler()
        }
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
