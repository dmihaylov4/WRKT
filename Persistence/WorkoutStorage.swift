//
//  WorkoutStorage.swift
//  WRKT
//
//  Unified, robust storage system for workout data
//

import Foundation

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
    private let migrationFlagURL: URL
    private let backupsDirectory: URL

    private let maxBackups = 5  // Keep last 5 backups

    // MARK: - Initialization

    private init() {
        // Setup encoder/decoder
        self.encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Setup directories
        let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.storageDirectory = documentsDir.appendingPathComponent("WRKT_Storage", isDirectory: true)
        self.backupsDirectory = storageDirectory.appendingPathComponent("Backups", isDirectory: true)

        // Setup file URLs
        self.workoutsFileURL = storageDirectory.appendingPathComponent("workouts_v2.json")
        self.currentWorkoutFileURL = storageDirectory.appendingPathComponent("current_workout_v2.json")
        self.runsFileURL = storageDirectory.appendingPathComponent("runs_v2.json")
        self.migrationFlagURL = storageDirectory.appendingPathComponent(".migrated")

        // Create directories if needed
        try? fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)

        print("📦 WorkoutStorage initialized")
        print("   Storage: \(storageDirectory.path)")
    }

    // MARK: - Workouts (with PR Index)

    /// Load workouts and PR index atomically
    func loadWorkouts() async throws -> (workouts: [CompletedWorkout], prIndex: [String: ExercisePRsV2]) {
        guard fileManager.fileExists(atPath: workoutsFileURL.path) else {
            print("📦 No workouts file found, returning empty")
            return ([], [:])
        }

        do {
            let data = try Data(contentsOf: workoutsFileURL)
            let container = try decoder.decode(WorkoutStorageContainer.self, from: data)

            // Validate data
            guard container.workouts.count == container.metadata.itemCount else {
                throw StorageError.validationFailed("Item count mismatch: expected \(container.metadata.itemCount), got \(container.workouts.count)")
            }

            print("📦 Loaded \(container.workouts.count) workouts with \(container.prIndex.count) PR entries")
            return (container.workouts, container.prIndex)

        } catch let error as DecodingError {
            throw StorageError.decodingFailed("WorkoutStorageContainer", underlying: error)
        } catch {
            throw error
        }
    }

    /// Save workouts and PR index atomically
    func saveWorkouts(_ workouts: [CompletedWorkout], prIndex: [String: ExercisePRsV2]) async throws {
        // Create backup before writing
        try await createBackup()

        let container = WorkoutStorageContainer(workouts: workouts, prIndex: prIndex)

        do {
            let data = try encoder.encode(container)
            try data.write(to: workoutsFileURL, options: [.atomic])
            print("✅ Saved \(workouts.count) workouts with \(prIndex.count) PR entries")
        } catch let error as EncodingError {
            throw StorageError.encodingFailed("WorkoutStorageContainer", underlying: error)
        } catch {
            throw StorageError.writeFailed(workoutsFileURL.path, underlying: error)
        }
    }

    // MARK: - Current Workout

    func loadCurrentWorkout() async throws -> CurrentWorkout? {
        guard fileManager.fileExists(atPath: currentWorkoutFileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: currentWorkoutFileURL)
            let workout = try decoder.decode(CurrentWorkout.self, from: data)
            print("📦 Loaded current workout with \(workout.entries.count) entries")
            return workout
        } catch let error as DecodingError {
            print("⚠️ Failed to decode current workout: \(error)")
            return nil
        }
    }

    func saveCurrentWorkout(_ workout: CurrentWorkout?) async throws {
        if let workout = workout {
            let data = try encoder.encode(workout)
            try data.write(to: currentWorkoutFileURL, options: [.atomic])
            print("✅ Saved current workout with \(workout.entries.count) entries")
        } else {
            try? fileManager.removeItem(at: currentWorkoutFileURL)
            print("✅ Deleted current workout")
        }
    }

    func deleteCurrentWorkout() async throws {
        try? fileManager.removeItem(at: currentWorkoutFileURL)
        print("✅ Deleted current workout")
    }

    // MARK: - Runs (Cardio/HealthKit)

    func loadRuns() async throws -> [Run] {
        guard fileManager.fileExists(atPath: runsFileURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: runsFileURL)
            let runs = try decoder.decode([Run].self, from: data)
            print("📦 Loaded \(runs.count) runs")
            return runs
        } catch let error as DecodingError {
            throw StorageError.decodingFailed("Runs", underlying: error)
        }
    }

    func saveRuns(_ runs: [Run]) async throws {
        do {
            let data = try encoder.encode(runs)
            try data.write(to: runsFileURL, options: [.atomic])
            print("✅ Saved \(runs.count) runs")
        } catch let error as EncodingError {
            throw StorageError.encodingFailed("Runs", underlying: error)
        } catch {
            throw StorageError.writeFailed(runsFileURL.path, underlying: error)
        }
    }

    // MARK: - Backup & Restore

    private func createBackup() async throws {
        guard fileManager.fileExists(atPath: workoutsFileURL.path) else {
            return  // Nothing to backup
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupURL = backupsDirectory.appendingPathComponent("workouts_backup_\(timestamp).json")

        do {
            try fileManager.copyItem(at: workoutsFileURL, to: backupURL)
            print("📦 Created backup: \(backupURL.lastPathComponent)")

            // Rotate old backups
            try await rotateBackups()
        } catch {
            throw StorageError.backupFailed(error.localizedDescription)
        }
    }

    private func rotateBackups() async throws {
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

        // Remove old backups (keep only maxBackups)
        for url in backupFiles.dropFirst(maxBackups) {
            try? fileManager.removeItem(at: url)
            print("🗑️ Removed old backup: \(url.lastPathComponent)")
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
        let _ = try decoder.decode(WorkoutStorageContainer.self, from: data)

        // Copy backup to main storage
        try fileManager.copyItem(at: url, to: workoutsFileURL)
        print("✅ Restored from backup: \(url.lastPathComponent)")
    }

    // MARK: - Migration

    func needsMigration() async -> Bool {
        return !fileManager.fileExists(atPath: migrationFlagURL.path)
    }

    func migrateFromLegacyStorage() async throws {
        print("🔄 Starting migration from legacy storage...")

        let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let oldAppDir = appSupportDir.appendingPathComponent("WRKT", isDirectory: true)
        let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!

        var migratedWorkouts: [CompletedWorkout] = []
        var migratedPRIndex: [String: ExercisePRsV2] = [:]
        var migratedRuns: [Run] = []
        var migratedCurrent: CurrentWorkout?

        // 1. Load from legacy Application Support location
        let oldWorkoutsURL = oldAppDir.appendingPathComponent("completed_workouts.json")
        if fileManager.fileExists(atPath: oldWorkoutsURL.path) {
            if let data = try? Data(contentsOf: oldWorkoutsURL),
               let workouts = try? decoder.decode([CompletedWorkout].self, from: data) {
                migratedWorkouts.append(contentsOf: workouts)
                print("   📦 Found \(workouts.count) workouts in legacy Application Support")
            }
        }

        let oldPRURL = oldAppDir.appendingPathComponent("pr_index.json")
        if fileManager.fileExists(atPath: oldPRURL.path) {
            if let data = try? Data(contentsOf: oldPRURL),
               let oldPRIndex = try? decoder.decode([String: ExercisePRs].self, from: data) {
                // Convert old PR format to new
                migratedPRIndex = convertOldPRIndex(oldPRIndex)
                print("   📦 Found \(migratedPRIndex.count) PR entries in legacy storage")
            }
        }

        let oldRunsURL = oldAppDir.appendingPathComponent("runs.json")
        if fileManager.fileExists(atPath: oldRunsURL.path) {
            if let data = try? Data(contentsOf: oldRunsURL),
               let runs = try? decoder.decode([Run].self, from: data) {
                migratedRuns.append(contentsOf: runs)
                print("   📦 Found \(runs.count) runs in legacy storage")
            }
        }

        let oldCurrentURL = oldAppDir.appendingPathComponent("current_workout.json")
        if fileManager.fileExists(atPath: oldCurrentURL.path) {
            if let data = try? Data(contentsOf: oldCurrentURL),
               let current = try? decoder.decode(CurrentWorkout.self, from: data) {
                migratedCurrent = current
                print("   📦 Found current workout in legacy storage")
            }
        }

        // 2. Load from old Persistence location (Documents)
        let oldPersistenceWorkoutsURL = documentsDir.appendingPathComponent("workouts.json")
        if fileManager.fileExists(atPath: oldPersistenceWorkoutsURL.path) {
            if let data = try? Data(contentsOf: oldPersistenceWorkoutsURL),
               let workouts = try? decoder.decode([CompletedWorkout].self, from: data) {
                migratedWorkouts.append(contentsOf: workouts)
                print("   📦 Found \(workouts.count) workouts in old Persistence location")
            }
        }

        let oldPersistenceRunsURL = documentsDir.appendingPathComponent("runs.json")
        if fileManager.fileExists(atPath: oldPersistenceRunsURL.path) {
            if let data = try? Data(contentsOf: oldPersistenceRunsURL),
               let runs = try? decoder.decode([Run].self, from: data) {
                migratedRuns.append(contentsOf: runs)
                print("   📦 Found \(runs.count) runs in old Persistence location")
            }
        }

        let oldPersistenceCurrentURL = documentsDir.appendingPathComponent("current_workout.json")
        if fileManager.fileExists(atPath: oldPersistenceCurrentURL.path) {
            if let data = try? Data(contentsOf: oldPersistenceCurrentURL),
               let current = try? decoder.decode(CurrentWorkout.self, from: data) {
                if migratedCurrent == nil {
                    migratedCurrent = current
                    print("   📦 Found current workout in old Persistence location")
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
            print("   🔄 Recomputing PR index from migrated workouts...")
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

        print("✅ Migration complete:")
        print("   Workouts: \(deduplicatedWorkouts.count)")
        print("   Runs: \(deduplicatedRuns.count)")
        print("   PR entries: \(migratedPRIndex.count)")
        print("   Current workout: \(migratedCurrent != nil ? "Yes" : "No")")

        // Note: Don't delete old files yet - let user verify data first
        print("⚠️ Old storage files retained for safety. You can delete them manually after verification.")
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
        print("🗑️ Cleaning up legacy storage files...")

        let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let oldAppDir = appSupportDir.appendingPathComponent("WRKT", isDirectory: true)

        if fileManager.fileExists(atPath: oldAppDir.path) {
            try fileManager.removeItem(at: oldAppDir)
            print("✅ Removed legacy Application Support directory")
        }

        let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let oldFiles = [
            "workouts.json",
            "runs.json",
            "current_workout.json"
        ]

        for filename in oldFiles {
            let url = documentsDir.appendingPathComponent(filename)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
                print("✅ Removed old Persistence file: \(filename)")
            }
        }
    }

    // MARK: - Debug & Maintenance

    func validateStorage() async throws -> Bool {
        print("🔍 Validating storage...")

        guard fileManager.fileExists(atPath: workoutsFileURL.path) else {
            print("⚠️ Workouts file not found")
            return false
        }

        let (workouts, prIndex) = try await loadWorkouts()

        // Check for duplicates
        let uniqueIDs = Set(workouts.map { $0.id })
        guard uniqueIDs.count == workouts.count else {
            print("❌ Found duplicate workout IDs")
            return false
        }

        // Validate PR index
        for (exerciseID, pr) in prIndex {
            if pr.bestPerReps.isEmpty && pr.bestE1RM == nil {
                print("⚠️ Empty PR entry for exercise: \(exerciseID)")
            }
        }

        print("✅ Storage validation passed")
        print("   Workouts: \(workouts.count)")
        print("   PR entries: \(prIndex.count)")
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

    // MARK: - Development Only

    func wipeAllData() async throws {
        print("⚠️ WIPING ALL DATA...")

        try? fileManager.removeItem(at: workoutsFileURL)
        try? fileManager.removeItem(at: currentWorkoutFileURL)
        try? fileManager.removeItem(at: runsFileURL)
        try? fileManager.removeItem(at: migrationFlagURL)
        try? fileManager.removeItem(at: backupsDirectory)

        // Also clean up legacy
        try? await cleanupLegacyStorage()

        print("✅ All data wiped")
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
