//
//  WorkoutStorage.swift
//  WRKT
//
//  Unified, robust storage system for workout data
//

import Foundation
import OSLog

// MARK: - Storage Errors

enum StorageError: LocalizedError {
    case fileNotFound(String)
    case encodingFailed(String, underlying: Error)
    case decodingFailed(String, underlying: Error)
    case writeFailed(String, underlying: Error)
    case migrationFailed(String)
    case validationFailed(String)
    case backupFailed(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .encodingFailed(let type, let error):
            return "Failed to encode \(type): \(error.localizedDescription)"
        case .decodingFailed(let type, let error):
            return "Failed to decode \(type): \(error.localizedDescription)"
        case .writeFailed(let path, let error):
            return "Failed to write to \(path): \(error.localizedDescription)"
        case .migrationFailed(let message):
            return "Migration failed: \(message)"
        case .validationFailed(let message):
            return "Validation failed: \(message)"
        case .backupFailed(let message):
            return "Backup failed: \(message)"
        }
    }
}

// MARK: - Storage Metadata

struct StorageMetadata: Codable {
    let version: Int
    let lastModified: Date
    let itemCount: Int

    static let currentVersion = 1
}

// MARK: - Discarded Workout Window

/// Tracks time windows when workouts were discarded to prevent re-importing from HealthKit
struct DiscardedWorkoutWindow: Codable {
    let workoutStartedAt: Date
    let discardedAt: Date

    /// Check if a HealthKit workout falls within this discarded window
    func contains(workoutStart: Date, workoutEnd: Date) -> Bool {
        // Window is from workout start to discard time, with 5 min buffer
        let windowStart = workoutStartedAt.addingTimeInterval(-60) // 1 min before
        let windowEnd = discardedAt.addingTimeInterval(60) // 1 min after

        // Check if the HK workout overlaps with this window
        return workoutStart >= windowStart && workoutStart <= windowEnd
    }
}

// MARK: - Workout Storage Container

struct WorkoutStorageContainer: Codable {
    var metadata: StorageMetadata
    var workouts: [CompletedWorkout]
    var prIndex: [String: ExercisePRsV2]

    init(workouts: [CompletedWorkout], prIndex: [String: ExercisePRsV2]) {
        self.metadata = StorageMetadata(
            version: StorageMetadata.currentVersion,
            lastModified: .now,
            itemCount: workouts.count
        )
        self.workouts = workouts
        self.prIndex = prIndex
    }
}

// MARK: - Stored Run

/// A run as `runs_v2.json` holds it. `route` is left out when it is exactly the points of
/// `routeWithHR`, and `routeFromRouteWithHR` says so; decoding rebuilds it, so the decoded run
/// equals the encoded one. Every other run, and every file written before this form, is
/// encoded and decoded exactly as `Run` alone. Older app versions ignore the marker, read
/// `route` as absent and use `routeWithHR`, which every reader prefers.
nonisolated struct StoredRun: Codable {
    let run: Run

    init(_ run: Run) { self.run = run }

    private enum Keys: String, CodingKey {
        case route, routeFromRouteWithHR
    }

    /// True when `route` holds the same coordinates as `routeWithHR`, bit for bit, so
    /// rebuilding it gives back the identical value.
    static func routeRepeatsRouteWithHR(_ run: Run) -> Bool {
        guard let route = run.route, let points = run.routeWithHR, route.count == points.count else { return false }
        for index in route.indices {
            guard route[index].lat.bitPattern == points[index].lat.bitPattern,
                  route[index].lon.bitPattern == points[index].lon.bitPattern else { return false }
        }
        return true
    }

    init(from decoder: Decoder) throws {
        var run = try Run(from: decoder)
        let container = try decoder.container(keyedBy: Keys.self)
        if try container.decodeIfPresent(Bool.self, forKey: .routeFromRouteWithHR) == true,
           !container.contains(.route), let points = run.routeWithHR {
            run.route = points.map { Coordinate(lat: $0.lat, lon: $0.lon) }
        }
        self.run = run
    }

    func encode(to encoder: Encoder) throws {
        guard Self.routeRepeatsRouteWithHR(run) else {
            try run.encode(to: encoder)
            return
        }
        var slim = run
        slim.route = nil
        try slim.encode(to: encoder)
        // The same object as the run's own keys.
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(true, forKey: .routeFromRouteWithHR)
    }
}

// MARK: - Validated History

/// Identifies one version of a file: an atomic replace changes the file number, an in-place
/// write the size or modification date.
nonisolated struct FileStamp: Equatable, Sendable {
    let number: Int
    let size: Int
    let modified: Date

    init?(_ url: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let number = (attributes[.systemFileNumber] as? NSNumber)?.intValue,
              let size = (attributes[.size] as? NSNumber)?.intValue,
              let modified = attributes[.modificationDate] as? Date else { return nil }
        self.number = number
        self.size = size
        self.modified = modified
    }
}

/// History decoded by startup validation, handed once to the first loads so it is not decoded
/// twice. A missing part means "read the disk", never "no data".
nonisolated struct ValidatedHistory: @unchecked Sendable {
    struct Part<Value> {
        let value: Value
        /// nil when the file changed while it was read; such a value is never reused.
        let stamp: FileStamp?
    }

    let directory: URL
    var workouts: Part<WorkoutStorageContainer>?
    var runs: Part<[Run]>?
    var current: Part<CurrentWorkout>?
    var ignored: Part<[UUID]>?
    var discardWindows: Part<[DiscardedWorkoutWindow]>?
}

// MARK: - PR Data Structures (V2 - Enhanced)

struct LastSetV2: Codable, Hashable {
    var date: Date
    var reps: Int
    var weightKg: Double
}

struct ExercisePRsV2: Codable, Hashable {
    var bestPerReps: [Int: Double] = [:]
    var bestE1RM: Double?
    var lastWorking: LastSetV2?
    var allTimeBest: Double?  // Track all-time best weight regardless of reps
    var firstRecorded: Date?  // When this exercise was first performed
    var bestReps: Int?  // Track best reps for bodyweight exercises
    var bestDuration: Int?  // Track best duration in seconds for timed exercises
}

// MARK: - Workout Storage Actor

actor WorkoutStorage {

    // MARK: - Singleton

    static let shared = WorkoutStorage()

    // MARK: - Properties

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private let storageDirectory: URL
    private let workoutsFileURL: URL
    private let currentWorkoutFileURL: URL
    private let runsFileURL: URL
    private let ignoredHealthKitUUIDsFileURL: URL
    private let discardedWorkoutWindowsFileURL: URL
    private let migrationFlagURL: URL
    private let backupsDirectory: URL

    private let maxBackups = 5  // Keep last 5 backups
    private let backupInterval: TimeInterval = 300  // 5 minutes between automatic backups
    /// nil until the first save of this process reads the newest backup on disk, so a relaunch
    /// inside the interval does not copy the whole file again.
    private var lastWorkoutsBackupTime: Date?
    private var lastRunsBackupTime: Date?

    /// What startup validation decoded, consumed by the first loads so history is decoded once.
    private var validated: ValidatedHistory?

    // MARK: - Initialization

    init(directory: URL? = nil) {
        // Setup encoder/decoder
        self.encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.storageDirectory = directory ?? documents.appendingPathComponent("WRKT_Storage", isDirectory: true)
        self.backupsDirectory = storageDirectory.appendingPathComponent("Backups", isDirectory: true)

        // Setup file URLs
        self.workoutsFileURL = storageDirectory.appendingPathComponent("workouts_v2.json")
        self.currentWorkoutFileURL = storageDirectory.appendingPathComponent("current_workout_v2.json")
        self.runsFileURL = storageDirectory.appendingPathComponent("runs_v2.json")
        self.ignoredHealthKitUUIDsFileURL = storageDirectory.appendingPathComponent("ignored_healthkit_uuids.json")
        self.discardedWorkoutWindowsFileURL = storageDirectory.appendingPathComponent("discarded_workout_windows.json")
        self.migrationFlagURL = storageDirectory.appendingPathComponent(".migrated")

        // Create directories if needed
        try? fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)

        // Enable file protection for data security (encrypts when device is locked)
        enableFileProtection(for: storageDirectory)
        enableFileProtection(for: backupsDirectory)

        AppLogger.info("WorkoutStorage initialized - Storage: \(storageDirectory.path)", category: AppLogger.storage)
    }

    // MARK: - Workouts (with PR Index)

    /// Read-only startup validation, before any service can interpret unreadable data as empty.
    /// Runs off the main thread. For already-migrated history it returns what it decoded, so the
    /// first loads can skip a second decode; nil whenever a migration may still run.
    @discardableResult
    static func validateExistingData(applicationSupport: URL, documents: URL) throws -> ValidatedHistory? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let fm = FileManager.default
        func read<T: Decodable>(_ type: T.Type, at url: URL) throws -> ValidatedHistory.Part<T>? {
            guard fm.fileExists(atPath: url.path) else { return nil }
            let before = FileStamp(url)
            let value = try decoder.decode(type, from: Data(contentsOf: url))
            // A file replaced while it was being read has no stamp, so its value is never reused.
            return ValidatedHistory.Part(value: value, stamp: before == FileStamp(url) ? before : nil)
        }
        let current = documents.appendingPathComponent("WRKT_Storage")
        let workouts = try read(WorkoutStorageContainer.self, at: current.appendingPathComponent("workouts_v2.json"))
        if let workouts = workouts?.value {
            guard workouts.metadata.version == StorageMetadata.currentVersion,
                  workouts.metadata.itemCount == workouts.workouts.count else {
                throw StorageError.validationFailed("Workout history format or count needs recovery")
            }
        }
        let runs = try read([StoredRun].self, at: current.appendingPathComponent("runs_v2.json"))
            .map { ValidatedHistory.Part(value: $0.value.map(\.run), stamp: $0.stamp) }
        let active = try read(CurrentWorkout.self, at: current.appendingPathComponent("current_workout_v2.json"))
        let ignored = try read([UUID].self, at: current.appendingPathComponent("ignored_healthkit_uuids.json"))
        let windows = try read([DiscardedWorkoutWindow].self, at: current.appendingPathComponent("discarded_workout_windows.json"))
        guard !fm.fileExists(atPath: current.appendingPathComponent(".migrated").path) else {
            return ValidatedHistory(directory: current, workouts: workouts, runs: runs, current: active,
                                    ignored: ignored, discardWindows: windows)
        }
        if workouts != nil || runs != nil || active != nil {
            guard workouts != nil && runs != nil else {
                throw StorageError.migrationFailed("An interrupted history import needs recovery")
            }
            return nil
        }
        let legacy = applicationSupport.appendingPathComponent("WRKT")
        _ = try read([CompletedWorkout].self, at: legacy.appendingPathComponent("completed_workouts.json"))
        _ = try read([String: ExercisePRs].self, at: legacy.appendingPathComponent("pr_index.json"))
        for root in [legacy, documents] {
            _ = try read([Run].self, at: root.appendingPathComponent("runs.json"))
            _ = try read(CurrentWorkout.self, at: root.appendingPathComponent("current_workout.json"))
        }
        _ = try read([CompletedWorkout].self, at: documents.appendingPathComponent("workouts.json"))
        return nil
    }

    /// Accepts what startup validation decoded, if it was read from this storage's directory.
    func adopt(_ history: ValidatedHistory) {
        guard history.directory.standardizedFileURL == storageDirectory.standardizedFileURL else { return }
        validated = history
    }

    /// Hands out one validated value, once. It is used only while the file is still the exact
    /// file validation decoded; any doubt returns nil and the caller reads the disk as before.
    private func takeValidated<Value>(_ part: WritableKeyPath<ValidatedHistory, ValidatedHistory.Part<Value>?>,
                                      at url: URL) -> Value? {
        guard let taken = validated?[keyPath: part] else { return nil }
        validated?[keyPath: part] = nil
        guard let stamp = taken.stamp, FileStamp(url) == stamp else {
            AppLogger.info("\(url.lastPathComponent) changed after validation; reading it from disk", category: AppLogger.storage)
            return nil
        }
        return taken.value
    }

    /// Load workouts and PR index atomically
    func loadWorkouts() async throws -> (workouts: [CompletedWorkout], prIndex: [String: ExercisePRsV2]) {
        let container: WorkoutStorageContainer
        if let validated = takeValidated(\.workouts, at: workoutsFileURL) {
            container = validated
        } else {
            guard fileManager.fileExists(atPath: workoutsFileURL.path) else {
                AppLogger.debug("No workouts file found, returning empty", category: AppLogger.storage)
                return ([], [:])
            }
            do {
                container = try decoder.decode(WorkoutStorageContainer.self, from: Data(contentsOf: workoutsFileURL))
            } catch let error as DecodingError {
                throw StorageError.decodingFailed("WorkoutStorageContainer", underlying: error)
            }
        }

        // Validate data
        guard container.workouts.count == container.metadata.itemCount else {
            throw StorageError.validationFailed("Item count mismatch: expected \(container.metadata.itemCount), got \(container.workouts.count)")
        }

        AppLogger.info("Loaded \(container.workouts.count) workouts with \(container.prIndex.count) PR entries", category: AppLogger.storage)
        return (container.workouts, container.prIndex)
    }

    /// Save workouts and PR index atomically
    func saveWorkouts(_ workouts: [CompletedWorkout], prIndex: [String: ExercisePRsV2]) async throws {
        // Create backup before writing (debounced - only if enough time has passed).
        // A failed backup must not block the primary write.
        do {
            try await createWorkoutsBackupIfNeeded()
        } catch {
            AppLogger.warning("Workouts backup skipped: \(error)", category: AppLogger.storage)
        }

        let container = WorkoutStorageContainer(workouts: workouts, prIndex: prIndex)

        do {
            let data = try encoder.encode(container)
            try data.write(to: workoutsFileURL, options: [.atomic])

            // Ensure file protection is applied after write
            try? fileManager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: workoutsFileURL.path)

            AppLogger.success("Saved \(workouts.count) workouts with \(prIndex.count) PR entries", category: AppLogger.storage)
        } catch let error as EncodingError {
            throw StorageError.encodingFailed("WorkoutStorageContainer", underlying: error)
        } catch {
            throw StorageError.writeFailed(workoutsFileURL.path, underlying: error)
        }
    }

    // MARK: - Current Workout

    func loadCurrentWorkout() async throws -> CurrentWorkout? {
        let workout: CurrentWorkout
        if let validated = takeValidated(\.current, at: currentWorkoutFileURL) {
            workout = validated
        } else {
            guard fileManager.fileExists(atPath: currentWorkoutFileURL.path) else {
                return nil
            }
            workout = try decoder.decode(CurrentWorkout.self, from: Data(contentsOf: currentWorkoutFileURL))
        }
        AppLogger.info("Loaded current workout with \(workout.entries.count) entries", category: AppLogger.storage)
        return workout
    }

    func saveCurrentWorkout(_ workout: CurrentWorkout?) async throws {
        if let workout = workout {
            let data = try encoder.encode(workout)
            try data.write(to: currentWorkoutFileURL, options: [.atomic])

            // Ensure file protection is applied after write
            try? fileManager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: currentWorkoutFileURL.path)

            AppLogger.success("Saved current workout with \(workout.entries.count) entries", category: AppLogger.storage)
        } else {
            try? fileManager.removeItem(at: currentWorkoutFileURL)
            AppLogger.success("Deleted current workout", category: AppLogger.storage)
        }
    }

    func deleteCurrentWorkout() async throws {
        try? fileManager.removeItem(at: currentWorkoutFileURL)
        AppLogger.success("Deleted current workout", category: AppLogger.storage)
    }

    // MARK: - Runs (Cardio/HealthKit)

    func loadRuns() async throws -> [Run] {
        try loadRunsWithStamp().runs
    }

    /// Also returns the stamp of the file the runs came from, so the caller can later tell
    /// whether that file is still the one it loaded. nil when there is no file or it changed.
    func loadRunsWithStamp() throws -> (runs: [Run], stamp: FileStamp?) {
        try stamped(runsFileURL) {
            let runs: [Run]
            if let validated = takeValidated(\.runs, at: runsFileURL) {
                runs = validated
            } else {
                guard fileManager.fileExists(atPath: runsFileURL.path) else {
                    return []
                }
                do {
                    runs = try decoder.decode([StoredRun].self, from: Data(contentsOf: runsFileURL)).map(\.run)
                } catch let error as DecodingError {
                    throw StorageError.decodingFailed("Runs", underlying: error)
                }
            }
            AppLogger.info("Loaded \(runs.count) runs", category: AppLogger.storage)
            return runs
        }
    }

    func runsFileStamp() -> FileStamp? {
        FileStamp(runsFileURL)
    }

    /// Returns the stamp of the file it wrote.
    @discardableResult
    func saveRuns(_ runs: [Run]) async throws -> FileStamp? {
        do {
            try await createRunsBackupIfNeeded()
        } catch {
            AppLogger.warning("Runs backup skipped: \(error)", category: AppLogger.storage)
        }
        do {
            let data = try encoder.encode(runs.map(StoredRun.init))
            try data.write(to: runsFileURL, options: [.atomic])

            // Ensure file protection is applied after write
            try? fileManager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: runsFileURL.path)

            AppLogger.success("Saved \(runs.count) runs", category: AppLogger.storage)
            return FileStamp(runsFileURL)
        } catch let error as EncodingError {
            throw StorageError.encodingFailed("Runs", underlying: error)
        } catch {
            throw StorageError.writeFailed(runsFileURL.path, underlying: error)
        }
    }

    /// For each pair, whether the two runs encode to the same bytes with the encoder `saveRuns`
    /// uses, so replacing one with the other cannot change the file. Values that differ only
    /// below the file's precision (sub-second dates) match. Failing to encode counts as a change.
    func runsEncodeIdentically(_ pairs: [(Run, Run)]) -> [Bool] {
        pairs.map { a, b in
            // Encoded as the file holds them: as elements of an array.
            guard let encodedA = try? encoder.encode([StoredRun(a)]),
                  let encodedB = try? encoder.encode([StoredRun(b)]) else { return false }
            return encodedA == encodedB
        }
    }

    // MARK: - Ignored HealthKit UUIDs (for discarded workouts)

    func loadIgnoredHealthKitUUIDs() async throws -> Set<UUID> {
        try loadIgnoredHealthKitUUIDsWithStamp().uuids
    }

    /// Also returns the stamp of the file the UUIDs came from, as `loadRunsWithStamp` does.
    func loadIgnoredHealthKitUUIDsWithStamp() throws -> (uuids: Set<UUID>, stamp: FileStamp?) {
        try stamped(ignoredHealthKitUUIDsFileURL) {
            let uuids: [UUID]
            if let validated = takeValidated(\.ignored, at: ignoredHealthKitUUIDsFileURL) {
                uuids = validated
            } else {
                guard fileManager.fileExists(atPath: ignoredHealthKitUUIDsFileURL.path) else {
                    return []
                }
                do {
                    uuids = try decoder.decode([UUID].self, from: Data(contentsOf: ignoredHealthKitUUIDsFileURL))
                } catch {
                    AppLogger.warning("Failed to load ignored HealthKit UUIDs: \(error)", category: AppLogger.storage)
                    throw error
                }
            }
            AppLogger.info("Loaded \(uuids.count) ignored HealthKit UUIDs", category: AppLogger.storage)
            return Set(uuids)
        }
    }

    func ignoredHealthKitUUIDsFileStamp() -> FileStamp? {
        FileStamp(ignoredHealthKitUUIDsFileURL)
    }

    /// Returns the stamp of the file it wrote.
    @discardableResult
    func saveIgnoredHealthKitUUIDs(_ uuids: Set<UUID>) async throws -> FileStamp? {
        do {
            let data = try encoder.encode(Array(uuids))
            try data.write(to: ignoredHealthKitUUIDsFileURL, options: [.atomic])
            AppLogger.success("Saved \(uuids.count) ignored HealthKit UUIDs", category: AppLogger.storage)
            return FileStamp(ignoredHealthKitUUIDsFileURL)
        } catch {
            AppLogger.error("Failed to save ignored HealthKit UUIDs: \(error)", category: AppLogger.storage)
            throw error
        }
    }

    /// Runs a read and pairs its result with the stamp of `url`, or nil if the file changed
    /// while it was read.
    private func stamped<Value>(_ url: URL, _ read: () throws -> Value) rethrows -> (Value, FileStamp?) {
        let before = FileStamp(url)
        let value = try read()
        return (value, before == FileStamp(url) ? before : nil)
    }

    // MARK: - Discarded Workout Windows

    func loadDiscardedWorkoutWindows() async throws -> [DiscardedWorkoutWindow] {
        var windows: [DiscardedWorkoutWindow]
        if let validated = takeValidated(\.discardWindows, at: discardedWorkoutWindowsFileURL) {
            windows = validated
        } else {
            guard fileManager.fileExists(atPath: discardedWorkoutWindowsFileURL.path) else {
                return []
            }
            do {
                windows = try decoder.decode([DiscardedWorkoutWindow].self, from: Data(contentsOf: discardedWorkoutWindowsFileURL))
            } catch {
                AppLogger.warning("Failed to load discarded workout windows: \(error)", category: AppLogger.storage)
                throw error
            }
        }

        // Clean up old windows (older than 7 days)
        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        windows = windows.filter { $0.discardedAt > cutoff }

        AppLogger.info("Loaded \(windows.count) discarded workout windows", category: AppLogger.storage)
        return windows
    }

    func saveDiscardedWorkoutWindows(_ windows: [DiscardedWorkoutWindow]) async throws {
        do {
            let data = try encoder.encode(windows)
            try data.write(to: discardedWorkoutWindowsFileURL, options: [.atomic])
            AppLogger.success("Saved \(windows.count) discarded workout windows", category: AppLogger.storage)
        } catch {
            AppLogger.error("Failed to save discarded workout windows: \(error)", category: AppLogger.storage)
        }
    }

    // MARK: - Backup & Restore

    /// Create workouts backup only if enough time has passed since the last workouts backup.
    private func createWorkoutsBackupIfNeeded() async throws {
        let now = Date()
        let last = lastWorkoutsBackupTime ?? newestBackupDate(prefix: "workouts_backup_", before: now)
        lastWorkoutsBackupTime = last

        guard now.timeIntervalSince(last) >= backupInterval else {
            return
        }

        try await createWorkoutsBackup()
        lastWorkoutsBackupTime = now
    }

    /// Create runs backup only if enough time has passed since the last runs backup.
    private func createRunsBackupIfNeeded() async throws {
        let now = Date()
        let last = lastRunsBackupTime ?? newestBackupDate(prefix: "runs_backup_", before: now)
        lastRunsBackupTime = last

        guard now.timeIntervalSince(last) >= backupInterval else {
            return
        }

        try await createRunsBackup()
        lastRunsBackupTime = now
    }

    /// Force workouts backup creation (for critical operations like migrations)
    private func createWorkoutsBackup() async throws {
        guard fileManager.fileExists(atPath: workoutsFileURL.path) else {
            return  // Nothing to backup
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupURL = backupsDirectory.appendingPathComponent("workouts_backup_\(timestamp)_\(UUID().uuidString).json")

        do {
            // A data reset removes this folder after init created it.
            try fileManager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
            try fileManager.copyItem(at: workoutsFileURL, to: backupURL)
            AppLogger.info("Created backup: \(backupURL.lastPathComponent)", category: AppLogger.storage)

            try await rotateBackups(prefix: "workouts_backup_")
        } catch {
            throw StorageError.backupFailed(error.localizedDescription)
        }
    }

    /// Force runs backup creation.
    private func createRunsBackup() async throws {
        guard fileManager.fileExists(atPath: runsFileURL.path) else {
            return
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupURL = backupsDirectory.appendingPathComponent("runs_backup_\(timestamp)_\(UUID().uuidString).json")

        do {
            try fileManager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
            try fileManager.copyItem(at: runsFileURL, to: backupURL)
            AppLogger.info("Created runs backup: \(backupURL.lastPathComponent)", category: AppLogger.storage)
            try await rotateBackups(prefix: "runs_backup_")
        } catch {
            throw StorageError.backupFailed(error.localizedDescription)
        }
    }

    /// When the newest backup with this prefix was made, read from the timestamp in its name:
    /// a copy keeps the source file's dates, so they tell when the backed-up file was written,
    /// not when it was copied. A name that does not parse or a time after `now` (the clock
    /// moved back) is ignored, so any doubt means "back up now".
    private func newestBackupDate(prefix: String, before now: Date) -> Date {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "UTC")
        parser.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        let names = (try? fileManager.contentsOfDirectory(atPath: backupsDirectory.path)) ?? []
        return names
            .filter { $0.hasPrefix(prefix) }
            .compactMap { parser.date(from: String($0.dropFirst(prefix.count).prefix(20))) }
            .filter { $0 <= now }
            .max() ?? .distantPast
    }

    private func rotateBackups(prefix: String) async throws {
        let backupFiles = try fileManager.contentsOfDirectory(
            at: backupsDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.lastPathComponent.hasPrefix(prefix) }
        .sorted { url1, url2 in
            let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            return date1 > date2
        }

        // Remove old backups (keep only maxBackups)
        for url in backupFiles.dropFirst(maxBackups) {
            try? fileManager.removeItem(at: url)
            AppLogger.debug("Removed old backup: \(url.lastPathComponent)", category: AppLogger.storage)
        }
    }

    func listBackups() async throws -> [URL] {
        let backupFiles = try fileManager.contentsOfDirectory(
            at: backupsDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.lastPathComponent.hasPrefix("workouts_backup_") }
        .sorted { url1, url2 in
            let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            return date1 > date2
        }

        return backupFiles
    }

    func restoreFromBackup(at url: URL) async throws {
        guard fileManager.fileExists(atPath: url.path) else {
            throw StorageError.fileNotFound(url.path)
        }

        // Validate backup before restoring
        let data = try Data(contentsOf: url)
        let container = try decoder.decode(WorkoutStorageContainer.self, from: data)
        guard container.workouts.count == container.metadata.itemCount else {
            throw StorageError.validationFailed("Backup item count mismatch")
        }

        // Retain the current file for recovery and atomically replace it only after validation.
        try await createWorkoutsBackup()
        try data.write(to: workoutsFileURL, options: [.atomic])
        enableFileProtection(for: workoutsFileURL)
        AppLogger.success("Restored from backup: \(url.lastPathComponent)", category: AppLogger.storage)
    }

    // MARK: - Migration

    func needsMigration() async -> Bool {
        return !fileManager.fileExists(atPath: migrationFlagURL.path)
    }

    func migrateFromLegacyStorage(applicationSupport: URL? = nil, documents: URL? = nil) async throws {
        AppLogger.info("Starting migration from legacy storage...", category: AppLogger.storage)

        guard let appSupportDir = applicationSupport ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw StorageError.migrationFailed("Application Support directory not accessible")
        }
        let oldAppDir = appSupportDir.appendingPathComponent("WRKT", isDirectory: true)

        guard let documentsDir = documents ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw StorageError.migrationFailed("Documents directory not accessible")
        }

        let existingWorkouts = fileManager.fileExists(atPath: workoutsFileURL.path)
        let existingRuns = fileManager.fileExists(atPath: runsFileURL.path)
        let existingCurrent = fileManager.fileExists(atPath: currentWorkoutFileURL.path)
        if existingWorkouts || existingRuns || existingCurrent {
            // A missing marker is not permission to overwrite history with legacy or empty data.
            guard existingWorkouts && existingRuns else {
                throw StorageError.migrationFailed("An interrupted history import needs recovery")
            }
            _ = try await loadWorkouts()
            _ = try await loadRuns()
            _ = try await loadCurrentWorkout()
            try "migrated".write(to: migrationFlagURL, atomically: true, encoding: .utf8)
            return
        }

        var migratedWorkouts: [CompletedWorkout] = []
        var migratedPRIndex: [String: ExercisePRsV2] = [:]
        var migratedRuns: [Run] = []
        var migratedCurrent: CurrentWorkout?

        // 1. Load from legacy Application Support location
        let oldWorkoutsURL = oldAppDir.appendingPathComponent("completed_workouts.json")
        if fileManager.fileExists(atPath: oldWorkoutsURL.path) {
            do {
                let data = try Data(contentsOf: oldWorkoutsURL)
                let workouts = try decoder.decode([CompletedWorkout].self, from: data)
                migratedWorkouts.append(contentsOf: workouts)
                AppLogger.info("Found \(workouts.count) workouts in legacy Application Support", category: AppLogger.storage)
            }
        }

        let oldPRURL = oldAppDir.appendingPathComponent("pr_index.json")
        if fileManager.fileExists(atPath: oldPRURL.path) {
            do {
                let data = try Data(contentsOf: oldPRURL)
                let oldPRIndex = try decoder.decode([String: ExercisePRs].self, from: data)
                // Convert old PR format to new
                migratedPRIndex = convertOldPRIndex(oldPRIndex)
                AppLogger.info("Found \(migratedPRIndex.count) PR entries in legacy storage", category: AppLogger.storage)
            }
        }

        let oldRunsURL = oldAppDir.appendingPathComponent("runs.json")
        if fileManager.fileExists(atPath: oldRunsURL.path) {
            do {
                let data = try Data(contentsOf: oldRunsURL)
                let runs = try decoder.decode([Run].self, from: data)
                migratedRuns.append(contentsOf: runs)
                AppLogger.info("Found \(runs.count) runs in legacy storage", category: AppLogger.storage)
            }
        }

        let oldCurrentURL = oldAppDir.appendingPathComponent("current_workout.json")
        if fileManager.fileExists(atPath: oldCurrentURL.path) {
            do {
                let data = try Data(contentsOf: oldCurrentURL)
                let current = try decoder.decode(CurrentWorkout.self, from: data)
                migratedCurrent = current
                AppLogger.info("Found current workout in legacy storage", category: AppLogger.storage)
            }
        }

        // 2. Load from old Persistence location (Documents)
        let oldPersistenceWorkoutsURL = documentsDir.appendingPathComponent("workouts.json")
        if fileManager.fileExists(atPath: oldPersistenceWorkoutsURL.path) {
            do {
                let data = try Data(contentsOf: oldPersistenceWorkoutsURL)
                let workouts = try decoder.decode([CompletedWorkout].self, from: data)
                migratedWorkouts.append(contentsOf: workouts)
                AppLogger.info("Found \(workouts.count) workouts in old Persistence location", category: AppLogger.storage)
            }
        }

        let oldPersistenceRunsURL = documentsDir.appendingPathComponent("runs.json")
        if fileManager.fileExists(atPath: oldPersistenceRunsURL.path) {
            do {
                let data = try Data(contentsOf: oldPersistenceRunsURL)
                let runs = try decoder.decode([Run].self, from: data)
                migratedRuns.append(contentsOf: runs)
                AppLogger.info("Found \(runs.count) runs in old Persistence location", category: AppLogger.storage)
            }
        }

        let oldPersistenceCurrentURL = documentsDir.appendingPathComponent("current_workout.json")
        if fileManager.fileExists(atPath: oldPersistenceCurrentURL.path) {
            do {
                let data = try Data(contentsOf: oldPersistenceCurrentURL)
                let current = try decoder.decode(CurrentWorkout.self, from: data)
                if migratedCurrent == nil {
                    migratedCurrent = current
                    AppLogger.info("Found current workout in old Persistence location", category: AppLogger.storage)
                }
            }
        }

        // 3. Deduplicate workouts by ID
        var uniqueWorkouts: [UUID: CompletedWorkout] = [:]
        for workout in migratedWorkouts {
            uniqueWorkouts[workout.id] = workout
        }
        let deduplicatedWorkouts = Array(uniqueWorkouts.values).sorted { $0.date > $1.date }

        // 4. Deduplicate runs by ID or healthKitUUID
        var uniqueRuns: [UUID: Run] = [:]
        var seenHealthKitUUIDs: Set<UUID> = []
        for run in migratedRuns {
            if let hkUUID = run.healthKitUUID {
                if !seenHealthKitUUIDs.contains(hkUUID) {
                    uniqueRuns[run.id] = run
                    seenHealthKitUUIDs.insert(hkUUID)
                }
            } else {
                uniqueRuns[run.id] = run
            }
        }
        let deduplicatedRuns = Array(uniqueRuns.values).sorted { $0.date > $1.date }

        // 5. If PR index is empty, recompute from workouts
        if migratedPRIndex.isEmpty && !deduplicatedWorkouts.isEmpty {
            AppLogger.info("Recomputing PR index from migrated workouts...", category: AppLogger.storage)
            migratedPRIndex = recomputePRIndex(from: deduplicatedWorkouts)
        }

        // 6. Save to new unified storage
        try await saveWorkouts(deduplicatedWorkouts, prIndex: migratedPRIndex)
        try await saveRuns(deduplicatedRuns)
        if let current = migratedCurrent {
            try await saveCurrentWorkout(current)
        }

        // 7. Mark migration as complete
        try "migrated".write(to: migrationFlagURL, atomically: true, encoding: .utf8)

        AppLogger.success("Migration complete - Workouts: \(deduplicatedWorkouts.count), Runs: \(deduplicatedRuns.count), PR entries: \(migratedPRIndex.count), Current workout: \(migratedCurrent != nil ? "Yes" : "No")", category: AppLogger.storage)

        // Note: Don't delete old files yet - let user verify data first
        AppLogger.warning("Old storage files retained for safety. You can delete them manually after verification.", category: AppLogger.storage)
    }

    // MARK: - Migration Helpers

    private func convertOldPRIndex(_ oldIndex: [String: ExercisePRs]) -> [String: ExercisePRsV2] {
        var newIndex: [String: ExercisePRsV2] = [:]

        for (exerciseID, oldPR) in oldIndex {
            var newPR = ExercisePRsV2()
            newPR.bestPerReps = oldPR.bestPerReps
            newPR.bestE1RM = oldPR.bestE1RM

            if let lastWorking = oldPR.lastWorking {
                newPR.lastWorking = LastSetV2(
                    date: lastWorking.date,
                    reps: lastWorking.reps,
                    weightKg: lastWorking.weightKg
                )
                newPR.firstRecorded = lastWorking.date
            }

            // Calculate all-time best
            if let best = oldPR.bestPerReps.values.max() {
                newPR.allTimeBest = best
            }

            newIndex[exerciseID] = newPR
        }

        return newIndex
    }

    private func recomputePRIndex(from workouts: [CompletedWorkout]) -> [String: ExercisePRsV2] {
        var index: [String: ExercisePRsV2] = [:]

        for workout in workouts.sorted(by: { $0.date < $1.date }) {
            for entry in workout.entries {
                var pr = index[entry.exerciseID] ?? ExercisePRsV2()

                for set in entry.sets where set.tag == .working && set.reps > 0 && set.weight > 0 {
                    // Best per reps
                    pr.bestPerReps[set.reps] = max(pr.bestPerReps[set.reps] ?? 0, set.weight)

                    // Best E1RM (Epley formula)
                    let e1rm = set.weight * (1.0 + Double(set.reps) / 30.0)
                    pr.bestE1RM = max(pr.bestE1RM ?? 0, e1rm)

                    // All-time best
                    pr.allTimeBest = max(pr.allTimeBest ?? 0, set.weight)

                    // Last working set
                    pr.lastWorking = LastSetV2(date: workout.date, reps: set.reps, weightKg: set.weight)

                    // First recorded
                    if pr.firstRecorded == nil {
                        pr.firstRecorded = workout.date
                    }
                }

                index[entry.exerciseID] = pr
            }
        }

        return index
    }

    // MARK: - Cleanup

    func cleanupLegacyStorage() async throws {
        AppLogger.info("Cleaning up legacy storage files...", category: AppLogger.storage)

        guard let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            AppLogger.warning("Application Support directory not accessible, skipping cleanup", category: AppLogger.storage)
            return
        }
        let oldAppDir = appSupportDir.appendingPathComponent("WRKT", isDirectory: true)

        if fileManager.fileExists(atPath: oldAppDir.path) {
            try fileManager.removeItem(at: oldAppDir)
            AppLogger.success("Removed legacy Application Support directory", category: AppLogger.storage)
        }

        guard let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            AppLogger.warning("Documents directory not accessible, skipping cleanup", category: AppLogger.storage)
            return
        }

        let oldFiles = [
            "workouts.json",
            "runs.json",
            "current_workout.json"
        ]

        for filename in oldFiles {
            let url = documentsDir.appendingPathComponent(filename)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
                AppLogger.success("Removed old Persistence file: \(filename)", category: AppLogger.storage)
            }
        }
    }

    // MARK: - Debug & Maintenance

    func validateStorage() async throws -> Bool {
        AppLogger.info("Validating storage...", category: AppLogger.storage)

        guard fileManager.fileExists(atPath: workoutsFileURL.path) else {
            AppLogger.warning("Workouts file not found", category: AppLogger.storage)
            return false
        }

        let (workouts, prIndex) = try await loadWorkouts()

        // Check for duplicates
        let uniqueIDs = Set(workouts.map { $0.id })
        guard uniqueIDs.count == workouts.count else {
            AppLogger.error("Found duplicate workout IDs", category: AppLogger.storage)
            return false
        }

        // Validate PR index
        for (exerciseID, pr) in prIndex {
            if pr.bestPerReps.isEmpty && pr.bestE1RM == nil {
                AppLogger.warning("Empty PR entry for exercise: \(exerciseID)", category: AppLogger.storage)
            }
        }

        AppLogger.success("Storage validation passed - Workouts: \(workouts.count), PR entries: \(prIndex.count)", category: AppLogger.storage)
        return true
    }

    func getStorageStats() async -> [String: Any] {
        var stats: [String: Any] = [:]

        if let (workouts, prIndex) = try? await loadWorkouts() {
            stats["workoutCount"] = workouts.count
            stats["prIndexSize"] = prIndex.count
            stats["oldestWorkout"] = workouts.map { $0.date }.min()
            stats["newestWorkout"] = workouts.map { $0.date }.max()
        }

        if let runs = try? await loadRuns() {
            stats["runCount"] = runs.count
        }

        if let current = try? await loadCurrentWorkout() {
            stats["hasCurrentWorkout"] = true
            stats["currentWorkoutEntries"] = current.entries.count
        } else {
            stats["hasCurrentWorkout"] = false
        }

        // File sizes
        if let workoutsAttr = try? fileManager.attributesOfItem(atPath: workoutsFileURL.path),
           let fileSize = workoutsAttr[.size] as? Int {
            stats["workoutsFileSize"] = ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
        }

        return stats
    }

    // MARK: - Security

    /// Enable file protection for a directory and all its contents.
    /// Uses .completeUntilFirstUserAuthentication so files remain accessible
    /// during background tasks (e.g. HealthKit sync) after the first device
    /// unlock — preventing data loss from a failed load overwriting good data.
    private func enableFileProtection(for directory: URL) {
        do {
            // Set protection for the directory itself
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: directory.path
            )

            AppLogger.success("File protection enabled for: \(directory.lastPathComponent)", category: AppLogger.storage)

            // Also protect any existing files in the directory
            if let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                for file in files {
                    try? fileManager.setAttributes(
                        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                        ofItemAtPath: file.path
                    )
                }
            }
        } catch {
            AppLogger.error("Failed to enable file protection for \(directory.lastPathComponent)", error: error, category: AppLogger.storage)
        }
    }

    // MARK: - Development Only

    func wipeAllData() async throws {
        AppLogger.warning("WIPING ALL DATA...", category: AppLogger.storage)

        try? fileManager.removeItem(at: workoutsFileURL)
        try? fileManager.removeItem(at: currentWorkoutFileURL)
        try? fileManager.removeItem(at: runsFileURL)
        try? fileManager.removeItem(at: migrationFlagURL)
        try? fileManager.removeItem(at: backupsDirectory)

        // Also clean up legacy
        try? await cleanupLegacyStorage()

        AppLogger.success("All data wiped", category: AppLogger.storage)
    }

    func wipeWorkoutDataPreservingRuns() async throws {
        AppLogger.warning("WIPING WORKOUT DATA (preserving runs)...", category: AppLogger.storage)

        try? fileManager.removeItem(at: workoutsFileURL)
        try? fileManager.removeItem(at: currentWorkoutFileURL)
        try? fileManager.removeItem(at: ignoredHealthKitUUIDsFileURL)
        try? fileManager.removeItem(at: discardedWorkoutWindowsFileURL)
        try? fileManager.removeItem(at: backupsDirectory)

        // Also clean up legacy workout data while preserving legacy runs.json.
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            AppLogger.warning("Application Support directory not available, skipping legacy workout cleanup", category: AppLogger.storage)
            return
        }
        let appDir = appSupport.appendingPathComponent("WRKT", isDirectory: true)
        try? fileManager.removeItem(at: appDir.appendingPathComponent("completed_workouts.json"))
        try? fileManager.removeItem(at: appDir.appendingPathComponent("current_workout.json"))
        try? fileManager.removeItem(at: appDir.appendingPathComponent("pr_index.json"))

        AppLogger.success("Workout data wiped, runs preserved", category: AppLogger.storage)
    }
}

// MARK: - Old PR Structure (for migration)

private struct LastSet: Codable {
    var date: Date
    var reps: Int
    var weightKg: Double
}

private struct ExercisePRs: Codable {
    var bestPerReps: [Int: Double] = [:]
    var bestE1RM: Double?
    var lastWorking: LastSet?
}
