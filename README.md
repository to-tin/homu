# Homu

A minimal SwiftUI iOS app that opens to an Apple Map and displays the user's current location.

## Requirements

- Xcode 16 or later
- iOS 17 or later

## Run the app

1. Open `Homu.xcodeproj` in Xcode.
2. Create `Config/Local.xcconfig` and add `MAPBOX_ACCESS_TOKEN = YOUR_PUBLIC_MAPBOX_TOKEN`.
3. Replace `YOUR_PUBLIC_MAPBOX_TOKEN` with a public Mapbox token beginning with `pk.`. Never put a secret token beginning with `sk.` in an iOS app.
4. Select the `Homu` scheme and an iPhone simulator or connected device.
5. Choose your development team under **Signing & Capabilities** if running on a device.
6. Build and run, then allow location access when prompted.

`Config/Local.xcconfig` is ignored by Git so the token stays on your machine. `Base.xcconfig` imports it when present and leaves the token empty otherwise.

To test a location in Simulator, choose **Features > Location** and select a preset or enter a custom location.

## Location architecture

`LocationManager` implements the `LocationProviding` protocol and publishes the latest one-shot location. Future features such as station autocomplete can depend on that protocol, observe `locationPublisher`, and rank results without coupling search logic to Core Location.

## Location usage storage

`LocalLocationUsageStore` records each selected location in an on-device SQLite database. `LocationSelectionHandler.didSelect(_:)` is the binding for a future autocomplete selection callback; it returns that location's rolling seven-day usage count. The store can also return the five most-used locations for any rolling date window.

## Trip notifications

`TripMonitor.startTrip(to:)` schedules one-shot location notifications at 1 km and 150 m from the selected station. `TripMonitor.endTrip()` performs the core cleanup by clearing the persisted trip and removing its notifications. `TripCancellationHandler.cancelTrip()` is an idempotent wrapper intended for a future cancel button, leaving room for cancellation-specific behavior without changing the underlying trip lifecycle. Notifications use the default system sound, which follows the user's notification haptic settings; foreground delivery also triggers notification feedback directly.
