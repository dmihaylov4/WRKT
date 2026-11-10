import XCTest
import SwiftData
@testable import WRKT

@MainActor
final class ExerciseTimeReconciliationTests: XCTestCase {
    func testHistoricalDeletionClearsLastDayAndWeekWithoutChangingTrainingStats() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let day = date(2026, 1, 5)
        let daily = DailyAppleExerciseSummary(dayStart: day, minutes: 60)
        let weekly = week(day, exerciseMinutes: 60)
        context.insert(daily)
        context.insert(weekly)
        try context.save()
        let manager = HealthKitManager.shared
        let start = try manager.exerciseTimeReconciliationStart(sampleDates: [], hasDeletions: true,
            context: context, now: date(2026, 9, 30))
        XCTAssertEqual(start, day)
        try await manager.reconcileExerciseTimeSummaries(from: start, to: date(2026, 9, 30), context: context) {
            from, _ in
            XCTAssertEqual(from, day)
            return []
        }
        XCTAssertEqual(daily.minutes, 0)
        XCTAssertEqual(weekly.appleExerciseMinutes, 0)
        XCTAssertEqual(weekly.totalVolume, 100)
        XCTAssertEqual(weekly.minutes, 30)
        XCTAssertEqual(weekly.sessions, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<DailyAppleExerciseSummary>()).first?.minutes, 0)
    }

    func testMidweekChangeIncludesEarlierDaysAndReplaysWithoutDoubleCounting() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let monday = date(2026, 1, 5)
        let wednesday = date(2026, 1, 7)
        let weekly = week(monday, exerciseMinutes: 20)
        context.insert(weekly)
        try context.save()
        let manager = HealthKitManager.shared
        let start = try manager.exerciseTimeReconciliationStart(sampleDates: [wednesday], hasDeletions: false,
            context: context, now: date(2026, 1, 9))
        XCTAssertEqual(start, monday)
        for _ in 0..<2 {
            try await manager.reconcileExerciseTimeSummaries(from: start, to: date(2026, 1, 9), context: context) {
                from, _ in
                XCTAssertEqual(from, monday)
                // These are HealthKit statistics, already aggregated across overlapping samples.
                return [(monday, 20), (wednesday, 35)]
            }
            XCTAssertEqual(weekly.appleExerciseMinutes, 55)
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<DailyAppleExerciseSummary>()).count, 2)
    }

    func testDeletionReconcilesLegacyWeeklyCacheWithoutDailyRows() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let historicalWeek = date(2025, 12, 29)
        let weekly = week(historicalWeek, exerciseMinutes: 120)
        context.insert(weekly)
        try context.save()
        let manager = HealthKitManager.shared
        let start = try manager.exerciseTimeReconciliationStart(sampleDates: [date(2026, 9, 28)],
            hasDeletions: true, context: context, now: date(2026, 9, 30))
        XCTAssertEqual(start, historicalWeek)
        try await manager.reconcileExerciseTimeSummaries(from: start, to: date(2026, 9, 30), context: context) {
            _, _ in []
        }
        XCTAssertEqual(weekly.appleExerciseMinutes, 0)
    }

    func testStatisticsFailurePreservesPreviouslySavedTotals() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let monday = date(2026, 3, 23)
        let weekly = week(monday, exerciseMinutes: 75)
        let daily = DailyAppleExerciseSummary(dayStart: monday, minutes: 75)
        context.insert(weekly)
        context.insert(daily)
        try context.save()
        do {
            try await HealthKitManager.shared.reconcileExerciseTimeSummaries(
                from: monday, to: date(2026, 3, 30), context: context
            ) { _, _ in throw CocoaError(.fileReadNoPermission) }
            XCTFail("A failed statistics query must reject reconciliation")
        } catch { }
        XCTAssertEqual(weekly.appleExerciseMinutes, 75)
        XCTAssertEqual(daily.minutes, 75)
        XCTAssertFalse(context.hasChanges)
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: DailyAppleExerciseSummary.self, WeeklyTrainingSummary.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func week(_ start: Date, exerciseMinutes: Int) -> WeeklyTrainingSummary {
        WeeklyTrainingSummary(key: ExerciseVolumeSummary.weekKey(from: start), weekStart: start,
            totalVolume: 100, sessions: 1, totalSets: 2, totalReps: 10, minutes: 30,
            appleExerciseMinutes: exerciseMinutes)
    }
}
