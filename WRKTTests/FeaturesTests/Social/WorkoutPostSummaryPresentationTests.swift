import XCTest
@testable import WRKT

final class WorkoutPostSummaryPresentationTests: WRKTTestCase {
    func testSingleStrengthSummaryUsesExistingWorkoutData() {
        let workout = makeStrengthWorkout(
            name: "Pull",
            entries: [
                makeEntry(name: "Barbell Romanian Deadlift", sets: [(8, 50), (8, 50), (6, 50)]),
                makeEntry(name: "Bench Press", sets: [(4, 50), (4, 50)])
            ],
            durationMinutes: 48,
            calories: 274,
            heartRate: 116
        )

        let summary = WorkoutPostSummaryPresentation.make(for: [workout])

        XCTAssertEqual(summary.title, "Strength Session")
        XCTAssertEqual(summary.badge, nil)
        XCTAssertEqual(summary.stats.map(\.label), ["Volume", "Exercises", "Sets", "Duration"])
        XCTAssertEqual(summary.stats.map(\.value), ["1.5k", "2", "5", "48m"])
        XCTAssertEqual(summary.stats.map(\.unit), ["KG", "EX", "TOTAL", "TIME"])
        XCTAssertEqual(summary.biometrics, ["116 BPM", "274 kcal"])
        XCTAssertEqual(summary.previewLine, "Barbell Romanian Deadlift, Bench Press")
        XCTAssertEqual(summary.breakdownRows.map(\.title), ["Barbell Romanian Deadlift", "Bench Press"])
    }

    func testMultiStrengthSummaryAggregatesAcrossWorkouts() {
        let first = makeStrengthWorkout(
            name: "Pull",
            entries: [makeEntry(name: "Romanian Deadlift", sets: [(8, 50), (8, 50), (6, 50)])],
            durationMinutes: 20,
            calories: 120,
            heartRate: 110
        )
        let second = makeStrengthWorkout(
            name: "Push",
            entries: [makeEntry(name: "Bench Press", sets: [(8, 60), (8, 60), (8, 60)])],
            durationMinutes: 28,
            calories: 154,
            heartRate: 122
        )

        let summary = WorkoutPostSummaryPresentation.make(for: [first, second])

        XCTAssertEqual(summary.title, "Strength Session")
        XCTAssertEqual(summary.badge, "2 workouts")
        XCTAssertEqual(summary.stats.map(\.value), ["2.5k", "2", "6", "48m"])
        XCTAssertEqual(summary.biometrics, ["116 BPM", "274 kcal"])
        XCTAssertEqual(summary.previewLine, "Romanian Deadlift, Bench Press")
    }

    func testCardioSummaryUsesDistancePaceAndWatchMetrics() {
        var workout = CompletedWorkout(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            date: makeDate(year: 2026, month: 5, day: 12, hour: 8, minute: 30),
            startedAt: makeDate(year: 2026, month: 5, day: 12, hour: 8),
            entries: [],
            workoutName: nil
        )
        workout.cardioWorkoutType = "Running"
        workout.matchedHealthKitUUID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        workout.matchedHealthKitDuration = 1800
        workout.matchedHealthKitDistance = 5000
        workout.matchedHealthKitCalories = 310
        workout.matchedHealthKitHeartRate = 142

        let summary = WorkoutPostSummaryPresentation.make(for: [workout])

        XCTAssertEqual(summary.title, "Running")
        XCTAssertEqual(summary.stats.map(\.label), ["Distance", "Duration", "Pace", "Calories"])
        XCTAssertEqual(summary.stats.map(\.value), ["5.00", "30:00", "6:00", "310"])
        XCTAssertEqual(summary.stats.map(\.unit), ["KM", "TIME", "/KM", "KCAL"])
        XCTAssertEqual(summary.biometrics, ["142 BPM"])
        XCTAssertEqual(summary.previewLine, "Running")
    }

    func testMixedSummaryDoesNotForceStrengthOrCardioLanguage() {
        let strength = makeStrengthWorkout(
            name: "Strength",
            entries: [makeEntry(name: "Lat Pulldown", sets: [(10, 45), (10, 45)])],
            durationMinutes: 24,
            calories: 130,
            heartRate: 118
        )
        var run = CompletedWorkout(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            date: makeDate(year: 2026, month: 5, day: 12, hour: 9, minute: 20),
            startedAt: makeDate(year: 2026, month: 5, day: 12, hour: 9),
            entries: [],
            workoutName: nil
        )
        run.cardioWorkoutType = "Running"
        run.matchedHealthKitUUID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        run.matchedHealthKitDuration = 1200
        run.matchedHealthKitDistance = 3000
        run.matchedHealthKitCalories = 170

        let summary = WorkoutPostSummaryPresentation.make(for: [strength, run])

        XCTAssertEqual(summary.title, "Strength + Cardio")
        XCTAssertEqual(summary.badge, "2 workouts")
        XCTAssertEqual(summary.stats.map(\.label), ["Volume", "Workouts", "Duration", "Calories"])
        XCTAssertEqual(summary.stats.map(\.value), ["900", "2", "44m", "300"])
        XCTAssertEqual(summary.previewLine, "Strength, Running")
    }

    private func makeStrengthWorkout(
        name: String,
        entries: [WorkoutEntry],
        durationMinutes: Int,
        calories: Double?,
        heartRate: Double?
    ) -> CompletedWorkout {
        let started = makeDate(year: 2026, month: 5, day: 12, hour: 8)
        var workout = CompletedWorkout(
            id: UUID(),
            date: started.addingTimeInterval(TimeInterval(durationMinutes * 60)),
            startedAt: started,
            entries: entries,
            workoutName: name
        )
        workout.matchedHealthKitDuration = durationMinutes * 60
        workout.matchedHealthKitCalories = calories
        workout.matchedHealthKitHeartRate = heartRate
        return workout
    }

    private func makeEntry(name: String, sets: [(Int, Double)]) -> WorkoutEntry {
        WorkoutEntry(
            exerciseID: UUID().uuidString,
            exerciseName: name,
            muscleGroups: [],
            sets: sets.map { reps, weight in
                SetInput(reps: reps, weight: weight, tag: .working, isCompleted: true)
            }
        )
    }
}
