import Foundation

enum L10n {
    static let searchStations = String(localized: "Search stations")
    static let cancelTrip = String(localized: "Cancel trip")
    static let centerOnUserLocation = String(localized: "Center on your location")
    static let unableToStartTrip = String(localized: "Unable to Start Trip")
    static let okay = String(localized: "OK")
    static let mapboxTokenRequired = String(localized: "Mapbox Token Required")
    static let mapboxTokenInstructions = String(
        localized: "Add your public Mapbox token to Config/Local.xcconfig, then rebuild the app."
    )
    static let tripInProgress = String(localized: "Trip In Progress")
    static let recentDestinations = String(localized: "Recent Destinations")
    static let closestTokyoStations = String(localized: "Stations")
    static let tokyoStations = String(localized: "Stations")
    static let noTokyoStations = String(localized: "No Tokyo stations found.")
    static let noMatchingStations = String(localized: "No stations match your search.")
    static let destinationSaveFailed = String(localized: "The destination could not be saved.")
    static let recentDestinationsUnavailable = String(localized: "Recent destinations are unavailable.")
    static let tokyoStationsLoadFailed = String(localized: "Couldn't load stations.")
    static let stationApproachingTitle = String(localized: "Your station is coming up")
    static let arrivedTitle = String(localized: "You've arrived")
    static let alwaysOnLocationRequired = String(
        localized: "Always-on location access is required for trip notifications."
    )
    static let notificationAccessRequired = String(
        localized: "Notification access is required for trip alerts."
    )
    static let locationAlertsUnavailable = String(
        localized: "Location-based trip alerts aren't available on this device."
    )
    static let invalidLocationData = String(
        localized: "The location usage database contains invalid data."
    )

    static func tripInProgress(to destination: String) -> String {
        format(String(localized: "Trip in progress to %@"), destination)
    }

    static func selectedStation(_ station: String) -> String {
        format(String(localized: "Selected station: %@"), station)
    }

    static func stationIsNear(_ station: String) -> String {
        format(String(localized: "You're near %@."), station)
    }

    static func arrived(at station: String) -> String {
        format(String(localized: "You're at %@."), station)
    }

    static func unableToOpenLocationDatabase(_ message: String) -> String {
        format(String(localized: "Unable to open the location usage database: %@"), message)
    }

    static func locationDatabaseQueryFailed(_ message: String) -> String {
        format(String(localized: "The location usage database query failed: %@"), message)
    }

    private static func format(_ format: String, _ value: String) -> String {
        String(format: format, locale: .current, value)
    }
}
