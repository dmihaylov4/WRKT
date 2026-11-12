import Foundation
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// Opt-in captures of the three production detail screens using isolated local fixtures.
@MainActor
struct WorkoutDetailScrollEdgeCaptureTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_DETAIL_SCROLL_EDGE"] == "1"))
    func captureScrolledDetails() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "WorkoutDetailScrollEdgeCaptureTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let storage = WorkoutStorage(directory: directory)
        try Data().write(to: directory.appendingPathComponent(".migrated"))
        let repository = ExerciseRepository()
        let store = WorkoutStoreV2(repo: repository, storage: storage, defaults: defaults)
        try await store.waitForStorage()

        let date = Date(timeIntervalSince1970: 1_794_398_400)
        let notes = String(repeating: "Steady effort with controlled movement. ", count: 35)
        let samples = (0...6).map {
            HeartRateSample(timestamp: date.addingTimeInterval(Double($0) * 10), bpm: 68)
        }
        var workout = CompletedWorkout(date: date, entries: [TestFixtures.benchPressEntry], workoutName: "Push Day")
        workout.matchedHealthKitHeartRateSamples = samples
        workout.matchedHealthKitHeartRate = 68
        let cardio = Run(date: date, distanceKm: 5, durationSec: 1_800, notes: notes,
                         avgHeartRate: 68, hrSamples: samples, calories: 250, workoutType: "Running")
        let strength = Run(date: date, distanceKm: 0, durationSec: 60, notes: notes,
                           avgHeartRate: 68, calories: 10, workoutType: "Traditional Strength Training")
        let mode = DS.Redesign.usesSystemShell ? "system" : "legacy"
        let root = URL(fileURLWithPath: "/private/tmp/volia-detail-scroll-edge/\(mode)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        try await capture(WorkoutDetailView(workout: workout), name: "workout", store: store,
                          repository: repository, root: root)
        try await capture(CardioDetailView(run: cardio), name: "cardio", store: store,
                          repository: repository, root: root)
        try await capture(HealthKitStrengthDetailView(run: strength), name: "healthkit-strength", store: store,
                          repository: repository, root: root)
    }

    private func capture<V: View>(_ view: V, name: String, store: WorkoutStoreV2,
                                 repository: ExerciseRepository, root: URL) async throws {
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
        try await Task.sleep(for: .milliseconds(500))
        let scroll = try #require(scrollViews(in: host.view).first { $0.contentSize.height > $0.bounds.height })
        for offset in [0, 80, 160, 240] {
            scroll.setContentOffset(CGPoint(x: 0, y: CGFloat(offset) - scroll.adjustedContentInset.top), animated: false)
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            try #require(image.pngData()).write(to: root.appendingPathComponent("\(name)-\(offset).png"))
        }
    }

    private func scrollViews(in view: UIView) -> [UIScrollView] {
        (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
    }
}
