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
    var workoutType: String?   // HealthKit workout activity type (e.g., "Running", "Cycling", "Traditional Strength Training")
    var workoutName: String?   // Custom workout name from Apple Fitness/Watch

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
        workoutType: String? = nil,
        workoutName: String? = nil
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
        self.workoutType = workoutType
        self.workoutName = workoutName
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
