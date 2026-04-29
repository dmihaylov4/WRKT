import XCTest
import SwiftData
@testable import WRKT

final class HealthAggregationStoreTests: WRKTTestCase {

    func testAppleExerciseMinutesSumsOnlyDaysInsideRequestedWindow() throws {
        let schema = Schema([DailyAppleExerciseSummary.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        let context = ModelContext(container)

        context.insert(DailyAppleExerciseSummary(dayStart: makeDate(year: 2026, month: 4, day: 5), minutes: 40))
        context.insert(DailyAppleExerciseSummary(dayStart: makeDate(year: 2026, month: 4, day: 6), minutes: 55))
        context.insert(DailyAppleExerciseSummary(dayStart: makeDate(year: 2026, month: 4, day: 7), minutes: 61))
        context.insert(DailyAppleExerciseSummary(dayStart: makeDate(year: 2026, month: 4, day: 8), minutes: 77))
        try context.save()

        let start = makeDate(year: 2026, month: 4, day: 6, hour: 0, minute: 0)
        let end = makeDate(year: 2026, month: 4, day: 8, hour: 0, minute: 0)

        let total = HealthAggregationStore.appleExerciseMinutes(from: start, to: end, in: context)

        XCTAssertEqual(total, 116)
    }

    func testAppleExerciseMinutesDoesNotDoubleCountAcrossIsoWeekBoundary() throws {
        let schema = Schema([DailyAppleExerciseSummary.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        let context = ModelContext(container)

        // User week: Wednesday Apr 8 -> Wednesday Apr 15.
        // This spans two ISO weeks; only days inside this exact window should count.
        context.insert(DailyAppleExerciseSummary(dayStart: makeDate(year: 2026, month: 4, day: 6), minutes: 45))
        context.insert(DailyAppleExerciseSummary(dayStart: makeDate(year: 2026, month: 4, day: 8), minutes: 30))
        context.insert(DailyAppleExerciseSummary(dayStart: makeDate(year: 2026, month: 4, day: 12), minutes: 25))
        context.insert(DailyAppleExerciseSummary(dayStart: makeDate(year: 2026, month: 4, day: 15), minutes: 90))
        try context.save()

        let start = makeDate(year: 2026, month: 4, day: 8, hour: 0, minute: 0)
        let end = makeDate(year: 2026, month: 4, day: 15, hour: 0, minute: 0)

        let total = HealthAggregationStore.appleExerciseMinutes(from: start, to: end, in: context)

        XCTAssertEqual(total, 55)
    }
}
