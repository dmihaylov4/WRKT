import Foundation
import SwiftUI
import Testing
@testable import WRKT

/// Shared fixtures for the Cut workout record logic and capture tests. Dates are fixed in UTC.
enum CutWorkoutDetailFixtures {
    static let locale = Locale(identifier: "en_GB")
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    /// Friday 13 November 2026, 12:00 UTC.
    static let now = Date(timeIntervalSince1970: 1_794_571_200)
    /// Friday 13 November 2026, 18:42 UTC: the workout ends here.
    static let end = Date(timeIntervalSince1970: 1_794_571_200 + 6 * 3600 + 42 * 60)

    static func set(_ reps: Int, _ kg: Double, tag: SetTag = .working, mode: TrackingMode = .weighted,
                    seconds: Int = 0, work: TimeInterval? = nil, rest: Int? = nil) -> SetInput {
        let start = work.map { _ in end.addingTimeInterval(-600) }
        return SetInput(reps: reps, weight: kg, tag: tag, isCompleted: true, durationSeconds: seconds, trackingMode: mode,
                        startTime: start, completionTime: start.flatMap { s in work.map { s.addingTimeInterval($0) } },
                        restAfterSeconds: rest)
    }

    static var squat: WorkoutEntry {
        WorkoutEntry(exerciseID: "squat", exerciseName: "Back Squat", muscleGroups: ["Quads"], sets: [
            set(8, 60, tag: .warmup), set(5, 80), set(5, 90), set(5, 100)
        ])
    }

    static var pullUps: WorkoutEntry {
        WorkoutEntry(exerciseID: "pullup", exerciseName: "Pull-Up", muscleGroups: ["Back"], sets: [
            set(12, 0, mode: .bodyweight), set(10, 0, mode: .bodyweight)
        ])
    }

    static var plank: WorkoutEntry {
        WorkoutEntry(exerciseID: "plank", exerciseName: "Plank", muscleGroups: ["Abs"], sets: [
            set(0, 0, mode: .timed, seconds: 90)
        ])
    }

    static func samples(count: Int = 40, from start: Date = end.addingTimeInterval(-48 * 60)) -> [HeartRateSample] {
        (0..<count).map { index in
            HeartRateSample(timestamp: start.addingTimeInterval(Double(index) * 72), bpm: 100 + Double((index * 7) % 60))
        }
    }

    static var zones: [HRZoneSummary] {
        [
            HRZoneSummary(zone: 3, name: "Aerobic", minutes: 18, rangeDisplay: "133-152", colorHex: ""),
            HRZoneSummary(zone: 1, name: "Light", minutes: 5, rangeDisplay: "95-114", colorHex: ""),
            HRZoneSummary(zone: 2, name: "Moderate", minutes: 14, rangeDisplay: "114-133", colorHex: ""),
            HRZoneSummary(zone: 4, name: "Threshold", minutes: 0, rangeDisplay: "152-171", colorHex: "")
        ]
    }

    /// A full workout: named, timed, matched to the watch with heart rate.
    static var full: CompletedWorkout {
        var workout = CompletedWorkout(date: end, startedAt: end.addingTimeInterval(-48 * 60 - 12),
                                       entries: [squat, pullUps], workoutName: "Lower Body")
        workout.matchedHealthKitUUID = UUID()
        workout.matchedHealthKitCalories = 412.4
        workout.matchedHealthKitHeartRate = 128.4
        workout.matchedHealthKitMaxHeartRate = 164
        workout.matchedHealthKitMinHeartRate = 71
        workout.matchedHealthKitDuration = 48 * 60 + 12
        workout.matchedHealthKitHeartRateSamples = samples()
        return workout
    }

    /// Logged in the app only: no watch match, no start time, no timing.
    static var bare: CompletedWorkout {
        CompletedWorkout(date: end, entries: [squat])
    }

    static func detail(_ workout: CompletedWorkout = full, unit: WeightUnit = .kg, zones: [HRZoneSummary] = zones,
                       sessionIDs: Set<String> = []) -> CutWorkoutDetailModel {
        CutWorkoutDetailLogic.detail(workout, zones: zones, zoneMethod: "Default (190 bpm)", unit: unit,
                                     sessionExerciseIDs: sessionIDs, now: now, calendar: calendar, locale: locale)
    }

    static func strengthRun(name: String? = "Strength", type: String? = "Traditional Strength Training",
                            seconds: Int = 41 * 60 + 6, calories: Double? = 356, heartRate: Double? = 121,
                            notes: String? = nil) -> Run {
        var run = Run(date: end, distanceKm: 0, durationSec: seconds, notes: notes, healthKitUUID: UUID(),
                      avgHeartRate: heartRate, calories: calories, workoutType: type, workoutName: name)
        run.maxHeartRate = 160
        return run
    }

    static func strength(_ run: Run = strengthRun(), existing: CompletedWorkout? = nil) -> CutHealthStrengthModel {
        CutWorkoutDetailLogic.healthStrength(run.summary, existing: existing, now: now, calendar: calendar, locale: locale)
    }
}

@Suite struct CutWorkoutDetailLogicTests {
    private typealias F = CutWorkoutDetailFixtures

    // MARK: Header

    @Test func titleUsesNameElseClassifier() {
        #expect(CutWorkoutDetailLogic.title(F.full) == "Lower Body")
        var unnamed = F.full
        unnamed.workoutName = "   "
        #expect(CutWorkoutDetailLogic.title(unnamed) == MuscleGroupClassifier.classify(unnamed))
    }

    @Test func dateLineShowsStartToEnd() {
        #expect(F.detail().dateLine == "Friday 13 Nov, 17:53 to 18:42")
    }

    @Test func dateLineFallsBackToWatchDurationThenSetTiming() {
        var workout = F.full
        workout.startedAt = nil
        #expect(F.detail(workout).dateLine == "Friday 13 Nov, 17:53 to 18:42")

        var timed = F.bare
        timed.entries = [WorkoutEntry(exerciseID: "x", exerciseName: "X", muscleGroups: [],
                                      sets: [F.set(5, 50, work: 30)])]
        #expect(F.detail(timed).dateLine == "Friday 13 Nov, 18:41 to 18:42")
    }

    @Test func dateLineWithoutAnyStartSaysEnded() {
        #expect(F.detail(F.bare).dateLine == "Friday 13 Nov, ended 18:42")
    }

    @Test func dateLineInAnotherYearShowsTheYear() {
        var old = F.bare
        old.date = F.end.addingTimeInterval(-400 * 86_400)
        #expect(F.detail(old).dateLine.contains("2025"))
    }

    @Test func enhancedOnlyWithWatchMatch() {
        #expect(F.detail().isEnhanced)
        #expect(!F.detail(F.bare).isEnhanced)
    }

    @Test func deleteTitleNamesWorkoutAndDay() {
        #expect(F.detail().deleteTitle == "Lower Body, 13 Nov")
    }

    // MARK: Stats

    @Test func fullWorkoutHasTimeAndCountRows() {
        let rows = F.detail().statRows
        #expect(rows.count == 2)
        #expect(rows[0].map(\.label) == ["Duration", "kcal"])
        #expect(rows[0].map(\.value) == ["48:12", "412"])
        #expect(rows[1].map(\.label) == ["Exercises", "Sets", "Reps", "kg volume"])
        // Volume from weighted sets only: 8x60 + 5x80 + 5x90 + 5x100 = 1,830 kg.
        #expect(rows[1].map(\.value) == ["2", "6", "22", "1.8K"])
    }

    @Test func durationOverAnHourDropsSeconds() {
        var workout = F.full
        workout.matchedHealthKitDuration = 3_725
        #expect(F.detail(workout).statRows[0][0].value == "1:02")
        #expect(F.detail(workout).statRows[0][0].unit == "h")
        #expect(F.detail().statRows[0][0].unit == nil)
    }

    @Test func volumeFollowsTheWeightUnit() {
        let rows = F.detail(unit: .lb).statRows
        #expect(rows[1].last == CutStatColumn(value: "4.0K", label: "lb volume"))
    }

    @Test func bareWorkoutHasOnlyCountRow() {
        let rows = F.detail(F.bare).statRows
        #expect(rows.count == 1)
        #expect(rows[0].map(\.label) == ["Exercise", "Sets", "kg volume"])
    }

    @Test func bodyweightOnlyShowsRepsNotVolume() {
        var workout = F.bare
        workout.entries = [F.pullUps]
        let counts = F.detail(workout).statRows[0]
        #expect(counts.map(\.label) == ["Exercise", "Sets", "Reps"])
        #expect(counts[2].value == "22")
    }

    @Test func zeroExercisesStillCounts() {
        var workout = F.bare
        workout.entries = []
        let model = F.detail(workout)
        #expect(model.statRows == [[CutStatColumn(value: "0", label: "Exercises"), CutStatColumn(value: "0", label: "Sets")]])
        #expect(model.exercises.isEmpty)
        #expect(model.title == MuscleGroupClassifier.classify(workout))
    }

    @Test func averageRestOverGapsBetweenSets() {
        var workout = F.bare
        workout.entries = [WorkoutEntry(exerciseID: "x", exerciseName: "X", muscleGroups: [], sets: [
            F.set(5, 50, rest: 90), F.set(5, 50, rest: 90), F.set(5, 50)
        ])]
        // 180 s of rest over two gaps.
        #expect(CutWorkoutDetailLogic.averageRestSeconds(workout.entries) == 90)
        #expect(F.detail(workout).statRows[0] == CutWorkoutDetailLogic.padded([CutStatColumn(value: "1:30", label: "Avg rest")]))
    }

    @Test func singleColumnRowIsPadded() {
        let padded = CutWorkoutDetailLogic.padded([CutStatColumn(value: "1", label: "A")])
        #expect(padded.count == 2)
        #expect(padded[1].value.isEmpty)
    }

    @Test func largeTextSplitsRowsIntoPairs() {
        let rows = CutWorkoutDetailLogic.columnRows(F.detail().statRows, maxColumns: 2)
        #expect(rows.map { $0.map(\.label) } == [["Duration", "kcal"], ["Exercises", "Sets"], ["Reps", "kg volume"]])
        let three = [[CutStatColumn(value: "71", label: "Min"), CutStatColumn(value: "128", label: "Average"),
                      CutStatColumn(value: "164", label: "Max")]]
        let split = CutWorkoutDetailLogic.columnRows(three, maxColumns: 2)
        #expect(split.map { $0.map(\.label) } == [["Min", "Average"], ["Max", ""]])
        #expect(CutWorkoutDetailLogic.columnRows(three, maxColumns: 4) == three)
        // A padded single column is not split again.
        let padded = [CutWorkoutDetailLogic.padded([CutStatColumn(value: "1", label: "A")])]
        #expect(CutWorkoutDetailLogic.columnRows(padded, maxColumns: 2) == padded)
    }

    @Test func longTitlesWrap() {
        #expect(!CutRecordTitle<EmptyView>.wraps("Lower Body"))
        #expect(!CutRecordTitle<EmptyView>.wraps("Upper Body Workout"))
        #expect(CutRecordTitle<EmptyView>.wraps("Heavy Lower Body With Paused Squats"))
        #expect(!CutRecordTitle<EmptyView>.wraps("Supercalifragilisticexpialidocious"))
    }

    // MARK: Heart rate

    @Test func heartRateStatsInLegacyOrder() throws {
        let heart = try #require(F.detail().heartRate)
        #expect(heart.stats.map(\.label) == ["Min", "Average", "Max"])
        #expect(heart.stats.map(\.value) == ["71", "128", "164"])
        #expect(heart.sampleCount == "40 samples")
        #expect(heart.startLabel == "17:54")
        #expect(heart.endLabel == "18:40")
        #expect(heart.bars.count == 16)
        #expect(heart.bars.allSatisfy { $0 > 0 && $0 <= 1 })
    }

    @Test func heartRateLeavesOutMissingValues() throws {
        var workout = F.full
        workout.matchedHealthKitMinHeartRate = nil
        workout.matchedHealthKitMaxHeartRate = 0
        let heart = try #require(F.detail(workout).heartRate)
        #expect(heart.stats.map(\.label) == ["Average"])
    }

    @Test func noHeartRateWithoutSamples() {
        var workout = F.full
        workout.matchedHealthKitHeartRateSamples = []
        let model = F.detail(workout)
        #expect(model.heartRate == nil)
        #expect(model.zones == nil)
        #expect(F.detail(F.bare).heartRate == nil)
    }

    @Test func twoSamplesShowStatsWithoutBars() throws {
        var workout = F.full
        workout.matchedHealthKitHeartRateSamples = F.samples(count: 2)
        let model = F.detail(workout)
        let heart = try #require(model.heartRate)
        #expect(heart.bars.isEmpty)
        #expect(heart.startLabel == nil)
        #expect(heart.sampleCount == "2 samples")
        // Zones need more than five samples, as before.
        #expect(model.zones == nil)
    }

    // MARK: Zones

    @Test func zonesSortedWithTimeAndShare() throws {
        let zones = try #require(F.detail().zones)
        #expect(zones.rows.map(\.label) == ["Zone 1", "Zone 2", "Zone 3"])
        #expect(zones.rows.map(\.time) == ["5:00", "14:00", "18:00"])
        #expect(abs(zones.rows[2].fraction - 18.0 / 37.0) < 0.0001)
        #expect(zones.method == "Zones: Default (190 bpm)")
    }

    @Test func zonesWithoutTimeShowEmptyState() throws {
        let zones = try #require(F.detail(zones: []).zones)
        #expect(zones.rows.isEmpty)
    }

    @Test func zoneSummariesKeepZonesWithTime() {
        let summaries = CutWorkoutDetailLogic.zoneSummaries(
            boundaries: [(2, "Moderate", "114-133"), (1, "Light", "95-114"), (3, "Aerobic", "133-152")],
            durations: [1: 120, 3: 300])
        #expect(summaries.map(\.zone) == [1, 3])
        #expect(summaries.map(\.minutes) == [2, 5])
        #expect(summaries[1].rangeDisplay == "133-152")
    }

    // MARK: Exercises

    @Test func exerciseSummaryAndSets() throws {
        let squat = try #require(F.detail().exercises.first)
        #expect(squat.name == "Back Squat")
        #expect(squat.summary == "4 sets, 23 reps, 1.8K kg")
        #expect(squat.timing == nil)
        #expect(squat.sets.map(\.value) == ["60 kg × 8", "80 kg × 5", "90 kg × 5", "100 kg × 5"])
        #expect(squat.sets.map(\.number) == ["1", "2", "3", "4"])
        #expect(squat.sets.map(\.tag) == ["Warm-up", nil, nil, nil])
    }

    @Test func setValuesFollowTrackingModeAndUnit() {
        #expect(CutWorkoutDetailLogic.setValue(F.set(5, 100), unit: .lb) == "220.5 lb × 5")
        #expect(CutWorkoutDetailLogic.setValue(F.set(5, 82.5), unit: .kg) == "82.5 kg × 5")
        #expect(CutWorkoutDetailLogic.setValue(F.set(12, 0, mode: .bodyweight), unit: .kg) == "12 reps")
        #expect(CutWorkoutDetailLogic.setValue(F.set(1, 0, mode: .bodyweight), unit: .kg) == "1 rep")
        #expect(CutWorkoutDetailLogic.setValue(F.set(0, 0, mode: .timed, seconds: 90), unit: .kg) == "1:30")
        var distance = F.set(0, 0, mode: .distance)
        distance.distanceMeters = 2_500
        #expect(CutWorkoutDetailLogic.setValue(distance, unit: .kg) == "2.50 km")
        distance.distanceMeters = 800
        #expect(CutWorkoutDetailLogic.setValue(distance, unit: .kg) == "800 m")
    }

    @Test func bodyweightExerciseHasNoVolume() throws {
        var workout = F.bare
        workout.entries = [F.pullUps]
        let pullUps = try #require(F.detail(workout).exercises.first)
        #expect(pullUps.summary == "2 sets, 22 reps")
    }

    @Test func setTimingShowsWorkAndRest() {
        let row = CutWorkoutDetailLogic.setRow(F.set(5, 100, work: 45, rest: 90), index: 0, unit: .kg)
        #expect(row.timing == "Work 0:45, rest 1:30")
        let restOnly = CutWorkoutDetailLogic.setRow(F.set(5, 100, rest: 120), index: 1, unit: .kg)
        #expect(restOnly.timing == "Rest 2:00")
        #expect(CutWorkoutDetailLogic.setRow(F.set(5, 100), index: 2, unit: .kg).timing == nil)
    }

    @Test func exerciseTimingWhenSetsAreTimed() throws {
        var workout = F.bare
        workout.entries = [WorkoutEntry(exerciseID: "x", exerciseName: "X", muscleGroups: [], sets: [
            F.set(5, 50, work: 40, rest: 90), F.set(5, 50, work: 50)
        ])]
        let exercise = try #require(F.detail(workout).exercises.first)
        #expect(exercise.timing == "Total 3:00, work 1:30, rest 1:30")
    }

    @Test func onlyListedExercisesOpenTheSession() {
        let model = F.detail(sessionIDs: ["squat"])
        #expect(model.exercises.map(\.opensSession) == [true, false])
        #expect(F.detail().exercises.allSatisfy { !$0.opensSession })
    }

    @Test func liveSessionRuleMatchesTheLegacyCheck() {
        let ids = ["squat", "pullup"]
        #expect(CutWorkoutDetailLogic.opensLiveSession(workoutDate: F.end, workoutExerciseIDs: ids,
                                                       currentStartedAt: F.end.addingTimeInterval(30),
                                                       currentExerciseIDs: ids.reversed()))
        #expect(!CutWorkoutDetailLogic.opensLiveSession(workoutDate: F.end, workoutExerciseIDs: ids,
                                                        currentStartedAt: F.end.addingTimeInterval(90),
                                                        currentExerciseIDs: ids))
        #expect(!CutWorkoutDetailLogic.opensLiveSession(workoutDate: F.end, workoutExerciseIDs: ids,
                                                        currentStartedAt: F.end, currentExerciseIDs: ["squat"]))
        #expect(!CutWorkoutDetailLogic.opensLiveSession(workoutDate: F.end, workoutExerciseIDs: ids,
                                                        currentStartedAt: nil, currentExerciseIDs: ids))
    }
}

@Suite struct CutWorkoutDetailHealthStrengthTests {
    private typealias F = CutWorkoutDetailFixtures

    @Test func fullHealthWorkout() {
        let model = F.strength()
        #expect(model.title == "Strength")
        #expect(model.dateLine == "Friday 13 Nov, 18:00 to 18:42")
        #expect(model.sourceLine == "Apple Watch, Traditional Strength Training")
        #expect(model.hero == CutCardioHero(value: "41:06", unit: "min"))
        #expect(model.stats == [CutStatColumn(value: "356", label: "kcal"), CutStatColumn(value: "121", label: "Avg bpm")])
        #expect(model.details == .canAdd)
        #expect(model.editTitle == "Add exercise details")
        #expect(model.deleteTitle == "Strength, 13 Nov")
        #expect(model.notes == nil)
    }

    @Test func titleFallsBackToTypeThenGeneric() {
        #expect(F.strength(F.strengthRun(name: "")).title == "Traditional Strength Training")
        #expect(F.strength(F.strengthRun(name: nil, type: nil)).title == "Strength Workout")
        #expect(F.strength(F.strengthRun(type: nil)).sourceLine == "Apple Watch")
    }

    @Test func convertedWorkoutUsesItsTitleAndEdits() {
        var existing = F.bare
        existing.workoutName = "Push Day"
        let model = F.strength(existing: existing)
        #expect(model.title == "Push Day")
        #expect(model.details == .added)
        #expect(model.editTitle == "Edit workout")
    }

    @Test func overAnHourShowsHoursAndMinutes() {
        let model = F.strength(F.strengthRun(seconds: 3_725))
        #expect(model.hero == CutCardioHero(value: "1:02", unit: "h"))
    }

    @Test func missingStatsAreLeftOutAndOneIsPadded() {
        #expect(F.strength(F.strengthRun(calories: nil, heartRate: nil)).stats.isEmpty)
        let one = F.strength(F.strengthRun(calories: 0, heartRate: 130)).stats
        #expect(one.count == 2)
        #expect(one[0] == CutStatColumn(value: "130", label: "Avg bpm"))
    }

    @Test func blankNotesAreHidden() {
        #expect(F.strength(F.strengthRun(notes: "  Felt strong ")).notes == "  Felt strong ")
        #expect(F.strength(F.strengthRun(notes: "   ")).notes == nil)
    }

    @Test func zeroDurationShowsEndOnly() {
        #expect(F.strength(F.strengthRun(seconds: 0)).dateLine == "Friday 13 Nov, 18:42")
    }

    @Test func newWorkoutCarriesHealthData() {
        let run = F.strengthRun()
        let workout = CutWorkoutDetailLogic.workout(from: run.summary)
        #expect(workout.date == run.date)
        #expect(workout.startedAt == run.date.addingTimeInterval(-2_466))
        #expect(workout.entries.isEmpty)
        #expect(workout.matchedHealthKitUUID == run.healthKitUUID)
        #expect(workout.matchedHealthKitCalories == 356)
        #expect(workout.matchedHealthKitHeartRate == 121)
        #expect(workout.matchedHealthKitDuration == 2_466)
    }
}
