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

    @Published var connectionState: HealthConnectionState {
        didSet {
            // Persist connection state to UserDefaults
            UserDefaults.standard.set(connectionState.rawValue, forKey: "healthkit.connectionState")
            AppLogger.debug("Saved connectionState: \(connectionState)", category: AppLogger.health)
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

        AppLogger.info("Requesting authorization for \(toRead.count) data types...", category: AppLogger.health)
        try await store.requestAuthorization(toShare: [], read: toRead)
        AppLogger.success("requestAuthorization completed", category: AppLogger.health)

        // Check authorization status
        let status = store.authorizationStatus(for: .workoutType())
        AppLogger.debug("Authorization status after request: \(status.rawValue) (.notDetermined=0, .sharingDenied=1, .sharingAuthorized=2)", category: AppLogger.health)

        // HealthKit often returns incorrect status for privacy reasons
        // The ONLY reliable way to know is to try querying data
        AppLogger.debug("Testing data access with a sample query...", category: AppLogger.health)
        let canReadData = await testDataAccess()

        if canReadData {
            AppLogger.success("Data access confirmed - setting connectionState to .connected (Note: status said \(status.rawValue) but we can actually read data)", category: AppLogger.health)
            connectionState = .connected
        } else {
            AppLogger.warning("Cannot read data", category: AppLogger.health)
            if status == .sharingDenied {
                AppLogger.debug("Setting connectionState to .disconnected", category: AppLogger.health)
                connectionState = .disconnected
            } else {
                AppLogger.debug("Setting connectionState to .limited", category: AppLogger.health)
                connectionState = .limited
            }
        }

        AppLogger.info("Final connectionState: \(connectionState)", category: AppLogger.health)
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
        guard connectionState == .connected else { return }

        // Observe workout changes
        workoutObserver = HKObserverQuery(sampleType: .workoutType(), predicate: nil) { [weak self] _, completionHandler, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    AppLogger.warning("Workout observer error: \(error)", category: AppLogger.health)
                    self.syncError = error
                } else {
                    AppLogger.info("HealthKit workout data changed - triggering sync", category: AppLogger.health)
                    await self.syncWorkoutsIncremental()
                }
                completionHandler()
            }
        }

        // Observe Apple Exercise Time changes
        if let exerciseType = HKObjectType.quantityType(forIdentifier: .appleExerciseTime) {
            exerciseTimeObserver = HKObserverQuery(sampleType: exerciseType, predicate: nil) { [weak self] _, completionHandler, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let error {
                        AppLogger.warning("Exercise time observer error: \(error)", category: AppLogger.health)
                    } else {
                        AppLogger.info("HealthKit exercise time changed - triggering sync", category: AppLogger.health)
                        await self.syncExerciseTimeIncremental()
                    }
                    completionHandler()
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

        isSyncing = true
        defer { isSyncing = false }

        do {
            // Fetch or create anchor
            let anchorRecord = try fetchOrCreateAnchor(dataType: "all_workouts", context: context)
            let anchor = anchorRecord.anchor

            AppLogger.debug("Syncing workouts (anchor: \(anchor != nil ? "exists" : "nil"))", category: AppLogger.health)

            // Anchored query
            let (added, deleted, newAnchor) = try await fetchWorkoutsAnchored(anchor: anchor)

            AppLogger.debug("Added: \(added.count), Deleted: \(deleted.count)", category: AppLogger.health)

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

        } catch {
            AppLogger.error("Workout sync failed: \(error)", category: AppLogger.health)
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

                    AppLogger.success("Batch complete: \(syncProcessedCount)/\(syncTotalCount) (\(Int(syncProgress * 100))%)", category: AppLogger.health)
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
                        updated.durationSec = Int(workout.duration)
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
                        let sec = Int(workout.duration)
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

        // Check if already imported
        let existing = await MainActor.run {
            store.runs.first(where: { $0.healthKitUUID == workout.uuid })
        }

        if let existing {
            // Update if needed (e.g., if HealthKit data changed)
            var updated = existing
            updated.distanceKm = (workout.totalDistance?.doubleValue(for: .meter()) ?? 0) / 1000.0
            updated.durationSec = Int(workout.duration)
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

            AppLogger.debug("Updating: \(workoutType) at \(workout.startDate.formatted(date: .abbreviated, time: .shortened))", category: AppLogger.health)

            await MainActor.run {
                store.updateRun(updated)
            }
            return
        }

        // Import new workout
        let km = (workout.totalDistance?.doubleValue(for: .meter()) ?? 0) / 1000.0
        let sec = Int(workout.duration)
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
    }

    private func deleteWorkoutIfExists(uuid: UUID, context: ModelContext) throws {
        guard let store = workoutStore else {
            AppLogger.warning("WorkoutStore not set", category: AppLogger.health)
            return
        }

        Task { @MainActor in
            if let existing = store.runs.first(where: { $0.healthKitUUID == uuid }) {
                store.removeRun(withId: existing.id)
                AppLogger.info("Deleted workout: \(uuid)", category: AppLogger.health)
            }
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

    func processRouteFetchQueue() async {
        guard let context = modelContext else { return }

        // Fetch pending tasks (prioritized)
        let descriptor = FetchDescriptor<RouteFetchTask>(
            predicate: #Predicate { $0.status == "pending" },
            sortBy: [SortDescriptor(\.priority), SortDescriptor(\.workoutDate, order: .reverse)]
        )

        guard let tasks = try? context.fetch(descriptor), !tasks.isEmpty else { return }

        AppLogger.info("Processing \(tasks.count) route fetch tasks", category: AppLogger.health)

        for task in tasks.prefix(10) {  // Process 10 at a time
            task.status = "fetching"
            task.lastAttemptDate = .now

            do {
                guard let uuid = UUID(uuidString: task.workoutUUID) else { continue }

                // Fetch workout from HealthKit
                let workouts = try await fetchWorkoutByUUID(uuid)
                guard let workout = workouts.first else {
                    task.status = "failed"
                    continue
                }

                // Fetch route
                let locations = try await fetchRoute(for: workout)

                // Update Run with route
                await MainActor.run {
                    if let store = workoutStore,
                       let existing = store.runs.first(where: { $0.healthKitUUID == uuid }) {
                        var updated = existing
                        let coords = locations.map { Coordinate(lat: $0.coordinate.latitude, lon: $0.coordinate.longitude) }
                        updated.route = coords.isEmpty ? nil : coords
                        store.updateRun(updated)
                        task.status = "completed"
                        AppLogger.success("Fetched route for \(uuid): \(coords.count) points", category: AppLogger.health)
                    } else {
                        task.status = "failed"
                    }
                }

            } catch {
                task.attemptCount += 1
                task.status = task.attemptCount >= 3 ? "failed" : "pending"
                AppLogger.warning("Route fetch failed: \(error)", category: AppLogger.health)
            }

            try? context.save()
        }
    }

    // MARK: - Route Fetching

    func fetchRoute(for workout: HKWorkout) async throws -> [CLLocation] {
        let routeType = HKSeriesType.workoutRoute()
        return try await withCheckedThrowingContinuation { cont in
            let routePredicate = HKQuery.predicateForObjects(from: workout)
            let routeQuery = HKSampleQuery(
                sampleType: routeType,
                predicate: routePredicate,
                limit: HKObjectQueryNoLimit,
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
                let q = HKWorkoutRouteQuery(route: route) { _, locations, done, err in
                    if let err { cont.resume(throwing: err); return }
                    if let locations { points.append(contentsOf: locations) }
                    if done { cont.resume(returning: points) }
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
}
