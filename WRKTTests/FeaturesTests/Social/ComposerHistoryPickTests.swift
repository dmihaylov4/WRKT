import XCTest
@testable import WRKT

/// The post composer and the year award pick their workouts before converting runs, from the
/// history the store already holds. The result must be exactly what converting every run gave.
@MainActor
final class ComposerHistoryPickTests: XCTestCase {

    // MARK: - The previous implementations, kept as the reference

    private static func referencePicker(workouts: [CompletedWorkout], runs: [Run]) -> [CompletedWorkout] {
        let matched = Set(workouts.compactMap { $0.matchedHealthKitUUID })
        let cardio = runs
            .filter { run in
                guard let hkUUID = run.healthKitUUID else { return true }
                return !matched.contains(hkUUID)
            }
            .map { $0.toCompletedWorkout() }
        return (workouts + cardio).sorted(by: { $0.date > $1.date }).prefix(10).map { $0 }
    }

    private static func referenceSocialWorkout(year: Int, workouts: [CompletedWorkout], runs: [Run],
                                               calendar: Calendar) -> CompletedWorkout? {
        guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else { return nil }
        let range = start..<end
        let matched = Set(workouts.compactMap(\.matchedHealthKitUUID))
        let logged = workouts.filter { range.contains($0.date) }
        let outings = runs
            .filter { range.contains($0.date) && !($0.healthKitUUID.map(matched.contains) ?? false) }
            .map { $0.toCompletedWorkout() }
        return (logged + outings).max { $0.date < $1.date }
    }

    // MARK: - Fixtures

    /// A deterministic mixed history with equal dates across and within both kinds, runs
    /// matched to logged workouts, runs without a HealthKit UUID and runs with routes.
    private static func history(seed: UInt64, count: Int) -> (workouts: [CompletedWorkout], runs: [Run]) {
        var generator = SeededGenerator(seed: seed)
        let base = Date(timeIntervalSinceReferenceDate: 790_000_000)
        // Few distinct dates, so ties are common.
        func date() -> Date { base.addingTimeInterval(Double(Int.random(in: 0..<(count / 2 + 1), using: &generator)) * 3600) }
        var runs: [Run] = []
        for index in 0..<count {
            let points = (0..<Int.random(in: 0..<4, using: &generator)).map {
                RoutePoint(lat: 48 + Double($0) * 0.001, lon: 16, t: base, hr: index.isMultiple(of: 2) ? 140 : nil)
            }
            runs.append(Run(date: date(), distanceKm: Double(index), durationSec: 600 + index,
                            healthKitUUID: index.isMultiple(of: 5) ? nil : UUID(),
                            avgHeartRate: index.isMultiple(of: 3) ? 150 : nil,
                            routeWithHR: points.isEmpty ? nil : points, workoutType: "Running"))
        }
        var workouts: [CompletedWorkout] = []
        for index in 0..<count {
            var workout = CompletedWorkout(date: date(), entries: [], workoutName: "Logged \(index)")
            if index.isMultiple(of: 3), let uuid = runs[index].healthKitUUID { workout.matchedHealthKitUUID = uuid }
            workouts.append(workout)
        }
        return (workouts, runs)
    }

    // MARK: - Composer

    func testPickerMatchesConvertingEveryRunAcrossManyHistories() {
        for seed in 1...200 as ClosedRange<UInt64> {
            for count in [0, 1, 3, 12, 40] {
                let (workouts, runs) = Self.history(seed: seed, count: count)
                XCTAssertEqual(PostCreationViewModel.pickerWorkouts(workouts: workouts, runs: runs),
                               Self.referencePicker(workouts: workouts, runs: runs), "seed \(seed), count \(count)")
            }
        }
    }

    func testPickerFromTheLoadedStoreEqualsThePickerFromTheFiles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "ComposerHistoryPickTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        // Distinct dates: the store keeps its own order, so only exact ties could order differently.
        var (workouts, runs) = Self.history(seed: 7, count: 30)
        let base = Date(timeIntervalSinceReferenceDate: 790_000_000)
        for index in workouts.indices { workouts[index].date = base.addingTimeInterval(Double(index) * 7_201) }
        for index in runs.indices { runs[index].date = base.addingTimeInterval(Double(index) * 7_203 + 1) }
        let writer = WorkoutStorage(directory: directory)
        try await writer.saveWorkouts(workouts.shuffled(), prIndex: [:])
        try await writer.saveRuns(runs.shuffled())
        try Data("migrated".utf8).write(to: directory.appendingPathComponent(".migrated"))

        let store = WorkoutStoreV2(storage: WorkoutStorage(directory: directory), defaults: defaults)
        try await store.waitForStorage()
        let fromDisk = WorkoutStorage(directory: directory)
        let diskWorkouts = try await fromDisk.loadWorkouts().workouts
        let diskRuns = try await fromDisk.loadRuns()

        XCTAssertEqual(PostCreationViewModel.pickerWorkouts(workouts: store.completedWorkouts, runs: store.runs),
                       Self.referencePicker(workouts: diskWorkouts, runs: diskRuns))
    }

    // MARK: - Year award

    func testYearAwardWorkoutMatchesConvertingEveryRun() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let year = calendar.component(.year, from: Date(timeIntervalSinceReferenceDate: 790_000_000))
        for seed in 1...200 as ClosedRange<UInt64> {
            for count in [0, 1, 3, 12, 40] {
                let (workouts, runs) = Self.history(seed: seed, count: count)
                for candidateYear in [year, year + 1] {
                    XCTAssertEqual(
                        CutYearAwardLogic.socialWorkout(year: candidateYear, workouts: workouts, runs: runs, calendar: calendar),
                        Self.referenceSocialWorkout(year: candidateYear, workouts: workouts, runs: runs, calendar: calendar),
                        "seed \(seed), count \(count), year \(candidateYear)")
                }
            }
        }
    }
}

/// SplitMix64, so every history is the same on every run.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
