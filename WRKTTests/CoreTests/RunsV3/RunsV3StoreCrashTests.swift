import SwiftData
import HealthKit
import XCTest
@testable import WRKT

/// Crashes between the store's own steps, not only inside the module: the whole store (load,
/// a handle, queued changes on several workouts, the Health anchor's flush) runs on the
/// file system model, killed or cut at every file system call; a fresh store then loads the
/// survivor. Per workout the result must be its state after the last batch whose anchor
/// committed, or after the batch in progress; a committed anchor never loses its batch; a
/// re-delivered import is never duplicated.
@MainActor
final class RunsV3StoreCrashTests: XCTestCase {
    private var suites: [String] = []

    override func tearDown() async throws {
        for suite in suites { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    }

    private func freshDefaults() -> UserDefaults {
        let suite = "RunsV3StoreCrashTests." + UUID().uuidString
        suites.append(suite)
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: "runs.deduplication.v1")
        return defaults
    }

    private static let seed = [V3.run(1, points: 3), V3.run(2), V3.run(3, points: 2)]
    private static let imported = V3.run(7, points: 4, name: "imported")

    private static func describe(_ run: Run) -> String {
        "\(run.distanceKm)|\(run.workoutName ?? "-")|\(run.routeWithHR?.count ?? -1)"
    }

    /// The expected state of each workout after 0, 1 and 2 committed batches.
    private static var models: [[UUID: String]] {
        var state = Dictionary(uniqueKeysWithValues: seed.map { ($0.id, describe($0)) })
        var result = [state]
        var one = seed[0]; one.workoutName = "a"
        state[imported.id] = describe(imported)
        state[one.id] = describe(one)
        state[V3.id(2)] = nil
        result.append(state)
        one.workoutName = "b"
        var seven = imported; seven.workoutName = "n2"
        state[one.id] = describe(one)
        state[seven.id] = describe(seven)
        state[V3.id(3)] = nil
        result.append(state)
        return result
    }

    private static let order = [V3.id(7), V3.id(1), V3.id(2), V3.id(3)]

    private func makeStore(_ fs: ModelFileSystem) -> WorkoutStoreV2 {
        let storage = WorkoutStorage(directory: V3.storage, fileSystem: fs, runsV3Environment: V3.environment(fs))
        return WorkoutStoreV2(storage: storage, defaults: freshDefaults(), protectedDataAvailable: { true })
    }

    /// The scenario; returns how many anchor commits succeeded, and whether the open handle
    /// followed its workout's edit.
    private func runScenario(on fs: ModelFileSystem) async -> (acknowledged: Int, handleFollowed: Bool) {
        let store = makeStore(fs)
        guard (try? await store.waitForStorage()) != nil else { return (0, true) }
        let container = try! ModelContainer(for: HealthSyncAnchor.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let anchor = HealthSyncAnchor(dataType: "all_workouts")
        container.mainContext.insert(anchor)
        var acknowledged = 0
        func commit() async {
            do {
                try await anchor.commit(HKQueryAnchor(fromValue: acknowledged + 2), in: container.mainContext) {
                    try await store.flushHealthKitChanges()
                }
                acknowledged += 1
            } catch { }
        }

        // Batch 1: a screen shows workout 1 (loaded), Health imports 7, edits 1, deletes 2.
        _ = try? await store.loadRun(id: V3.id(1))
        let detail = store.runDetail(id: V3.id(1))
        store.addRun(Self.imported)
        store.editRun(RunEdit(id: V3.id(1), light: { $0.workoutName = "a" }))
        let handleFollowed = detail.run == nil || detail.run?.workoutName == "a"
        store.removeRun(withId: V3.id(2))
        await commit()
        guard acknowledged == 1 else { return (acknowledged, handleFollowed) }
        // Batch 2: a resync batch on two workouts, and a delete.
        store.editRuns([RunEdit(id: V3.id(1), light: { $0.workoutName = "b" }),
                        RunEdit(id: Self.imported.id, light: { $0.workoutName = "n2" })])
        store.removeRun(withId: V3.id(3))
        await commit()
        _ = detail
        return (acknowledged, handleFollowed)
    }

    private func observe(_ fs: ModelFileSystem, label: String) async -> (state: [UUID: String], ids: [UUID], store: WorkoutStoreV2)? {
        let store = makeStore(fs)
        do {
            try await store.waitForStorage()
        } catch {
            XCTFail("\(label): the survivor did not load: \(error)")
            return nil
        }
        var state: [UUID: String] = [:]
        for summary in store.runSummaries {
            if case .loaded(let run)? = try? await store.loadRun(id: summary.id) {
                state[summary.id] = Self.describe(run)
            } else {
                state[summary.id] = "unreadable"
            }
        }
        return (state, store.runSummaries.map(\.id), store)
    }

    private func check(_ observed: [UUID: String], ids: [UUID], acknowledged: Int, label: String) {
        let models = Self.models
        let before = models[acknowledged]
        let after = acknowledged + 1 < models.count ? models[acknowledged + 1] : before
        for id in Set(before.keys).union(after.keys).union(observed.keys) {
            let seen = observed[id]
            if seen != before[id] && seen != after[id] {
                XCTFail("\(label): \(id.uuidString.suffix(4)) is \(seen ?? "absent"), expected \(before[id] ?? "absent") or \(after[id] ?? "absent")")
            }
        }
        XCTAssertEqual(ids, Self.order.filter { ids.contains($0) }, "\(label): history order")
        XCTAssertEqual(Set(ids).count, ids.count, "\(label): duplicate ids")
    }

    func testEveryCrashPointOfTheStore() async throws {
        let reference = ModelFileSystem()
        V3.seed(reference, Self.seed)
        let start = reference.callCount
        let outcome = await runScenario(on: reference)
        XCTAssertEqual(outcome.acknowledged, 2, "reference run")
        XCTAssertTrue(outcome.handleFollowed)
        guard let final = await observe(reference.afterKill(), label: "reference") else { return }
        XCTAssertEqual(final.state, Self.models[2])
        let total = reference.callCount - start

        var cases = 0
        for cut in 0...total {
            let strategies: [(String, (ModelFileSystem) -> ModelFileSystem)] = [
                ("kill", { $0.afterKill() }),
                ("power durableOnly", { $0.afterPowerLoss(.durableOnly) }),
                ("power random", { $0.afterPowerLoss(.random(UInt64(cut) &* 31 &+ 7)) }),
            ]
            for (name, after) in strategies {
                let fs = ModelFileSystem()
                V3.seed(fs, Self.seed)
                fs.killAfterCalls = fs.callCount + cut
                let run = await runScenario(on: fs)
                XCTAssertTrue(run.handleFollowed, "an open handle follows its workout's edit")
                let label = "store \(name) at \(cut) (acknowledged \(run.acknowledged))"
                guard let observed = await observe(after(fs), label: label) else { continue }
                check(observed.state, ids: observed.ids, acknowledged: run.acknowledged, label: label)
                // Health delivers an import again when its anchor did not commit: never twice.
                observed.store.addRun(Self.imported)
                XCTAssertEqual(observed.store.runSummaries.filter { $0.healthKitUUID == Self.imported.healthKitUUID }.count, 1, label)
                XCTAssertEqual(observed.store.runsV3SummaryMismatches, 0, label)
                cases += 1
            }
        }
        print("store crash matrix: \(total) calls, \(cases) cases")
    }
}
