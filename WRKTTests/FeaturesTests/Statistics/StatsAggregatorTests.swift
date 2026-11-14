import XCTest
import SwiftData
@testable import WRKT

final class StatsAggregatorTests: WRKTTestCase {

    func testInvalidatePreservesWeeklyHealthDataForReplacedWeeks() async throws {
        let schema = Schema([
            WeeklyTrainingSummary.self,
            ExerciseVolumeSummary.self,
            PRStamp.self,
            MovingAverage.self,
            ExerciseProgressionSummary.self,
            ExerciseTrend.self,
            PushPullBalance.self,
            MuscleGroupFrequency.self,
            MovementPatternBalance.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        let context = ModelContext(container)

        let workoutDate = makeDate(year: 2026, month: 4, day: 18)
        let weekStart = Calendar.current.date(from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: workoutDate))!
        let key = ExerciseVolumeSummary.weekKey(from: weekStart)
        let lastHealthSync = makeDate(year: 2026, month: 4, day: 18, hour: 14, minute: 30)

        let existingSummary = WeeklyTrainingSummary(
            key: key,
            weekStart: weekStart,
            totalVolume: 1200,
            sessions: 2,
            totalSets: 10,
            totalReps: 60,
            minutes: 45,
            appleExerciseMinutes: 87,
            cardioSessions: 3,
            lastHealthSync: lastHealthSync
        )
        context.insert(existingSummary)
        try context.save()

        let workout = CompletedWorkout(date: workoutDate, entries: [])
        let aggregator = StatsAggregator(container: container)

        await aggregator.invalidate(weeks: [weekStart], from: [workout])

        let request = FetchDescriptor<WeeklyTrainingSummary>(
            predicate: #Predicate { $0.key == key }
        )
        let refreshed = try XCTUnwrap(context.fetch(request).first)

        XCTAssertEqual(refreshed.appleExerciseMinutes, 87)
        XCTAssertEqual(refreshed.cardioSessions, 3)
        XCTAssertEqual(refreshed.lastHealthSync, lastHealthSync)
        XCTAssertEqual(refreshed.sessions, 1)
    }

    // A2: applying a second workout must add to the week, not replace it.
    func testApplyKeepsEarlierWorkoutsOfTheSameWeek() async throws {
        let container = try StatsTestSupport.makeContainer()
        let aggregator = StatsAggregator(container: container)
        let monday = makeDate(year: 2026, month: 4, day: 13, hour: 9)
        let first = CompletedWorkout(date: monday, entries: [benchEntry(reps: 5, weight: 100)])
        let second = CompletedWorkout(date: monday.addingTimeInterval(86_400 * 2), entries: [benchEntry(reps: 5, weight: 100)])

        await aggregator.apply(first, allWorkouts: [first])
        await aggregator.apply(second, allWorkouts: [first, second])

        let key = ExerciseVolumeSummary.weekKey(from: StatsTestSupport.startOfWeek(monday))
        let weekly = try XCTUnwrap(StatsTestSupport.weekly(key: key, in: container))
        XCTAssertEqual(weekly.sessions, 2)
        XCTAssertEqual(weekly.totalSets, 2)
        XCTAssertEqual(weekly.totalVolume, 1000, accuracy: 0.001)
    }

    // A5: deleting the only workout of a week must clear that week.
    func testInvalidatingAWeekWithNoWorkoutsLeftClearsItsTotals() async throws {
        let container = try StatsTestSupport.makeContainer()
        let aggregator = StatsAggregator(container: container)
        let date = makeDate(year: 2026, month: 4, day: 15, hour: 9)
        let only = CompletedWorkout(date: date, entries: [benchEntry(reps: 5, weight: 100)])
        let weekStart = StatsTestSupport.startOfWeek(date)
        let key = ExerciseVolumeSummary.weekKey(from: weekStart)

        await aggregator.invalidate(weeks: [weekStart], from: [only])
        XCTAssertEqual(StatsTestSupport.weekly(key: key, in: container)?.sessions, 1)

        await aggregator.invalidate(weeks: [weekStart], from: [])

        let remaining = StatsTestSupport.weekly(key: key, in: container)
        XCTAssertNil(remaining, "No strength rows may remain for a week without workouts")
        let volumes = try ModelContext(container).fetch(FetchDescriptor<ExerciseVolumeSummary>())
        XCTAssertTrue(volumes.filter { $0.weekStart == weekStart }.isEmpty)
    }

    private func benchEntry(reps: Int, weight: Double) -> WorkoutEntry {
        WorkoutEntry(
            exerciseID: TestFixtures.benchPress.id,
            exerciseName: TestFixtures.benchPress.name,
            muscleGroups: TestFixtures.benchPress.primaryMuscles,
            sets: [SetInput(reps: reps, weight: weight, tag: .working, isCompleted: true)]
        )
    }
}
