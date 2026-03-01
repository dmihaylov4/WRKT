//
//  HealthKitManager.swift
//  WRKT
//
//  Unified Health pipeline with observer queries, anchored queries,
//  background tasks, and idempotent import
//

import HealthKit
import CoreLocation
import SwiftData
import BackgroundTasks
import Combine
import OSLog
import SwiftUI
// MARK: - Connection State

enum HealthConnectionState: String, Codable {
    case connected      // Full access granted
    case limited        // Partial access or authorization pending
    case disconnected   // Not authorized or unavailable
}

// MARK: - HealthKitManager

@MainActor
final class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    let store = HKHealthStore()

    /// Increment this any time `toRead` or `toShare` gains a new type.
    /// On app launch, if the stored version is lower, requestAuthorization() will fire
    /// and iOS will prompt the user for only the new, ungranted types.
    private static let authScopeVersion = 2  // bumped when workoutRoute was added to toRead

    @Published var connectionState: HealthConnectionState {
        didSet {
            // Persist connection state to UserDefaults
            UserDefaults.standard.set(connectionState.rawValue, forKey: "healthkit.connectionState")
            AppLogger.info("⚡️ connectionState changed: \(oldValue) → \(connectionState)", category: AppLogger.health)
        }
    }

    private init() {
        // Restore connection state from UserDefaults
        if let savedState = UserDefaults.standard.string(forKey: "healthkit.connectionState"),
           let state = HealthConnectionState(rawValue: savedState) {
            self.connectionState = state
            AppLogger.debug("Restored connectionState: \(state)", category: AppLogger.health)
        } else {
            self.connectionState = .disconnected
            AppLogger.debug("No saved state, defaulting to .disconnected", category: AppLogger.health)
        }
    }

    /// True when the stored auth-scope version is behind the current one,
    /// meaning new HealthKit types were added since the user last saw the permission dialog.
    var needsAuthScopeUpdate: Bool {
        UserDefaults.standard.integer(forKey: "healthkit.authScopeVersion") < Self.authScopeVersion
    }

    private func markAuthScopeUpToDate() {
        UserDefaults.standard.set(Self.authScopeVersion, forKey: "healthkit.authScopeVersion")
    }
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: Error?

    // Progress tracking for batch sync
    @Published var syncProgress: Double = 0.0  // 0.0 to 1.0
    @Published var syncCurrentBatch: Int = 0
    @Published var syncTotalBatches: Int = 0
    @Published var syncProcessedCount: Int = 0
    @Published var syncTotalCount: Int = 0

    // Auto-sync throttling (avoid syncing too frequently)
    private var lastAutoSyncDate: Date?
    private let autoSyncThrottleInterval: TimeInterval = 5 * 60  // 5 minutes

    // Batch processing configuration
    private let batchSize = 100
    private let batchDelayMs: UInt64 = 50_000_000  // 50ms between batches

    // SwiftData context (injected from app)
    var modelContext: ModelContext?

    // WorkoutStore reference (injected from app)
    weak var workoutStore: WorkoutStoreV2?

    // Observer queries (kept alive)
    private var workoutObserver: HKObserverQuery?
    private var exerciseTimeObserver: HKObserverQuery?

    // MARK: - Authorization

    /// Check if HealthKit authorization needs to be requested
    var needsAuthorization: Bool {
        let status = store.authorizationStatus(for: HKObjectType.workoutType())
        return status == .notDetermined || connectionState == .disconnected
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            connectionState = .disconnected
            throw HKError(.errorHealthDataUnavailable)
        }

        var toRead: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute()
        ]

        let qtyIds: [HKQuantityTypeIdentifier] = [
            .heartRate,
            .restingHeartRate,  // For Karvonen HR zone calculation
            .activeEnergyBurned,
            .distanceWalkingRunning,
            .stepCount,
            .appleExerciseTime,
            .runningPower,
            .runningStrideLength,
            .runningGroundContactTime,
            .runningVerticalOscillation,
            .runningSpeed
        ]

        for id in qtyIds {
            if let qt = HKObjectType.quantityType(forIdentifier: id) {
                toRead.insert(qt)
            }
        }

        // Add date of birth characteristic type for age-based HR calculation
        if let dobType = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) {
            toRead.insert(dobType)
        }

        AppLogger.info("Requesting authorization for \(toRead.count) data types...", category: AppLogger.health)

        do {
            try await store.requestAuthorization(toShare: [], read: toRead)
            AppLogger.success("Authorization request completed", category: AppLogger.health)

            // Small delay to let iOS update its authorization state
            try? await Task.sleep(for: .milliseconds(500))

            // Test actual data access first (more reliable than status check)
            // Try multiple times with increasing delays if first attempt fails
            var canRead = false
            for attempt in 1...3 {
                canRead = await testDataAccess()
                if canRead {
                    break
                }
                AppLogger.debug("Test data access attempt \(attempt) failed, retrying...", category: AppLogger.health)
                try? await Task.sleep(for: .milliseconds(500 * attempt)) // 500ms, 1000ms, 1500ms
            }

            if canRead {
                connectionState = .connected
                AppLogger.success("HealthKit connection established", category: AppLogger.health)
            } else {
                // If all test attempts failed, assume connection is working anyway
                // (HealthKit authorization can take time to propagate)
                AppLogger.warning("Data access test failed after 3 attempts, assuming .connected", category: AppLogger.health)
                connectionState = .connected
            }
            // Stamp the version so we don't re-prompt until the scope changes again
            markAuthScopeUpToDate()
        } catch {
            AppLogger.error("HealthKit authorization failed", error: error, category: AppLogger.health)
            connectionState = .disconnected
            throw error
        }

        AppLogger.info("Final connectionState: \(connectionState)", category: AppLogger.health)
    }

    // MARK: - Authorization Verification

    /// Verify that saved connectionState matches actual HealthKit authorization
    /// DEPRECATED: This method is unreliable due to HealthKit privacy protections.
    /// authorizationStatus(for:) may return .notDetermined or .sharingDenied even after authorization.
    /// Use testDataAccess() instead for reliable verification.
    @available(*, deprecated, message: "Use testDataAccess() for reliable authorization checks")
    func verifyAuthorizationStatus() {
        guard HKHealthStore.isHealthDataAvailable() else {
            connectionState = .disconnected
            return
        }

        // Note: This check is unreliable and kept only for legacy compatibility
        // authorizationStatus(for:) returns ambiguous results due to privacy protections
        let workoutAuthStatus = store.authorizationStatus(for: .workoutType())

        AppLogger.debug("Auth verification (unreliable): connectionState=\(connectionState), actualStatus=\(workoutAuthStatus.rawValue)", category: AppLogger.health)

        // Don't automatically reset to disconnected based on this unreliable API
        // If we think we're connected, trust that until actual data access fails
    }

    // MARK: - Test Data Access

    private func testDataAccess() async -> Bool {
        do {
            // Try to fetch just 1 workout to test if we have access
            let (workouts, _, _) = try await fetchWorkoutsAnchored(anchor: nil)
            AppLogger.debug("Test query returned \(workouts.count) workouts", category: AppLogger.health)
            return true
        } catch {
            AppLogger.error("Test query failed: \(error)", category: AppLogger.health)
            return false
        }
    }

    // MARK: - Observer Queries (Background Change Notifications)

    func setupBackgroundObservers() {
        guard connectionState == .connected else {
            AppLogger.debug("Skipping observer setup - connectionState: \(connectionState)", category: AppLogger.health)
            return
        }

        // Note: We trust the connectionState that was set by testDataAccess() in requestAuthorization()
        // because authorizationStatus(for:) is unreliable due to HealthKit privacy protections.
        // It may return .notDetermined or .sharingDenied even when access was granted.

        AppLogger.info("Setting up HealthKit background observers...", category: AppLogger.health)

        // Observe workout changes
        workoutObserver = HKObserverQuery(sampleType: .workoutType(), predicate: nil) { [weak self] _, completionHandler, error in
            // Acknowledge immediately — HealthKit background budget is ~30s
            completionHandler()
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    if self.connectionState == .connected {
                        AppLogger.debug("Workout observer error: \(error)", category: AppLogger.health)
                    }
                    self.syncError = error
                } else {
                    AppLogger.info("HealthKit workout data changed - triggering sync", category: AppLogger.health)
                    await self.syncWorkoutsIncremental()
                }
            }
        }

        // Observe Apple Exercise Time changes
        if let exerciseType = HKObjectType.quantityType(forIdentifier: .appleExerciseTime) {
            exerciseTimeObserver = HKObserverQuery(sampleType: exerciseType, predicate: nil) { [weak self] _, completionHandler, error in
                // Acknowledge immediately — HealthKit background budget is ~30s
                completionHandler()
                guard let self else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let error {
                        if self.connectionState == .connected {
                            AppLogger.debug("Exercise time observer error: \(error)", category: AppLogger.health)
                        }
                    } else {
                        AppLogger.info("HealthKit exercise time changed - triggering sync", category: AppLogger.health)
                        await self.syncExerciseTimeIncremental()
                    }
                }
            }
        }

        // Start observing
        if let workoutObserver {
            store.execute(workoutObserver)
            store.enableBackgroundDelivery(for: .workoutType(), frequency: .immediate) { success, error in
                if let error {
                    AppLogger.warning("Background delivery setup failed: \(error)", category: AppLogger.health)
                } else if success {
                    AppLogger.success("Background delivery enabled for workouts", category: AppLogger.health)
                }
            }
        }

        if let exerciseTimeObserver, let exerciseType = HKObjectType.quantityType(forIdentifier: .appleExerciseTime) {
            store.execute(exerciseTimeObserver)
            store.enableBackgroundDelivery(for: exerciseType, frequency: .hourly) { success, error in
                if let error {
                    AppLogger.warning("Background delivery setup failed for exercise time: \(error)", category: AppLogger.health)
                } else if success {
                    AppLogger.success("Background delivery enabled for exercise time", category: AppLogger.health)
                }
            }
        }
    }

    func stopBackgroundObservers() {
        if let workoutObserver {
            store.stop(workoutObserver)
        }
        if let exerciseTimeObserver {
            store.stop(exerciseTimeObserver)
        }
        self.workoutObserver = nil
        self.exerciseTimeObserver = nil
    }

    // MARK: - Incremental Sync (Anchored Queries)

    /// Performs auto-sync if data is stale (throttled to avoid excessive syncing)
    /// Returns true if sync was performed
    @discardableResult
    func autoSyncIfNeeded() async -> Bool {
        // Only sync if connected
        guard connectionState == .connected else { return false }

        // Don't sync if already syncing
        guard !isSyncing else { return false }

        // Check if we need to sync (throttle to avoid too frequent syncs)
        let now = Date()
        if let lastSync = lastAutoSyncDate {
            let timeSinceLastSync = now.timeIntervalSince(lastSync)
            if timeSinceLastSync < autoSyncThrottleInterval {
                AppLogger.debug("Skipping auto-sync (last sync was \(Int(timeSinceLastSync))s ago)", category: AppLogger.health)
                return false
            }
        }

        AppLogger.info("Auto-syncing HealthKit data...", category: AppLogger.health)
        lastAutoSyncDate = now

        await syncWorkoutsIncremental()
        await syncExerciseTimeIncremental()

        return true
    }

    func syncWorkoutsIncremental() async {
        guard let context = modelContext else {
            AppLogger.warning("ModelContext not set", category: AppLogger.health)
            return
        }
        guard !isSyncing else { return }

        // Re-request auth when the scope has been extended since the user last saw the dialog
        // (HealthKit is idempotent — it only prompts for genuinely new types)
        if connectionState != .connected || needsAuthScopeUpdate {
            AppLogger.info("Requesting HealthKit authorization (connected: \(connectionState == .connected), scopeStale: \(needsAuthScopeUpdate))", category: AppLogger.health)
            do {
                try await requestAuthorization()
            } catch {
                AppLogger.error("HealthKit authorization failed: \(error.localizedDescription)", category: AppLogger.health)
                return
            }
        }

        isSyncing = true
        defer { isSyncing = false }

        do {
            // Fetch or create anchor
            let anchorRecord = try fetchOrCreateAnchor(dataType: "all_workouts", context: context)
            let anchor = anchorRecord.anchor

            AppLogger.debug("Syncing workouts (anchor: \(anchor != nil ? "exists" : "nil"), last sync: \(anchorRecord.lastSyncDate))", category: AppLogger.health)

            // Anchored query
            let (added, deleted, newAnchor) = try await fetchWorkoutsAnchored(anchor: anchor)

            AppLogger.info("📊 Incremental sync: Added: \(added.count), Deleted: \(deleted.count)", category: AppLogger.health)

            if added.isEmpty && deleted.isEmpty {
                AppLogger.debug("No new workouts found since last sync", category: AppLogger.health)
            }

            // Process additions
            for workout in added {
                try await importWorkoutIdempotent(workout, context: context)
            }

            // Process deletions
            for deletedWorkout in deleted {
                try deleteWorkoutIfExists(uuid: deletedWorkout.uuid, context: context)
            }

            // Update anchor
            anchorRecord.updateAnchor(newAnchor)
            try context.save()

            lastSyncDate = .now
            syncError = nil

            // Queue route fetching for recently added workouts
            await queueRouteFetching(for: added, context: context)

            // Match app workouts with newly imported HealthKit workouts
            if !added.isEmpty {
                let strengthTypes: Set = ["Strength Training", "Functional Training", "Core Training"]
                let hasStrengthWorkouts = added.contains { workout in
                    strengthTypes.contains(workoutActivityTypeName(workout.workoutActivityType))
                }

                if hasStrengthWorkouts {
                    AppLogger.info("Imported \(added.count) HealthKit workouts, attempting to match with app workouts", category: AppLogger.health)
                    await MainActor.run {
                        // Match workouts from the last 7 days (recent window)
                        workoutStore?.matchRecentWorkoutsWithHealthKit(days: 7)
                    }
                }
            }

        } catch {
            AppLogger.error("Workout sync failed: \(error)", category: AppLogger.health)
            syncError = error
        }
    }

    /// Sync recent workouts by resetting the anchor (used for pull-to-refresh)
    /// More reliable than incremental sync, more efficient than full resync
    func syncRecentWorkouts() async {
        guard let context = modelContext else {
            AppLogger.warning("ModelContext not set", category: AppLogger.health)
            return
        }

        AppLogger.info("📊 Syncing recent workouts (resetting anchor)", category: AppLogger.health)

        // Ensure authorization before syncing (also re-prompts when scope has been extended)
        if connectionState != .connected || needsAuthScopeUpdate {
            AppLogger.info("📊 Requesting HealthKit authorization (scopeStale: \(needsAuthScopeUpdate))...", category: AppLogger.health)
            do {
                try await requestAuthorization()
            } catch {
                AppLogger.error("❌ HealthKit authorization failed: \(error.localizedDescription)", category: AppLogger.health)
                return
            }
        }

        isSyncing = true
        defer { isSyncing = false }

        do {
            // Delete the anchor to force re-fetch of recent data
            let descriptor = FetchDescriptor<HealthSyncAnchor>(
                predicate: #Predicate { $0.dataType == "all_workouts" }
            )
            if let existingAnchor = try context.fetch(descriptor).first {
                context.delete(existingAnchor)
                try context.save()
                AppLogger.debug("Reset sync anchor for recent workout sync", category: AppLogger.health)
            }

            // Check authorization status
            let workoutType = HKObjectType.workoutType()
            let authStatus = store.authorizationStatus(for: workoutType)
            let authStatusStr: String
            switch authStatus {
            case .notDetermined: authStatusStr = "NOT DETERMINED"
            case .sharingDenied: authStatusStr = "DENIED"
            case .sharingAuthorized: authStatusStr = "AUTHORIZED"
            @unknown default: authStatusStr = "UNKNOWN"
            }
            AppLogger.info("📊 HealthKit Workout READ authorization: \(authStatusStr)", category: AppLogger.health)

            // First, get the last 10 workouts from HealthKit (no date filter, no type filter)
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

            let last10Workouts = try await fetchLastNWorkouts(limit: 10)
            AppLogger.info("📊 LAST 10 WORKOUTS IN HEALTHKIT (ALL TYPES):", category: AppLogger.health)
            if last10Workouts.isEmpty {
                AppLogger.warning("  ⚠️ NO WORKOUTS FOUND - Check HealthKit permissions!", category: AppLogger.health)
            }
            for workout in last10Workouts {
                let typeName = workoutActivityTypeName(workout.workoutActivityType)
                AppLogger.info("  - \(typeName) ended: \(dateFormatter.string(from: workout.endDate)) (duration: \(Int(workout.duration / 60)) min)", category: AppLogger.health)
            }

            // Now do the anchored fetch
            let (added, deleted, newAnchor) = try await fetchWorkoutsAnchored(anchor: nil)
            AppLogger.info("📊 ANCHORED QUERY: returned \(added.count) workouts total", category: AppLogger.health)

            // Filter to only recent workouts (last 14 days)
            let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: Date())!
            let recentWorkouts = added.filter { $0.startDate >= twoWeeksAgo }

            AppLogger.info("📊 Found \(recentWorkouts.count) recent workouts (last 14 days) out of \(added.count) total", category: AppLogger.health)

            // Process recent additions
            for workout in recentWorkouts {
                try await importWorkoutIdempotent(workout, context: context)
            }

            // Process deletions
            for deletedWorkout in deleted {
                try deleteWorkoutIfExists(uuid: deletedWorkout.uuid, context: context)
            }

            // Create new anchor with the current state
            let newAnchorRecord = HealthSyncAnchor(dataType: "all_workouts")
            newAnchorRecord.updateAnchor(newAnchor)
            context.insert(newAnchorRecord)
            try context.save()

            lastSyncDate = .now
            syncError = nil

            // Queue route fetching for recently added workouts
            await queueRouteFetching(for: recentWorkouts, context: context)

            // Match app workouts with newly imported HealthKit workouts
            if !recentWorkouts.isEmpty {
                let strengthTypes: Set = ["Strength Training", "Functional Training", "Core Training"]
                let hasStrengthWorkouts = recentWorkouts.contains { workout in
                    strengthTypes.contains(workoutActivityTypeName(workout.workoutActivityType))
                }

                if hasStrengthWorkouts {
                    AppLogger.info("Imported \(recentWorkouts.count) recent HealthKit workouts, attempting to match with app workouts", category: AppLogger.health)
                    await MainActor.run {
                        workoutStore?.matchRecentWorkoutsWithHealthKit(days: 14)
                    }
                }
            }

            AppLogger.success("✅ Recent workout sync completed", category: AppLogger.health)

        } catch {
            AppLogger.error("Recent workout sync failed: \(error)", category: AppLogger.health)
            syncError = error
        }
    }

    /// Force re-import all workouts from HealthKit with batched, parallel processing
    func forceFullResync() async {
        AppLogger.info("forceFullResync() called - batched mode", category: AppLogger.health)

        guard let context = modelContext else {
            AppLogger.warning("ModelContext not set", category: AppLogger.health)
            return
        }

        guard let store = workoutStore else {
            AppLogger.warning("WorkoutStore not set", category: AppLogger.health)
            return
        }

        AppLogger.success("ModelContext and WorkoutStore are set", category: AppLogger.health)

        isSyncing = true
        defer {
            isSyncing = false
            syncProgress = 0.0
            syncCurrentBatch = 0
            syncTotalBatches = 0
            syncProcessedCount = 0
            syncTotalCount = 0
            AppLogger.debug("isSyncing set to false", category: AppLogger.health)
        }

        do {
            AppLogger.info("Starting batched full re-sync of all HealthKit workouts...", category: AppLogger.health)
            AppLogger.debug("Current runs count: \(await MainActor.run { store.runs.count })", category: AppLogger.health)

            // Delete the anchor to force full re-import
            let descriptor = FetchDescriptor<HealthSyncAnchor>(
                predicate: #Predicate { $0.dataType == "all_workouts" }
            )
            if let existingAnchor = try context.fetch(descriptor).first {
                context.delete(existingAnchor)
                try context.save()
                AppLogger.success("Reset sync anchor", category: AppLogger.health)
            }

            // Perform full sync (with nil anchor, it fetches everything)
            let (added, deleted, newAnchor) = try await fetchWorkoutsAnchored(anchor: nil)

            AppLogger.info("Processing \(added.count) workouts in batches of \(batchSize)", category: AppLogger.health)

            // Update progress tracking
            await MainActor.run {
                syncTotalCount = added.count
                syncTotalBatches = (added.count + batchSize - 1) / batchSize
                syncProcessedCount = 0
                syncCurrentBatch = 0
                syncProgress = 0.0
            }

            // Split workouts into batches
            let batches = stride(from: 0, to: added.count, by: batchSize).map { startIndex in
                Array(added[startIndex..<min(startIndex + batchSize, added.count)])
            }

            // Process each batch with parallel processing
            for (batchIndex, batch) in batches.enumerated() {
                await MainActor.run {
                    syncCurrentBatch = batchIndex + 1
                    AppLogger.info("Processing batch \(batchIndex + 1)/\(batches.count) (\(batch.count) workouts)", category: AppLogger.health)
                }

                // Process batch in parallel using TaskGroup
                let batchResults = await processBatchInParallel(batch, store: store)

                // Apply results on main actor
                await MainActor.run {
                    if !batchResults.updatedRuns.isEmpty {
                        store.batchUpdateRuns(batchResults.updatedRuns)
                    }

                    for newRun in batchResults.newRuns {
                        store.addRun(newRun)
                    }

                    syncProcessedCount += batch.count
                    syncProgress = Double(syncProcessedCount) / Double(syncTotalCount)

                    AppLogger.success("Batch complete: \(syncProcessedCount)/\(syncTotalCount) (\((syncProgress * 100).safeInt)%)", category: AppLogger.health)
                }

                // Small delay between batches to keep UI responsive
                if batchIndex < batches.count - 1 {
                    try? await Task.sleep(nanoseconds: batchDelayMs)
                }
            }

            // Process deletions
            for deletedWorkout in deleted {
                try deleteWorkoutIfExists(uuid: deletedWorkout.uuid, context: context)
            }

            // Save new anchor
            let anchorRecord = try fetchOrCreateAnchor(dataType: "all_workouts", context: context)
            anchorRecord.updateAnchor(newAnchor)
            try context.save()

            lastSyncDate = .now
            syncError = nil

            AppLogger.success("Batched full re-sync complete! Processed \(added.count) workouts in \(batches.count) batches", category: AppLogger.health)

            // Queue route fetching for recent workouts
            await queueRouteFetching(for: Array(added.prefix(20)), context: context)

        } catch {
            AppLogger.error("Full re-sync failed: \(error)", category: AppLogger.health)
            syncError = error
        }
    }

    /// Process a batch of workouts in parallel using TaskGroup
    private func processBatchInParallel(_ batch: [HKWorkout], store: WorkoutStoreV2) async -> (updatedRuns: [Run], newRuns: [Run]) {
        var updatedRuns: [Run] = []
        var newRuns: [Run] = []

        await withTaskGroup(of: (Run?, Bool).self) { group in
            // Add tasks for each workout in the batch
            for workout in batch {
                group.addTask {
                    // Check if run already exists
                    let existingRun = await MainActor.run {
                        store.runs.first(where: { $0.healthKitUUID == workout.uuid })
                    }

                    if let existing = existingRun {
                        // Update existing run
                        var updated = existing
                        updated.date = workout.endDate
                        updated.distanceKm = (workout.totalDistance?.doubleValue(for: .meter()) ?? 0) / 1000.0
                        updated.durationSec = workout.duration.safeInt
                        updated.calories = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())

                        let newType = self.workoutActivityTypeName(workout.workoutActivityType)
                        updated.workoutType = newType
                        updated.workoutName = workout.metadata?[HKMetadataKeyWorkoutBrandName] as? String

                        // Fetch heart rate if missing or 0 (Apple Watch data may not be available immediately)
                        if updated.avgHeartRate == nil || updated.avgHeartRate == 0 {
                            updated.avgHeartRate = try? await self.averageHeartRate(for: workout)
                        }

                        return (updated, true)  // true = existing
                    } else {
                        // Import new workout
                        let km = (workout.totalDistance?.doubleValue(for: .meter()) ?? 0) / 1000.0
                        let sec = workout.duration.safeInt
                        let kcal = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())
                        let avgHR = try? await self.averageHeartRate(for: workout)
                        let workoutType = self.workoutActivityTypeName(workout.workoutActivityType)
                        let workoutName = workout.metadata?[HKMetadataKeyWorkoutBrandName] as? String

                        let run = Run(
                            date: workout.endDate,
                            distanceKm: km,
                            durationSec: sec,
                            notes: nil,
                            healthKitUUID: workout.uuid,
                            avgHeartRate: avgHR,
                            calories: kcal,
                            route: nil,
                            workoutType: workoutType,
                            workoutName: workoutName
                        )

                        return (run, false)  // false = new
                    }
                }
            }

            // Collect results
            for await (run, isExisting) in group {
                if let run = run {
                    if isExisting {
                        updatedRuns.append(run)
                    } else {
                        newRuns.append(run)
                    }
                }
            }
        }

        return (updatedRuns, newRuns)
    }

    func syncExerciseTimeIncremental() async {
        guard let context = modelContext else { return }

        do {
            let anchorRecord = try fetchOrCreateAnchor(dataType: "exercise_time", context: context)
            let anchor = anchorRecord.anchor

            let (samples, newAnchor) = try await fetchExerciseTimeSamplesAnchored(anchor: anchor)

            AppLogger.info("Syncing exercise time: \(samples.count) samples", category: AppLogger.health)

            // Aggregate by week and update WeeklyTrainingSummary
            await aggregateExerciseTimeIntoWeeklySummaries(samples: samples, context: context)

            // Update anchor
            anchorRecord.updateAnchor(newAnchor)
            try context.save()

        } catch {
            AppLogger.error("Exercise time sync failed: \(error)", category: AppLogger.health)
        }
    }

    // MARK: - Direct Query (for debugging)

    /// Fetch the last N workouts from HealthKit (no date filter, sorted by end date descending)
    private func fetchLastNWorkouts(limit: Int) async throws -> [HKWorkout] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: nil,  // No filter - get everything
                limit: limit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let workouts = (samples as? [HKWorkout]) ?? []
                continuation.resume(returning: workouts)
            }

            store.execute(query)
        }
    }

    // MARK: - Anchored Query Implementations

    private func fetchWorkoutsAnchored(anchor: HKQueryAnchor?) async throws -> (added: [HKWorkout], deleted: [HKDeletedObject], newAnchor: HKQueryAnchor?) {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: .workoutType(),
                predicate: nil,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { _, addedSamples, deletedSamples, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let added = (addedSamples as? [HKWorkout]) ?? []
                let deleted = deletedSamples ?? []
                continuation.resume(returning: (added, deleted, newAnchor))
            }

            store.execute(query)
        }
    }

    private func fetchExerciseTimeSamplesAnchored(anchor: HKQueryAnchor?) async throws -> (samples: [HKQuantitySample], newAnchor: HKQueryAnchor?) {
        guard let exerciseType = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) else {
            return ([], nil)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: exerciseType,
                predicate: nil,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { _, addedSamples, _, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let samples = (addedSamples as? [HKQuantitySample]) ?? []
                continuation.resume(returning: (samples, newAnchor))
            }

            store.execute(query)
        }
    }

    // MARK: - Anchor Persistence

    private func fetchOrCreateAnchor(dataType: String, context: ModelContext) throws -> HealthSyncAnchor {
        let descriptor = FetchDescriptor<HealthSyncAnchor>(
            predicate: #Predicate { $0.dataType == dataType }
        )

        if let existing = try context.fetch(descriptor).first {
            return existing
        }

        let newAnchor = HealthSyncAnchor(dataType: dataType)
        context.insert(newAnchor)
        return newAnchor
    }

    // MARK: - Idempotent Workout Import

    private func importWorkoutIdempotent(_ workout: HKWorkout, context: ModelContext) async throws {
        guard let store = workoutStore else {
            AppLogger.warning("WorkoutStore not set", category: AppLogger.health)
            return
        }

        // Check if this workout should be ignored (from a discarded app workout)
        let strengthTypes: Set<HKWorkoutActivityType> = [.traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining]
        if strengthTypes.contains(workout.workoutActivityType) {
            let shouldIgnore = await MainActor.run {
                store.shouldIgnoreHealthKitWorkout(uuid: workout.uuid, startDate: workout.startDate, endDate: workout.endDate)
            }
            if shouldIgnore {
                AppLogger.info("Skipping discarded strength workout: \(workout.uuid)", category: AppLogger.health)
                // Add to permanent ignore list
                await MainActor.run {
                    store.addIgnoredHealthKitUUID(workout.uuid)
                }
                return
            }
        }

        // Check if already imported
        let existing = await MainActor.run {
            store.runs.first(where: { $0.healthKitUUID == workout.uuid })
        }

        if let existing {
            // Update if needed (e.g., if HealthKit data changed)
            var updated = existing
            updated.distanceKm = (workout.totalDistance?.doubleValue(for: .meter()) ?? 0) / 1000.0
            updated.durationSec = workout.duration.safeInt
            updated.calories = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())
            let workoutType = workoutActivityTypeName(workout.workoutActivityType)
            updated.workoutType = workoutType
            updated.workoutName = workout.metadata?[HKMetadataKeyWorkoutBrandName] as? String

            // Refetch heart rate if missing or 0 (Apple Watch data may not be available immediately)
            if updated.avgHeartRate == nil || updated.avgHeartRate == 0 {
                updated.avgHeartRate = try? await averageHeartRate(for: workout)
                if let hr = updated.avgHeartRate {
                    AppLogger.debug("Refetched heart rate for \(workoutType): \(Int(hr)) bpm", category: AppLogger.health)
                }
            }

            // Only persist if data actually changed to avoid redundant saves
            guard updated != existing else { return }

            AppLogger.debug("Updating: \(workoutType) at \(workout.startDate.formatted(date: .abbreviated, time: .shortened))", category: AppLogger.health)

            await MainActor.run {
                store.updateRun(updated)
            }
            return
        }

        // Import new workout
        let km = (workout.totalDistance?.doubleValue(for: .meter()) ?? 0) / 1000.0
        let sec = workout.duration.safeInt
        let kcal = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())

        // Fetch average heart rate
        let avgHR = try? await averageHeartRate(for: workout)

        // Extract workout type name (e.g., "Running", "Cycling", "Traditional Strength Training")
        let workoutType = workoutActivityTypeName(workout.workoutActivityType)

        // Extract custom workout name from metadata (if user named it in Apple Fitness)
        let workoutName = workout.metadata?[HKMetadataKeyWorkoutBrandName] as? String

        AppLogger.debug("Importing: \(workoutType) at \(workout.startDate.formatted(date: .abbreviated, time: .shortened))", category: AppLogger.health)

        let run = Run(
            date: workout.endDate,  // Use END date for matching with app workout completion time
            distanceKm: km,
            durationSec: sec,
            notes: nil,
            healthKitUUID: workout.uuid,
            avgHeartRate: avgHR,
            calories: kcal,
            route: nil,  // Fetched separately via queue
            workoutType: workoutType,
            workoutName: workoutName
        )

        await MainActor.run {
            store.addRun(run)
        }

        // Note: Auto-post for cardio is triggered in processRouteFetchQueue
        // after route data is fetched, so posts include the map visualization
    }

    private func deleteWorkoutIfExists(uuid: UUID, context: ModelContext) throws {
        guard let store = workoutStore else {
            AppLogger.warning("WorkoutStore not set", category: AppLogger.health)
            return
        }

        // HealthKitManager is @MainActor, so this method is already on the main actor.
        // Call store directly — no Task wrapper needed (and a Task would defer the
        // deletion past context.save(), causing the save to miss it).
        if let existing = store.runs.first(where: { $0.healthKitUUID == uuid }) {
            store.removeRun(withId: existing.id)
            AppLogger.info("Deleted workout: \(uuid)", category: AppLogger.health)
        }
    }

    // MARK: - Delete Workout

    /// Delete a cardio workout from HealthKit and local storage
    func deleteCardioWorkout(run: Run) async throws {
        guard connectionState == .connected else {
            AppLogger.warning("Cannot delete workout - HealthKit not authorized", category: AppLogger.health)
            throw SupabaseError.notAuthenticated
        }

        // Delete from HealthKit if it has a HealthKit UUID
        if let hkUUID = run.healthKitUUID {
            AppLogger.info("Deleting workout from HealthKit: \(hkUUID)", category: AppLogger.health)

            // Find the HKWorkout object
            let predicate = HKQuery.predicateForObject(with: hkUUID)
            let workouts = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKWorkout], Error>) in
                let query = HKSampleQuery(
                    sampleType: .workoutType(),
                    predicate: predicate,
                    limit: 1,
                    sortDescriptors: nil
                ) { _, samples, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: samples as? [HKWorkout] ?? [])
                    }
                }
                store.execute(query)
            }

            // Delete from HealthKit
            if !workouts.isEmpty {
                try await store.delete(workouts)
                AppLogger.success("Deleted workout from HealthKit", category: AppLogger.health)
            }
        }

        // Delete from local storage
        await MainActor.run {
            workoutStore?.removeRun(withId: run.id)
            AppLogger.success("Deleted workout from local storage", category: AppLogger.health)
        }
    }

    // MARK: - Route Fetching Queue

    private func queueRouteFetching(for workouts: [HKWorkout], context: ModelContext) async {
        for workout in workouts {
            // Check if task already exists
            let workoutUUIDString = workout.uuid.uuidString
            let descriptor = FetchDescriptor<RouteFetchTask>(
                predicate: #Predicate { $0.workoutUUID == workoutUUIDString }
            )

            if (try? context.fetch(descriptor).first) == nil {
                let priority = workouts.firstIndex(of: workout) ?? 0 < 5 ? 0 : 1  // High priority for recent 5
                let task = RouteFetchTask(
                    workoutUUID: workout.uuid.uuidString,
                    workoutDate: workout.startDate,
                    priority: priority
                )
                context.insert(task)
            }
        }

        try? context.save()

        // Process queue in background
        Task.detached { [weak self] in
            await self?.processRouteFetchQueue()
        }
    }

    /// Resets a "failed" route task for the given workout UUID back to "pending" so the
    /// next `processRouteFetchQueue` run will retry it.  Called when the user manually
    /// opens the share sheet for a run whose background fetch was exhausted.
    func retryFailedRouteTaskIfNeeded(for workoutUUID: UUID) async {
        guard let context = modelContext else { return }
        let uuidString = workoutUUID.uuidString
        let descriptor = FetchDescriptor<RouteFetchTask>(
            predicate: #Predicate { $0.workoutUUID == uuidString && $0.status == "failed" }
        )
        guard let task = try? context.fetch(descriptor).first else { return }
        task.status = "pending"
        task.attemptCount = 0
        try? context.save()
        AppLogger.info("Reset failed route task to pending for retry: \(uuidString)", category: AppLogger.health)
        Task.detached { [weak self] in
            await self?.processRouteFetchQueue(limit: 1)
        }
    }

    func processRouteFetchQueue(limit: Int = 10) async {
        guard let context = modelContext else { return }

        // Reset any tasks that got stuck in "fetching" state (e.g., app killed mid-processing).
        // Use a 2-minute staleness window — legitimate fetches complete well within that.
        let staleThreshold = Date.now.addingTimeInterval(-120)
        let fetchingDescriptor = FetchDescriptor<RouteFetchTask>(
            predicate: #Predicate { $0.status == "fetching" }
        )
        if let stuckTasks = try? context.fetch(fetchingDescriptor) {
            let stale = stuckTasks.filter { ($0.lastAttemptDate ?? .distantPast) < staleThreshold }
            for task in stale {
                task.status = "pending"
                AppLogger.warning("Reset stale 'fetching' route task to 'pending': \(task.workoutUUID)", category: AppLogger.health)
            }
            if !stale.isEmpty { try? context.save() }
        }

        // Fetch pending tasks (prioritized)
        let descriptor = FetchDescriptor<RouteFetchTask>(
            predicate: #Predicate { $0.status == "pending" },
            sortBy: [SortDescriptor(\.priority), SortDescriptor(\.workoutDate, order: .reverse)]
        )

        guard let tasks = try? context.fetch(descriptor), !tasks.isEmpty else {
            AppLogger.debug("No pending route fetch tasks", category: AppLogger.health)
            return
        }

        AppLogger.info("Processing \(tasks.count) route fetch tasks (limit: \(limit))", category: AppLogger.health)

        let tasksToProcess = limit > 0 ? Array(tasks.prefix(limit)) : tasks
        for task in tasksToProcess {
            task.status = "fetching"
            task.lastAttemptDate = Date.now

            do {
                guard let uuid = UUID(uuidString: task.workoutUUID) else { continue }

                // Fetch workout from HealthKit
                let workouts = try await fetchWorkoutByUUID(uuid)
                guard let workout = workouts.first else {
                    task.status = "failed"
                    continue
                }

                // Fetch route, splits, heart rate data, and running metrics
                let locations = try await fetchRoute(for: workout)
                let routeWithHR = try? await fetchRouteWithHeartRate(for: workout)
                let splits = try? await fetchKilometerSplits(for: workout)
                let runningMetrics = await fetchRunningMetrics(for: workout)

                // Update Run with route, HR data, splits, and running metrics
                let coords = locations.map { Coordinate(lat: $0.coordinate.latitude, lon: $0.coordinate.longitude) }

                await MainActor.run {
                    if let store = workoutStore,
                       let existing = store.runs.first(where: { $0.healthKitUUID == uuid }) {
                        var updated = existing
                        updated.route = coords.isEmpty ? nil : coords
                        updated.routeWithHR = routeWithHR
                        updated.splits = splits
                        updated.avgRunningPower = runningMetrics.avgPower
                        updated.avgCadence = runningMetrics.avgCadence
                        updated.avgStrideLength = runningMetrics.avgStrideLength
                        updated.avgGroundContactTime = runningMetrics.avgGroundContactTime
                        updated.avgVerticalOscillation = runningMetrics.avgVerticalOscillation
                        store.updateRun(updated)

                        if coords.isEmpty {
                            // Route not yet available in HealthKit — retry up to 3 times
                            task.attemptCount += 1
                            task.status = task.attemptCount >= 3 ? "failed" : "pending"
                            AppLogger.warning("Route fetch returned no coordinates for \(uuid), attempt \(task.attemptCount)/3 → \(task.status)", category: AppLogger.health)

                            // After exhausting retries, still trigger auto-post without route
                            if task.status == "failed" {
                                let workoutType = updated.workoutType?.lowercased() ?? ""
                                if workoutType.contains("run") && updated.distanceKm >= 1.0 {
                                    Task {
                                        await CardioAutoPostService.shared.handleRunIfNeeded(run: updated)
                                    }
                                }
                            }
                        } else {
                            task.status = "completed"
                            AppLogger.success("Fetched route for \(uuid): \(coords.count) points, HR: \(routeWithHR != nil), \(splits?.count ?? 0) splits", category: AppLogger.health)

                            // Trigger auto-post for cardio workouts with route data
                            let workoutType = updated.workoutType?.lowercased() ?? ""
                            if workoutType.contains("run") && updated.distanceKm >= 1.0 {
                                Task {
                                    await CardioAutoPostService.shared.handleRunIfNeeded(
                                        run: updated,
                                        route: coords,
                                        routeWithHR: routeWithHR
                                    )
                                }
                            }
                        }
                    } else {
                        task.status = "failed"
                        AppLogger.warning("Route fetch completed but run not found in store for \(uuid)", category: AppLogger.health)
                    }
                }

            } catch {
                task.attemptCount += 1
                task.status = task.attemptCount >= 3 ? "failed" : "pending"
                AppLogger.warning("Route fetch failed: \(error)", category: AppLogger.health)

                // Still attempt auto-post even if route fetch failed (route is optional)
                if task.status == "failed" {
                    await MainActor.run {
                        if let store = workoutStore,
                           let uuid = UUID(uuidString: task.workoutUUID),
                           let existing = store.runs.first(where: { $0.healthKitUUID == uuid }) {
                            let workoutType = existing.workoutType?.lowercased() ?? ""
                            if workoutType.contains("run") && existing.distanceKm >= 1.0 {
                                Task {
                                    await CardioAutoPostService.shared.handleRunIfNeeded(run: existing)
                                }
                            }
                        }
                    }
                }
            }

            try? context.save()
        }
    }

    // MARK: - Route Fetching

    func fetchRoute(for workout: HKWorkout) async throws -> [CLLocation] {
        // Pass 1: workout-association predicate (most precise — links directly to this HKWorkout)
        let associated = try await fetchRouteLocations(predicate: HKQuery.predicateForObjects(from: workout))
        if !associated.isEmpty {
            AppLogger.debug("Route via association predicate: \(associated.count) pts", category: AppLogger.health)
            return associated
        }

        // Pass 2: time-window fallback — catches cases where association link is missing
        // (e.g. Watch sync completed but metadata association dropped)
        AppLogger.warning("No route via association for \(workout.uuid) — trying time-window fallback", category: AppLogger.health)
        let timePredicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: .strictStartDate
        )
        let timeBased = try await fetchRouteLocations(predicate: timePredicate, limit: 1)
        if !timeBased.isEmpty {
            AppLogger.debug("Route via time-window fallback: \(timeBased.count) pts", category: AppLogger.health)
        } else {
            AppLogger.warning("No route found via either predicate for \(workout.uuid) — check HealthKit route read permission in Settings > Health > Apps > WRKT", category: AppLogger.health)
        }
        return timeBased
    }

    /// Shared helper: runs HKSampleQuery for a route then streams it via HKWorkoutRouteQuery.
    private func fetchRouteLocations(predicate: NSPredicate, limit: Int = HKObjectQueryNoLimit) async throws -> [CLLocation] {
        let routeType = HKSeriesType.workoutRoute()
        return try await withCheckedThrowingContinuation { cont in
            let routeQuery = HKSampleQuery(
                sampleType: routeType,
                predicate: predicate,
                limit: limit,
                sortDescriptors: nil
            ) { [weak self] _, samples, error in
                guard let self else {
                    if let error { cont.resume(throwing: error) } else { cont.resume(returning: []) }
                    return
                }
                if let error { cont.resume(throwing: error); return }
                guard let routes = samples as? [HKWorkoutRoute], let route = routes.first else {
                    cont.resume(returning: [])
                    return
                }

                var points: [CLLocation] = []
                var didResume = false
                let q = HKWorkoutRouteQuery(route: route) { _, locations, done, err in
                    guard !didResume else { return }
                    if let err {
                        didResume = true
                        cont.resume(throwing: err)
                        return
                    }
                    if let locations { points.append(contentsOf: locations) }
                    if done {
                        didResume = true
                        cont.resume(returning: points)
                    }
                }
                self.store.execute(q)
            }
            store.execute(routeQuery)
        }
    }

    // MARK: - Helper Queries

    func fetchWorkoutByUUID(_ uuid: UUID) async throws -> [HKWorkout] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForObject(with: uuid)
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }
    }

    private func averageHeartRate(for workout: HKWorkout) async throws -> Double? {
        guard let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return nil }
        let pred = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: [])

        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: hrType, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, s, e in
                if let e { cont.resume(throwing: e); return }
                cont.resume(returning: (s as? [HKQuantitySample]) ?? [])
            }
            store.execute(q)
        }

        guard !samples.isEmpty else { return nil }
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        let values = samples.map { $0.quantity.doubleValue(for: bpmUnit) }
        return values.reduce(0, +) / Double(values.count)
    }

    // MARK: - Resting Heart Rate & Age (for Karvonen HR Zones)

    /// Fetch average resting heart rate over past N days
    func fetchAverageRestingHeartRate(days: Int = 14) async throws -> Double? {
        guard let restingHRType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else {
            return nil
        }

        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date(), options: .strictStartDate)

        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { cont in
            let query = HKSampleQuery(
                sampleType: restingHRType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, s, e in
                if let e { cont.resume(throwing: e); return }
                cont.resume(returning: (s as? [HKQuantitySample]) ?? [])
            }
            store.execute(query)
        }

        guard !samples.isEmpty else { return nil }

        let unit = HKUnit.count().unitDivided(by: .minute())
        let total = samples.reduce(0.0) { $0 + $1.quantity.doubleValue(for: unit) }
        return total / Double(samples.count)
    }

    /// Fetch user's age from HealthKit date of birth
    func fetchUserAge() -> Int? {
        do {
            let dobComponents = try store.dateOfBirthComponents()
            guard let dob = Calendar.current.date(from: dobComponents) else { return nil }
            let ageComponents = Calendar.current.dateComponents([.year], from: dob, to: Date())
            return ageComponents.year
        } catch {
            AppLogger.debug("Could not fetch date of birth: \(error)", category: AppLogger.health)
            return nil
        }
    }

    // MARK: - Heart Rate Samples (for graphing)

    func fetchHeartRateSamples(for workout: HKWorkout) async throws -> (samples: [HeartRateSample], avg: Double, max: Double, min: Double) {
        guard let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            return ([], 0, 0, 0)
        }

        let pred = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: [])
        let sortByDate = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let hkSamples: [HKQuantitySample] = try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: hrType, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: [sortByDate]) { _, s, e in
                if let e { cont.resume(throwing: e); return }
                cont.resume(returning: (s as? [HKQuantitySample]) ?? [])
            }
            store.execute(q)
        }

        guard !hkSamples.isEmpty else { return ([], 0, 0, 0) }

        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        let samples = hkSamples.map { sample in
            HeartRateSample(
                timestamp: sample.startDate,
                bpm: sample.quantity.doubleValue(for: bpmUnit)
            )
        }

        let bpms = samples.map { $0.bpm }
        let avg = bpms.reduce(0, +) / Double(bpms.count)
        let max = bpms.max() ?? 0
        let min = bpms.min() ?? 0

        return (samples, avg, max, min)
    }

    // MARK: - Kilometer Splits Calculation

    /// Fetches actual per-kilometer splits by querying distance samples
    func fetchKilometerSplits(for workout: HKWorkout) async throws -> [KilometerSplit] {

        guard let distanceType = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) else {
            AppLogger.warning("Distance type not available for splits", category: AppLogger.health)
            return []
        }

        // CRITICAL: Use predicateForObjects to get ONLY samples associated with THIS workout
        // Using time-based predicate would include samples from other activities in the same timeframe
        let pred = HKQuery.predicateForObjects(from: workout)
        let sortByDate = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        AppLogger.debug("Fetching distance samples for workout UUID: \(workout.uuid)", category: AppLogger.health)

        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: distanceType, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: [sortByDate]) { _, s, e in
                if let e {
                    cont.resume(throwing: e)
                    return
                }
                let samples = (s as? [HKQuantitySample]) ?? []
                cont.resume(returning: samples)
            }
            store.execute(q)
        }

        AppLogger.debug("Found \(samples.count) distance samples", category: AppLogger.health)

        guard !samples.isEmpty else {
            AppLogger.warning("No distance samples found for workout", category: AppLogger.health)
            return []
        }

        // Build timeline of distance points with timestamps
        let meterUnit = HKUnit.meter()
        struct DistancePoint {
            let timestamp: Date
            let cumulativeMeters: Double
        }

        var distancePoints: [DistancePoint] = [DistancePoint(timestamp: workout.startDate, cumulativeMeters: 0)]
        var cumulativeMeters = 0.0

        for sample in samples {
            let distanceMeters = sample.quantity.doubleValue(for: meterUnit)
            cumulativeMeters += distanceMeters
            distancePoints.append(DistancePoint(timestamp: sample.endDate, cumulativeMeters: cumulativeMeters))
        }

        let totalKm = cumulativeMeters / 1000.0
        AppLogger.debug("Total distance: \(String(format: "%.2f", totalKm)) km from \(distancePoints.count) points", category: AppLogger.health)

        // Calculate splits by finding when each kilometer was crossed
        var splits: [KilometerSplit] = []

        // First, create splits for all COMPLETE kilometers
        let completeKilometers = Int(totalKm)

        for currentKilometer in stride(from: 1, through: completeKilometers, by: 1) {
            let kmThresholdMeters = Double(currentKilometer) * 1000.0
            let prevKmThresholdMeters = Double(currentKilometer - 1) * 1000.0

            // Find the time when we crossed this kilometer
            var startTime: Date?
            var endTime: Date?

            // Find start time (previous km threshold or workout start)
            if currentKilometer == 1 {
                startTime = workout.startDate
            } else {
                // Interpolate where we crossed the previous km threshold
                for i in 1..<distancePoints.count {
                    if distancePoints[i].cumulativeMeters >= prevKmThresholdMeters {
                        let prev = distancePoints[i - 1]
                        let curr = distancePoints[i]

                        if prev.cumulativeMeters == prevKmThresholdMeters {
                            startTime = prev.timestamp
                        } else {
                            // Linear interpolation
                            let fraction = (prevKmThresholdMeters - prev.cumulativeMeters) / (curr.cumulativeMeters - prev.cumulativeMeters)
                            let timeDiff = curr.timestamp.timeIntervalSince(prev.timestamp)
                            startTime = prev.timestamp.addingTimeInterval(timeDiff * fraction)
                        }
                        break
                    }
                }
            }

            // Find end time (current km threshold)
            for i in 1..<distancePoints.count {
                if distancePoints[i].cumulativeMeters >= kmThresholdMeters {
                    let prev = distancePoints[i - 1]
                    let curr = distancePoints[i]

                    if curr.cumulativeMeters == kmThresholdMeters {
                        endTime = curr.timestamp
                    } else {
                        // Linear interpolation
                        let fraction = (kmThresholdMeters - prev.cumulativeMeters) / (curr.cumulativeMeters - prev.cumulativeMeters)
                        let timeDiff = curr.timestamp.timeIntervalSince(prev.timestamp)
                        endTime = prev.timestamp.addingTimeInterval(timeDiff * fraction)
                    }
                    break
                }
            }

            if let startTime = startTime, let endTime = endTime {
                let duration = Int(endTime.timeIntervalSince(startTime))

                // Only add if duration is positive and reasonable (>0 and <2 hours per km)
                if duration > 0 && duration < 7200 {
                    splits.append(KilometerSplit(
                        number: currentKilometer,
                        distanceKm: 1.0,
                        durationSec: duration
                    ))
                }
            }
        }

        // Then, handle partial final kilometer if >= 0.1 km remains
        let remainingKm = totalKm - Double(completeKilometers)
        if remainingKm >= 0.1 {
            let partialKmNumber = completeKilometers + 1
            let prevKmThresholdMeters = Double(completeKilometers) * 1000.0

            var startTime: Date?

            // Find start time (where we crossed the last complete km)
            if completeKilometers == 0 {
                // If no complete km, start is workout start
                startTime = workout.startDate
            } else {
                for i in 1..<distancePoints.count {
                    if distancePoints[i].cumulativeMeters >= prevKmThresholdMeters {
                        let prev = distancePoints[i - 1]
                        let curr = distancePoints[i]

                        if prev.cumulativeMeters == prevKmThresholdMeters {
                            startTime = prev.timestamp
                        } else {
                            // Linear interpolation
                            let fraction = (prevKmThresholdMeters - prev.cumulativeMeters) / (curr.cumulativeMeters - prev.cumulativeMeters)
                            let timeDiff = curr.timestamp.timeIntervalSince(prev.timestamp)
                            startTime = prev.timestamp.addingTimeInterval(timeDiff * fraction)
                        }
                        break
                    }
                }
            }

            // End time is the last distance sample's timestamp (more accurate than workout.endDate)
            let endTime = distancePoints.last?.timestamp ?? workout.endDate

            if let startTime = startTime {
                let duration = Int(endTime.timeIntervalSince(startTime))

                if duration > 0 && duration < 7200 {
                    splits.append(KilometerSplit(
                        number: partialKmNumber,
                        distanceKm: remainingKm,
                        durationSec: duration
                    ))
                }
            }
        }

        for split in splits {
            let paceMin = split.paceSecPerKm / 60
            let paceSec = split.paceSecPerKm % 60
        }

        // Renumber splits sequentially (1, 2, 3...) since some kilometers may have been filtered out
        let renumberedSplits = splits.enumerated().map { index, split in
            KilometerSplit(
                number: index + 1,
                distanceKm: split.distanceKm,
                durationSec: split.durationSec
            )
        }

        AppLogger.success("Calculated \(renumberedSplits.count) splits", category: AppLogger.health)
        for split in renumberedSplits {
            let paceMin = split.paceSecPerKm / 60
            let paceSec = split.paceSecPerKm % 60
            AppLogger.debug("  KM \(split.number): \(String(format: "%.2f", split.distanceKm)) km in \(split.durationSec)s (pace: \(paceMin):\(String(format: "%02d", paceSec)))", category: AppLogger.health)
        }

        return renumberedSplits
    }

    // MARK: - Running Dynamics

    /// Fetches running dynamics metrics (power, cadence, stride length, GCT, vertical oscillation)
    func fetchRunningMetrics(for workout: HKWorkout) async -> (
        avgPower: Double?,
        avgCadence: Double?,
        avgStrideLength: Double?,
        avgGroundContactTime: Double?,
        avgVerticalOscillation: Double?
    ) {
        let metrics: [(HKQuantityTypeIdentifier, HKUnit)] = [
            (.runningPower, .watt()),
            (.runningSpeed, HKUnit.meter().unitDivided(by: .second())), // m/s, cadence from stepCount below
            (.runningStrideLength, .meter()),
            (.runningGroundContactTime, HKUnit.secondUnit(with: .milli)),
            (.runningVerticalOscillation, HKUnit.meterUnit(with: .centi))
        ]

        var results: [Double?] = Array(repeating: nil, count: metrics.count)

        for (index, (identifier, unit)) in metrics.enumerated() {
            guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else { continue }

            do {
                let avg: Double? = try await withCheckedThrowingContinuation { cont in
                    let pred = HKQuery.predicateForObjects(from: workout)
                    let q = HKSampleQuery(
                        sampleType: quantityType,
                        predicate: pred,
                        limit: HKObjectQueryNoLimit,
                        sortDescriptors: nil
                    ) { _, samples, error in
                        if let error { cont.resume(throwing: error); return }
                        guard let quantitySamples = samples as? [HKQuantitySample], !quantitySamples.isEmpty else {
                            cont.resume(returning: nil)
                            return
                        }
                        let values = quantitySamples.map { $0.quantity.doubleValue(for: unit) }
                        let average = values.reduce(0, +) / Double(values.count)
                        cont.resume(returning: average)
                    }
                    self.store.execute(q)
                }
                results[index] = avg
            } catch {
                AppLogger.debug("Could not fetch \(identifier.rawValue): \(error)", category: AppLogger.health)
            }
        }

        // For cadence: runningSpeed gives m/s, we need to compute cadence from step count if available
        // Actually use stepCount / duration as cadence instead of runningSpeed
        if results[1] == nil {
            if let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) {
                do {
                    let cadence: Double? = try await withCheckedThrowingContinuation { cont in
                        let pred = HKQuery.predicateForObjects(from: workout)
                        let q = HKSampleQuery(
                            sampleType: stepType,
                            predicate: pred,
                            limit: HKObjectQueryNoLimit,
                            sortDescriptors: nil
                        ) { _, samples, error in
                            if let error { cont.resume(throwing: error); return }
                            guard let quantitySamples = samples as? [HKQuantitySample], !quantitySamples.isEmpty else {
                                cont.resume(returning: nil)
                                return
                            }
                            let totalSteps = quantitySamples.reduce(0.0) { $0 + $1.quantity.doubleValue(for: .count()) }
                            let durationMinutes = workout.duration / 60.0
                            guard durationMinutes > 0 else { cont.resume(returning: nil); return }
                            cont.resume(returning: totalSteps / durationMinutes)
                        }
                        self.store.execute(q)
                    }
                    results[1] = cadence
                } catch {
                    AppLogger.debug("Could not fetch step count for cadence: \(error)", category: AppLogger.health)
                }
            }
        }

        return (results[0], results[1], results[2], results[3], results[4])
    }

    // MARK: - Route with Heart Rate

    /// Fetches route with heart rate data correlated by timestamp
    func fetchRouteWithHeartRate(for workout: HKWorkout) async throws -> [RoutePoint] {
        // Fetch route locations
        let locations = try await fetchRoute(for: workout)

        guard !locations.isEmpty else { return [] }

        // Fetch heart rate samples
        let (hrSamples, _, _, _) = try await fetchHeartRateSamples(for: workout)

        guard !hrSamples.isEmpty else {
            // No HR data, return route without HR
            return locations.map { RoutePoint(from: $0, heartRate: nil) }
        }

        // Correlate HR with locations by timestamp
        return locations.map { location in
            // Find the closest HR sample by timestamp
            let closestHR = hrSamples.min(by: { sample1, sample2 in
                let diff1 = abs(sample1.timestamp.timeIntervalSince(location.timestamp))
                let diff2 = abs(sample2.timestamp.timeIntervalSince(location.timestamp))
                return diff1 < diff2
            })

            // Only use HR if it's within 10 seconds of the location timestamp
            let timeDiff = closestHR.map { abs($0.timestamp.timeIntervalSince(location.timestamp)) } ?? Double.infinity
            let hr = timeDiff < 10.0 ? closestHR?.bpm : nil

            return RoutePoint(from: location, heartRate: hr)
        }
    }

    // MARK: - Manual Data Refresh for Existing Run

    /// Manually fetch and update splits and HR data for an existing run
    func refreshDetailedDataForRun(runId: UUID) async {

        guard let store = workoutStore else {
            AppLogger.warning("Cannot refresh detailed data - WorkoutStore not set", category: AppLogger.health)
            return
        }

        let run = await MainActor.run { store.runs.first(where: { $0.id == runId }) }

        guard let run = run, let workoutUUID = run.healthKitUUID else {
            AppLogger.warning("Cannot refresh detailed data - run not found or no HealthKit UUID", category: AppLogger.health)
            return
        }


        do {
            // Fetch workout from HealthKit
            let workouts = try await fetchWorkoutByUUID(workoutUUID)
            guard let workout = workouts.first else {
                AppLogger.warning("Workout not found in HealthKit", category: AppLogger.health)
                return
            }

         

            // Fetch detailed data
          
            let splits = try? await fetchKilometerSplits(for: workout)

            let routeWithHR = try? await fetchRouteWithHeartRate(for: workout)

            // Update run
            await MainActor.run {
                var updated = run
                updated.splits = splits
                updated.routeWithHR = routeWithHR
                store.updateRun(updated)
                AppLogger.success("Refreshed detailed data for run: \(splits?.count ?? 0) splits", category: AppLogger.health)
            }
        } catch {
            AppLogger.error("Failed to refresh detailed data: \(error)", category: AppLogger.health)
        }
    }

    /// Fetch cardio data (splits and HR zones) for a HealthKit workout UUID
    /// Used for refreshing social post data
    func fetchCardioDataByHealthKitUUID(_ healthKitUUID: UUID, totalDuration: Int) async -> (splits: [KilometerSplit]?, hrZones: [HRZoneSummary]?) {
        do {
            let workouts = try await fetchWorkoutByUUID(healthKitUUID)
            guard let workout = workouts.first else {
                AppLogger.warning("Workout not found in HealthKit for UUID: \(healthKitUUID)", category: AppLogger.health)
                return (nil, nil)
            }

            // Fetch splits
            let splits = try? await fetchKilometerSplits(for: workout)

            // Fetch route with HR for zone calculation
            let routeWithHR = try? await fetchRouteWithHeartRate(for: workout)

            // Calculate HR zones from route data
            var hrZones: [HRZoneSummary]? = nil
            if let routePoints = routeWithHR, !routePoints.isEmpty {
                let zones = calculateHRZonesFromRoute(routePoints, totalDuration: totalDuration)
                let totalMinutes = zones.reduce(0) { $0 + $1.minutes }
                if totalMinutes > 0 {
                    hrZones = zones
                }
            }

            // Fallback: estimate from average HR if route-based zones are empty
            if hrZones == nil || hrZones?.isEmpty == true {
                let (hrSamples, avg, _, _) = try await fetchHeartRateSamples(for: workout)
                if avg > 0 {
                    hrZones = CardioDataExtractor.shared.calculateEstimatedHRZones(avgHR: avg, totalDuration: totalDuration)
                }
            }

            AppLogger.success("Fetched cardio data: \(splits?.count ?? 0) splits, \(hrZones?.count ?? 0) zones", category: AppLogger.health)
            return (splits, hrZones)
        } catch {
            AppLogger.error("Failed to fetch cardio data: \(error)", category: AppLogger.health)
            return (nil, nil)
        }
    }

    /// Calculate HR zones from route points with heart rate data
    private func calculateHRZonesFromRoute(_ points: [RoutePoint], totalDuration: Int) -> [HRZoneSummary] {
        let hrCalculator = HRZoneCalculator.shared
        let boundaries = hrCalculator.zoneBoundaries()

        // Count samples in each zone
        var zoneCounts: [Int: Int] = [:]
        for point in points {
            guard let hr = point.hr, hr > 0 else { continue }
            let zone = hrCalculator.zone(for: hr)
            zoneCounts[zone, default: 0] += 1
        }

        // Calculate time per zone based on average sampling rate
        let totalSamples = zoneCounts.values.reduce(0, +)
        guard totalSamples > 0 else {
            return boundaries.map { boundary in
                HRZoneSummary(
                    zone: boundary.zone,
                    name: boundary.name,
                    minutes: 0,
                    rangeDisplay: boundary.rangeString,
                    colorHex: boundary.color.toHex()
                )
            }
        }

        let secondsPerSample = Double(totalDuration) / Double(totalSamples)

        return boundaries.map { boundary in
            let count = zoneCounts[boundary.zone] ?? 0
            let minutes = (Double(count) * secondsPerSample) / 60.0

            return HRZoneSummary(
                zone: boundary.zone,
                name: boundary.name,
                minutes: minutes,
                rangeDisplay: boundary.rangeString,
                colorHex: boundary.color.toHex()
            )
        }
    }

    // MARK: - Workout Type Mapping

    private nonisolated func workoutActivityTypeName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .hiking: return "Hiking"
        case .swimming: return "Swimming"
        case .traditionalStrengthTraining: return "Strength Training"
        case .functionalStrengthTraining: return "Functional Training"
        case .rowing: return "Rowing"
        case .elliptical: return "Elliptical"
        case .stairClimbing: return "Stair Climbing"
        case .yoga: return "Yoga"
        case .pilates: return "Pilates"
        case .dance: return "Dance"
        case .soccer: return "Soccer"
        case .basketball: return "Basketball"
        case .tennis: return "Tennis"
        case .golf: return "Golf"
        case .mixedCardio: return "Mixed Cardio"
        case .highIntensityIntervalTraining: return "HIIT"
        case .coreTraining: return "Core Training"
        case .flexibility: return "Flexibility"
        case .cooldown: return "Cooldown"
        case .crossTraining: return "Cross Training"
        case .mixedMetabolicCardioTraining: return "Mixed Cardio"
        case .preparationAndRecovery: return "Recovery"
        default: return "Other"
        }
    }

    // MARK: - Exercise Time Aggregation

    private func aggregateExerciseTimeIntoWeeklySummaries(samples: [HKQuantitySample], context: ModelContext) async {
        // Group samples by ISO week
        let calendar = Calendar.current
        var weeklyMinutes: [String: Int] = [:]

        for sample in samples {
            let weekStart = calendar.startOfWeek(for: sample.startDate, anchorWeekday: 2)
            let key = ExerciseVolumeSummary.weekKey(from: weekStart)
            let minutes = Int(sample.quantity.doubleValue(for: .minute()).rounded())
            weeklyMinutes[key, default: 0] += minutes
        }

        // Update WeeklyTrainingSummary records
        for (key, minutes) in weeklyMinutes {
            let descriptor = FetchDescriptor<WeeklyTrainingSummary>(
                predicate: #Predicate { $0.key == key }
            )

            if let summary = try? context.fetch(descriptor).first {
                // Update existing summary
                if summary.appleExerciseMinutes == nil {
                    summary.appleExerciseMinutes = minutes
                } else {
                    summary.appleExerciseMinutes = (summary.appleExerciseMinutes ?? 0) + minutes
                }
                summary.lastHealthSync = .now
            } else {
                // Create new summary if it doesn't exist
                guard let weekStart = weekStartFromKey(key) else { continue }
                let summary = WeeklyTrainingSummary(
                    key: key,
                    weekStart: weekStart,
                    totalVolume: 0,
                    sessions: 0,
                    totalSets: 0,
                    totalReps: 0,
                    minutes: 0,
                    appleExerciseMinutes: minutes,
                    cardioSessions: 0
                )
                context.insert(summary)
            }
        }

        try? context.save()
    }

    private func weekStartFromKey(_ key: String) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let week = Int(parts[1]) else { return nil }

        var comps = DateComponents()
        comps.yearForWeekOfYear = year
        comps.weekOfYear = week
        comps.weekday = 2  // Monday

        return Calendar.current.date(from: comps)
    }
}

// MARK: - Background Task Registration

extension HealthKitManager {
    static let healthSyncTaskID = "com.dmihaylov.trak.health.sync"
    private static var hasRegisteredBackgroundTask = false

    func registerBackgroundTasks() {
        // Background task registration now happens in WRKTApp.init() to comply with iOS requirement
        // that all launch handlers must be registered before application finishes launching.
        // This method is kept for backward compatibility but does nothing.
        AppLogger.debug("Background task registration handled in WRKTApp.init()", category: AppLogger.health)
    }

    func scheduleHealthSyncTask() {
        let request = BGProcessingTaskRequest(identifier: Self.healthSyncTaskID)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3600)  // 1 hour from now

        try? BGTaskScheduler.shared.submit(request)
    }

    func handleHealthSyncTask(task: BGProcessingTask) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        Task {
            await syncWorkoutsIncremental()
            await syncExerciseTimeIncremental()
            await processRouteFetchQueue()

            task.setTaskCompleted(success: true)
            scheduleHealthSyncTask()  // Reschedule
        }
    }

    // MARK: - Timeout Helper

    /// Runs an async operation with a timeout to prevent hanging
    private func withTimeout(seconds: TimeInterval, operation: @escaping () async -> Void) async {
        enum TaskResult {
            case completed
            case timedOut
        }

        let result = await withTaskGroup(of: TaskResult.self) { group in
            // Run the actual operation
            group.addTask {
                await operation()
                return .completed
            }

            // Run the timeout timer
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return .timedOut
            }

            // Wait for first task to complete
            let firstResult = await group.next()
            group.cancelAll()
            return firstResult ?? .completed
        }

        // Only log if we actually timed out
        if result == .timedOut {
            AppLogger.warning("HealthKit operation timed out after \(seconds) seconds", category: AppLogger.health)
        }
    }
}

// MARK: - Color Extension for HR Zone Hex Colors

private extension Color {
    func toHex() -> String {
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        return String(format: "#%02X%02X%02X",
                      Int(red * 255),
                      Int(green * 255),
                      Int(blue * 255))
    }
}
