import Foundation
@testable import WRKT

/// A frozen copy of the run helpers as they were on `test/wave1` at bac5f1f, before run
/// summaries existed: `RouteModels.swift:181-276`, `HealthKitWorkoutCategory.swift:76-87` and
/// `WorkoutStoreV2.validRuns`. The summary facts are proven equal to these. Do not edit them to
/// make a test pass: they are the definition of today's behaviour.
enum LegacyRunHelpers {
    private static func normalizedWorkoutType(_ run: Run) -> String {
        (run.workoutType ?? "").lowercased()
    }

    static func isSupportedCardioForEnrichment(_ run: Run) -> Bool {
        normalizedWorkoutType(run).contains("run")
            || normalizedWorkoutType(run).contains("walk")
            || normalizedWorkoutType(run).contains("cycl")
    }

    static func hasUsableRouteData(_ run: Run) -> Bool {
        (run.routeWithHR?.count ?? 0) > 1 || (run.route?.count ?? 0) > 1
    }

    static func hasHeartRateDetailData(_ run: Run) -> Bool {
        (run.avgHeartRate ?? 0) > 0
            || (run.maxHeartRate ?? 0) > 0
            || (run.minHeartRate ?? 0) > 0
            || !(run.hrSamples?.isEmpty ?? true)
            || (run.routeWithHR?.contains { $0.hr != nil } ?? false)
    }

    static func hasSplitData(_ run: Run) -> Bool {
        !(run.splits?.isEmpty ?? true)
    }

    static func hasRunningDynamicsData(_ run: Run) -> Bool {
        run.avgRunningPower != nil
            || run.avgCadence != nil
            || run.avgStrideLength != nil
            || run.avgGroundContactTime != nil
            || run.avgVerticalOscillation != nil
    }

    static func needsHistoricalEnrichment(_ run: Run) -> Bool {
        guard run.healthKitUUID != nil, isSupportedCardioForEnrichment(run) else { return false }
        if !hasUsableRouteData(run) || !hasSplitData(run) || !hasHeartRateDetailData(run) {
            return true
        }
        if normalizedWorkoutType(run).contains("run") && !hasRunningDynamicsData(run) {
            return true
        }
        return false
    }

    /// `CutCardioLogic.detail`'s route test.
    static func detailHasRouteMap(_ run: Run) -> Bool {
        max(run.routeWithHR?.count ?? 0, run.route?.count ?? 0) > 1
    }

    /// The legacy splits tab's "Load Splits" test and the auto-post fetch test.
    static func splitsAbsent(_ run: Run) -> Bool {
        run.splits == nil
    }

    /// "Load Details" and `canLoadDetails`.
    static func lacksHeartRateRoute(_ run: Run) -> Bool {
        (run.routeWithHR?.count ?? 0) < 2
    }

    static func maxHeartRate(_ run: Run) -> Double? {
        run.maxHeartRate ?? run.routeWithHR?.compactMap { $0.hr }.max()
    }

    static func minHeartRate(_ run: Run) -> Double? {
        run.minHeartRate ?? run.routeWithHR?.compactMap { $0.hr }.min()
    }

    static func category(_ run: Run) -> HealthKitWorkoutCategory {
        HealthKitWorkoutCategory.categorize(run.workoutType)
    }

    static func countsAsStrengthDay(_ run: Run) -> Bool {
        guard run.healthKitUUID != nil else { return false }
        return category(run).countsAsStrengthDay
    }

    /// `WorkoutStoreV2.validRuns`' filter for one run.
    static func isValidRun(_ run: Run) -> Bool {
        if run.distanceKm <= 0 {
            guard let workoutType = run.workoutType else { return false }
            let validZeroDistanceTypes = [
                "Elliptical", "Stair Climbing", "Rowing", "High Intensity Interval Training", "Dance",
                "Kickboxing", "Boxing", "Soccer", "Basketball", "Tennis", "Pickleball", "Badminton",
                "Volleyball", "Handball", "Racquetball", "Squash", "Table Tennis", "Hockey",
                "Field Hockey", "Lacrosse", "Rugby", "Football", "Cricket", "Martial Arts", "Wrestling",
                "Skating Sports", "Snow Sports"
            ]
            if !validZeroDistanceTypes.contains(workoutType) {
                return false
            }
        }
        let excludedWorkoutTypes = [
            "Traditional Strength Training", "Functional Strength Training", "Core Training",
            "Flexibility", "Mind and Body", "Yoga"
        ]
        if let workoutType = run.workoutType, excludedWorkoutTypes.contains(workoutType) {
            return false
        }
        if run.durationSec <= 0 {
            return false
        }
        return true
    }

    static func toCompletedWorkout(_ run: Run) -> CompletedWorkout {
        let maxHR = run.maxHeartRate ?? run.routeWithHR?.compactMap { $0.hr }.max()
        let minHR = run.minHeartRate ?? run.routeWithHR?.compactMap { $0.hr }.min()
        let distanceMeters = run.distanceKm * 1000

        var workout = CompletedWorkout(
            id: run.id,
            date: run.date,
            startedAt: run.date.addingTimeInterval(-Double(run.durationSec)),
            entries: [],
            plannedWorkoutID: nil,
            workoutName: run.workoutName
        )
        workout.matchedHealthKitUUID = run.healthKitUUID
        workout.matchedHealthKitCalories = run.calories
        workout.matchedHealthKitHeartRate = run.avgHeartRate
        workout.matchedHealthKitMaxHeartRate = maxHR
        workout.matchedHealthKitMinHeartRate = minHR
        workout.matchedHealthKitDuration = run.durationSec
        workout.matchedHealthKitDistance = distanceMeters

        workout.cardioWorkoutType = run.workoutType
        if let samples = run.hrSamples, !samples.isEmpty {
            workout.matchedHealthKitHeartRateSamples = samples
        }
        workout.cardioAvgPower = run.avgRunningPower
        workout.cardioAvgCadence = run.avgCadence
        workout.cardioAvgStrideLength = run.avgStrideLength
        workout.cardioAvgGroundContactTime = run.avgGroundContactTime
        workout.cardioAvgVerticalOscillation = run.avgVerticalOscillation
        return workout
    }

    /// Every difference between a summary and today's helpers on its run, by name. Empty when
    /// they agree.
    static func differences(_ summary: RunSummary, from run: Run) -> [String] {
        var found: [String] = []
        func check(_ name: String, _ equal: Bool) { if !equal { found.append(name) } }
        check("id", summary.id == run.id)
        check("date", summary.date == run.date)
        check("distanceKm", summary.distanceKm.bitPattern == run.distanceKm.bitPattern)
        check("durationSec", summary.durationSec == run.durationSec)
        check("notes", summary.notes == run.notes)
        check("healthKitUUID", summary.healthKitUUID == run.healthKitUUID)
        check("avgHeartRate", summary.avgHeartRate == run.avgHeartRate)
        check("calories", summary.calories == run.calories)
        check("workoutType", summary.workoutType == run.workoutType)
        check("workoutName", summary.workoutName == run.workoutName)
        check("maxHeartRate", summary.maxHeartRate == run.maxHeartRate)
        check("minHeartRate", summary.minHeartRate == run.minHeartRate)
        check("avgRunningPower", summary.avgRunningPower == run.avgRunningPower)
        check("avgCadence", summary.avgCadence == run.avgCadence)
        check("avgStrideLength", summary.avgStrideLength == run.avgStrideLength)
        check("avgGroundContactTime", summary.avgGroundContactTime == run.avgGroundContactTime)
        check("avgVerticalOscillation", summary.avgVerticalOscillation == run.avgVerticalOscillation)
        check("isSupportedCardioForEnrichment", summary.isSupportedCardioForEnrichment == isSupportedCardioForEnrichment(run))
        check("hasUsableRouteData", summary.hasUsableRouteData == hasUsableRouteData(run))
        check("hasUsableRouteData as detail map", summary.hasUsableRouteData == detailHasRouteMap(run))
        check("hasHeartRateDetailData", summary.hasHeartRateDetailData == hasHeartRateDetailData(run))
        check("hasSplitData", summary.hasSplitData == hasSplitData(run))
        check("splitsAbsent", summary.splitsAbsent == splitsAbsent(run))
        check("lacksHeartRateRoute", summary.lacksHeartRateRoute == lacksHeartRateRoute(run))
        check("hasRunningDynamicsData", summary.hasRunningDynamicsData == hasRunningDynamicsData(run))
        check("needsHistoricalEnrichment", summary.needsHistoricalEnrichment == needsHistoricalEnrichment(run))
        check("effectiveMaxHeartRate", summary.effectiveMaxHeartRate == maxHeartRate(run))
        check("effectiveMinHeartRate", summary.effectiveMinHeartRate == minHeartRate(run))
        check("category", summary.category == category(run))
        check("countsAsStrengthDay", summary.countsAsStrengthDay == countsAsStrengthDay(run))
        check("isValidCardio", summary.isValidCardio == isValidRun(run))
        let legacyWorkout = toCompletedWorkout(run)
        check("toCompletedWorkout", run.toCompletedWorkout() == legacyWorkout)
        var withoutSamples = legacyWorkout
        withoutSamples.matchedHealthKitHeartRateSamples = nil
        check("completedWorkoutWithoutSamples", summary.completedWorkoutWithoutSamples() == withoutSamples)
        return found
    }
}
