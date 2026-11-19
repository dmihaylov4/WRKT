import XCTest
@testable import WRKT

/// Opt-in: compares every summary fact with today's helpers on a real history file.
///
/// Runs only when `VOLIA_RUNS_FILE` names a runs_v2.json (pass it to xcodebuild as
/// `TEST_RUNNER_VOLIA_RUNS_FILE=/path/to/runs_v2.json`). The file is read, never written or
/// copied, and the test reports counts only.
@MainActor
final class RunSummaryRealHistoryTests: XCTestCase {
    func testEverySummaryFactMatchesTodaysHelpersOnARealHistory() throws {
        guard let path = ProcessInfo.processInfo.environment["VOLIA_RUNS_FILE"], !path.isEmpty else {
            throw XCTSkip("Set VOLIA_RUNS_FILE to run against a real history file")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
        let runs = try decoder.decode([StoredRun].self, from: data).map(\.run)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var mismatched: [String: Int] = [:]
        var codingMismatches = 0
        for run in runs {
            let summary = RunSummary(run)
            for name in LegacyRunHelpers.differences(summary, from: run) { mismatched[name, default: 0] += 1 }
            if try decoder.decode(RunSummary.self, from: encoder.encode(summary)) != summary { codingMismatches += 1 }
        }

        let summaries = runs.map(RunSummary.init)
        print("""
        Real history: \(runs.count) runs; fact mismatches \(mismatched.values.reduce(0, +)) \(mismatched); \
        coding mismatches \(codingMismatches); empty splits \(runs.filter { $0.splits?.isEmpty == true }.count); \
        empty routeWithHR \(runs.filter { $0.routeWithHR?.isEmpty == true }.count); \
        route max HR fallback \(summaries.filter { $0.maxHeartRate == nil && $0.routeMaxHeartRate != nil }.count); \
        needs enrichment \(summaries.filter { $0.needsHistoricalEnrichment }.count); \
        valid cardio \(summaries.filter { $0.isValidCardio }.count)
        """)
        XCTAssertFalse(runs.isEmpty)
        XCTAssertTrue(mismatched.isEmpty, "\(mismatched)")
        XCTAssertEqual(codingMismatches, 0)
    }

    /// The composer's explicit order (newest first, ties in input order, logged workouts before
    /// runs) equals what today's sort gives, over the whole real history, not only ten entries.
    func testPickerOrderEqualsTodaysSortOnARealHistory() throws {
        guard let path = ProcessInfo.processInfo.environment["VOLIA_RUNS_FILE"], !path.isEmpty else {
            throw XCTSkip("Set VOLIA_RUNS_FILE to run against a real history file")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let runs = try decoder.decode([StoredRun].self, from: Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)).map(\.run)
        var workouts: [CompletedWorkout] = []
        if let workoutsPath = ProcessInfo.processInfo.environment["VOLIA_WORKOUTS_FILE"], !workoutsPath.isEmpty {
            workouts = try decoder.decode(WorkoutStorageContainer.self, from: Data(contentsOf: URL(fileURLWithPath: workoutsPath))).workouts
        }
        let matched = Set(workouts.compactMap(\.matchedHealthKitUUID))
        let reference = (workouts + runs.filter { $0.healthKitUUID.map { !matched.contains($0) } ?? true }
            .map { $0.toCompletedWorkout() })
            .sorted(by: { $0.date > $1.date })
        let explicit = PostCreationViewModel.pickerCandidates(workouts: workouts, runs: runs.map(\.summary), limit: .max)
        let tiedDates = Dictionary(grouping: reference.map(\.date), by: { $0 }).values.filter { $0.count > 1 }.count
        print("Real history order: \(runs.count) runs, \(workouts.count) workouts, \(reference.count) entries, \(tiedDates) tied dates")
        XCTAssertEqual(explicit.map(\.completedWorkout.id), reference.map(\.id))
        XCTAssertFalse(runs.isEmpty)
    }
}
