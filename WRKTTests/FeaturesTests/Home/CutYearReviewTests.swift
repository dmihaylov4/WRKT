import Foundation
import SwiftUI
import Testing
@testable import WRKT

/// The year in review's numbers, comparison ladders and pop-up window.
struct CutYearReviewLogicTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Vienna")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func workout(on date: Date, sets: [SetInput], records: Int? = nil) -> CompletedWorkout {
        var workout = CompletedWorkout(
            date: date, startedAt: date.addingTimeInterval(-3600),
            entries: [WorkoutEntry(exerciseID: "bench", exerciseName: "Bench Press", muscleGroups: ["Chest"], sets: sets)])
        workout.detectedPRCount = records
        return workout
    }

    private func set(_ weight: Double, _ reps: Int, done: Bool = true) -> SetInput {
        var set = SetInput(reps: reps, weight: weight)
        set.isCompleted = done
        return set
    }

    @Test func ladderPicksTheHeaviestRungReached() {
        #expect(CutYearReviewLadder.rung(forKg: 100) == nil)
        #expect(CutYearReviewLadder.rung(forKg: 430_000)?.rung.name == "the Riesenrad")
        #expect(CutYearReviewLadder.rung(forKg: 430_000)?.count == 1)
        #expect(CutYearReviewLadder.rung(forKg: 13_000)?.rung.name == "a city bus")
        #expect(CutYearReviewLadder.rung(forKg: 25_000)?.count == 2)
        #expect(CutYearReviewLadder.weight.map(\.kg) == CutYearReviewLadder.weight.map(\.kg).sorted())
    }

    @Test func liftedCopyScalesWithTheTotal() {
        #expect(CutYearReviewLogic.lifted(kg: 430_000, unit: .kg).headline == "You lifted the Riesenrad.")
        #expect(CutYearReviewLogic.lifted(kg: 410_000, unit: .kg).headline == "You lifted the Statue of Liberty, twice.")
        #expect(CutYearReviewLogic.lifted(kg: 900_000, unit: .kg).headline == "You lifted a fully loaded A380.")
        #expect(CutYearReviewLogic.lifted(kg: 25_000, unit: .kg).headline == "You lifted two city buses.")
        #expect(CutYearReviewLogic.lifted(kg: 25_000, unit: .kg).detail
                == "One weighs about 12 tonnes. You moved that twice over this year.")
        #expect(CutYearReviewLogic.lifted(kg: 430_000, unit: .kg).detail
                == "The Riesenrad weighs about 430 tonnes. You moved that much iron this year.")
        #expect(CutYearReviewLogic.lifted(kg: 40, unit: .kg).headline == "Every kilo counted.")
        // The decimal separator follows the device's region.
        #expect(CutYearReviewLogic.weightText(kg: 1_500, unit: .kg)
                == "\(1.5.formatted(.number.precision(.fractionLength(1)))) tonnes")
        #expect(CutYearReviewLogic.weightText(kg: 480, unit: .kg) == "480 kg")
    }

    @Test func distanceReadsAsMarathons() {
        #expect(CutYearReviewLogic.distance(km: 486, longestKm: 21.1).headline == "Eleven and a half marathons.")
        #expect(CutYearReviewLogic.distance(km: 43, longestKm: 10).headline == "A full marathon.")
        #expect(CutYearReviewLogic.distance(km: 25, longestKm: 10).headline == "Half a marathon.")
        #expect(CutYearReviewLogic.distance(km: 4, longestKm: 4).headline == "Ten laps of a running track.")
    }

    @Test func timeReadsAsDays() {
        #expect(CutYearReviewLogic.time(seconds: 118 * 3600, workouts: 142).headline == "Almost five days, non-stop.")
        #expect(CutYearReviewLogic.time(seconds: 48 * 3600, workouts: 40).headline == "Two full days, non-stop.")
        #expect(CutYearReviewLogic.time(seconds: 36 * 3600, workouts: 40).headline == "A day and a half, non-stop.")
        #expect(CutYearReviewLogic.time(seconds: 10 * 3600, workouts: 9).headline == "Ten hours, back to back.")
    }

    @Test func statsSumTheYearOnly() {
        let workouts = [
            workout(on: date(2026, 3, 2), sets: [set(100, 5), set(100, 5), set(60, 10, done: false)], records: 2),
            workout(on: date(2026, 3, 9), sets: [set(80, 10)]),
            workout(on: date(2025, 12, 30), sets: [set(200, 5)])
        ]
        let runs = [Run(date: date(2026, 3, 17), distanceKm: 10, durationSec: 3000),
                    Run(date: date(2026, 6, 1), distanceKm: 21.1, durationSec: 7200)]
        let stats = CutYearReviewLogic.stats(year: 2026, workouts: workouts, runs: runs,
                                             now: date(2026, 11, 14), calendar: calendar)
        #expect(stats.liftedKg == 1_800)
        #expect(stats.records == 2)
        #expect(stats.distanceKm == 31.1)
        #expect(stats.longestDistanceKm == 21.1)
        #expect(stats.workouts == 4)
        #expect(stats.trainedSeconds == 2 * 3600 + 3000 + 7200)
        #expect(stats.longestStreakWeeks == 3)
        #expect(CutYearReviewLogic.cards(for: stats) == [.lifted, .distance, .time, .streak])
    }

    @Test func popUpWindowAndOncePerYear() {
        #expect(CutYearReviewLogic.reviewYear(now: date(2026, 11, 14), calendar: calendar) == nil)
        #expect(CutYearReviewLogic.reviewYear(now: date(2026, 12, 15), calendar: calendar) == 2026)
        #expect(CutYearReviewLogic.reviewYear(now: date(2027, 1, 20), calendar: calendar) == 2026)
        #expect(CutYearReviewLogic.reviewYear(now: date(2027, 2, 1), calendar: calendar) == nil)
        let sample = CutYearReviewStats.sample(year: 2026)
        #expect(CutYearReviewLogic.shouldAutoPresent(stats: sample, seenYear: nil))
        #expect(!CutYearReviewLogic.shouldAutoPresent(stats: sample, seenYear: 2026))
        #expect(!CutYearReviewLogic.shouldAutoPresent(stats: CutYearReviewStats(year: 2026, workouts: 2), seenYear: nil))
    }

    @Test func teaserUsesWhatTheYearHas() {
        #expect(CutYearReviewLogic.teaser(stats: .sample(year: 2026), unit: .kg)
                == "You lifted the Riesenrad, covered eleven and a half marathons and set 23 records.")
        #expect(CutYearReviewLogic.teaser(stats: CutYearReviewStats(year: 2026, workouts: 7), unit: .kg)
                == "You logged 7 workouts.")
    }
}

/// Opt-in captures of every year in review step (VOLIA_CAPTURE_YEAR=1). Writes to
/// VOLIA_CAPTURE_DIR or /private/tmp/volia-cut-year. Run on the dedicated capture simulator.
@MainActor
struct CutYearReviewCaptureTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_YEAR"] == "1"))
    func captureSteps() async throws {
        let helper = CutWorkoutCaptureTests()
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_DIR"] ?? "/private/tmp/volia-cut-year")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sample = CutYearReviewStats.sample(year: 2026)
        for step in 0...5 {
            try await helper.capture(host(sample, step: step), name: "year-\(step)", wait: .seconds(4))
        }
        var light = sample
        light.liftedKg = 25_000
        light.distanceKm = 0
        light.trainedSeconds = 30 * 3600
        try await helper.capture(host(light, step: 1), name: "year-light-1", wait: .seconds(4))
        try await helper.capture(host(light, step: 4), name: "year-light-share", wait: .seconds(4))
        try await helper.capture(host(sample, step: 1), name: "year-1-ax", dynamicType: .accessibility2, wait: .seconds(4))
    }

    private func host(_ stats: CutYearReviewStats, step: Int) -> some View {
        ZStack {
            DS.Cut.Colors.lime.ignoresSafeArea()
            CutYearReviewDeck(stats: stats, unit: .kg, startStep: step) { _ in }
        }
    }
}
