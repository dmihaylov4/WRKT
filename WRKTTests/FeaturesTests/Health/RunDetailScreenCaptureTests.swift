import Foundation
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// Opt-in captures of the cardio and Health strength detail screens, for comparing the screens
/// before and after they read their workout through a detail handle. Run with
/// `TEST_RUNNER_VOLIA_CAPTURE_RUN_DETAIL=1`; files go to `VOLIA_CAPTURE_DIR`
/// (default /private/tmp/volia-run-detail). Which design is captured follows the Cut gate.
@MainActor
struct RunDetailScreenCaptureTests {
    private static let date = Date(timeIntervalSince1970: 1_794_398_400)

    private static func points(_ count: Int) -> [RoutePoint] {
        (0..<count).map { i in
            let angle = Double(i) / Double(count) * 2 * .pi
            return RoutePoint(lat: 48.2082 + 0.004 * sin(angle), lon: 16.3738 + 0.006 * cos(angle),
                              t: date.addingTimeInterval(Double(i) * 30), hr: 128 + 30 * sin(angle * 2))
        }
    }

    /// Fixed ids so file names and identities match between runs.
    private static func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }

    static var routeAndHeartRate: Run {
        let route = points(60)
        return Run(id: id(1), date: date, distanceKm: 6.2, durationSec: 2_052, notes: "Felt easy.", healthKitUUID: id(11),
                   avgHeartRate: 142, maxHeartRate: 168, minHeartRate: 101,
                   hrSamples: route.map { HeartRateSample(timestamp: $0.t, bpm: $0.hr!) }, calories: 412,
                   route: route.map { Coordinate(lat: $0.lat, lon: $0.lon) }, routeWithHR: route,
                   splits: (1...6).map { KilometerSplit(number: $0, distanceKm: 1, durationSec: 320 + $0 * 4) },
                   workoutType: "Running", workoutName: "Morning Run", avgRunningPower: 245, avgCadence: 168)
    }

    static var splitsOnly: Run {
        Run(id: id(2), date: date, distanceKm: 4.4, durationSec: 1_640, healthKitUUID: id(12), avgHeartRate: 136,
            calories: 280, splits: (1...4).map { KilometerSplit(number: $0, distanceKm: 1, durationSec: 360 + $0 * 5) }
                + [KilometerSplit(number: 5, distanceKm: 0.4, durationSec: 150)],
            workoutType: "Running", workoutName: "Treadmill")
    }

    static var nothing: Run {
        Run(id: id(3), date: date, distanceKm: 2.1, durationSec: 1_500, healthKitUUID: id(13), workoutType: "Walking")
    }

    static var strength: Run {
        Run(id: id(4), date: date, distanceKm: 0, durationSec: 2_760, notes: "Upper body.", healthKitUUID: id(14),
            avgHeartRate: 118, maxHeartRate: 151, minHeartRate: 72,
            hrSamples: (0..<20).map { HeartRateSample(timestamp: date.addingTimeInterval(Double($0) * 60), bpm: 100 + Double($0)) },
            calories: 356, workoutType: "Traditional Strength Training", workoutName: "Strength")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_RUN_DETAIL"] == "1"))
    func captureDetailScreens() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "RunDetailScreenCaptureTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let storage = WorkoutStorage(directory: directory)
        try Data().write(to: directory.appendingPathComponent(".migrated"))
        try await storage.saveWorkouts([], prIndex: [:])
        let runs = [Self.routeAndHeartRate, Self.splitsOnly, Self.nothing, Self.strength]
        try await storage.saveRuns(runs)
        defaults.set(true, forKey: "runs.deduplication.v1")
        let repository = ExerciseRepository()
        let store = WorkoutStoreV2(repo: repository, storage: WorkoutStorage(directory: directory), defaults: defaults)
        try await store.waitForStorage()

        let design = DS.Redesign.cutEnabled ? "cut" : "legacy"
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_DIR"] ?? "/private/tmp/volia-run-detail")
            .appendingPathComponent(design)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        for (name, run) in [("route-hr", Self.routeAndHeartRate), ("splits-only", Self.splitsOnly), ("nothing", Self.nothing)] {
            try await capture(cardio(run, store: store), name: name, store: store, repository: repository, root: root)
        }
        try await capture(strengthView(Self.strength, store: store), name: "strength", store: store,
                          repository: repository, root: root)
        try await capture(cardio(Self.routeAndHeartRate, store: store), name: "deleted-while-open", store: store,
                          repository: repository, root: root) {
            store.removeRun(withId: Self.routeAndHeartRate.id)
        }
    }

    // CAPTURE-API: the only lines that differ between the two sides of the comparison.
    private func cardio(_ run: Run, store: WorkoutStoreV2) -> some View {
        CardioDetailView(run: run)
    }

    private func strengthView(_ run: Run, store: WorkoutStoreV2) -> some View {
        HealthKitStrengthDetailView(run: run)
    }
    // END CAPTURE-API

    private func capture<V: View>(_ view: V, name: String, store: WorkoutStoreV2, repository: ExerciseRepository,
                                  root: URL, whileOpen: () -> Void = {}) async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let host = UIHostingController(rootView: NavigationStack { view }
            .environmentObject(store).environmentObject(repository)
            .environment(\.colorScheme, .dark))
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
        try await Task.sleep(for: .milliseconds(400))
        whileOpen()
        try await Task.sleep(for: .milliseconds(1_500))
        try save(window, root.appendingPathComponent("\(name).png"))

        // Legacy only: the Splits and Heart Rate tabs.
        if let segments = segmentedControls(in: host.view).first {
            for index in 1..<segments.numberOfSegments {
                segments.selectedSegmentIndex = index
                segments.sendActions(for: .valueChanged)
                try await Task.sleep(for: .milliseconds(600))
                try save(window, root.appendingPathComponent("\(name)-tab\(index).png"))
            }
        }
        // The rest of the page.
        if let scroll = scrollViews(in: host.view).first(where: { $0.contentSize.height > $0.bounds.height }) {
            if let segments = segmentedControls(in: host.view).first {
                segments.selectedSegmentIndex = 0
                segments.sendActions(for: .valueChanged)
            }
            scroll.setContentOffset(CGPoint(x: 0, y: min(scroll.contentSize.height - scroll.bounds.height, 600)
                                            - scroll.adjustedContentInset.top), animated: false)
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(600))
            try save(window, root.appendingPathComponent("\(name)-lower.png"))
        }
    }

    private func save(_ window: UIWindow, _ url: URL) throws {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try #require(image.pngData()).write(to: url)
    }

    private func scrollViews(in view: UIView) -> [UIScrollView] {
        (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
    }

    private func segmentedControls(in view: UIView) -> [UISegmentedControl] {
        (view as? UISegmentedControl).map { [$0] } ?? view.subviews.flatMap { segmentedControls(in: $0) }
    }
}
