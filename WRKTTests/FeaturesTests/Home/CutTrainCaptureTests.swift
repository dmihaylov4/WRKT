import Foundation
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// Opt-in capture of every Cut Train state from fixture values. Runs only with
/// VOLIA_CAPTURE_TRAIN=1 (pass TEST_RUNNER_VOLIA_CAPTURE_TRAIN=1 to xcodebuild). Writes to
/// /private/tmp/volia-cut-train, or to VOLIA_CAPTURE_DIR when set:
///   train-<state>.png             each hero state inside a system tab bar
///   train-<state>-scrolled.png    the same scrolled to the end (planned and live)
///   train-<state>-ax.png          accessibility Dynamic Type (planned, resting, no plan)
///   train-empty.png               no plan, no weekly goal, no rows
@MainActor
struct CutTrainCaptureTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_TRAIN"] == "1"))
    func captureTrainStates() async throws {
        let environment = ProcessInfo.processInfo.environment
        let root = URL(fileURLWithPath: environment["VOLIA_CAPTURE_DIR"] ?? "/private/tmp/volia-cut-train")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        for state in CutTrainFixtures.states {
            let model = CutTrainFixtures.model(state.hero)
            try await capture(model, to: root.appendingPathComponent("train-\(state.name).png"),
                              scrolledTo: ["planned", "live"].contains(state.name)
                                  ? root.appendingPathComponent("train-\(state.name)-scrolled.png") : nil)
            if ["planned", "resting", "no-plan"].contains(state.name) {
                try await capture(model, dynamicType: .accessibility3,
                                  to: root.appendingPathComponent("train-\(state.name)-ax.png"))
            }
        }
        try await capture(CutTrainModel(hero: .noPlan, weeklyGoal: nil, rows: []),
                          to: root.appendingPathComponent("train-empty.png"))
    }

    /// The real Train tab in the running app (local mode), idle, with a workout, and resting.
    /// VOLIA_CAPTURE_TRAIN_APP=1; run on a dedicated capture simulator. The capture workout
    /// and rest timer are discarded afterwards. Files are prefixed app-cut- or app-legacy-.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_TRAIN_APP"] == "1"))
    func captureRunningApp() async throws {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "has_completed_onboarding")
        defaults.set("9.9.9", forKey: "whats_new_last_seen_version")
        if !AppSettings.shared.isLocalMode {
            AppSettings.shared.enableLocalMode()
        }
        let environment = ProcessInfo.processInfo.environment
        let root = URL(fileURLWithPath: environment["VOLIA_CAPTURE_DIR"] ?? "/private/tmp/volia-cut-train")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let prefix = DS.Redesign.cutEnabled ? "app-cut" : "app-legacy"

        try await Task.sleep(for: .seconds(4))
        try saveKeyWindow(to: root.appendingPathComponent("\(prefix)-idle.png"))

        let store = AppDependencies.shared.workoutStore
        let hadWorkout = store.currentWorkout != nil
        if !hadWorkout {
            store.addExerciseToCurrent(TestFixtures.benchPress)
        }
        try await Task.sleep(for: .seconds(2))
        try saveKeyWindow(to: root.appendingPathComponent("\(prefix)-live.png"))

        let timer = RestTimerManager.shared
        timer.startTimer(duration: 92, exerciseID: TestFixtures.benchPress.id, exerciseName: TestFixtures.benchPress.name)
        try await Task.sleep(for: .seconds(2))
        try saveKeyWindow(to: root.appendingPathComponent("\(prefix)-resting.png"))
        timer.stopTimer()

        if !hadWorkout {
            store.discardCurrentWorkout()
        }
        try await Task.sleep(for: .seconds(1))
    }

    /// Status bar style per state (VOLIA_CAPTURE_STATUSBAR=1). The status bar is outside the
    /// app's drawing, so for each state the test records the scene's effective style in
    /// statusbar.txt, then writes `<name>.ready` and holds the state for a few seconds so a
    /// shell loop can take `simctl io screenshot` while it is on screen.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_STATUSBAR"] == "1"))
    func captureStatusBar() async throws {
        let environment = ProcessInfo.processInfo.environment
        let root = URL(fileURLWithPath: environment["VOLIA_CAPTURE_DIR"] ?? "/private/tmp/volia-cut-train/statusbar")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let mode = DS.Redesign.cutEnabled ? "cut" : "legacy"
        var lines: [String] = []

        func record(_ name: String) async throws {
            try await Task.sleep(for: .seconds(1.5))
            let style = scene.statusBarManager?.statusBarStyle ?? .default
            let label = switch style {
            case .darkContent: "darkContent"
            case .lightContent: "lightContent"
            default: "default"
            }
            lines.append("\(mode)-\(name): \(label)")
            try Data().write(to: root.appendingPathComponent("\(mode)-\(name).ready"))
            try await Task.sleep(for: .seconds(6))
        }

        // The running app's Train tab (local mode: no plan, so a lime field).
        try await Task.sleep(for: .seconds(3))
        try await record("app-train")

        // The Plan tab, through the shell's own navigation (a program invite opens Plan),
        // then back to Train through its user-intent reset.
        let invite = AppNotification(id: UUID(), userId: UUID(), type: .programInvite, actorId: UUID(),
                                     targetId: nil, read: true, createdAt: .now, metadata: nil)
        NotificationCenter.default.post(name: .init("NavigateToNotification"), object: invite)
        try await record("app-plan-tab")
        NotificationCenter.default.post(name: .resetHomeToRoot, object: nil, userInfo: ["reason": "user_intent"])
        try await record("app-train-back")

        // A rest day: an active plan whose block today is a rest block (dedicated capture
        // simulator only; the plan is left inactive afterwards).
        if DS.Redesign.cutEnabled {
            let planner = AppDependencies.shared.plannerStore
            try planner.createSplit(name: "Status bar capture", planBlocks: [
                PlanBlock(dayName: "Rest", exercises: [], isRestDay: true)
            ])
            NotificationCenter.default.post(name: .plannedWorkoutsChanged, object: nil)
            try await record("app-rest-day")
            if let split = try planner.activeSplit() {
                split.isActive = false
                try planner.saveContext()
            }
            NotificationCenter.default.post(name: .plannedWorkoutsChanged, object: nil)
            try await record("app-train-after-rest")
        }
        try lines.joined(separator: "\n").appending("\n")
            .write(to: root.appendingPathComponent("statusbar-\(mode).txt"), atomically: true, encoding: .utf8)
    }

    private func saveKeyWindow(to url: URL) throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try #require(scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first)
        try save(window: window, to: url)
    }

    private func capture(
        _ model: CutTrainModel,
        dynamicType: DynamicTypeSize = .large,
        to url: URL,
        scrolledTo scrolledURL: URL? = nil
    ) async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = UIHostingController(
            rootView: CutTrainCaptureShell(model: model).environment(\.dynamicTypeSize, dynamicType)
        )
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .seconds(2))
        try save(window: window, to: url)

        if let scrolledURL, let scrollView = firstScrollView(in: window) {
            let maxOffset = scrollView.contentSize.height + scrollView.adjustedContentInset.bottom - scrollView.bounds.height
            scrollView.setContentOffset(CGPoint(x: 0, y: max(-scrollView.adjustedContentInset.top, maxOffset)), animated: false)
            try await Task.sleep(for: .seconds(1))
            try save(window: window, to: scrolledURL)
        }
    }

    private func firstScrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView, scroll.contentSize.height > scroll.bounds.height / 2 { return scroll }
        for subview in view.subviews {
            if let found = firstScrollView(in: subview) { return found }
        }
        return nil
    }

    private func save(window: UIWindow, to url: URL) throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try #require(image.pngData()).write(to: url)
    }
}

/// The Train tab as the app shell hosts it: inside a NavigationStack in the first tab of a
/// system tab bar, with HomeViewNew's bottom clearance.
private struct CutTrainCaptureShell: View {
    let model: CutTrainModel

    var body: some View {
        TabView {
            Tab("Train", image: "tab-train") {
                NavigationStack {
                    CutTrainView(model: model, actions: CutTrainActions(tappableRows: [.lastWorkout]))
                        .safeAreaInset(edge: .bottom) {
                            Color.clear.frame(height: DS.Redesign.tabBarClearance(legacy: 90, system: 70))
                        }
                        .toolbar(.hidden, for: .navigationBar)
                }
            }
            Tab("Plan", image: "tab-plan-inactive") { Color.black }
            Tab("Social", image: "tab-social-inactive") { Color.black }
            Tab("Cardio", image: "tab-cardio-inactive") { Color.black }
            Tab("Me", image: "tab-profile-inactive") { Color.black }
        }
        .tint(DS.Palette.marone)
    }
}
