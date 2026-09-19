import Foundation
import SQLite3

struct LocationUsageSummary: Identifiable, Sendable {
    let location: LocationSelection
    let usageCount: Int
    let lastUsedAt: Date

    var id: String { location.id }
}

protocol LocationUsageStoring: Sendable {
    @discardableResult
    func recordSelection(_ location: LocationSelection, at date: Date) async throws -> Int

    @discardableResult
    func recordArrival(_ location: LocationSelection, at date: Date) async throws -> Int

    func usageCount(for locationID: String, since date: Date) async throws -> Int

    func topLocations(limit: Int, since date: Date) async throws -> [LocationUsageSummary]

    func recentLocations(limit: Int) async throws -> [LocationUsageSummary]
}

extension LocationUsageStoring {
    @discardableResult
    func recordSelection(_ location: LocationSelection) async throws -> Int {
        try await recordSelection(location, at: .now)
    }

    @discardableResult
    func recordArrival(_ location: LocationSelection) async throws -> Int {
        try await recordArrival(location, at: .now)
    }

    func topLocationsForPastWeek(limit: Int = 5) async throws -> [LocationUsageSummary] {
        try await topLocations(limit: limit, since: Date.now.addingTimeInterval(-.oneWeek))
    }
}

struct LocationSelectionHandler: Sendable {
    private let usageStore: any LocationUsageStoring

    static func live() throws -> LocationSelectionHandler {
        try LocationSelectionHandler(usageStore: LocalLocationUsageStore.makeDefault())
    }

    init(usageStore: any LocationUsageStoring) {
        self.usageStore = usageStore
    }

    /// Call this from the future autocomplete selection callback.
    @discardableResult
    func didSelect(_ location: LocationSelection) async throws -> Int {
        try await usageStore.recordSelection(location)
    }
}

struct TripArrivalHandler: Sendable {
    private let usageStore: any LocationUsageStoring

    static func live() throws -> TripArrivalHandler {
        try TripArrivalHandler(usageStore: LocalLocationUsageStore.makeDefault())
    }

    init(usageStore: any LocationUsageStoring) {
        self.usageStore = usageStore
    }

    @discardableResult
    func didArrive(at location: LocationSelection) async throws -> Int {
        try await usageStore.recordArrival(location)
    }
}

actor LocalLocationUsageStore: LocationUsageStoring {
    private let database: OpaquePointer

    static func makeDefault() throws -> LocalLocationUsageStore {
        let fileManager = FileManager.default
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appendingPathComponent("Homu", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        return try LocalLocationUsageStore(
            databaseURL: directory.appendingPathComponent("location-usage.sqlite3")
        )
    }

    init(databaseURL: URL) throws {
        var connection: OpaquePointer?
        let result = sqlite3_open_v2(
            databaseURL.path,
            &connection,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )

        guard result == SQLITE_OK, let connection else {
            let message = connection.map { String(cString: sqlite3_errmsg($0)) }
                ?? "Unknown SQLite error"
            sqlite3_close(connection)
            throw LocationUsageStoreError.unableToOpenDatabase(message)
        }

        database = connection

        do {
            try Self.execute("PRAGMA foreign_keys = ON;", on: connection)
            try Self.execute(
                """
                CREATE TABLE IF NOT EXISTS locations (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    latitude REAL NOT NULL,
                    longitude REAL NOT NULL,
                    updated_at REAL NOT NULL
                );

                CREATE TABLE IF NOT EXISTS location_usage_events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    location_id TEXT NOT NULL REFERENCES locations(id) ON DELETE CASCADE,
                    used_at REAL NOT NULL
                );

                CREATE INDEX IF NOT EXISTS location_usage_events_location_date
                ON location_usage_events(location_id, used_at);

                CREATE INDEX IF NOT EXISTS location_usage_events_date
                ON location_usage_events(used_at);

                CREATE TABLE IF NOT EXISTS location_selection_events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    location_id TEXT NOT NULL REFERENCES locations(id) ON DELETE CASCADE,
                    selected_at REAL NOT NULL
                );

                CREATE INDEX IF NOT EXISTS location_selection_events_location_date
                ON location_selection_events(location_id, selected_at);

                CREATE INDEX IF NOT EXISTS location_selection_events_date
                ON location_selection_events(selected_at);
                """,
                on: connection
            )
            try Self.migrateSelectionEventsIfNeeded(on: connection)
        } catch {
            sqlite3_close(connection)
            throw error
        }
    }

    deinit {
        sqlite3_close(database)
    }

    @discardableResult
    func recordSelection(_ location: LocationSelection, at date: Date) async throws -> Int {
        try execute("BEGIN IMMEDIATE TRANSACTION;")

        do {
            try upsert(location, at: date)
            try insertSelectionEvent(for: location.id, at: date)
            let count = try usageCountSynchronously(
                for: location.id,
                since: date.addingTimeInterval(-.oneWeek)
            )
            try execute("COMMIT;")
            return count
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    @discardableResult
    func recordArrival(_ location: LocationSelection, at date: Date) async throws -> Int {
        try execute("BEGIN IMMEDIATE TRANSACTION;")

        do {
            try upsert(location, at: date)
            try insertUsageEvent(for: location.id, at: date)
            let count = try usageCountSynchronously(
                for: location.id,
                since: date.addingTimeInterval(-.oneWeek)
            )
            try execute("COMMIT;")
            return count
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    func usageCount(for locationID: String, since date: Date) async throws -> Int {
        try usageCountSynchronously(for: locationID, since: date)
    }

    private func usageCountSynchronously(for locationID: String, since date: Date) throws -> Int {
        let statement = try prepare(
            """
            SELECT COUNT(*)
            FROM location_usage_events
            WHERE location_id = ? AND used_at >= ?;
            """
        )
        defer { sqlite3_finalize(statement) }

        try bind(locationID, at: 1, to: statement)
        sqlite3_bind_double(statement, 2, date.timeIntervalSince1970)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw databaseError()
        }

        return Int(sqlite3_column_int64(statement, 0))
    }

    func topLocations(limit: Int, since date: Date) async throws -> [LocationUsageSummary] {
        let safeLimit = max(0, min(limit, 100))
        guard safeLimit > 0 else { return [] }

        let statement = try prepare(
            """
            SELECT
                locations.id,
                locations.name,
                locations.latitude,
                locations.longitude,
                COUNT(location_usage_events.id) AS usage_count,
                MAX(location_usage_events.used_at) AS last_used_at
            FROM location_usage_events
            JOIN locations ON locations.id = location_usage_events.location_id
            WHERE location_usage_events.used_at >= ?
            GROUP BY locations.id
            ORDER BY usage_count DESC, last_used_at DESC, locations.name COLLATE NOCASE ASC
            LIMIT ?;
            """
        )
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, date.timeIntervalSince1970)
        sqlite3_bind_int(statement, 2, Int32(safeLimit))

        var summaries: [LocationUsageSummary] = []

        while true {
            let result = sqlite3_step(statement)
            guard result == SQLITE_ROW else {
                if result == SQLITE_DONE {
                    break
                }

                throw databaseError()
            }

            guard
                let idText = sqlite3_column_text(statement, 0),
                let nameText = sqlite3_column_text(statement, 1)
            else {
                throw LocationUsageStoreError.invalidStoredData
            }

            let location = LocationSelection(
                id: String(cString: idText),
                name: String(cString: nameText),
                latitude: sqlite3_column_double(statement, 2),
                longitude: sqlite3_column_double(statement, 3)
            )
            summaries.append(
                LocationUsageSummary(
                    location: location,
                    usageCount: Int(sqlite3_column_int64(statement, 4)),
                    lastUsedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
                )
            )
        }

        return summaries
    }

    func recentLocations(limit: Int) async throws -> [LocationUsageSummary] {
        let safeLimit = max(0, min(limit, 100))
        guard safeLimit > 0 else { return [] }

        let statement = try prepare(
            """
            SELECT
                locations.id,
                locations.name,
                locations.latitude,
                locations.longitude,
                COUNT(location_selection_events.id) AS selection_count,
                MAX(location_selection_events.selected_at) AS last_selected_at
            FROM location_selection_events
            JOIN locations ON locations.id = location_selection_events.location_id
            GROUP BY locations.id
            ORDER BY last_selected_at DESC, locations.name COLLATE NOCASE ASC
            LIMIT ?;
            """
        )
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(safeLimit))

        var summaries: [LocationUsageSummary] = []

        while true {
            let result = sqlite3_step(statement)
            guard result == SQLITE_ROW else {
                if result == SQLITE_DONE {
                    break
                }

                throw databaseError()
            }

            guard
                let idText = sqlite3_column_text(statement, 0),
                let nameText = sqlite3_column_text(statement, 1)
            else {
                throw LocationUsageStoreError.invalidStoredData
            }

            let location = LocationSelection(
                id: String(cString: idText),
                name: String(cString: nameText),
                latitude: sqlite3_column_double(statement, 2),
                longitude: sqlite3_column_double(statement, 3)
            )
            summaries.append(
                LocationUsageSummary(
                    location: location,
                    usageCount: Int(sqlite3_column_int64(statement, 4)),
                    lastUsedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
                )
            )
        }

        return summaries
    }

    private func upsert(_ location: LocationSelection, at date: Date) throws {
        let statement = try prepare(
            """
            INSERT INTO locations (id, name, latitude, longitude, updated_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                latitude = excluded.latitude,
                longitude = excluded.longitude,
                updated_at = excluded.updated_at;
            """
        )
        defer { sqlite3_finalize(statement) }

        try bind(location.id, at: 1, to: statement)
        try bind(location.name, at: 2, to: statement)
        sqlite3_bind_double(statement, 3, location.latitude)
        sqlite3_bind_double(statement, 4, location.longitude)
        sqlite3_bind_double(statement, 5, date.timeIntervalSince1970)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw databaseError()
        }
    }

    private func insertUsageEvent(for locationID: String, at date: Date) throws {
        let statement = try prepare(
            "INSERT INTO location_usage_events (location_id, used_at) VALUES (?, ?);"
        )
        defer { sqlite3_finalize(statement) }

        try bind(locationID, at: 1, to: statement)
        sqlite3_bind_double(statement, 2, date.timeIntervalSince1970)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw databaseError()
        }
    }

    private func insertSelectionEvent(for locationID: String, at date: Date) throws {
        let statement = try prepare(
            "INSERT INTO location_selection_events (location_id, selected_at) VALUES (?, ?);"
        )
        defer { sqlite3_finalize(statement) }

        try bind(locationID, at: 1, to: statement)
        sqlite3_bind_double(statement, 2, date.timeIntervalSince1970)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw databaseError()
        }
    }

    private func execute(_ sql: String) throws {
        try Self.execute(sql, on: database)
    }

    private static func execute(_ sql: String, on database: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)

        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) }
                ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorMessage)
            throw LocationUsageStoreError.queryFailed(message)
        }
    }

    private static func migrateSelectionEventsIfNeeded(on database: OpaquePointer) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA user_version;", -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw LocationUsageStoreError.queryFailed(String(cString: sqlite3_errmsg(database)))
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            sqlite3_finalize(statement)
            throw LocationUsageStoreError.queryFailed(String(cString: sqlite3_errmsg(database)))
        }

        let schemaVersion = sqlite3_column_int(statement, 0)
        sqlite3_finalize(statement)

        guard schemaVersion < 2 else { return }

        try execute("BEGIN IMMEDIATE TRANSACTION;", on: database)
        do {
            try execute(
                """
                INSERT INTO location_selection_events (location_id, selected_at)
                SELECT location_id, used_at FROM location_usage_events;
                DELETE FROM location_usage_events;
                PRAGMA user_version = 2;
                """,
                on: database
            )
            try execute("COMMIT;", on: database)
        } catch {
            try? execute("ROLLBACK;", on: database)
            throw error
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw databaseError()
        }

        return statement
    }

    private func bind(_ value: String, at index: Int32, to statement: OpaquePointer) throws {
        guard sqlite3_bind_text(statement, index, value, -1, sqliteTransient) == SQLITE_OK else {
            throw databaseError()
        }
    }

    private func databaseError() -> LocationUsageStoreError {
        .queryFailed(String(cString: sqlite3_errmsg(database)))
    }
}

private enum LocationUsageStoreError: LocalizedError {
    case unableToOpenDatabase(String)
    case queryFailed(String)
    case invalidStoredData

    var errorDescription: String? {
        switch self {
        case .unableToOpenDatabase(let message):
            L10n.unableToOpenLocationDatabase(message)
        case .queryFailed(let message):
            L10n.locationDatabaseQueryFailed(message)
        case .invalidStoredData:
            L10n.invalidLocationData
        }
    }
}

private extension TimeInterval {
    static let oneWeek: TimeInterval = 7 * 24 * 60 * 60
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
