//
//  RunSummary.swift
//  WRKT
//
//  One workout as history-wide code sees it: the scalar fields of `Run` plus a few facts about
//  its detail arrays (route, route with heart rate, heart-rate samples, splits). It never holds
//  the arrays, so code that lists, counts or totals workouts cannot reach them.
//

import Foundation

/// A workout without its detail arrays. Built only from a full `Run`, so its facts are exact
/// for the run it came from.
///
/// The coding keys are explicit and stable: renaming or removing one changes a stored format
/// that a later version may depend on.
struct RunSummary: Identifiable, Hashable, Codable {
    let id: UUID

    // Light fields: the same names, types and meaning as on `Run`.
    var date: Date
    var distanceKm: Double
    var durationSec: Int
    var notes: String?
    var healthKitUUID: UUID?
    var avgHeartRate: Double?
    var calories: Double?
    var workoutType: String?
    var workoutName: String?
    var maxHeartRate: Double?
    var minHeartRate: Double?
    var avgRunningPower: Double?
    var avgCadence: Double?
    var avgStrideLength: Double?
    var avgGroundContactTime: Double?
    var avgVerticalOscillation: Double?

    // Facts about the detail arrays. nil means the array is absent, which is not the same as
    // empty: an empty `splits` reads differently from a missing one.

    /// `route?.count`.
    private(set) var routePointCount: Int?
    /// `routeWithHR?.count`.
    private(set) var routeWithHRPointCount: Int?
    /// Whether any point of `routeWithHR` carries a heart rate.
    private(set) var routeHasHeartRate: Bool
    /// `routeWithHR?.compactMap(\.hr).max()`.
    private(set) var routeMaxHeartRate: Double?
    /// `routeWithHR?.compactMap(\.hr).min()`.
    private(set) var routeMinHeartRate: Double?
    /// `hrSamples?.count`.
    private(set) var heartRateSampleCount: Int?
    /// `splits?.count`.
    private(set) var splitCount: Int?

    private enum CodingKeys: String, CodingKey {
        case id, date, distanceKm, durationSec, notes, healthKitUUID, avgHeartRate, calories
        case workoutType, workoutName, maxHeartRate, minHeartRate
        case avgRunningPower, avgCadence, avgStrideLength, avgGroundContactTime, avgVerticalOscillation
        case routePointCount, routeWithHRPointCount, routeHasHeartRate, routeMaxHeartRate, routeMinHeartRate
        case heartRateSampleCount, splitCount
    }

    /// One pass over the run's arrays.
    init(_ run: Run) {
        id = run.id
        date = run.date
        distanceKm = run.distanceKm
        durationSec = run.durationSec
        notes = run.notes
        healthKitUUID = run.healthKitUUID
        avgHeartRate = run.avgHeartRate
        calories = run.calories
        workoutType = run.workoutType
        workoutName = run.workoutName
        maxHeartRate = run.maxHeartRate
        minHeartRate = run.minHeartRate
        avgRunningPower = run.avgRunningPower
        avgCadence = run.avgCadence
        avgStrideLength = run.avgStrideLength
        avgGroundContactTime = run.avgGroundContactTime
        avgVerticalOscillation = run.avgVerticalOscillation

        routePointCount = run.route?.count
        routeWithHRPointCount = run.routeWithHR?.count
        heartRateSampleCount = run.hrSamples?.count
        splitCount = run.splits?.count

        // The same comparisons as `Sequence.max()` and `Sequence.min()`, in one pass.
        var hasHeartRate = false
        var highest: Double?
        var lowest: Double?
        for point in run.routeWithHR ?? [] {
            guard let hr = point.hr else { continue }
            hasHeartRate = true
            if let current = highest { if current < hr { highest = hr } } else { highest = hr }
            if let current = lowest { if hr < current { lowest = hr } } else { lowest = hr }
        }
        routeHasHeartRate = hasHeartRate
        routeMaxHeartRate = highest
        routeMinHeartRate = lowest
    }
}

// MARK: - Facts

extension RunSummary {
    private var normalizedWorkoutType: String {
        (workoutType ?? "").lowercased()
    }

    var isSupportedCardioForEnrichment: Bool {
        normalizedWorkoutType.contains("run")
            || normalizedWorkoutType.contains("walk")
            || normalizedWorkoutType.contains("cycl")
    }

    /// More than one point in either route.
    var hasUsableRouteData: Bool {
        (routeWithHRPointCount ?? 0) > 1 || (routePointCount ?? 0) > 1
    }

    var hasHeartRateDetailData: Bool {
        (avgHeartRate ?? 0) > 0
            || (maxHeartRate ?? 0) > 0
            || (minHeartRate ?? 0) > 0
            || (heartRateSampleCount ?? 0) > 0
            || routeHasHeartRate
    }

    var hasSplitData: Bool {
        (splitCount ?? 0) > 0
    }

    /// No splits array at all, as opposed to an empty one.
    var splitsAbsent: Bool {
        splitCount == nil
    }

    /// Fewer than two points with heart rate in the route.
    var lacksHeartRateRoute: Bool {
        (routeWithHRPointCount ?? 0) < 2
    }

    var hasRunningDynamicsData: Bool {
        avgRunningPower != nil
            || avgCadence != nil
            || avgStrideLength != nil
            || avgGroundContactTime != nil
            || avgVerticalOscillation != nil
    }

    var needsHistoricalEnrichment: Bool {
        guard healthKitUUID != nil, isSupportedCardioForEnrichment else { return false }
        if !hasUsableRouteData || !hasSplitData || !hasHeartRateDetailData {
            return true
        }
        if normalizedWorkoutType.contains("run") && !hasRunningDynamicsData {
            return true
        }
        return false
    }

    /// The stored maximum, else the route's: what a converted workout shows.
    var effectiveMaxHeartRate: Double? { maxHeartRate ?? routeMaxHeartRate }

    /// The stored minimum, else the route's.
    var effectiveMinHeartRate: Double? { minHeartRate ?? routeMinHeartRate }

    /// The category of this workout.
    var category: HealthKitWorkoutCategory {
        HealthKitWorkoutCategory.categorize(workoutType)
    }

    /// Whether this HealthKit workout counts as a strength day.
    var countsAsStrengthDay: Bool {
        guard healthKitUUID != nil else { return false }
        return category.countsAsStrengthDay
    }
}

// MARK: - Valid cardio

extension RunSummary {
    /// Types that may have no distance and still count as cardio.
    static let validZeroDistanceTypes: Set<String> = [
        "Elliptical", "Stair Climbing", "Rowing", "High Intensity Interval Training", "Dance",
        "Kickboxing", "Boxing", "Soccer", "Basketball", "Tennis", "Pickleball", "Badminton",
        "Volleyball", "Handball", "Racquetball", "Squash", "Table Tennis", "Hockey", "Field Hockey",
        "Lacrosse", "Rugby", "Football", "Cricket", "Martial Arts", "Wrestling", "Skating Sports",
        "Snow Sports"
    ]

    /// Strength and mind-body types that are never cardio.
    static let excludedFromCardioTypes: Set<String> = [
        "Traditional Strength Training", "Functional Strength Training", "Core Training",
        "Flexibility", "Mind and Body", "Yoga"
    ]

    /// The store's `validRuns` rule: a cardio activity with real data.
    static func isValidCardio(distanceKm: Double, durationSec: Int, workoutType: String?) -> Bool {
        // No distance: likely misclassified strength, unless a cardio type that has none.
        if distanceKm <= 0 {
            guard let workoutType, validZeroDistanceTypes.contains(workoutType) else { return false }
        }
        if let workoutType, excludedFromCardioTypes.contains(workoutType) {
            return false
        }
        return durationSec > 0
    }

    var isValidCardio: Bool {
        Self.isValidCardio(distanceKm: distanceKm, durationSec: durationSec, workoutType: workoutType)
    }
}

extension Run {
    /// This run without its arrays. O(points): use it on one run, never across history.
    var summary: RunSummary { RunSummary(self) }
}
