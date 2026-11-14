//
//  WorkoutStoreAuditFixTests.swift
//  WRKTTests
//
//  Covers audited store bugs: PR auto-post detection, addWorkout ordering
//  and stats, and discard ordering against the save queue.
//

import XCTest
import SwiftData
@testable import WRKT

@MainActor
final class WorkoutStoreAuditFixTests: WRKTTestCase {
    private var directory: URL!
    private var suiteName: String!
    private var rewardsContainer: ModelContainer!

    override func setUp() async throws {
        // A thrown failure on the main actor can hang async tests; record and continue.
        continueAfterFailure = true
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        suiteName = "WorkoutStoreAuditFixTests." + UUID().uuidString
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    private func makeLoadedStore() async throws -> (WorkoutStoreV2, WorkoutStorage) {
        let storage = WorkoutStorage(directory: directory)
        try "migrated".write(to: directory.appendingPathComponent(".migrated"), atomically: true, encoding: .utf8)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        // Finishing unlocks dex entries a moment later: give it its own in-memory context.
        rewardsContainer = try ModelContainer(for: DexStamp.self, RewardProgress.self, Wallet.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let rewards = RewardsEngine()
        rewards.context = rewardsContainer.mainContext
        let store = WorkoutStoreV2(storage: storage, defaults: defaults, rewardsEngine: rewards)
        try await store.waitForStorage()
        return (store, storage)
    }

    private func entry(weight: Double, reps: Int = 5) -> WorkoutEntry {
        WorkoutEntry(
            exerciseID: TestFixtures.benchPress.id,
            exerciseName: TestFixtures.benchPress.name,
            muscleGroups: TestFixtures.benchPress.primaryMuscles,
            sets: [SetInput(reps: reps, weight: weight, tag: .working, isCompleted: true)]
        )
    }

    // MARK: A3

    func testFinishingWithAHeavierSetSendsThePRToAutoPost() async throws {
        let (store, _) = try await makeLoadedStore()
        store.addWorkout(CompletedWorkout(date: Date().addingTimeInterval(-86_400 * 3), entries: [entry(weight: 100)]))

        var posted: [PRAchievement] = []
        store.prAutoPostSink = { achievements, _ in posted = achievements }
        store.currentWorkout = CurrentWorkout(startedAt: Date().addingTimeInterval(-1800), entries: [entry(weight: 110)])

        let result = store.finishCurrentWorkoutAndReturnPRs()

        XCTAssertEqual(result.prCount, 1)
        XCTAssertEqual(posted.count, 1, "The PR must be found against the index as it was before this workout")
        XCTAssertEqual(posted.first?.previousBest, 100)
        XCTAssertEqual(posted.first?.newBest, 110)
        try await store.flushPendingSaves()
    }

    // MARK: A1 (mechanism)

    func testFinishedWorkoutIsLastCompletedNotFirstInHistory() async throws {
        let (store, _) = try await makeLoadedStore()
        let older = CompletedWorkout(date: Date().addingTimeInterval(-86_400 * 10), entries: [entry(weight: 60)])
        store.addWorkout(older)
        store.prAutoPostSink = { _, _ in }
        store.currentWorkout = CurrentWorkout(startedAt: Date().addingTimeInterval(-1800), entries: [entry(weight: 70)])

        let result = store.finishCurrentWorkoutAndReturnPRs()

        XCTAssertEqual(store.completedWorkouts.first?.id, older.id, "History is ascending, so first is the oldest")
        XCTAssertEqual(store.lastCompletedWorkout?.id.uuidString, result.workoutId)
        try await store.flushPendingSaves()
    }

    // MARK: A7

    func testAddWorkoutKeepsHistoryAscendingAndRefreshesItsWeek() async throws {
        let (store, _) = try await makeLoadedStore()
        let container = try StatsTestSupport.makeContainer()
        store.installStats(StatsAggregator(container: container))

        let newer = CompletedWorkout(date: Date(), entries: [entry(weight: 80)])
        let older = CompletedWorkout(date: Date().addingTimeInterval(-86_400 * 21), entries: [entry(weight: 70)])
        store.addWorkout(older)
        store.addWorkout(newer)

        XCTAssertEqual(store.completedWorkouts.map(\.id), [older.id, newer.id])

        let olderWeekKey = ExerciseVolumeSummary.weekKey(from: StatsTestSupport.startOfWeek(older.date))
        let found = await StatsTestSupport.waitForWeekly(key: olderWeekKey, in: container) { $0.sessions == 1 }
        XCTAssertTrue(found, "Adding a past workout must refresh that week's stats")
        try await store.flushPendingSaves()
    }

    // MARK: A8

    func testDiscardIsNotOverwrittenByAQueuedCurrentWorkoutSave() async throws {
        let (store, storage) = try await makeLoadedStore()
        store.startWorkoutIfNeeded()
        for _ in 0..<25 {
            _ = store.addExerciseToCurrent(TestFixtures.benchPress)
        }
        store.discardCurrentWorkout()
        try await store.flushPendingSaves()
        // Let any detached delete land as well.
        try await Task.sleep(for: .milliseconds(300))

        let durable = try await storage.loadCurrentWorkout()
        XCTAssertNil(durable, "A discarded workout must not come back from a queued save")
    }
}

/// Shared helpers for stats checks in store and aggregator tests.
enum StatsTestSupport {
    static func makeContainer() throws -> ModelContainer {
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
        return try ModelContainer(for: schema, configurations: config)
    }

    static func startOfWeek(_ date: Date) -> Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date))!
    }

    static func weekly(key: String, in container: ModelContainer) -> WeeklyTrainingSummary? {
        let context = ModelContext(container)
        let request = FetchDescriptor<WeeklyTrainingSummary>(predicate: #Predicate { $0.key == key })
        return try? context.fetch(request).first
    }

    static func waitForWeekly(key: String, in container: ModelContainer,
                              timeout: TimeInterval = 3,
                              where condition: (WeeklyTrainingSummary) -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let row = weekly(key: key, in: container), condition(row) { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }
}

// A1: new-exercise detection compares the finished workout against the rest of history.
final class LiveWorkoutNewExerciseTests: XCTestCase {
    func testOnlyExercisesMissingFromOtherWorkoutsAreNew() {
        func workout(_ ids: [String], daysAgo: Double) -> CompletedWorkout {
            CompletedWorkout(date: Date().addingTimeInterval(-86_400 * daysAgo),
                entries: ids.map { WorkoutEntry(exerciseID: $0, exerciseName: $0, muscleGroups: [], sets: []) })
        }
        let oldest = workout(["squat"], daysAgo: 30)
        let middle = workout(["bench"], daysAgo: 10)
        let finished = workout(["bench", "row"], daysAgo: 0)
        let history = [oldest, middle, finished]

        XCTAssertEqual(LiveWorkoutOverlayCard.newExerciseIDs(in: finished, history: history), ["row"])
        XCTAssertEqual(LiveWorkoutOverlayCard.newExerciseIDs(in: nil, history: history), [])
    }
}
