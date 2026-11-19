import XCTest
@testable import WRKT

/// The composer lists workouts from the loaded store and never decodes history itself. If the
/// history fails to load, or never loads, the composer ends in its error state instead of
/// waiting forever.
@MainActor
final class ComposerHistoryWaitTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    private var runsFile: URL { directory.appendingPathComponent("runs_v2.json") }

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        suiteName = "ComposerHistoryWaitTests." + UUID().uuidString
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: directory.appendingPathComponent(".migrated"))
        try await WorkoutStorage(directory: directory).saveWorkouts([], prIndex: [:])
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func composer(_ store: WorkoutStoreV2) -> PostCreationViewModel {
        PostCreationViewModel(postRepository: PostRepository(), imageUploadService: ImageUploadService(),
                              authService: SupabaseAuthService.shared, friendshipRepository: FriendshipRepository(),
                              workoutStore: store)
    }

    func testLoadedHistoryFillsThePickerFromSummaries() async throws {
        let run = Run(date: Date(timeIntervalSince1970: 1_794_398_400), distanceKm: 5, durationSec: 1_800,
                      healthKitUUID: UUID(), avgHeartRate: 150,
                      hrSamples: [HeartRateSample(timestamp: Date(timeIntervalSince1970: 1_794_397_000), bpm: 140)],
                      workoutType: "Running")
        try await WorkoutStorage(directory: directory).saveRuns([run])
        let store = WorkoutStoreV2(storage: WorkoutStorage(directory: directory), defaults: defaults)
        let vm = composer(store)
        await vm.loadRecentWorkouts()
        XCTAssertFalse(vm.isLoadingWorkouts)
        XCTAssertNil(vm.error)
        XCTAssertEqual(vm.recentWorkouts.map(\.id), [run.id])
        XCTAssertNil(vm.recentWorkouts.first?.matchedHealthKitHeartRateSamples, "the list shows the run without samples")
    }

    func testFailedHistoryEndsInTheErrorState() async throws {
        try Data("not json".utf8).write(to: runsFile)
        let store = WorkoutStoreV2(storage: WorkoutStorage(directory: directory), defaults: defaults)
        let vm = composer(store)
        await vm.loadRecentWorkouts()
        XCTAssertFalse(vm.isLoadingWorkouts)
        XCTAssertEqual(vm.error?.title, "Workouts Load Failed")
        XCTAssertTrue(vm.recentWorkouts.isEmpty)
        guard case .failed(let error) = await PostCreationViewModel.waitForHistory(store, limit: .seconds(5)) else {
            return XCTFail("a failed history must not count as loaded")
        }
        XCTAssertFalse(error is PostCreationViewModel.HistoryWaitTimedOut, "a failed load answers at once")
    }

    /// A history whose load never ends: the wait gives up at its limit.
    func testHistoryThatNeverLoadsTimesOut() async throws {
        let started = ContinuousClock.now
        let result = await PostCreationViewModel.waitForHistory(limit: .milliseconds(300)) {
            try await Task.sleep(for: .seconds(3_600))
        }
        guard case .failed(let error) = result else { return XCTFail("a history that never loads must not count as loaded") }
        XCTAssertTrue(error is PostCreationViewModel.HistoryWaitTimedOut)
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(5))
    }

    func testAHistoryLoadingInTimeCountsAsLoaded() async throws {
        let result = await PostCreationViewModel.waitForHistory(limit: .seconds(5)) {
            try await Task.sleep(for: .milliseconds(50))
        }
        guard case .loaded = result else { return XCTFail("expected loaded") }
    }
}
