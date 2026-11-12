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
import UIKit
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
    private static let authScopeVersion = 3  // bumped to re-surface workoutRoute read permission (was in toRead but read toggle never appeared for some users)

    @Published var connectionState: HealthConnectionState {
        didSet {
            // Persist connection state to UserDefaults
            UserDefaults.standard.set(connectionState.rawValue, forKey: "healthkit.connectionState")
            AppLogger.info("⚡️ connectionState changed: \(oldValue) → \(connectionState)", category: AppLogger.health)
        }
    }

    init() {
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
    private let fullResyncInitialEnrichmentLimit = 5

    // SwiftData context (injected from app)
    var modelContext: ModelContext?

    // WorkoutStore reference (injected from app)
    weak var workoutStore: WorkoutStoreV2?

    // Competitive feature references (injected from app)
    weak var challengeRepository: ChallengeRepository?
    weak var authService: SupabaseAuthService?

    // Observer queries (kept alive)
    private var workoutObserver: HKObserverQuery?
    private var exerciseTimeObserver: HKObserverQuery?
    private var workoutRouteObserver: HKObserverQuery?
    private let syncDelivery = HealthSyncDelivery()
    private var isSyncingExerciseTime = false
    private var isProcessingRouteQueue = false
    private var routeQueueProcessStartedAt: Date = .now
    private var routeQueueLaunchWindowEndsAt: Date = .distantPast

    // MARK: - Authorization

    var isInRouteQueueLaunchWindow: Bool {
        Date.now < routeQueueLaunchWindowEndsAt
    }

    func beginRouteQueueLaunchProtection() {
        routeQueueProcessStartedAt = .now
        routeQueueLaunchWindowEndsAt = .distantFuture
        AppLogger.info("Enabled route queue launch protection", category: AppLogger.health)
    }

    func endRouteQueueLaunchProtection(bufferSeconds: TimeInterval = 5) {
        routeQueueLaunchWindowEndsAt = .now.addingTimeInterval(bufferSeconds)
        AppLogger.info("Route queue launch protection will end at \(routeQueueLaunchWindowEndsAt)", category: AppLogger.health)
    }

    private var isProtectedHealthDataAvailable: Bool {
        UIApplication.shared.isProtectedDataAvailable
    }

    private func isProtectedHealthDataError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return (nsError.domain == HKErrorDomain && nsError.code == 6)
            || nsError.localizedDescription.localizedCaseInsensitiveContains("protected health data")
    }

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
        guard connectionState == .connected, workoutObserver == nil,
              HKHealthStore.isHealthDataAvailable() else { return }

        func observe(_ type: HKSampleType, frequency: HKUpdateFrequency) -> HKObserverQuery {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, error in
                Task { @MainActor [weak self] in
                    guard let self else { completion(); return }
                    if let error { self.syncError = error }
                    do {
                        try self.syncDelivery.receive(completion: completion)
                    } catch {
                        // The unchanged anchors and unconditional foreground sweep remain
                        // the fallback if the retry marker itself cannot be written.
                        self.syncError = error
                        AppLogger.error("HealthKit delivery handoff failed: \(error)", category: AppLogger.health)
                        completion()
                    }
                    self.scheduleHealthSyncTask()
                    _ = await self.drainPendingHealthSync()
                }
            }
            store.execute(query)
            store.enableBackgroundDelivery(for: type, frequency: frequency) { _, error in
                if let error { AppLogger.warning("HealthKit background delivery setup failed: \(error)", category: AppLogger.health) }
            }
            return query
        }

        workoutObserver = observe(.workoutType(), frequency: .immediate)
        if let type = HKObjectType.quantityType(forIdentifier: .appleExerciseTime) {
            exerciseTimeObserver = observe(type, frequency: .hourly)
        }
        workoutRouteObserver = observe(HKSeriesType.workoutRoute(), frequency: .immediate)
    }

    /// Always enqueue on foreground/BG launch too, recovering even a failed marker write.
    @discardableResult
    func catchUpHealthChanges() async -> Bool {
        guard connectionState == .connected else { return false }
        do {
            try syncDelivery.receive { }
        } catch {
            syncError = error
            return false
        }
        scheduleHealthSyncTask()
        return await drainPendingHealthSync()
    }

    private func drainPendingHealthSync() async -> Bool {
        do {
            return try await syncDelivery.drain { [weak self] in
                guard let self, self.connectionState == .connected,
                      self.isProtectedHealthDataAvailable, !Task.isCancelled else { return false }
                let workouts = await self.syncWorkoutsIncremental()
                guard !Task.isCancelled else { return false }
                let exerciseTime = await self.syncExerciseTimeIncremental()
                guard !Task.isCancelled else { return false }
                let routes = await self.processRouteFetchQueue()
                return workouts && exerciseTime && routes
            }
        } catch {
            syncError = error
            return false
        }
    }

    func stopBackgroundObservers() {
        if let workoutObserver {
            store.stop(workoutObserver)
        }
        if let exerciseTimeObserver {
            store.stop(exerciseTimeObserver)
        }
        if let workoutRouteObserver {
            store.stop(workoutRouteObserver)
        }
        self.workoutObserver = nil
        self.exerciseTimeObserver = nil
        self.workoutRouteObserver = nil
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
        let succeeded = await catchUpHealthChanges()
        if succeeded { lastAutoSyncDate = now }
        return succeeded
    }

    @discardableResult
    func syncWorkoutsIncremental() async -> Bool {
        guard let context = modelContext else {
            AppLogger.warning("ModelContext not set", category: AppLogger.health)
            return false
        }
        guard !isSyncing else { return false }
        isSyncing = true
        defer { isSyncing = false }

        // Re-request auth when the scope has been extended since the user last saw the dialog
        // (HealthKit is idempotent — it only prompts for genuinely new types)
        if connectionState != .connected || (needsAuthScopeUpdate && UIApplication.shared.applicationState == .active) {
            guard UIApplication.shared.applicationState == .active else { return false }
            AppLogger.info("Requesting HealthKit authorization (connected: \(connectionState == .connected), scopeStale: \(needsAuthScopeUpdate))", category: AppLogger.health)
            do {
                try await requestAuthorization()
            } catch {
                AppLogger.error("HealthKit authorization failed: \(error.localizedDescription)", category: AppLogger.health)
                return false
            }
        }


        do {
            guard let workoutStore else { throw StorageError.validationFailed("Workout storage is unavailable") }
            try await workoutStore.waitForStorage()
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
                try Task.checkCancellation()
                try await importWorkoutIdempotent(workout, context: context)
            }

            // Process deletions
            for deletedWorkout in deleted {
                try deleteWorkoutIfExists(uuid: deletedWorkout.uuid, context: context)
            }

            try Task.checkCancellation()
            try queueRouteFetching(for: added, context: context)

            // Update anchor
            try await commitWorkoutAnchor(anchorRecord, newAnchor: newAnchor, context: context)

            lastSyncDate = .now
            syncError = nil


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
                        workoutStore.matchRecentWorkoutsWithHealthKit(days: 7)
                    }
                }
            }

            return true
        } catch {
            AppLogger.error("Workout sync failed: \(error)", category: AppLogger.health)
            syncError = error
            return false
        }
    }

    /// Refresh recent workout details without advancing the global import anchor.
    func syncRecentWorkouts() async {
        guard let context = modelContext else {
            AppLogger.warning("ModelContext not set", category: AppLogger.health)
            return
        }

        AppLogger.info("Refreshing recent workouts without advancing the global anchor", category: AppLogger.health)

        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

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


        do {
            guard let workoutStore else { throw StorageError.validationFailed("Workout storage is unavailable") }
            try await workoutStore.waitForStorage()
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
            let (added, deleted, _) = try await fetchWorkoutsAnchored(anchor: nil)
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

            // A query whose imports are restricted to 14 days must not advance the
            // global anchor past historical workouts that it did not import.
            try await workoutStore.flushHealthKitChanges()

            lastSyncDate = .now
            syncError = nil

            // Queue route fetching for recently added workouts
            try queueRouteFetching(for: recentWorkouts, context: context)
            try context.save()
            await processRouteFetchQueue()

            // Match app workouts with newly imported HealthKit workouts
            if !recentWorkouts.isEmpty {
                let strengthTypes: Set = ["Strength Training", "Functional Training", "Core Training"]
                let hasStrengthWorkouts = recentWorkouts.contains { workout in
                    strengthTypes.contains(workoutActivityTypeName(workout.workoutActivityType))
                }

                if hasStrengthWorkouts {
                    AppLogger.info("Imported \(recentWorkouts.count) recent HealthKit workouts, attempting to match with app workouts", category: AppLogger.health)
                    await MainActor.run {
                        workoutStore.matchRecentWorkoutsWithHealthKit(days: 14)
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

        guard !isSyncing else { return }
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
            try await store.waitForStorage()
            AppLogger.info("Starting batched full re-sync of all HealthKit workouts...", category: AppLogger.health)
            AppLogger.debug("Current runs count: \(await MainActor.run { store.runs.count })", category: AppLogger.health)

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
                        Task { @MainActor in
                            await BarbellProgressService.shared.evaluateAndAwardFunctionalHK(run: newRun)
                        }
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

            try Task.checkCancellation()
            try queueHistoricalEnrichment(for: store.runs.filter(\.needsHistoricalEnrichment), context: context)

            // Save new anchor
            let anchorRecord = try fetchOrCreateAnchor(dataType: "all_workouts", context: context)
            try await commitWorkoutAnchor(anchorRecord, newAnchor: newAnchor, context: context)

            lastSyncDate = .now
            syncError = nil

            AppLogger.success("Batched full re-sync complete! Processed \(added.count) workouts in \(batches.count) batches", category: AppLogger.health)

            await processRouteFetchQueue(limit: fullResyncInitialEnrichmentLimit)
            AppLogger.info("Historical cardio enrichment queued; full resync processed only the first \(fullResyncInitialEnrichmentLimit) route task(s) to keep the app responsive", category: AppLogger.health)

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

    @discardableResult
    func syncExerciseTimeIncremental() async -> Bool {
        guard let context = modelContext, !isSyncingExerciseTime else { return false }
        isSyncingExerciseTime = true
        defer { isSyncingExerciseTime = false }

        do {
            await resetExerciseTimeAnchorIfNeeded()

            let anchorRecord = try fetchOrCreateAnchor(dataType: "exercise_time", context: context)
            let anchor = anchorRecord.anchor

            let (samples, deleted, newAnchor) = try await fetchExerciseTimeSamplesAnchored(anchor: anchor)

            AppLogger.info("Syncing exercise time: \(samples.count) samples", category: AppLogger.health)

            // Rebuild the affected date range from HealthKit's daily statistics query instead of
            // summing raw appleExerciseTime samples. Raw samples can overlap and overcount.
            let affectedStart = try exerciseTimeReconciliationStart(
                sampleDates: samples.map(\.startDate), hasDeletions: !deleted.isEmpty, context: context)

            try await reconcileExerciseTimeSummaries(from: affectedStart, to: .now, context: context)

            try Task.checkCancellation()
            // Update anchor
            try await anchorRecord.commit(newAnchor, in: context) { }
            return true

        } catch {
            AppLogger.error("Exercise time sync failed: \(error)", category: AppLogger.health)
            syncError = error
            return false
        }
    }

    /// One-time recovery: resets the exercise_time anchor so the next syncExerciseTimeIncremental()
    /// call replays ALL historical Apple Exercise Time samples. Guarded by a UserDefaults flag so it
    /// only runs once. After resetting the anchor, the caller is responsible for calling
    /// syncExerciseTimeIncremental() -- do not call it inside this method to avoid a double-sync.
    func resetExerciseTimeAnchorIfNeeded() async {
        let flagKey = "wrkt_exercise_time_anchor_reset_v3"
        guard !UserDefaults.standard.bool(forKey: flagKey) else { return }
        guard let context = modelContext else { return }

        do {
            // Reset all exercise-time caches before replaying history so additive incremental
            // aggregation cannot double-count old samples.
            let summaryDescriptor = FetchDescriptor<WeeklyTrainingSummary>()
            let summaries = try context.fetch(summaryDescriptor)
            for summary in summaries {
                summary.appleExerciseMinutes = nil
            }

            let dailyDescriptor = FetchDescriptor<DailyAppleExerciseSummary>()
            let dailySummaries = try context.fetch(dailyDescriptor)
            for daily in dailySummaries {
                context.delete(daily)
            }

            let anchorRecord = try fetchOrCreateAnchor(dataType: "exercise_time", context: context)
            anchorRecord.anchorData = nil
            try context.save()
            UserDefaults.standard.set(true, forKey: flagKey)
            AppLogger.info("Reset exercise_time anchor and cleared daily/weekly exercise-time caches for full historical re-sync (v3)", category: AppLogger.health)
        } catch {
            AppLogger.error("Failed to reset exercise_time anchor: \(error)", category: AppLogger.health)
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

    private func fetchExerciseTimeSamplesAnchored(anchor: HKQueryAnchor?) async throws -> (samples: [HKQuantitySample], deleted: [HKDeletedObject], newAnchor: HKQueryAnchor?) {
        guard let exerciseType = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) else {
            return ([], [], nil)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: exerciseType,
                predicate: nil,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { _, addedSamples, deletedSamples, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let samples = (addedSamples as? [HKQuantitySample]) ?? []
                continuation.resume(returning: (samples, deletedSamples ?? [], newAnchor))
            }

            store.execute(query)
        }
    }

    // MARK: - Anchor Persistence

    private func commitWorkoutAnchor(_ record: HealthSyncAnchor, newAnchor: HKQueryAnchor?,
                                     context: ModelContext) async throws {
        guard let workoutStore else { throw StorageError.validationFailed("Workout storage is unavailable") }
        try await record.commit(newAnchor, in: context) {
            try await workoutStore.flushHealthKitChanges()
            try Task.checkCancellation()
        }
    }


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

    // MARK: - Operational State Repair

    /// Rebuilds low-value HealthKit operational SwiftData state from durable `Run` data.
    /// Safe to run on startup. Does not modify durable workout/run history.
    func repairOperationalStateIfNeeded(runs: [Run]) async {
        guard let context = modelContext else { return }

        let validWorkoutUUIDs = Set(runs.compactMap { $0.healthKitUUID?.uuidString })
        let enrichmentCandidates = runs
            .filter(\.needsHistoricalEnrichment)
            .sorted { $0.date > $1.date }

        var insertedTaskCount = 0
        var removedTaskCount = 0
        var resetTaskCount = 0
        var removedSnapshotCount = 0
        var insertedAnchorCount = 0
        var removedAnchorCount = 0

        let staleThreshold = Date.now.addingTimeInterval(-120)

        // Repair route/enrichment tasks from durable runs.
        let routeTaskDescriptor = FetchDescriptor<RouteFetchTask>()
        let routeTasks = (try? context.fetch(routeTaskDescriptor)) ?? []
        var routeTaskByUUID: [String: RouteFetchTask] = [:]

        for task in routeTasks {
            if !validWorkoutUUIDs.contains(task.workoutUUID) {
                context.delete(task)
                removedTaskCount += 1
                continue
            }

            if let existing = routeTaskByUUID[task.workoutUUID] {
                let keepCurrent = (task.lastAttemptDate ?? .distantPast) >= (existing.lastAttemptDate ?? .distantPast)
                let duplicate = keepCurrent ? existing : task
                let keeper = keepCurrent ? task : existing
                context.delete(duplicate)
                routeTaskByUUID[keeper.workoutUUID] = keeper
                removedTaskCount += 1
                continue
            }

            routeTaskByUUID[task.workoutUUID] = task
        }

        for (index, run) in enrichmentCandidates.enumerated() {
            guard let workoutUUIDString = run.healthKitUUID?.uuidString else { continue }
            if let existing = routeTaskByUUID[workoutUUIDString] {
                if existing.status == "failed" || (existing.status == "fetching" && (existing.lastAttemptDate ?? .distantPast) < staleThreshold) {
                    existing.status = "pending"
                    existing.attemptCount = 0
                    existing.priority = index < 5 ? 0 : 1
                    existing.allowAutoPost = false
                    resetTaskCount += 1
                }
                continue
            }

            let task = RouteFetchTask(
                workoutUUID: workoutUUIDString,
                workoutDate: run.date,
                priority: index < 5 ? 0 : 1,
                allowAutoPost: false
            )
            context.insert(task)
            insertedTaskCount += 1
        }

        // Remove orphaned snapshot cache entries. They are always regenerable.
        let snapshotDescriptor = FetchDescriptor<MapSnapshotCache>()
        let snapshotEntries = (try? context.fetch(snapshotDescriptor)) ?? []
        for snapshot in snapshotEntries where !validWorkoutUUIDs.contains(snapshot.workoutUUID) {
            context.delete(snapshot)
            removedSnapshotCount += 1
        }

        // Keep only expected HealthKit anchors and ensure the expected records exist.
        let expectedAnchorTypes = Set(["all_workouts", "exercise_time"])
        let anchorDescriptor = FetchDescriptor<HealthSyncAnchor>()
        let anchors = (try? context.fetch(anchorDescriptor)) ?? []
        var seenAnchorTypes: Set<String> = []
        for anchor in anchors {
            if !expectedAnchorTypes.contains(anchor.dataType) {
                context.delete(anchor)
                removedAnchorCount += 1
                continue
            }

            if seenAnchorTypes.contains(anchor.dataType) {
                context.delete(anchor)
                removedAnchorCount += 1
                continue
            }

            seenAnchorTypes.insert(anchor.dataType)
        }

        for anchorType in expectedAnchorTypes where !seenAnchorTypes.contains(anchorType) {
            context.insert(HealthSyncAnchor(dataType: anchorType))
            insertedAnchorCount += 1
        }

        if insertedTaskCount > 0 || removedTaskCount > 0 || resetTaskCount > 0 || removedSnapshotCount > 0 || insertedAnchorCount > 0 || removedAnchorCount > 0 {
            try? context.save()
            AppLogger.info(
                "Repaired HealthKit operational state. tasks +\(insertedTaskCount)/-\(removedTaskCount)/reset \(resetTaskCount), snapshots -\(removedSnapshotCount), anchors +\(insertedAnchorCount)/-\(removedAnchorCount)",
                category: AppLogger.health
            )

            if insertedTaskCount > 0 || resetTaskCount > 0 {
                Task.detached { [weak self] in
                    await self?.processRouteFetchQueue(limit: 10)
                }
            }
        } else {
            AppLogger.debug("HealthKit operational state already healthy", category: AppLogger.health)
        }
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
                if strengthTypes.contains(workout.workoutActivityType) {
                    // Fetch full HR stats for strength workouts (avg, max, min, samples)
                    if let (samples, avg, max, min) = try? await fetchHeartRateSamples(for: workout), avg > 0 {
                        updated.avgHeartRate = avg
                        updated.maxHeartRate = max
                        updated.minHeartRate = min
                        updated.hrSamples = samples
                        AppLogger.debug("Refetched HR for \(workoutType): avg \(Int(avg)) max \(Int(max)) min \(Int(min)) bpm", category: AppLogger.health)
                    }
                } else {
                    updated.avgHeartRate = try? await averageHeartRate(for: workout)
                    if let hr = updated.avgHeartRate {
                        AppLogger.debug("Refetched heart rate for \(workoutType): \(Int(hr)) bpm", category: AppLogger.health)
                    }
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

        // Extract workout type name (e.g., "Running", "Cycling", "Functional Training")
        let workoutType = workoutActivityTypeName(workout.workoutActivityType)

        // Extract custom workout name from metadata (if user named it in Apple Fitness)
        let workoutName = workout.metadata?[HKMetadataKeyWorkoutBrandName] as? String

        // For strength-type workouts fetch full HR stats (avg, max, min, samples) since
        // there is no GPS route to derive them from. For cardio, avg HR suffices here;
        // max/min are derived later from the route with HR when the route is fetched.
        var avgHR: Double? = nil
        var maxHR: Double? = nil
        var minHR: Double? = nil
        var hrSamples: [HeartRateSample]? = nil

        if strengthTypes.contains(workout.workoutActivityType) {
            if let (samples, avg, max, min) = try? await fetchHeartRateSamples(for: workout), avg > 0 {
                avgHR = avg
                maxHR = max
                minHR = min
                hrSamples = samples
            }
        } else {
            avgHR = try? await averageHeartRate(for: workout)
        }

        AppLogger.debug("Importing: \(workoutType) at \(workout.startDate.formatted(date: .abbreviated, time: .shortened))", category: AppLogger.health)

        let run = Run(
            date: workout.endDate,  // Use END date for matching with app workout completion time
            distanceKm: km,
            durationSec: sec,
            notes: nil,
            healthKitUUID: workout.uuid,
            avgHeartRate: avgHR,
            maxHeartRate: maxHR,
            minHeartRate: minHR,
            hrSamples: hrSamples,
            calories: kcal,
            route: nil,  // Fetched separately via queue
            workoutType: workoutType,
            workoutName: workoutName
        )

        await MainActor.run {
            store.addRun(run)
            Task { @MainActor in
                await BarbellProgressService.shared.evaluateAndAwardFunctionalHK(run: run)
            }
        }

        // Update challenge progress for imported workouts (Watch/HealthKit-sourced)
        if let challengeRepo = challengeRepository,
           let userId = authService?.currentUser?.id {
            var imported = CompletedWorkout(date: run.date, entries: [])
            imported.cardioWorkoutType = run.workoutType
            imported.matchedHealthKitDuration = run.durationSec
            Task.detached(priority: .utility) {
                do {
                    try await challengeRepo.updateChallengeProgress(after: imported, userId: userId)
                } catch {
                    AppLogger.error("Failed to update challenge progress for HK import: \(error.localizedDescription)", category: AppLogger.health)
                }
            }
        }

        // Runs are auto-posted via processRouteFetchQueue after GPS route is fetched.
        // Non-run Watch workouts (HIIT, Functional Training, etc.) have no route, so post immediately.
        // Exclude traditionalStrengthTraining: the WRKT Watch app always saves this type, so we
        // cannot distinguish a Watch-native session from an app-tracked one. All other types are
        // only produced by the Watch's native Workout app (never by WRKT), so they are safe.
        let isAmbiguousAppType = workout.workoutActivityType == .traditionalStrengthTraining
        if !workoutType.lowercased().contains("run") && !isAmbiguousAppType {
            Task {
                await CardioAutoPostService.shared.handleWatchWorkoutIfNeeded(run: run)
            }
        }
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

    private func queueRouteFetching(for workouts: [HKWorkout], context: ModelContext) throws {
        for workout in workouts {
            let workoutUUIDString = workout.uuid.uuidString
            let descriptor = FetchDescriptor<RouteFetchTask>(
                predicate: #Predicate { $0.workoutUUID == workoutUUIDString }
            )

            if let existing = try context.fetch(descriptor).first {
                // Reset failed tasks so they get another attempt on the next queue run.
                // Watch GPS routes sync separately from the workout summary and can lag
                // 10-60+ minutes, so tasks often exhaust their attempt limit before the
                // data arrives. Resetting here means pull-to-refresh and incremental syncs
                // automatically unblock them without the user tapping "Get Route" manually.
                if existing.status == "failed" {
                    existing.status = "pending"
                    existing.attemptCount = 0
                    existing.allowAutoPost = true
                    AppLogger.info("Reset failed route task to pending for re-queue: \(workoutUUIDString)", category: AppLogger.health)
                }
                // pending / fetching / completed tasks are left as-is
            } else {
                let priority = workouts.firstIndex(of: workout) ?? 0 < 5 ? 0 : 1  // High priority for recent 5
                let task = RouteFetchTask(
                    workoutUUID: workout.uuid.uuidString,
                    workoutDate: workout.startDate,
                    priority: priority,
                    allowAutoPost: true
                )
                context.insert(task)
            }
        }

    }

    private func queueHistoricalEnrichment(for runs: [Run], context: ModelContext) throws {
        let sortedRuns = runs.sorted { $0.date > $1.date }

        for (index, run) in sortedRuns.enumerated() {
            guard let workoutUUID = run.healthKitUUID else { continue }
            let workoutUUIDString = workoutUUID.uuidString
            let descriptor = FetchDescriptor<RouteFetchTask>(
                predicate: #Predicate { $0.workoutUUID == workoutUUIDString }
            )

            if let existing = try context.fetch(descriptor).first {
                if existing.status == "failed" {
                    existing.status = "pending"
                    existing.attemptCount = 0
                    existing.priority = index < 5 ? 0 : 1
                    existing.allowAutoPost = false
                    AppLogger.info("Reset failed historical enrichment task to pending for \(workoutUUIDString)", category: AppLogger.health)
                }
            } else {
                let task = RouteFetchTask(
                    workoutUUID: workoutUUIDString,
                    workoutDate: run.date,
                    priority: index < 5 ? 0 : 1,
                    allowAutoPost: false
                )
                context.insert(task)
            }
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

    @discardableResult
    func processRouteFetchQueue(limit: Int = 10,
                               fetchEnrichment: ((UUID) async throws -> DetailedRunEnrichment?)? = nil) async -> Bool {
        guard let context = modelContext, let workoutStore,
              !isProcessingRouteQueue, isProtectedHealthDataAvailable else { return false }
        isProcessingRouteQueue = true
        defer { isProcessingRouteQueue = false }

        // Keep the outcome local until the corresponding run data has reached disk.
        var results: [(task: RouteFetchTask, uuid: UUID, enrichment: DetailedRunEnrichment, attemptCount: Int)] = []
        do {
            try await workoutStore.waitForStorage()
            try Task.checkCancellation()

            // This worker is serialized; any fetching rows belong to an interrupted pass.
            let interrupted = try context.fetch(FetchDescriptor<RouteFetchTask>(
                predicate: #Predicate { $0.status == "fetching" }))
            for task in interrupted { task.status = "pending" }
            try context.save()

            let processStartedAt = routeQueueProcessStartedAt
            let inLaunchWindow = isInRouteQueueLaunchWindow
            var descriptor = FetchDescriptor<RouteFetchTask>(
                predicate: #Predicate {
                    $0.status == "pending" && (!inLaunchWindow || $0.createdAt >= processStartedAt)
                },
                sortBy: [SortDescriptor(\.lastAttemptDate), SortDescriptor(\.priority),
                         SortDescriptor(\.workoutDate, order: .reverse)])
            let effectiveLimit = inLaunchWindow ? min(limit, 2) : limit
            if effectiveLimit > 0 { descriptor.fetchLimit = effectiveLimit }
            let tasks = try context.fetch(descriptor)
            var succeeded = true

            for task in tasks {
                try Task.checkCancellation()
                guard isProtectedHealthDataAvailable else { throw HKError(.errorDatabaseInaccessible) }
                guard let uuid = UUID(uuidString: task.workoutUUID) else {
                    task.status = "failed"
                    continue
                }
                task.lastAttemptDate = .now
                // Leave the row pending during the query; the in-process guard owns this pass.
                do {
                    let enrichment: DetailedRunEnrichment?
                    if let fetchEnrichment {
                        enrichment = try await fetchEnrichment(uuid)
                    } else if let workout = try await fetchWorkoutByUUID(uuid).first {
                        enrichment = try await fetchDetailedRunEnrichment(for: workout)
                    } else {
                        enrichment = nil
                    }
                    try Task.checkCancellation()
                    if let enrichment {
                        results.append((task, uuid, enrichment, task.attemptCount))
                    } else {
                        task.status = "failed"
                    }
                } catch {
                    if error is CancellationError || isProtectedHealthDataError(error) { throw error }
                    succeeded = false
                    task.attemptCount += 1
                    task.status = task.attemptCount >= 3 ? "failed" : "pending"
                    AppLogger.warning("Route fetch failed: \(error)", category: AppLogger.health)
                }
            }

            // Re-read runs after the queries so an intervening deletion is never resurrected.
            let updates = results.compactMap { result -> Run? in
                guard let run = workoutStore.runs.first(where: { $0.healthKitUUID == result.uuid }) else { return nil }
                return applyDetailedRunEnrichment(result.enrichment, to: run)
            }
            if !updates.isEmpty {
                workoutStore.batchUpdateRuns(updates)
                try await workoutStore.flushHealthKitChanges()
            }
            try Task.checkCancellation()

            for result in results {
                guard workoutStore.runs.contains(where: { $0.healthKitUUID == result.uuid }) else {
                    result.task.status = "failed"
                    continue
                }
                if result.enrichment.route?.isEmpty != false {
                    result.task.attemptCount += 1
                    // Watch routes can arrive well after the workout summary.
                    result.task.status = Date.now.timeIntervalSince(result.task.createdAt) >= 86_400 ? "failed" : "pending"
                } else {
                    result.task.status = "completed"
                }
            }
            try context.save()

            // Optional social work starts only after the local data and job outcome commit.
            for task in tasks where task.status != "pending" && (task.allowAutoPost ?? true) {
                guard let uuid = UUID(uuidString: task.workoutUUID),
                      let run = workoutStore.runs.first(where: { $0.healthKitUUID == uuid }),
                      run.workoutType?.lowercased().contains("run") == true, run.distanceKm >= 1 else { continue }
                Task {
                    await CardioAutoPostService.shared.handleRunIfNeeded(
                        run: run, route: run.route, routeWithHR: run.routeWithHR)
                }
            }
            return succeeded
        } catch {
            // Do not spend a HealthKit retry on local persistence, cancellation or locked data.
            for result in results {
                result.task.status = "pending"
                result.task.attemptCount = result.attemptCount
            }
            syncError = error
            AppLogger.error("Route queue did not commit: \(error)", category: AppLogger.health)
            return false
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
        // Use no options so routes that began recording a few seconds before the
        // workout start (GPS warm-up) or ended slightly after are still matched.
        let timePredicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: []
        )
        let timeBased = try await fetchRouteLocations(predicate: timePredicate, limit: 1)
        if !timeBased.isEmpty {
            AppLogger.debug("Route via time-window fallback: \(timeBased.count) pts", category: AppLogger.health)
            return timeBased
        }

        // Both predicates returned 0. If already connected, missing route is a data gap
        // (route permission not granted, or route genuinely absent) — re-requesting auth
        // won't help and fires connectionState notifications with no state change, causing
        // UI updates on every failing task in the queue. Only re-request when not yet connected.
        AppLogger.warning("Both predicates returned 0 for \(workout.uuid) — re-requesting HK authorization and retrying", category: AppLogger.health)
        guard connectionState != .connected else {
            AppLogger.warning("No route found after already-connected check for \(workout.uuid) — user may need to grant route access in Settings > Health > Apps > Volia", category: AppLogger.health)
            return []
        }
        try? await requestAuthorization()

        let retryAssociated = try await fetchRouteLocations(predicate: HKQuery.predicateForObjects(from: workout))
        if !retryAssociated.isEmpty {
            AppLogger.debug("Route found after auth re-request (association): \(retryAssociated.count) pts", category: AppLogger.health)
            return retryAssociated
        }
        let retryTimeBased = try await fetchRouteLocations(predicate: timePredicate, limit: 1)
        if !retryTimeBased.isEmpty {
            AppLogger.debug("Route found after auth re-request (time-window): \(retryTimeBased.count) pts", category: AppLogger.health)
        } else {
            AppLogger.warning("No route found after auth re-request for \(workout.uuid) — user may need to grant route access in Settings > Health > Apps > Volia", category: AppLogger.health)
        }
        return retryTimeBased
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
                    AppLogger.warning("fetchRouteLocations: HKSampleQuery returned 0 route objects (no HKWorkoutRoute found)", category: AppLogger.health)
                    cont.resume(returning: [])
                    return
                }

                AppLogger.debug("fetchRouteLocations: Found route object, streaming \(route.count) expected points via HKWorkoutRouteQuery", category: AppLogger.health)
                var points: [CLLocation] = []
                var didResume = false
                let q = HKWorkoutRouteQuery(route: route) { _, locations, done, err in
                    guard !didResume else { return }
                    if let err {
                        AppLogger.error("fetchRouteLocations: HKWorkoutRouteQuery error: \(err)", category: AppLogger.health)
                        didResume = true
                        cont.resume(throwing: err)
                        return
                    }
                    if let locations { points.append(contentsOf: locations) }
                    if done {
                        AppLogger.debug("fetchRouteLocations: HKWorkoutRouteQuery done — \(points.count) pts streamed", category: AppLogger.health)
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

    struct DetailedRunEnrichment {
        let distanceKm: Double
        let durationSec: Int
        let calories: Double?
        let workoutType: String
        let workoutName: String?
        let route: [Coordinate]?
        let routeWithHR: [RoutePoint]?
        let splits: [KilometerSplit]?
        let avgHeartRate: Double?
        let maxHeartRate: Double?
        let minHeartRate: Double?
        let hrSamples: [HeartRateSample]?
        let avgRunningPower: Double?
        let avgCadence: Double?
        let avgStrideLength: Double?
        let avgGroundContactTime: Double?
        let avgVerticalOscillation: Double?
    }

    private func optionalHealthKitValue<T>(_ operation: () async throws -> T) async throws -> T? {
        do {
            return try await operation()
        } catch {
            if isProtectedHealthDataError(error) {
                throw error
            }
            return nil
        }
    }

    private func fetchDetailedRunEnrichment(for workout: HKWorkout) async throws -> DetailedRunEnrichment {
        let workoutType = workoutActivityTypeName(workout.workoutActivityType)
        let workoutName = workout.metadata?[HKMetadataKeyWorkoutBrandName] as? String
        let distanceKm = (workout.totalDistance?.doubleValue(for: .meter()) ?? 0) / 1000.0
        let durationSec = workout.duration.safeInt
        let calories = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())

        let splits = try await optionalHealthKitValue {
            try await fetchKilometerSplits(for: workout)
        }
        let routeWithHRResult = try await optionalHealthKitValue {
            try await fetchRouteWithHeartRate(for: workout)
        }

        let routeWithHR = (routeWithHRResult?.count ?? 0) > 1 ? routeWithHRResult : nil
        let route: [Coordinate]?
        if let routeWithHR, !routeWithHR.isEmpty {
            route = routeWithHR.map { Coordinate(lat: $0.lat, lon: $0.lon) }
        } else if let locations = try await optionalHealthKitValue({ try await fetchRoute(for: workout) }), locations.count > 1 {
            route = locations.map { Coordinate(lat: $0.coordinate.latitude, lon: $0.coordinate.longitude) }
        } else {
            route = nil
        }

        let hrTuple = try await optionalHealthKitValue {
            try await fetchHeartRateSamples(for: workout)
        }
        let hrSamples = hrTuple?.0
        let avgHeartRate: Double?
        if let fetchedAvgHeartRate = hrTuple?.1 {
            avgHeartRate = fetchedAvgHeartRate
        } else {
            do {
                avgHeartRate = try await averageHeartRate(for: workout)
            } catch {
                if isProtectedHealthDataError(error) {
                    throw error
                }
                avgHeartRate = nil
            }
        }
        let maxHeartRate = hrTuple?.2
        let minHeartRate = hrTuple?.3

        let runningMetrics = await fetchRunningMetrics(for: workout)

        return DetailedRunEnrichment(
            distanceKm: distanceKm,
            durationSec: durationSec,
            calories: calories,
            workoutType: workoutType,
            workoutName: workoutName,
            route: route,
            routeWithHR: routeWithHR,
            splits: splits,
            avgHeartRate: avgHeartRate,
            maxHeartRate: maxHeartRate,
            minHeartRate: minHeartRate,
            hrSamples: hrSamples,
            avgRunningPower: runningMetrics.avgPower,
            avgCadence: runningMetrics.avgCadence,
            avgStrideLength: runningMetrics.avgStrideLength,
            avgGroundContactTime: runningMetrics.avgGroundContactTime,
            avgVerticalOscillation: runningMetrics.avgVerticalOscillation
        )
    }

    private func applyDetailedRunEnrichment(_ enrichment: DetailedRunEnrichment, to run: Run) -> Run {
        var updated = run
        updated.distanceKm = enrichment.distanceKm
        updated.durationSec = enrichment.durationSec
        updated.calories = enrichment.calories
        updated.workoutType = enrichment.workoutType
        updated.workoutName = enrichment.workoutName
        if let splits = enrichment.splits {
            updated.splits = splits
        }
        if let avgHeartRate = enrichment.avgHeartRate {
            updated.avgHeartRate = avgHeartRate
        }
        if let maxHeartRate = enrichment.maxHeartRate {
            updated.maxHeartRate = maxHeartRate
        }
        if let minHeartRate = enrichment.minHeartRate {
            updated.minHeartRate = minHeartRate
        }
        if let hrSamples = enrichment.hrSamples, !hrSamples.isEmpty {
            updated.hrSamples = hrSamples
        }
        if let avgRunningPower = enrichment.avgRunningPower {
            updated.avgRunningPower = avgRunningPower
        }
        if let avgCadence = enrichment.avgCadence {
            updated.avgCadence = avgCadence
        }
        if let avgStrideLength = enrichment.avgStrideLength {
            updated.avgStrideLength = avgStrideLength
        }
        if let avgGroundContactTime = enrichment.avgGroundContactTime {
            updated.avgGroundContactTime = avgGroundContactTime
        }
        if let avgVerticalOscillation = enrichment.avgVerticalOscillation {
            updated.avgVerticalOscillation = avgVerticalOscillation
        }

        if let route = enrichment.route, !route.isEmpty {
            updated.route = route
        }

        if let routeWithHR = enrichment.routeWithHR, !routeWithHR.isEmpty {
            updated.routeWithHR = routeWithHR
            updated.route = routeWithHR.map { Coordinate(lat: $0.lat, lon: $0.lon) }
        }

        return updated
    }

    // MARK: - Manual Data Refresh for Existing Run

    /// Manually fetch and update splits and HR data for an existing run
    func refreshDetailedDataForRun(runId: UUID) async -> Run? {

        guard let store = workoutStore else {
            AppLogger.warning("Cannot refresh detailed data - WorkoutStore not set", category: AppLogger.health)
            return nil
        }

        let run = await MainActor.run { store.runs.first(where: { $0.id == runId }) }

        guard let run = run, let workoutUUID = run.healthKitUUID else {
            AppLogger.warning("Cannot refresh detailed data - run not found or no HealthKit UUID", category: AppLogger.health)
            return nil
        }


        do {
            // Fetch workout from HealthKit
            let workouts = try await fetchWorkoutByUUID(workoutUUID)
            guard let workout = workouts.first else {
                AppLogger.warning("Workout not found in HealthKit", category: AppLogger.health)
                return nil
            }
            let enrichment = try await fetchDetailedRunEnrichment(for: workout)
            let updated = applyDetailedRunEnrichment(enrichment, to: run)

            // Update run
            await MainActor.run {
                store.updateRun(updated)
                AppLogger.success("Refreshed detailed data for run: \(updated.splits?.count ?? 0) splits, route: \(updated.route?.count ?? 0) pts, dynamics loaded: \(updated.avgCadence != nil || updated.avgRunningPower != nil)", category: AppLogger.health)
            }
            return updated
        } catch {
            AppLogger.error("Failed to refresh detailed data: \(error)", category: AppLogger.health)
            return nil
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
            if let routePoints = routeWithHR, routePoints.contains(where: { ($0.hr ?? 0) > 0 }) {
                hrZones = calculateHRZonesFromRoute(routePoints, totalDuration: totalDuration)
            }

            // Fallback: use HR samples, then estimate only when samples are unavailable.
            if hrZones == nil || hrZones?.isEmpty == true {
                let (hrSamples, avg, _, _) = try await fetchHeartRateSamples(for: workout)
                if hrSamples.count > 1 {
                    hrZones = CardioDataExtractor.shared.calculateHRZones(from: hrSamples)
                } else if avg > 0 {
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

    /// Deleted HealthKit objects have no sample date. Reconcile the saved historical
    /// range in that case, including weeks whose final exercise-time sample disappeared.
    func exerciseTimeReconciliationStart(sampleDates: [Date], hasDeletions: Bool,
                                         context: ModelContext, now: Date = .now,
                                         calendar: Calendar = .current) throws -> Date {
        var earliest = sampleDates.min() ?? now
        if hasDeletions {
            var days = FetchDescriptor<DailyAppleExerciseSummary>(sortBy: [SortDescriptor(\.dayStart)])
            days.fetchLimit = 1
            var weeks = FetchDescriptor<WeeklyTrainingSummary>(
                predicate: #Predicate { $0.appleExerciseMinutes != nil },
                sortBy: [SortDescriptor(\.weekStart)])
            weeks.fetchLimit = 1
            if let day = try context.fetch(days).first { earliest = min(earliest, day.dayStart) }
            if let week = try context.fetch(weeks).first { earliest = min(earliest, week.weekStart) }
        }
        // A partial first week would otherwise replace its total with only the changed days.
        return calendar.startOfWeek(for: earliest, anchorWeekday: 2)
    }

    func reconcileExerciseTimeSummaries(from startDate: Date, to endDate: Date, context: ModelContext,
        fetchDailyTotals: ((Date, Date) async throws -> [(dayStart: Date, minutes: Int)])? = nil
    ) async throws {
        let dailyTotals: [(dayStart: Date, minutes: Int)]
        if let fetchDailyTotals {
            dailyTotals = try await fetchDailyTotals(startDate, endDate)
        } else {
            dailyTotals = try await fetchExerciseTimeDailyTotals(from: startDate, to: endDate)
        }
        let calendar = Calendar.current
        var weeklyTotals: [String: (weekStart: Date, minutes: Int)] = [:]
        let existingWeeks = try context.fetch(FetchDescriptor<WeeklyTrainingSummary>(
            predicate: #Predicate { $0.weekStart >= startDate && $0.weekStart < endDate }
        ))
        for week in existingWeeks {
            weeklyTotals[week.key] = (week.weekStart, 0)
        }
        let fetchedDayStarts = Set(dailyTotals.map(\.dayStart))

        for day in dailyTotals {
            let key = dailyKey(for: day.dayStart, calendar: calendar)
            let descriptor = FetchDescriptor<DailyAppleExerciseSummary>(
                predicate: #Predicate { $0.key == key }
            )

            if let summary = try context.fetch(descriptor).first {
                summary.minutes = day.minutes
                summary.lastHealthSync = .now
            } else {
                context.insert(
                    DailyAppleExerciseSummary(
                        dayStart: day.dayStart,
                        minutes: day.minutes,
                        lastHealthSync: .now
                    )
                )
            }

            let isoWeekStart = calendar.startOfWeek(for: day.dayStart, anchorWeekday: 2)
            let weekKey = ExerciseVolumeSummary.weekKey(from: isoWeekStart)
            var weeklyTotal = weeklyTotals[weekKey] ?? (isoWeekStart, 0)
            weeklyTotal.minutes += day.minutes
            weeklyTotals[weekKey] = weeklyTotal
        }

        let existingDailyDescriptor = FetchDescriptor<DailyAppleExerciseSummary>(
            predicate: #Predicate { $0.dayStart >= startDate && $0.dayStart < endDate }
        )
        let existingDailyRows = try context.fetch(existingDailyDescriptor)
        for row in existingDailyRows where !fetchedDayStarts.contains(calendar.startOfDay(for: row.dayStart)) {
            row.minutes = 0
            row.lastHealthSync = .now
        }

        for (weekKey, value) in weeklyTotals {
            let descriptor = FetchDescriptor<WeeklyTrainingSummary>(
                predicate: #Predicate { $0.key == weekKey }
            )

            if let summary = try context.fetch(descriptor).first {
                summary.appleExerciseMinutes = value.minutes
                summary.lastHealthSync = .now
            } else if value.minutes > 0 {
                context.insert(
                    WeeklyTrainingSummary(
                        key: weekKey,
                        weekStart: value.weekStart,
                        totalVolume: 0,
                        sessions: 0,
                        totalSets: 0,
                        totalReps: 0,
                        minutes: 0,
                        appleExerciseMinutes: value.minutes,
                        cardioSessions: 0,
                        lastHealthSync: .now
                    )
                )
            }
        }

        try context.save()
    }

    private func fetchExerciseTimeDailyTotals(from startDate: Date, to endDate: Date) async throws -> [(dayStart: Date, minutes: Int)] {
        guard let exerciseType = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) else {
            return []
        }

        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
            let interval = DateComponents(day: 1)
            let anchorDate = Calendar.current.startOfDay(for: startDate)

            let query = HKStatisticsCollectionQuery(
                quantityType: exerciseType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchorDate,
                intervalComponents: interval
            )

            query.initialResultsHandler = { _, collection, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                var rows: [(dayStart: Date, minutes: Int)] = []
                collection?.enumerateStatistics(from: startDate, to: endDate) { statistics, _ in
                    let minutes = Int((statistics.sumQuantity()?.doubleValue(for: .minute()) ?? 0).rounded())
                    rows.append((Calendar.current.startOfDay(for: statistics.startDate), minutes))
                }
                continuation.resume(returning: rows)
            }

            store.execute(query)
        }
    }

    private func dailyKey(for date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: calendar.startOfDay(for: date))
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
    func scheduleHealthSyncTask() {
        let request = BGProcessingTaskRequest(identifier: Self.healthSyncTaskID)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3600)  // 1 hour from now

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            AppLogger.warning("Could not schedule HealthKit catch-up: \(error)", category: AppLogger.health)
        }
    }

    func handleHealthSyncTask(task: BGProcessingTask) {
        let completion = HealthSyncTaskCompletion { task.setTaskCompleted(success: $0) }
        task.expirationHandler = { [weak self] in
            Task { @MainActor in
                self?.syncDelivery.cancel()
                completion.finish(success: false)
            }
        }
        Task {
            guard !completion.isFinished else { return }
            let succeeded = await catchUpHealthChanges()
            completion.finish(success: succeeded)
            scheduleHealthSyncTask()
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
