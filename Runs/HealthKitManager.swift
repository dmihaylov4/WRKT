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
    private init() {}

    let store = HKHealthStore()

    @Published var connectionState: HealthConnectionState = .disconnected
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: Error?

    // SwiftData context (injected from app)
    var modelContext: ModelContext?

    // WorkoutStore reference (injected from app)
    weak var workoutStore: WorkoutStore?

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

        try await store.requestAuthorization(toShare: [], read: toRead)

        // Check authorization status
        let status = store.authorizationStatus(for: .workoutType())
        switch status {
        case .sharingAuthorized:
            connectionState = .connected
        case .notDetermined:
            connectionState = .limited
        case .sharingDenied:
            connectionState = .disconnected
        @unknown default:
            connectionState = .limited
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
                    print("⚠️ Workout observer error: \(error)")
                    self.syncError = error
                } else {
                    print("🔔 HealthKit workout data changed - triggering sync")
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
                        print("⚠️ Exercise time observer error: \(error)")
                    } else {
                        print("🔔 HealthKit exercise time changed - triggering sync")
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
                    print("⚠️ Background delivery setup failed: \(error)")
                } else if success {
                    print("✅ Background delivery enabled for workouts")
                }
            }
        }

        if let exerciseTimeObserver, let exerciseType = HKObjectType.quantityType(forIdentifier: .appleExerciseTime) {
            store.execute(exerciseTimeObserver)
            store.enableBackgroundDelivery(for: exerciseType, frequency: .hourly) { success, error in
                if let error {
                    print("⚠️ Background delivery setup failed for exercise time: \(error)")
                } else if success {
                    print("✅ Background delivery enabled for exercise time")
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

    func syncWorkoutsIncremental() async {
        guard let context = modelContext else {
            print("⚠️ ModelContext not set")
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        do {
            // Fetch or create anchor
            let anchorRecord = try fetchOrCreateAnchor(dataType: "all_workouts", context: context)
            let anchor = anchorRecord.anchor

            print("📊 Syncing workouts (anchor: \(anchor != nil ? "exists" : "nil"))")

            // Anchored query
            let (added, deleted, newAnchor) = try await fetchWorkoutsAnchored(anchor: anchor)

            print("  → Added: \(added.count), Deleted: \(deleted.count)")

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
            print("❌ Workout sync failed: \(error)")
            syncError = error
        }
    }

    func syncExerciseTimeIncremental() async {
        guard let context = modelContext else { return }

        do {
            let anchorRecord = try fetchOrCreateAnchor(dataType: "exercise_time", context: context)
            let anchor = anchorRecord.anchor

            let (samples, newAnchor) = try await fetchExerciseTimeSamplesAnchored(anchor: anchor)

            print("📊 Syncing exercise time: \(samples.count) samples")

            // Aggregate by week and update WeeklyTrainingSummary
            await aggregateExerciseTimeIntoWeeklySummaries(samples: samples, context: context)

            // Update anchor
            anchorRecord.updateAnchor(newAnchor)
            try context.save()

        } catch {
            print("❌ Exercise time sync failed: \(error)")
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
            print("⚠️ WorkoutStore not set")
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

        let run = Run(
            date: workout.startDate,
            distanceKm: km,
            durationSec: sec,
            notes: nil,
            healthKitUUID: workout.uuid,
            avgHeartRate: avgHR,
            calories: kcal,
            route: nil  // Fetched separately via queue
        )

        await MainActor.run {
            store.addRun(run)
        }
    }

    private func deleteWorkoutIfExists(uuid: UUID, context: ModelContext) throws {
        guard let store = workoutStore else {
            print("⚠️ WorkoutStore not set")
            return
        }

        Task { @MainActor in
            if let existing = store.runs.first(where: { $0.healthKitUUID == uuid }) {
                store.removeRun(withId: existing.id)
                print("🗑️ Deleted workout: \(uuid)")
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

        print("🗺️ Processing \(tasks.count) route fetch tasks")

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
                        print("  ✅ Fetched route for \(uuid): \(coords.count) points")
                    } else {
                        task.status = "failed"
                    }
                }

            } catch {
                task.attemptCount += 1
                task.status = task.attemptCount >= 3 ? "failed" : "pending"
                print("  ⚠️ Route fetch failed: \(error)")
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

    private func fetchWorkoutByUUID(_ uuid: UUID) async throws -> [HKWorkout] {
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

    private func averageHeartRate(for workout: HKWorkout) async throws -> Double {
        guard let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return 0 }
        let pred = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: [])

        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: hrType, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, s, e in
                if let e { cont.resume(throwing: e); return }
                cont.resume(returning: (s as? [HKQuantitySample]) ?? [])
            }
            store.execute(q)
        }

        guard !samples.isEmpty else { return 0 }
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        let values = samples.map { $0.quantity.doubleValue(for: bpmUnit) }
        return values.reduce(0, +) / Double(values.count)
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
    static let healthSyncTaskID = "com.wrkt.health.sync"

    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.healthSyncTaskID, using: nil) { task in
            self.handleHealthSyncTask(task: task as! BGProcessingTask)
        }
    }

    func scheduleHealthSyncTask() {
        let request = BGProcessingTaskRequest(identifier: Self.healthSyncTaskID)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3600)  // 1 hour from now

        try? BGTaskScheduler.shared.submit(request)
    }

    private func handleHealthSyncTask(task: BGProcessingTask) {
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
