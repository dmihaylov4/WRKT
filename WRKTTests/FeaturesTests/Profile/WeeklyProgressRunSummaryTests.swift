import SwiftData
import XCTest
@testable import WRKT

/// The weekly goal's progress counts Health strength days from run summaries exactly as it
/// counted them from full runs: same result for synthetic weeks covering Health strength
/// sessions, sessions also logged in the app, week boundaries, the data cutoff and empty weeks,
/// and (opt-in) for real weeks of a real history.
@MainActor
final class WeeklyProgressRunSummaryTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var container: ModelContainer!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        suiteName = "WeeklyProgressRunSummaryTests." + UUID().uuidString
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: directory.appendingPathComponent(".migrated"))
        container = try ModelContainer(for: RewardProgress.self, WeeklyTrainingSummary.self, DailyAppleExerciseSummary.self,
                                       WeeklyGoal.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
        container = nil
    }

    // MARK: - The previous computation, kept as the reference (WeeklyProgressTypes.swift on 1eceab1)

    private static func legacyCountsAsStrengthDay(_ run: Run) -> Bool {
        guard run.healthKitUUID != nil else { return false }
        return HealthKitWorkoutCategory.categorize(run.workoutType).countsAsStrengthDay
    }

    private static func legacyProgress(runs: [Run], completedWorkouts: [CompletedWorkout], goal: WeeklyGoal,
                                       context: ModelContext, now: Date, calendar: Calendar) -> WeeklyProgress {
        let cutoffDate: Date
        if let progress = try? context.fetch(FetchDescriptor<RewardProgress>()).first {
            cutoffDate = progress.dataCutoffDate
        } else {
            cutoffDate = goal.createdAt
        }
        let start = calendar.startOfWeek(for: now, anchorWeekday: goal.anchorWeekday)
        let end = calendar.date(byAdding: .day, value: 7, to: start)!
        let weekSecs = end.timeIntervalSince(start)
        let secsElapsed = max(0, now.timeIntervalSince(start))
        let daysFrac = min(max(secsElapsed / weekSecs, 0), 1)
        let fdMinutes = FetchDescriptor<WeeklyTrainingSummary>(predicate: #Predicate { $0.weekStart >= start && $0.weekStart < end })
        let weeklyRows = (try? context.fetch(fdMinutes)) ?? []
        let validRows = weeklyRows.filter { row in
            let weekEndDate = calendar.date(byAdding: .day, value: 7, to: row.weekStart) ?? row.weekStart
            return weekEndDate > cutoffDate
        }
        let minutesFromSummaries = validRows.reduce(0) { $0 + $1.minutes }
        let appleExerciseMinutes = HealthAggregationStore.appleExerciseMinutes(from: max(start, cutoffDate), to: end,
                                                                                in: context, calendar: calendar)
        let mvpaDone = minutesFromSummaries + appleExerciseMinutes
        let inAppStrengthDays: Set<Date> = Set(
            completedWorkouts
                .filter { $0.date >= start && $0.date < end && $0.date >= cutoffDate }
                .compactMap { w in
                    let didStrength = w.entries.contains { e in e.sets.contains { $0.tag == .working && $0.reps > 0 } }
                    return didStrength ? calendar.startOfDay(for: w.date) : nil
                }
        )
        let healthKitStrengthDays: Set<Date> = Set(
            runs.filter { run in
                guard run.date >= start && run.date < end else { return false }
                guard run.healthKitUUID != nil else { return false }
                guard legacyCountsAsStrengthDay(run) else { return false }
                return run.date >= cutoffDate
            }
            .map { calendar.startOfDay(for: $0.date) }
        )
        let strengthDone = inAppStrengthDays.union(healthKitStrengthDays).count
        let mvpaTarget = max(0, goal.targetActiveMinutes)
        let strengthTarget = max(0, goal.targetStrengthDays)
        let expectedM = Int(round(Double(mvpaTarget) * daysFrac))
        let expectedS = min(strengthTarget, Int(floor(Double(strengthTarget) * daysFrac + 1e-6)))
        let minutesLeft = max(0, mvpaTarget - mvpaDone)
        let strengthLeft = max(0, strengthTarget - strengthDone)
        let mvpaPct = (mvpaTarget > 0) ? min(1, Double(mvpaDone) / Double(mvpaTarget)) : 1
        let aheadM = mvpaDone >= expectedM + 10
        let aheadS = strengthDone >= expectedS + 1
        let behindM = mvpaDone < max(0, expectedM - 10)
        let behindS = strengthDone < max(0, expectedS - 1)
        let status: PaceStatus = (aheadM || aheadS) ? .ahead : ((behindM || behindS) ? .behind : .onTrack)
        return WeeklyProgress(weekStart: start, weekEnd: end, mvpaTarget: mvpaTarget, strengthTarget: strengthTarget,
                              mvpaDone: mvpaDone, strengthDaysDone: strengthDone, mvpaPct: mvpaPct, daysElapsedFrac: daysFrac,
                              expectedMinutesByNow: expectedM, expectedStrengthByNow: expectedS, minutesLeft: minutesLeft,
                              strengthDaysLeft: strengthLeft, paceStatus: status)
    }

    // MARK: - Fixtures

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Vienna")!
        return calendar
    }()

    /// Monday 9 November 2026, 00:00 in Vienna: a week start for a Monday anchor.
    private static let monday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 9))!
    private static func at(day: Double) -> Date { monday.addingTimeInterval(day * 86_400) }

    private static func strength(_ type: String?, at date: Date, health: Bool = true, id: UUID = UUID()) -> Run {
        Run(id: id, date: date, distanceKm: 0, durationSec: 2_400, healthKitUUID: health ? UUID() : nil, avgHeartRate: 120,
            workoutType: type)
    }

    private static func logged(at date: Date, matching run: Run? = nil, working: Bool = true) -> CompletedWorkout {
        let set = SetInput(reps: working ? 5 : 0, weight: 100, tag: .working, autoWeight: false, isCompleted: true)
        var workout = CompletedWorkout(date: date, entries: [WorkoutEntry(exerciseID: "bench-press", exerciseName: "Bench",
                                                                          muscleGroups: ["Chest"], sets: [set])])
        workout.matchedHealthKitUUID = run?.healthKitUUID
        return workout
    }

    private func store(runs: [Run], workouts: [CompletedWorkout]) async throws -> WorkoutStoreV2 {
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: directory.appendingPathComponent(".migrated"))
        let previous = WorkoutStorage(directory: directory)
        try await previous.saveWorkouts(workouts, prIndex: [:])
        try await previous.saveRuns(runs)
        defaults.set(true, forKey: "runs.deduplication.v1")
        let store = WorkoutStoreV2(storage: WorkoutStorage(directory: directory), defaults: defaults)
        try await store.waitForStorage()
        return store
    }

    private func assertSame(_ store: WorkoutStoreV2, runs: [Run], goal: WeeklyGoal, nows: [Date],
                            file: StaticString = #filePath, line: UInt = #line) async throws -> [WeeklyProgress] {
        let decodedRuns = try await WorkoutStorage(directory: directory).loadRuns()
        XCTAssertEqual(decodedRuns.map(\.id), runs.map(\.id), file: file, line: line)
        var results: [WeeklyProgress] = []
        for now in nows {
            let new = store.currentWeekProgress(goal: goal, context: container.mainContext, now: now, calendar: Self.calendar)
            let old = Self.legacyProgress(runs: decodedRuns, completedWorkouts: store.completedWorkouts, goal: goal,
                                          context: container.mainContext, now: now, calendar: Self.calendar)
            XCTAssertEqual(new, old, "now \(now)", file: file, line: line)
            results.append(new)
        }
        return results
    }

    // MARK: - Synthetic weeks

    func testHealthStrengthDaysCountAsBefore() async throws {
        let matchedRun = Self.strength("Functional Strength Training", at: Self.at(day: 3.4))
        let runs = [
            Self.strength("Traditional Strength Training", at: Self.at(day: 0.3)),
            Self.strength("High Intensity Interval Training", at: Self.at(day: 1.5)),
            Self.strength("Traditional Strength Training", at: Self.at(day: 1.7)),        // same day twice
            matchedRun,                                                                    // also logged in the app
            Self.strength("Core Training", at: Self.at(day: 0)),                           // exactly at week start
            Self.strength("Traditional Strength Training", at: Self.at(day: 7)),           // exactly at next week start
            Self.strength("Traditional Strength Training", at: Self.at(day: -0.0001)),     // just before the week
            Self.strength("Traditional Strength Training", at: Self.at(day: 2.2), health: false), // not from Health
            Self.strength(nil, at: Self.at(day: 4.1)),                                     // no type
            Run(date: Self.at(day: 5.2), distanceKm: 6, durationSec: 1_900, healthKitUUID: UUID(), workoutType: "Running"),
            Self.strength("Yoga", at: Self.at(day: 6.1))
        ]
        let workouts = [Self.logged(at: Self.at(day: 3.45), matching: matchedRun), Self.logged(at: Self.at(day: 5.5)),
                        Self.logged(at: Self.at(day: 6.5), working: false)]
        let store = try await store(runs: runs, workouts: workouts)
        let goal = WeeklyGoal(isSet: true, targetActiveMinutes: 150, targetStrengthDays: 3, anchorWeekday: 2,
                              createdAt: Self.at(day: -30))
        let nows = stride(from: -0.5, through: 7.5, by: 0.25).map(Self.at(day:))
        let results = try await assertSame(store, runs: runs, goal: goal, nows: nows)
        // Monday, Tuesday, Thursday (Health and logged, once) and Saturday (logged).
        XCTAssertEqual(results[nows.firstIndex(of: Self.at(day: 6.75))!].strengthDaysDone, 4)
    }

    func testTheDataCutoffAndOtherAnchorsCountAsBefore() async throws {
        let runs = (0..<14).map { Self.strength("Traditional Strength Training", at: Self.at(day: Double($0) * 0.5 - 1)) }
        let store = try await store(runs: runs, workouts: [])
        for anchor in [1, 2, 4, 7] {
            for cutoffDay in [-10.0, 0.75, 2.5] {
                let goal = WeeklyGoal(isSet: true, targetActiveMinutes: 0, targetStrengthDays: 4, anchorWeekday: anchor,
                                      createdAt: Self.at(day: cutoffDay))
                _ = try await assertSame(store, runs: runs, goal: goal, nows: [Self.at(day: 1.1), Self.at(day: 5.9)])
            }
        }
    }

    func testAnEmptyHistoryCountsAsBefore() async throws {
        let store = try await store(runs: [], workouts: [])
        let goal = WeeklyGoal(isSet: true, targetActiveMinutes: 150, targetStrengthDays: 2, anchorWeekday: 2,
                              createdAt: Self.at(day: -5))
        let results = try await assertSame(store, runs: [], goal: goal, nows: [Self.at(day: 0.5), Self.at(day: 6.9)])
        XCTAssertEqual(results.map(\.strengthDaysDone), [0, 0])
    }

    // MARK: - Real weeks (opt-in)

    /// The last twelve weeks of a real history, from a temporary copy that is deleted afterwards.
    func testRealWeeksCountAsBefore() async throws {
        guard let runsPath = ProcessInfo.processInfo.environment["VOLIA_RUNS_FILE"], !runsPath.isEmpty,
              let workoutsPath = ProcessInfo.processInfo.environment["VOLIA_WORKOUTS_FILE"], !workoutsPath.isEmpty else {
            throw XCTSkip("Set VOLIA_RUNS_FILE and VOLIA_WORKOUTS_FILE to run against a real history")
        }
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.copyItem(at: URL(fileURLWithPath: runsPath), to: directory.appendingPathComponent("runs_v2.json"))
        try FileManager.default.copyItem(at: URL(fileURLWithPath: workoutsPath), to: directory.appendingPathComponent("workouts_v2.json"))
        try Data().write(to: directory.appendingPathComponent(".migrated"))
        defaults.set(true, forKey: "runs.deduplication.v1")
        let store = WorkoutStoreV2(storage: WorkoutStorage(directory: directory), defaults: defaults)
        try await store.waitForStorage()
        let runs = try await WorkoutStorage(directory: directory).loadRuns()
        let latest = try XCTUnwrap(runs.map(\.date).max())
        let goal = WeeklyGoal(isSet: true, targetActiveMinutes: 150, targetStrengthDays: 3, anchorWeekday: 2,
                              createdAt: .distantPast)
        let calendar = Calendar.current
        var nows: [Date] = []
        for week in 0..<12 {
            for day in [3.0, 6.9] {
                let back: TimeInterval = Double(week) * 7 * 86_400 + day * 86_400
                nows.append(latest.addingTimeInterval(-back))
            }
        }
        var strengthDays = 0
        for now in nows {
            let new = store.currentWeekProgress(goal: goal, context: container.mainContext, now: now, calendar: calendar)
            let old = Self.legacyProgress(runs: runs, completedWorkouts: store.completedWorkouts, goal: goal,
                                          context: container.mainContext, now: now, calendar: calendar)
            XCTAssertEqual(new, old)
            strengthDays += new.strengthDaysDone
        }
        print("Real weeks: \(nows.count) checks over 12 weeks, \(strengthDays) strength days counted in total")
    }
}
