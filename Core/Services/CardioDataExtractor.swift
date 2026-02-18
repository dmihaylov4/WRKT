//
//  CardioDataExtractor.swift
//  WRKT
//
//  Shared logic for enriching workouts with cardio-specific data for social sharing
//  Extracts splits, HR zones, and generates map snapshots from Run data
//

import SwiftUI
import MapKit
import CoreLocation

@MainActor
final class CardioDataExtractor {
    static let shared = CardioDataExtractor()

    private let hrCalculator = HRZoneCalculator.shared

    private init() {}

    // MARK: - Public API

    /// Enrich a CompletedWorkout with cardio-specific data from a Run
    func enrichWorkout(_ workout: inout CompletedWorkout, from run: Run) {
        workout.cardioSplits = run.splits
        workout.cardioHRZones = calculateHRZones(from: run)
        workout.cardioWorkoutType = run.workoutType ?? run.workoutName

        // Copy running dynamics
        workout.cardioAvgPower = run.avgRunningPower
        workout.cardioAvgCadence = run.avgCadence
        workout.cardioAvgStrideLength = run.avgStrideLength
        workout.cardioAvgGroundContactTime = run.avgGroundContactTime
        workout.cardioAvgVerticalOscillation = run.avgVerticalOscillation
    }

    /// Calculate HR zone breakdown from route data
    func calculateHRZones(from run: Run) -> [HRZoneSummary]? {
        // Try to calculate from route with HR data
        if let routeWithHR = run.routeWithHR, !routeWithHR.isEmpty {
            let zones = calculateActualHRZones(from: routeWithHR, totalDuration: run.durationSec)
            // Check if actual zones have meaningful data (not all zeros)
            let totalMinutes = zones.reduce(0) { $0 + $1.minutes }
            if totalMinutes > 0 {
                return zones
            }
            // Fall through to estimated if route HR data was all nil/empty
        }

        // Fallback: estimate from average HR
        if let avgHR = run.avgHeartRate, avgHR > 0 {
            return calculateEstimatedHRZones(avgHR: avgHR, totalDuration: run.durationSec)
        }

        return nil
    }

    
    func generateMapSnapshot(from run: Run, size: CGSize = CGSize(width: 600, height: 400)) async throws -> UIImage? {
        guard let routeWithHR = run.routeWithHR, routeWithHR.count > 1 else {
          
            if let route = run.route, route.count > 1 {
                let coordinates = route.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
                return try await MapSnapshotService.shared.generateRouteSnapshot(
                    coordinates: coordinates,
                    hrValues: nil,
                    size: size
                )
            }
            return nil
        }

       
        let coordinates = routeWithHR.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        let hrValues = routeWithHR.map { $0.hr ?? .nan }

        return try await MapSnapshotService.shared.generateRouteSnapshot(
            coordinates: coordinates,
            hrValues: hrValues,
            size: size
        )
    }

    // MARK: - Private Methods

    /// Calculate actual HR zones from route data with heart rate samples
    private func calculateActualHRZones(from points: [RoutePoint], totalDuration: Int) -> [HRZoneSummary] {
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
            return buildEmptyZones(boundaries: boundaries)
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

    /// Calculate estimated HR zones from average HR only
    func calculateEstimatedHRZones(avgHR: Double, totalDuration: Int) -> [HRZoneSummary] {
        let boundaries = hrCalculator.zoneBoundaries()
        let dominantZone = hrCalculator.zone(for: avgHR)

        // Distribute time: dominant zone gets 60%, adjacent zones get 20% each
        let totalMinutes = Double(totalDuration) / 60.0

        return boundaries.map { boundary in
            let zoneDiff = abs(boundary.zone - dominantZone)
            let fraction: Double
            switch zoneDiff {
            case 0: fraction = 0.60  // Dominant zone
            case 1: fraction = 0.20  // Adjacent zones
            default: fraction = 0.0  // Further zones
            }

            return HRZoneSummary(
                zone: boundary.zone,
                name: boundary.name,
                minutes: totalMinutes * fraction,
                rangeDisplay: boundary.rangeString,
                colorHex: boundary.color.toHex()
            )
        }
    }

    /// Build empty zones when no HR data available
    private func buildEmptyZones(boundaries: [HRZoneBoundary]) -> [HRZoneSummary] {
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
}

// MARK: - Color Extension

private extension Color {
    /// Convert Color to hex string
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
