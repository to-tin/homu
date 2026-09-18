# Homu

A minimal SwiftUI iOS app that opens to an Apple Map and displays the user's current location.

## Requirements

- Xcode 16 or later
- iOS 17 or later

## Run the app

1. Open `Homu.xcodeproj` in Xcode.
2. Select the `Homu` scheme and an iPhone simulator or connected device.
3. Choose your development team under **Signing & Capabilities** if running on a device.
4. Build and run, then allow location access when prompted.

To test a location in Simulator, choose **Features > Location** and select a preset or enter a custom location.

## Location architecture

`LocationManager` implements the `LocationProviding` protocol and publishes the latest one-shot location. Future features such as station autocomplete can depend on that protocol, observe `locationPublisher`, and rank results without coupling search logic to Core Location.

## Location usage storage

`LocalLocationUsageStore` records each selected location in an on-device SQLite database. `LocationSelectionHandler.didSelect(_:)` is the binding for a future autocomplete selection callback; it returns that location's rolling seven-day usage count. The store can also return the five most-used locations for any rolling date window.

## Trip notifications

`TripMonitor.startTrip(to:)` schedules one-shot location notifications at 1 km and 150 m from the selected station. `TripMonitor.endTrip()` cancels them. The active trip is persisted locally so future UI can reflect it after an app relaunch. Notifications use the default system sound, which follows the user's notification haptic settings; foreground delivery also triggers notification feedback directly.
