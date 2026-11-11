import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import WRKT

@MainActor
struct WorkoutSessionCaptureTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_WORKOUT_SESSION"] == "1"))
    func captureIsolatedWorkoutScreens() async throws {
        try #require(UserDefaults.standard.bool(forKey: "tutorial_exercise_session"),
                "Pass -tutorial_exercise_session YES as a volatile launch argument")
        let mode = DS.Redesign.roundedShapesEnabled ? "rounded" : "legacy"
        var root = URL(fileURLWithPath: "/private/tmp/volia-shape-redesign-04")
        if ProcessInfo.processInfo.environment["VOLIA_CAPTURE_WORKOUT_STAGE"] == "baseline" {
            root.appendPathComponent("baseline")
        }
        root.appendPathComponent(mode)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suiteName = "WorkoutSessionCaptureTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
        let storage = WorkoutStorage(directory: directory)
        try Data().write(to: directory.appendingPathComponent(".migrated"))
        let schema = Schema([PlannedWorkout.self, PlannedExercise.self, WorkoutSplit.self,
                             PlanBlock.self, PlanBlockExercise.self, WeeklyGoal.self])
        let container = try ModelContainer(for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let repository = ExerciseRepository()
        let date = Date(timeIntervalSince1970: 1_794_312_000)
        var exercises: [Exercise] = []
        var entries: [WorkoutEntry] = []
        for (index, tracking) in [TrackingMode.weighted, .bodyweight, .timed].enumerated() {
            var exercise = TestFixtures.benchPress
            exercise.id = "capture-04-" + tracking.rawValue
            exercise.name = ["Barbell Bench Press", "Push-up", "Plank"][index]
            exercise.trackingMode = tracking.rawValue
            exercise.defaultDurationSeconds = tracking == .timed ? 30 : nil
            exercises.append(exercise)
            let completed = SetInput(reps: 8, weight: tracking == .weighted ? 60 : 0,
                autoWeight: false, didSeedFromMemory: true, isCompleted: true,
                durationSeconds: tracking == .timed ? 30 : 0, trackingMode: tracking,
                startTime: date.addingTimeInterval(-120), completionTime: date.addingTimeInterval(-90),
                restAfterSeconds: 60)
            let active = SetInput(reps: 8, weight: tracking == .weighted ? 60 : 0,
                autoWeight: false, didSeedFromMemory: true,
                durationSeconds: tracking == .timed ? 30 : 0, trackingMode: tracking)
            entries.append(WorkoutEntry(exerciseID: exercise.id, exerciseName: exercise.name,
                                        muscleGroups: exercise.primaryMuscles, sets: [completed, active], activeSetIndex: 1))
        }
        try await storage.saveCurrentWorkout(CurrentWorkout(startedAt: .now.addingTimeInterval(-900), entries: entries))
        let store = WorkoutStoreV2(storage: storage, defaults: defaults)
        try await store.waitForStorage()

        for expanded in [false, true] {
            try await save(OverlayCaptureHost(expanded: expanded, startDate: .now.addingTimeInterval(-900)),
                name: expanded ? "live-workout-overlay-expanded" : "live-workout-overlay-collapsed",
                root: root, store: store, repository: repository, container: container)
        }
        for (exercise, entry) in zip(exercises, entries) {
            try await save(NavigationStack {
                ExerciseSessionView(exercise: exercise, initialEntryID: entry.id)
            }, name: "exercise-session-" + exercise.trackingMode,
                root: root, store: store, repository: repository, container: container)
        }
        try await save(NavigationStack { CustomTimerEditorView(exercise: exercises[0]) },
            name: "rest-timer", root: root, store: store, repository: repository, container: container)
        let completedWorkout = CompletedWorkout(date: date, entries: entries)
        try await save(NavigationStack { WorkoutDetailView(workout: completedWorkout) },
            name: "workout-detail", root: root, store: store, repository: repository, container: container)
        try await save(QuickWorkoutTypeSelector(date: date, onSelect: { _ in }),
            name: "quick-workout-selector", root: root, store: store, repository: repository, container: container)
        try await save(RetrospectiveWorkoutBuilder(date: date),
            name: "retrospective-builder", root: root, store: store, repository: repository, container: container)
        try await store.flushPendingSaves()
    }

    private func save<V: View>(
        _ content: V, name: String, root: URL, store: WorkoutStoreV2,
        repository: ExerciseRepository, container: ModelContainer
    ) async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        let controller = UIHostingController(rootView: content
            .environmentObject(store).environmentObject(repository).modelContainer(container)
            .environment(\.colorScheme, .dark)
            .transaction { $0.disablesAnimations = true })
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
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
        try await Task.sleep(for: .milliseconds(350))
        controller.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        let data = renderer.pngData { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        try data.write(to: root.appendingPathComponent(name + ".png"))
    }
}

private struct OverlayCaptureHost: View {
    @Namespace private var namespace
    let expanded: Bool
    let startDate: Date

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()
            LiveWorkoutOverlayCard(namespace: namespace, title: "Live workout", subtitle: "November 10, 2026",
                showContent: expanded, onClose: {}, startDate: startDate)
                .padding(.horizontal, 12)
                .padding(.bottom, 100)
        }
    }
}
