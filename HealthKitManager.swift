//
//  HealthKitManager.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 06.10.25.
//

import HealthKit
import CoreLocation

final class HealthKitManager {
    static let shared = HealthKitManager()
    private init() {}
    let store = HKHealthStore()

    // Call on app start or from a “Connect Apple Health” screen
    func requestReadPermissions() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw HKError(.errorHealthDataUnavailable) }

        // Workout + route
        var toRead: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute()
        ]

        // Common quantities we’ll summarize (optional but useful)
        let qtyIds: [HKQuantityTypeIdentifier] = [
            .heartRate,
            .activeEnergyBurned,
            .distanceWalkingRunning,
            // Running dynamics (available on newer OS/devices). Ignore if not found.
            .runningPower,
            .runningStrideLength,
            .runningGroundContactTime,
            .runningVerticalOscillation,
            .runningSpeed,
            //.runningCadence
        ]
        for id in qtyIds {
                if let qt = HKObjectType.quantityType(forIdentifier: id) {
                    toRead.insert(qt)
                }
            }

        try await store.requestAuthorization(toShare: [], read: toRead)
    }

    // Fetch running workouts since date (pulls summaries first; routes fetched separately)
    func fetchRunningWorkouts(since: Date?) async throws -> [HKWorkout] {
        let predicateParts: [NSPredicate] = [
            HKQuery.predicateForWorkouts(with: .running),
            since.map { HKQuery.predicateForSamples(withStart: $0, end: nil, options: []) }
        ].compactMap { $0 }

        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicateParts)
        return try await withCheckedThrowingContinuation { cont in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, error in
                if let error = error { cont.resume(throwing: error); return }
                cont.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }
    }

    // Route retrieval: returns [[CLLocation]] chunks; flatten if needed
    func fetchRoute(for workout: HKWorkout) async throws -> [CLLocation] {
        // Find route objects attached to the workout
        let routeType = HKSeriesType.workoutRoute()
        return try await withCheckedThrowingContinuation { cont in
            let routePredicate = HKQuery.predicateForObjects(from: workout)
            let routeQuery = HKSampleQuery(
                sampleType: routeType,
                predicate: routePredicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { [weak self] _, samples, error in
                guard let self else { if let error { cont.resume(throwing: error) } else { cont.resume(returning: []) }; return }
                if let error = error { cont.resume(throwing: error); return }
                guard let routes = samples as? [HKWorkoutRoute], let route = routes.first else {
                    cont.resume(returning: [])
                    return
                }
                var points: [CLLocation] = []
                let q = HKWorkoutRouteQuery(route: route) { _, locations, done, err in
                    if let err = err { cont.resume(throwing: err); return }
                    if let locations { points.append(contentsOf: locations) }
                    if done { cont.resume(returning: points) }
                }
                self.store.execute(q)
            }
            store.execute(routeQuery)
        }
    }
}
