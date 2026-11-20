import Darwin
import SwiftUI
import XCTest
@testable import WRKT

/// Opt-in measurements of the store on a real history (spec 10), and captures of the detail
/// screens with a slow and a failing loader.
///
/// - `VOLIA_RUNS_FILE=/path/to/runs_v2.json` plus `VOLIA_RUNS_V3_STORE_PERF=1`: the history is
///   read (never written or copied outside a temporary directory that is deleted), seeded as
///   runs_v3 and as a compact runs_v2.json, and the store's launch time and memory are reported
///   for both. Counts and timings only.
/// - `VOLIA_CAPTURE_RUN_DETAIL_V3=1`: PNGs of the detail screens while loading, loaded and
///   unreadable, to `VOLIA_CAPTURE_DIR` (default /private/tmp/volia-run-detail-v3).
@MainActor
final class RunsV3StoreRealHistoryTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("RunsV3RealStore-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// Bytes allocated on the heap and still in use (all malloc zones). Unlike the process
    /// footprint it falls when memory is freed, so it shows what the store holds.
    private static func footprint() -> Int {
        var stats = malloc_statistics_t()
        malloc_zone_statistics(nil, &stats)
        return Int(stats.size_in_use)
    }

    /// Samples the footprint on another thread while `body` runs; returns the highest seen.
    private static func peak(during body: () async throws -> Void) async rethrows -> Int {
        final class Sampler: @unchecked Sendable {
            let lock = NSLock(); var highest = 0; var running = true
        }
        let sampler = Sampler()
        let thread = Thread {
            while sampler.lock.withLock({ sampler.running }) {
                let now = Self.footprint()
                sampler.lock.withLock { sampler.highest = max(sampler.highest, now) }
                usleep(500)
            }
        }
        thread.start()
        try await body()
        sampler.lock.withLock { sampler.running = false }
        return sampler.lock.withLock { sampler.highest }
    }

    private static func mb(_ bytes: Int) -> String { String(format: "%.1f MB", Double(bytes) / 1_048_576) }
    private static func ms(_ start: UInt64) -> String {
        String(format: "%.0f ms", Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
    }

    func testLaunchAndMemoryOnARealHistory() async throws {
        guard let path = ProcessInfo.processInfo.environment["VOLIA_RUNS_FILE"], !path.isEmpty,
              ProcessInfo.processInfo.environment["VOLIA_RUNS_V3_STORE_PERF"] == "1" else {
            throw XCTSkip("Set VOLIA_RUNS_FILE and VOLIA_RUNS_V3_STORE_PERF=1 to measure")
        }
        let v3Dir = root.appendingPathComponent("v3/WRKT_Storage")
        let v2Dir = root.appendingPathComponent("v2/WRKT_Storage")
        try FileManager.default.createDirectory(at: v3Dir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: v2Dir, withIntermediateDirectories: true)
        var count = 0
        try autoreleasepool {
            let runs = try RunsV3.makeDecoder().decode([StoredRun].self, from: Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)).map(\.run)
            count = runs.count
            try V3Disk.seed(v3Dir, runs)
            try RunsV3.makeEncoder().encode(runs.map(StoredRun.init)).write(to: v2Dir.appendingPathComponent("runs_v2.json"))
        }
        try Data().write(to: v2Dir.appendingPathComponent(".migrated"))
        let suite = "RunsV3StoreRealHistoryTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(true, forKey: "runs.deduplication.v1")
        defer { defaults.removePersistentDomain(forName: suite) }
        try await Task.sleep(for: .milliseconds(300))

        for (name, directory) in [("runs_v3", v3Dir), ("runs_v2 (compact)", v2Dir)] {
            let before = Self.footprint()
            var store: WorkoutStoreV2!
            var openTime = ""
            var readyTime = ""
            let launchPeak = try await Self.peak {
                let start = DispatchTime.now().uptimeNanoseconds
                let storage = WorkoutStorage(directory: directory)
                _ = try await storage.openRunHistory(isProtectedDataAvailable: true)
                openTime = Self.ms(start)
                let readyStart = DispatchTime.now().uptimeNanoseconds
                store = WorkoutStoreV2(storage: WorkoutStorage(directory: directory), defaults: defaults)
                try await store.waitForStorage()
                readyTime = Self.ms(readyStart)
            }
            try await Task.sleep(for: .milliseconds(300))
            let held = Self.footprint() - before
            XCTAssertEqual(store.runSummaries.count, count)

            // The first screen that lists the history: the cardio list.
            let frameStart = DispatchTime.now().uptimeNanoseconds
            let host = UIHostingController(rootView: NavigationStack { CardioView() }
                .environmentObject(HealthKitManager()).environmentObject(store).environmentObject(ExerciseRepository()))
            host.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
            host.view.layoutIfNeeded()
            let firstFrame = Self.ms(frameStart)

            var imported = V3.run(990_001, points: 900, samples: 300)
            imported.id = UUID()
            imported.healthKitUUID = UUID()
            imported.date = .now
            let base = Self.footprint()
            let importPeak = try await Self.peak {
                store.addRun(imported)
                try await store.flushHealthKitChanges()
            }
            print("""
            runs_v3 store perf [\(name)]: \(count) workouts; storage open \(openTime); history ready \(readyTime); \
            first list frame \(firstFrame); held after launch \(Self.mb(held)) (peak during launch \(Self.mb(max(0, launchPeak - before)))); \
            full runs in memory \(store.runsV3CachedRunCount); import of one workout peak +\(Self.mb(max(0, importPeak - base)))
            """)
            store = nil
            _ = host
            try await Task.sleep(for: .milliseconds(300))
        }
    }
}

extension RunsV3StoreRealHistoryTests {
    /// The detail screens while their workout loads from a slow disk, once loaded, and when its
    /// file is damaged: they were written for these states in Stage 1.
    func testCaptureDetailScreensWhileLoadingLoadedAndUnreadable() async throws {
        guard ProcessInfo.processInfo.environment["VOLIA_CAPTURE_RUN_DETAIL_V3"] == "1" else {
            throw XCTSkip("Set VOLIA_CAPTURE_RUN_DETAIL_V3=1 to capture")
        }
        let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_DIR"] ?? "/private/tmp/volia-run-detail-v3")
            .appendingPathComponent(DS.Redesign.cutEnabled ? "cut" : "legacy")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let directory = root.appendingPathComponent("WRKT_Storage")
        let morning = Calendar.current.startOfDay(for: .now).addingTimeInterval(7 * 3600)
        var routed = RunDetailScreenCaptureTests.routeAndHeartRate
        routed.date = morning
        var splits = RunDetailScreenCaptureTests.splitsOnly
        splits.date = morning.addingTimeInterval(-3600)
        var strength = RunDetailScreenCaptureTests.strength
        strength.date = morning.addingTimeInterval(-7200)
        try V3Disk.seed(directory, [routed, splits, strength])
        let suite = "RunsV3Capture." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(true, forKey: "runs.deduplication.v1")
        let prompted = UserDefaults.standard.object(forKey: "hasPromptedForHealthKitAuth")
        UserDefaults.standard.set(true, forKey: "hasPromptedForHealthKitAuth")
        defer {
            defaults.removePersistentDomain(forName: suite)
            UserDefaults.standard.set(prompted, forKey: "hasPromptedForHealthKitAuth")
        }
        let slow = FaultyFileSystem()
        let repository = ExerciseRepository()
        let store = WorkoutStoreV2(repo: repository, storage: WorkoutStorage(directory: directory, fileSystem: slow), defaults: defaults)
        try await store.waitForStorage()

        slow.readDelay = 2.5
        for (name, view) in [("detail-route-hr", AnyView(CardioDetailView(run: routed.summary))),
                             ("detail-splits-only", AnyView(CardioDetailView(run: splits.summary))),
                             ("strength", AnyView(HealthKitStrengthDetailView(run: strength.summary))),
                             ("cardio-list", AnyView(CardioView().environmentObject(HealthKitManager())))] {
            try await capture(view, store: store, repository: repository, steps: [(0.4, out.appendingPathComponent("\(name)-loading.png")),
                                                                                  (3.2, out.appendingPathComponent("\(name)-loaded.png"))])
        }
        // A damaged file: the screen's unavailable state.
        slow.readDelay = 0
        try Data("damaged".utf8).write(to: RunsV3Layout(storage: directory).runFile(RunsV3FileName(id: splits.id, rev: 1)))
        let damagedStore = WorkoutStoreV2(repo: repository, storage: WorkoutStorage(directory: directory), defaults: defaults)
        try await damagedStore.waitForStorage()
        try await capture(AnyView(CardioDetailView(run: splits.summary)), store: damagedStore, repository: repository,
                          steps: [(1.0, out.appendingPathComponent("detail-splits-only-unreadable.png"))])
        print("runs_v3 detail captures written to \(out.path)")
    }

    private func capture(_ view: AnyView, store: WorkoutStoreV2, repository: ExerciseRepository,
                         steps: [(TimeInterval, URL)]) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let host = UIHostingController(rootView: NavigationStack { view }
            .environmentObject(store).environmentObject(repository).environment(\.colorScheme, .dark))
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = host
        window.overrideUserInterfaceStyle = .dark
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
        }
        host.view.layoutIfNeeded()
        var elapsed: TimeInterval = 0
        for (at, url) in steps {
            try await Task.sleep(for: .milliseconds(Int((at - elapsed) * 1000)))
            elapsed = at
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            try XCTUnwrap(image.pngData()).write(to: url)
        }
    }
}
