import Foundation
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// Opt-in component captures for the health-and-browse shape roles.
/// Uses in-memory fixtures only: no network, no HealthKit queries, no authorization prompts.
@MainActor
struct HealthBrowseComponentCaptureTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_HEALTH_BROWSE_COMPONENTS"] == "1"))
    func captureComponents() async throws {
        let phase = ProcessInfo.processInfo.environment["VOLIA_HEALTH_BROWSE_CAPTURE_PHASE"] ?? "after"
        try #require(["baseline", "after"].contains(phase))
        let mode = DS.Redesign.roundedShapesEnabled ? "rounded" : "legacy"
        let root = URL(fileURLWithPath: "/private/tmp/volia-shape-redesign-08/\(mode)/\(phase)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let date = Date(timeIntervalSince1970: 1_794_398_400)
        defer { cleanUp() }

        // Cardio charts: value data only.
        let splits = [KilometerSplit(number: 1, distanceKm: 1, durationSec: 330),
                      KilometerSplit(number: 2, distanceKm: 1, durationSec: 318),
                      KilometerSplit(number: 3, distanceKm: 1, durationSec: 341),
                      KilometerSplit(number: 4, distanceKm: 1, durationSec: 312)]
        try save(SplitsChart(splits: splits), "splits-chart", root)
        let zones = [HRZoneSummary(zone: 1, name: "Light", minutes: 4, rangeDisplay: "100-120 bpm", colorHex: "#4A90E2"),
                     HRZoneSummary(zone: 2, name: "Moderate", minutes: 8, rangeDisplay: "120-140 bpm", colorHex: "#50E3C2"),
                     HRZoneSummary(zone: 3, name: "Aerobic", minutes: 10, rangeDisplay: "140-155 bpm", colorHex: "#F5A623"),
                     HRZoneSummary(zone: 4, name: "Threshold", minutes: 5, rangeDisplay: "155-170 bpm", colorHex: "#F8661C"),
                     HRZoneSummary(zone: 5, name: "Max", minutes: 1, rangeDisplay: "170+ bpm", colorHex: "#D0021B")]
        try save(HRZoneChart(zones: zones, samples: nil, showTimeSeriesSection: false), "hr-zone-chart", root)
        try save(RunningDynamicsGrid(avgPower: 245, avgCadence: 172, avgStrideLength: 1.12,
            avgGroundContactTime: 238, avgVerticalOscillation: 8.4), "running-dynamics-grid", root)

        // Sync progress banner and auth sheet use a fresh local manager. Its init only reads
        // UserDefaults and creates an HKHealthStore; connectionState is never written.
        let manager = HealthKitManager()
        manager.isSyncing = true
        manager.syncTotalCount = 120
        manager.syncProcessedCount = 48
        manager.syncCurrentBatch = 1
        manager.syncTotalBatches = 2
        manager.syncProgress = 0.4
        try save(HealthKitSyncProgressView(healthKit: manager), "healthkit-sync-progress", root)
        try await saveHosted(HealthAuthSheet().environmentObject(manager), "health-auth-sheet", height: 874, root)

        // Detail screens with an in-memory workout store. No route and no lifecycle HealthKit work.
        let run = Run(date: date, distanceKm: 8.42, durationSec: 2_712, notes: "Easy loop along the river.",
            healthKitUUID: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1"),
            avgHeartRate: 148, maxHeartRate: 171, minHeartRate: 102, calories: 612, splits: splits,
            workoutType: "Running", avgRunningPower: 245, avgCadence: 172, avgStrideLength: 1.12,
            avgGroundContactTime: 238, avgVerticalOscillation: 8.4)
        let empty = try await makeStore(workouts: [])
        try await saveHosted(NavigationStack { CardioDetailView(run: run) }
            .environmentObject(empty.store).environmentObject(empty.repository),
            "cardio-detail-overview", height: 1_400, root)

        let strengthUUID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
        let strength = Run(date: date, distanceKm: 0, durationSec: 3_480, notes: "Upper body session.",
            healthKitUUID: strengthUUID, avgHeartRate: 121, calories: 402,
            workoutType: "Traditional Strength Training", workoutName: "Push Day")
        try await saveHosted(NavigationStack { HealthKitStrengthDetailView(run: strength) }
            .environmentObject(empty.store).environmentObject(empty.repository),
            "strength-detail-unmatched", height: 1_100, root)
        var matched = CompletedWorkout(date: date, entries: [TestFixtures.benchPressEntry], workoutName: "Push Day")
        matched.matchedHealthKitUUID = strengthUUID
        let matchedStore = try await makeStore(workouts: [matched])
        try await saveHosted(NavigationStack { HealthKitStrengthDetailView(run: strength) }
            .environmentObject(matchedStore.store).environmentObject(matchedStore.repository),
            "strength-detail-matched", height: 1_100, root)

        // Exercise browse components.
        try await saveHosted(SearchBarHost(text: "bench"), "exercise-search-bar", height: 140, root)
        var custom = TestFixtures.squat
        custom.isCustom = true
        let suggestion = MuscleSuggestion(muscle: "Chest", region: "Upper Body",
            exercises: [TestFixtures.benchPress, custom], totalCount: 5)
        try await saveHosted(List {
            CrossMuscleSuggestionSection(suggestion: suggestion, isExpanded: true,
                onToggle: {}, onSelectExercise: { _ in }, onShowAll: {})
        }.listStyle(.plain).scrollContentBackground(.hidden), "cross-muscle-suggestion", height: 520, root)
        try save(HStack(spacing: 8) {
            CustomExerciseBadge()
            MechanicPill(mechanic: "compound")
            MechanicPill(mechanic: "isolation")
        }, "exercise-list-pills", root)
        try save(EmptyExercisesView(title: "No exercises found", message: "Try a different muscle or filter.",
            onClear: {}), "empty-exercises", root)

        // Onboarding first page and What's New.
        try await saveHosted(OnboardingCarouselView(onComplete: {}), "onboarding-first-page", height: 874, root)
        try await saveHosted(WhatsNewView(release: WhatsNewRelease(version: "9.9.9", title: "Fixture",
            bullets: ["Rounded surfaces across the app.", "Faster exercise search."]),
            currentVersion: "9.9.9", onDismiss: {}), "whats-new", height: 640, root)
    }

    private struct SearchBarHost: View {
        @State var text: String
        @FocusState private var focused: Bool
        var body: some View {
            ExerciseSearchBar(text: $text, isFocused: $focused, onCancel: {})
        }
    }

    private final class Cleanup {
        var directories: [URL] = []
        var suites: [String] = []
    }
    private let cleanup = Cleanup()

    private func cleanUp() {
        for suite in cleanup.suites { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        for directory in cleanup.directories { try? FileManager.default.removeItem(at: directory) }
    }

    private func makeStore(workouts: [CompletedWorkout]) async throws
        -> (store: WorkoutStoreV2, repository: ExerciseRepository) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suiteName = "HealthBrowseComponentCaptureTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        cleanup.directories.append(directory)
        cleanup.suites.append(suiteName)
        let storage = WorkoutStorage(directory: directory)
        try Data().write(to: directory.appendingPathComponent(".migrated"))
        if !workouts.isEmpty {
            try await storage.saveWorkouts(workouts, prIndex: [:])
        }
        let repository = ExerciseRepository()
        let store = WorkoutStoreV2(repo: repository, storage: storage, defaults: defaults)
        try await store.waitForStorage()
        return (store, repository)
    }

    private func save<V: View>(_ view: V, _ name: String, _ root: URL) throws {
        // ImageRenderer evaluates leaf content without mounting lifecycle tasks.
        let renderer = ImageRenderer(content: view
            .frame(width: 370).padding(16).background(Color.black)
            .environment(\.colorScheme, .dark)
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            .environment(\.dynamicTypeSize, .large)
            .transaction { $0.disablesAnimations = true })
        renderer.scale = 2
        let data = try #require(renderer.uiImage?.pngData())
        try data.write(to: root.appendingPathComponent(name + ".png"))
    }

    private func saveHosted<V: View>(_ view: V, _ name: String, height: CGFloat, _ root: URL) async throws {
        // Lists, ScrollViews, focus state and navigation need a host rather than ImageRenderer.
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        let controller = UIHostingController(rootView: view.frame(width: 370).padding(16)
            .background(Color.black).environment(\.colorScheme, .dark)
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            .environment(\.dynamicTypeSize, .large)
            .transaction { $0.disablesAnimations = true }.ignoresSafeArea())
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: height)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = controller
        controller.view.backgroundColor = .black
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(500))
        controller.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        let data = renderer.pngData { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        try data.write(to: root.appendingPathComponent(name + ".png"))
    }
}
