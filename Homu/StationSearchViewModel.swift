import Combine
import CoreLocation
import Foundation

@MainActor
final class StationSearchViewModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var recentDestinations: [LocationSelection] = []
    @Published private(set) var stationResults: [LocationSelection] = []
    @Published private(set) var selectedDestination: LocationSelection?
    @Published private(set) var isUsingCurrentLocation = false
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    let locationManager: LocationManager

    private let stationSearch: any StationSearching
    private let usageStore: (any LocationUsageStoring)?
    private let selectionHandler: LocationSelectionHandler?

    private var currentLocation: CLLocation?
    private var isActive = false
    private var ignoresNextQueryChange = false
    private var searchGeneration = 0
    private var locationCancellable: AnyCancellable?
    private var searchTask: Task<Void, Never>?
    private var recentTask: Task<Void, Never>?
    private var selectionTask: Task<Void, Never>?

    convenience init() {
        let usageStore = try? LocalLocationUsageStore.makeDefault()
        self.init(
            locationManager: LocationManager(),
            stationSearch: AppleMapsStationSearchService(),
            usageStore: usageStore
        )
    }

    init(
        locationManager: LocationManager,
        stationSearch: any StationSearching,
        usageStore: (any LocationUsageStoring)?
    ) {
        self.locationManager = locationManager
        self.stationSearch = stationSearch
        self.usageStore = usageStore
        selectionHandler = usageStore.map { LocationSelectionHandler(usageStore: $0) }
        currentLocation = locationManager.currentLocation
        isUsingCurrentLocation = currentLocation != nil

        locationCancellable = locationManager.locationPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] location in
                guard let self, let location else { return }
                currentLocation = location
                isUsingCurrentLocation = true

                if isActive && normalizedQuery.isEmpty {
                    scheduleStationSearch(debounce: false)
                }
            }
    }

    func activate() {
        if !normalizedQuery.isEmpty {
            ignoresNextQueryChange = true
            query = ""
        }

        isActive = true
        locationManager.requestAccess()

        if normalizedQuery.isEmpty {
            loadRecentDestinations()
        }
        scheduleStationSearch(debounce: false)
    }

    func queryDidChange() {
        if ignoresNextQueryChange {
            ignoresNextQueryChange = false
            return
        }

        guard isActive else { return }

        if normalizedQuery.isEmpty {
            loadRecentDestinations()
        }
        scheduleStationSearch(debounce: true)
    }

    func deactivate(clearQuery: Bool) {
        isActive = false
        searchGeneration += 1
        searchTask?.cancel()
        isLoading = false

        if clearQuery {
            query = ""
            stationResults = []
        }
    }

    func select(_ destination: LocationSelection) {
        query = destination.name
        selectedDestination = destination

        guard let selectionHandler else { return }
        selectionTask?.cancel()
        selectionTask = Task { [weak self, selectionHandler] in
            do {
                try await selectionHandler.didSelect(destination)
                guard !Task.isCancelled else { return }
                self?.loadRecentDestinations()
            } catch is CancellationError {
                return
            } catch {
                self?.errorMessage = L10n.destinationSaveFailed
            }
        }
    }

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadRecentDestinations() {
        guard let usageStore else {
            recentDestinations = []
            return
        }

        recentTask?.cancel()
        recentTask = Task { [weak self, usageStore] in
            do {
                let summaries = try await usageStore.recentLocations(limit: 5)
                guard !Task.isCancelled else { return }
                self?.recentDestinations = summaries.map(\.location)
            } catch is CancellationError {
                return
            } catch {
                self?.recentDestinations = []
                self?.errorMessage = L10n.recentDestinationsUnavailable
            }
        }
    }

    private func scheduleStationSearch(debounce: Bool) {
        searchTask?.cancel()
        searchGeneration += 1

        let generation = searchGeneration
        let query = normalizedQuery
        let location = currentLocation
        let stationSearch = stationSearch

        isLoading = true
        errorMessage = nil
        stationResults = []

        searchTask = Task { [weak self, stationSearch] in
            do {
                if debounce {
                    try await Task.sleep(nanoseconds: 300_000_000)
                }

                let results = try await stationSearch.searchStations(
                    query: query,
                    near: location,
                    limit: 10
                )
                try Task.checkCancellation()

                guard let self, generation == searchGeneration else { return }
                stationResults = results
                isLoading = false
            } catch is CancellationError {
                return
            } catch {
                guard let self, generation == searchGeneration else { return }
                stationResults = []
                isLoading = false
                errorMessage = L10n.tokyoStationsLoadFailed
            }
        }
    }
}
