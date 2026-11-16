import Foundation
@testable import WRKT

/// Made-up training for the Cut statistics tests and captures. Nothing here reads the account,
/// SwiftData, HealthKit or the server; workouts are plain values fed to the real aggregator.
enum CutStatsFixtures {
    static let locale = Locale(identifier: "en_GB")
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }()
    /// Friday 13 November 2026, 12:00 UTC. Its week runs Monday 9 to Sunday 15 November.
    static let now = Date(timeIntervalSince1970: 1_794_571_200)
    /// Monday 9 November 2026, 00:00 UTC.
    static let thisMonday = Date(timeIntervalSince1970: 1_794_182_400)

    static func monday(weeksAgo: Int) -> Date {
        calendar.date(byAdding: .day, value: -7 * weeksAgo, to: thisMonday)!
    }

    static func daysAgo(_ days: Int, hour: Int = 12) -> Date {
        let day = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now))!
        return calendar.date(byAdding: .hour, value: hour, to: day)!
    }

    // MARK: Trends

    /// Twelve weeks oldest first; this week 26,446 kg, up 8% on last week's 24,487 kg.
    static let weekVolumes: [Double] = [11_100, 12_700, 10_600, 14_800, 15_900, 13_700, 18_000, 16_900, 20_100, 21_200, 24_487, 26_446]

    static var trendWeeks: [CutTrendsFacts.Week] {
        weekVolumes.enumerated().map { index, volume in
            let current = index == weekVolumes.count - 1
            return CutTrendsFacts.Week(weekStart: monday(weeksAgo: weekVolumes.count - 1 - index), volumeKg: volume,
                                       sessions: current ? 3 : 4, sets: current ? 58 : 70, reps: current ? 412 : 500)
        }
    }

    static var trends: CutTrendsFacts {
        CutTrendsFacts(
            weeks: trendWeeks,
            personalAverageKg: 17_200,
            exerciseVolumes: [
                .init(exerciseID: "squat", volumeKg: 3_400), .init(exerciseID: "squat", volumeKg: 2_840),
                .init(exerciseID: "bench", volumeKg: 2_600), .init(exerciseID: "bench", volumeKg: 2_380),
                .init(exerciseID: "deadlift", volumeKg: 4_400),
                .init(exerciseID: "row", volumeKg: 3_100),
                .init(exerciseID: "ohp", volumeKg: 1_900),
                .init(exerciseID: "curl", volumeKg: 900)
            ],
            names: ["squat": "Back Squat", "bench": "Bench Press", "deadlift": "Deadlift", "row": "Barbell Row",
                    "ohp": "Overhead Press", "curl": "Biceps Curl"],
            unit: .kg
        )
    }

    // MARK: Balance

    static var balance: CutBalanceFacts {
        CutBalanceFacts(
            pushPull: .init(push: 4_700, pull: 5_300, horizontalPush: 3_300, verticalPush: 1_400,
                            horizontalPull: 2_400, verticalPull: 2_900, ratio: 5_300.0 / 4_700.0),
            patterns: .init(squat: 2_600, hinge: 1_150),
            muscles: [
                .init(name: "Chest", lastTrained: daysAgo(0, hour: 8)),
                .init(name: "Back", lastTrained: daysAgo(0, hour: 8)),
                .init(name: "Quadriceps", lastTrained: daysAgo(2)),
                .init(name: "Hamstrings", lastTrained: daysAgo(2)),
                .init(name: "Shoulders", lastTrained: daysAgo(5)),
                .init(name: "Calves", lastTrained: daysAgo(9))
            ],
            unit: .kg
        )
    }

    // MARK: Exercise

    static func set(_ weight: Double, _ reps: Int, tag: SetTag = .working, rest: Int? = 150,
                    mode: TrackingMode = .weighted, seconds: Int = 0) -> SetInput {
        SetInput(reps: reps, weight: weight, tag: tag, isCompleted: true, durationSeconds: seconds,
                 trackingMode: mode, restAfterSeconds: rest)
    }

    static func workout(daysAgo days: Int, exerciseID: String = "bench", name: String = "Bench Press",
                        sets: [SetInput]) -> CompletedWorkout {
        let entry = WorkoutEntry(exerciseID: exerciseID, exerciseName: name, muscleGroups: ["Chest"], sets: sets)
        return CompletedWorkout(date: daysAgo(days, hour: 18), startedAt: daysAgo(days, hour: 17), entries: [entry])
    }

    /// Ten bench sessions over three months, rising from 75 to 90 kg. The latest holds the
    /// heaviest set and the best estimated 1RM; an older lighter day holds the most reps.
    static var benchWorkouts: [CompletedWorkout] {
        [
            workout(daysAgo: 95, sets: [set(60, 10, tag: .warmup), set(75, 6), set(75, 6), set(75, 5)]),
            workout(daysAgo: 84, sets: [set(60, 10, tag: .warmup), set(77.5, 6), set(77.5, 5), set(77.5, 5)]),
            workout(daysAgo: 70, sets: [set(60, 12), set(60, 11), set(60, 10)]),
            workout(daysAgo: 56, sets: [set(60, 10, tag: .warmup), set(80, 6), set(80, 5), set(80, 5)]),
            workout(daysAgo: 42, sets: [set(60, 10, tag: .warmup), set(82.5, 5), set(82.5, 5), set(82.5, 5)]),
            workout(daysAgo: 28, sets: [set(60, 10, tag: .warmup), set(85, 5), set(85, 5), set(85, 4)]),
            workout(daysAgo: 18, sets: [set(60, 10, tag: .warmup), set(85, 6), set(85, 5), set(85, 5)]),
            workout(daysAgo: 11, sets: [set(60, 10, tag: .warmup), set(87.5, 5), set(87.5, 5), set(87.5, 4)]),
            workout(daysAgo: 7, sets: [set(60, 10, tag: .warmup), set(85, 6), set(87.5, 5), set(87.5, 5)]),
            workout(daysAgo: 2, sets: [set(60, 10, tag: .warmup), set(90, 5), set(90, 5), set(90, 4)])
        ]
    }

    static func statistics(_ workouts: [CompletedWorkout], id: String = "bench", name: String = "Bench Press",
                           mode: TrackingMode = .weighted) -> ExerciseStatistics {
        ExerciseStatsAggregator().computeStatistics(exerciseID: id, exerciseName: name, trackingMode: mode, from: workouts)
    }

    static var bench: ExerciseStatistics { statistics(benchWorkouts) }

    static var pullUps: ExerciseStatistics {
        statistics([
            workout(daysAgo: 20, exerciseID: "pullup", name: "Pull Up", sets: [set(0, 8, mode: .bodyweight), set(0, 7, mode: .bodyweight)]),
            workout(daysAgo: 9, exerciseID: "pullup", name: "Pull Up", sets: [set(0, 10, mode: .bodyweight), set(0, 9, mode: .bodyweight), set(0, 8, mode: .bodyweight)]),
            workout(daysAgo: 3, exerciseID: "pullup", name: "Pull Up", sets: [set(10, 6, mode: .bodyweight), set(0, 9, mode: .bodyweight)])
        ], id: "pullup", name: "Pull Up", mode: .bodyweight)
    }

    static var oneSession: ExerciseStatistics {
        statistics([workout(daysAgo: 4, sets: [set(60, 10, tag: .warmup), set(80, 5), set(80, 5)])])
    }

    static var neverLogged: ExerciseStatistics { statistics([]) }
}
