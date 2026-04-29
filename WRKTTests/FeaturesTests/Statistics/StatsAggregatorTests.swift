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
}
