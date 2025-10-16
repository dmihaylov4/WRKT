//
//  HealthRunImporter.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 06.10.25.
//

import HealthKit
import CoreLocation

enum HealthImportError: Error { case unauthorized }

final class HealthRunImporter {
    let hk = HealthKitManager.shared

    // Grab new runs since the last imported HealthKit workout endDate
    func importNewRuns(into store: WorkoutStore, since: Date?) async throws {
        let workouts = try await hk.fetchRunningWorkouts(since: since)
        guard !workouts.isEmpty else { return }

        for wk in workouts {
            // Skip if already imported
            if store.runs.contains(where: { $0.healthKitUUID == wk.uuid }) { continue }

            // distance in km
            let km = (wk.totalDistance?.doubleValue(for: .meter()) ?? 0) / 1000.0
            let sec = Int(wk.duration)

            // Calories (active energy)
            let kcal = wk.totalEnergyBurned?.doubleValue(for: .kilocalorie())

            // Average heart rate (cheap version: query discrete HR samples during interval and average them)
            let avgHR = try? await averageHeartRate(for: wk)

            // Route (may be empty)
            let routeLocs = try? await hk.fetchRoute(for: wk)
            let coords: [Coordinate]? = routeLocs?.map { Coordinate(lat: $0.coordinate.latitude, lon: $0.coordinate.longitude) }

            let run = Run(
                date: wk.startDate,
                distanceKm: km,
                durationSec: sec,
                notes: nil,
                healthKitUUID: wk.uuid,
                avgHeartRate: avgHR,
                calories: kcal,
                route: coords?.isEmpty == false ? coords : nil
            )
            await MainActor.run {
                store.addRun(run) // persists
            }
        }
    }



    private func averageHeartRate(for workout: HKWorkout) async throws -> Double {
        guard let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return 0 }
        let pred = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: [])

        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[HKQuantitySample], Error>) in
            let q = HKSampleQuery(sampleType: hrType,
                                  predicate: pred,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: nil) { _, s, e in
                if let e { cont.resume(throwing: e); return }
                cont.resume(returning: (s as? [HKQuantitySample]) ?? [])
            }
            hk.store.execute(q)
        }

        guard !samples.isEmpty else { return 0 }
        // Same as "count/min"
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        let values = samples.map { $0.quantity.doubleValue(for: bpmUnit) }
        return values.reduce(0, +) / Double(values.count)
    }
}
