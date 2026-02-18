//
//  RouteModels.swift
//  WRKT
//
//  Models for workout routes and GPS data
//

import Foundation
import CoreLocation

// MARK: - Enhanced Route Point (future: timestamps + per-point HR)

struct Coordinate: Codable, Hashable {
    let lat: Double
    let lon: Double
}

// MARK: - Kilometer Split

struct KilometerSplit: Codable, Hashable, Identifiable {
    var id: Int { number }
    let number: Int          // Split number (1, 2, 3...)
    let distanceKm: Double   // Distance covered in this split (usually 1.0, but may be less for final split)
    let durationSec: Int     // Time taken for this split in seconds
    let paceSecPerKm: Int    // Pace for this split (seconds per kilometer)

    init(number: Int, distanceKm: Double, durationSec: Int) {
        self.number = number
        self.distanceKm = distanceKm
        self.durationSec = durationSec
        // Calculate pace (extrapolate to full km if partial split)
        if distanceKm > 0 {
            self.paceSecPerKm = (Double(durationSec) / distanceKm).safeInt
        } else {
            self.paceSecPerKm = 0
        }
    }
}

struct Run: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date
    var distanceKm: Double
    var durationSec: Int
    var notes: String?

    // HealthKit fields
    var healthKitUUID: UUID?   // to de-duplicate imports
    var avgHeartRate: Double?
    var calories: Double?
    var route: [Coordinate]?   // nil when no route
    var routeWithHR: [RoutePoint]?  // Route with per-point heart rate data
    var splits: [KilometerSplit]?   // Per-kilometer splits
    var workoutType: String?   // HealthKit workout activity type (e.g., "Running", "Cycling", "Traditional Strength Training")
    var workoutName: String?   // Custom workout name from Apple Fitness/Watch

    // Running dynamics (from Apple Watch)
    var avgRunningPower: Double?           // Watts
    var avgCadence: Double?                // Steps per minute
    var avgStrideLength: Double?           // Meters
    var avgGroundContactTime: Double?      // Milliseconds
    var avgVerticalOscillation: Double?    // Centimeters

    init(
        id: UUID = UUID(),
        date: Date = .now,
        distanceKm: Double,
        durationSec: Int,
        notes: String? = nil,
        healthKitUUID: UUID? = nil,
        avgHeartRate: Double? = nil,
        calories: Double? = nil,
        route: [Coordinate]? = nil,
        routeWithHR: [RoutePoint]? = nil,
        splits: [KilometerSplit]? = nil,
        workoutType: String? = nil,
        workoutName: String? = nil,
        avgRunningPower: Double? = nil,
        avgCadence: Double? = nil,
        avgStrideLength: Double? = nil,
        avgGroundContactTime: Double? = nil,
        avgVerticalOscillation: Double? = nil
    ) {
        self.id = id
        self.date = date
        self.distanceKm = distanceKm
        self.durationSec = durationSec
        self.notes = notes
        self.healthKitUUID = healthKitUUID
        self.avgHeartRate = avgHeartRate
        self.calories = calories
        self.route = route
        self.routeWithHR = routeWithHR
        self.splits = splits
        self.workoutType = workoutType
        self.workoutName = workoutName
        self.avgRunningPower = avgRunningPower
        self.avgCadence = avgCadence
        self.avgStrideLength = avgStrideLength
        self.avgGroundContactTime = avgGroundContactTime
        self.avgVerticalOscillation = avgVerticalOscillation
    }
}

struct RunLog: Identifiable, Codable, Hashable {
    let id: UUID
    var date: Date
    var distanceKm: Double
    var durationSec: Int
    var notes: String?
    init(id: UUID = UUID(), date: Date = .now, distanceKm: Double, durationSec: Int, notes: String? = nil) {
        self.id = id
        self.date = date
        self.distanceKm = distanceKm
        self.durationSec = durationSec
        self.notes = notes
    }
}

struct RoutePoint: Hashable, Codable {
    let lat: Double
    let lon: Double
    let t: Date           // Timestamp
    let hr: Double?       // Heart rate (optional)

    init(lat: Double, lon: Double, t: Date, hr: Double? = nil) {
        self.lat = lat
        self.lon = lon
        self.t = t
        self.hr = hr
    }

    // Convert from CLLocation
    init(from location: CLLocation, heartRate: Double? = nil) {
        self.lat = location.coordinate.latitude
        self.lon = location.coordinate.longitude
        self.t = location.timestamp
        self.hr = heartRate
    }

    // Convert to CLLocationCoordinate2D
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

// MARK: - Extensions

extension Array where Element == RoutePoint {
    /// Extract just the coordinates
    var coordinates: [CLLocationCoordinate2D] {
        map { $0.coordinate }
    }

    /// Extract heart rate values (NaN for missing)
    var heartRates: [Double] {
        map { $0.hr ?? .nan }
    }
}

extension Array where Element == Coordinate {
    /// Convert to CLLocationCoordinate2D
    var clCoordinates: [CLLocationCoordinate2D] {
        map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }
}

// MARK: - Run to CompletedWorkout Conversion

extension Run {
    /// Convert a cardio Run to a CompletedWorkout for sharing
    /// Empty entries array will make isCardioWorkout return true
    func toCompletedWorkout() -> CompletedWorkout {
        // Calculate max heart rate from routeWithHR if available
        let maxHR = routeWithHR?.compactMap { $0.hr }.max()

        // Calculate min heart rate from routeWithHR if available
        let minHR = routeWithHR?.compactMap { $0.hr }.min()

        // Convert distance from km to meters
        let distanceMeters = distanceKm * 1000

        var workout = CompletedWorkout(
            id: id,
            date: date,
            startedAt: date.addingTimeInterval(-Double(durationSec)), // Estimate start time
            entries: [], // Empty entries make this a cardio workout
            plannedWorkoutID: nil,
            workoutName: workoutName
        ).with(
            healthKitUUID: healthKitUUID,
            calories: calories,
            heartRate: avgHeartRate,
            maxHeartRate: maxHR,
            minHeartRate: minHR,
            duration: durationSec,
            distance: distanceMeters
        )

        // Map running dynamics
        workout.cardioAvgPower = avgRunningPower
        workout.cardioAvgCadence = avgCadence
        workout.cardioAvgStrideLength = avgStrideLength
        workout.cardioAvgGroundContactTime = avgGroundContactTime
        workout.cardioAvgVerticalOscillation = avgVerticalOscillation

        return workout
    }
}

// Helper to apply HealthKit data to CompletedWorkout
private extension CompletedWorkout {
    func with(
        healthKitUUID: UUID?,
        calories: Double?,
        heartRate: Double?,
        maxHeartRate: Double?,
        minHeartRate: Double?,
        duration: Int?,
        distance: Double? = nil
    ) -> CompletedWorkout {
        var workout = self
        workout.matchedHealthKitUUID = healthKitUUID
        workout.matchedHealthKitCalories = calories
        workout.matchedHealthKitHeartRate = heartRate
        workout.matchedHealthKitMaxHeartRate = maxHeartRate
        workout.matchedHealthKitMinHeartRate = minHeartRate
        workout.matchedHealthKitDuration = duration
        workout.matchedHealthKitDistance = distance
        return workout
    }
}
