import Foundation
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// Drives the real workout flow in the running app (local mode) through its accessibility
/// elements, as VoiceOver would: overview, set logging, log two sets with rest, finish and the
/// win screen. VOLIA_CAPTURE_WORKOUT_APP=1; run on the dedicated capture simulator only. Files
/// are prefixed app-cut- or app-legacy- after the switch. Writes to /private/tmp/volia-cut-workout
/// or VOLIA_CAPTURE_DIR. The workout it finishes is a real, local completed workout.
@MainActor
struct CutWorkoutAppRunTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_WORKOUT_APP"] == "1"))
    func runWorkoutFlow() async throws {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "has_completed_onboarding")
        defaults.set("9.9.9", forKey: "whats_new_last_seen_version")
        defaults.set(true, forKey: "tutorial_exercise_session")
        OnboardingManager.shared.complete(.exerciseSession)
        if !AppSettings.shared.isLocalMode {
            AppSettings.shared.enableLocalMode()
        }
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_DIR"] ?? "/private/tmp/volia-cut-workout")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let prefix = DS.Redesign.cutEnabled ? "app-cut" : "app-legacy"
        var log: [String] = []
        func shot(_ name: String) async throws {
            try await Task.sleep(for: .seconds(1.5))
            try saveScreen(to: root.appendingPathComponent("\(prefix)-\(name).png"))
            log.append(name)
        }

        enableAccessibilityAutomation()
        try await Task.sleep(for: .seconds(4))
        let store = AppDependencies.shared.workoutStore
        if store.currentWorkout != nil { store.discardCurrentWorkout() }
        try await Task.sleep(for: .seconds(1))
        try await shot("01-train")

        // Start a workout with one real exercise (the Train tab's "Add exercise" flow ends here).
        let repo = ExerciseRepository.shared
        let exercise = try #require(repo.exercises.first { $0.name == "Barbell Bench Press" }
            ?? repo.exercises.first { $0.name.localizedCaseInsensitiveContains("bench press") && $0.isWeightedExercise })
        _ = store.addExerciseToCurrent(exercise)
        try await Task.sleep(for: .seconds(1))
        NotificationCenter.default.post(name: .openLiveOverlay, object: nil)
        try await shot("02-overview")

        // The legacy hero card opens on a tap gesture that accessibility activation cannot reach,
        // so the legacy run stops at the overview and discards its workout.
        guard DS.Redesign.cutEnabled else {
            store.discardCurrentWorkout()
            try await Task.sleep(for: .seconds(1))
            return
        }

        // Into set logging through the current exercise row.
        try activate { $0.hasPrefix(exercise.name) }
        try await shot("03-set-logging")
        // An exercise added on its own has no sets yet: add the first, as a person would.
        try activate { $0.lowercased() == "add set" }
        try await shot("03b-first-set")
        // After the first set's rest, the app adds the next set itself (auto add set after rest).

        let logLabel = DS.Redesign.cutEnabled ? "Log set" : "Log This Set"
        try activate { $0 == logLabel }
        try await shot("04-rest-after-set-1")
        try activate { $0 == (DS.Redesign.cutEnabled ? "Skip rest" : "Cancel rest") || $0.contains("Cancel") }
        try await shot("05-after-skip")
        try activate { $0 == logLabel }
        try await shot("06-rest-after-set-2")
        RestTimerManager.shared.stopTimer()
        try await Task.sleep(for: .seconds(1))

        // Leave set logging (saves the sets, closes the overlay), then reopen the overview.
        try activate { $0 == "Done" }
        try await Task.sleep(for: .seconds(1.5))
        NotificationCenter.default.post(name: .openLiveOverlay, object: nil)
        try await shot("07-overview-done")

        if DS.Redesign.cutEnabled {
            try activate { $0 == "Finish workout" }
            try await shot("08-finish-dialog")
            try activate(last: true) { $0 == "Finish workout" }
        } else {
            try activate { $0.localizedCaseInsensitiveContains("finish") }
        }
        try await Task.sleep(for: .seconds(2))
        try await shot("09-win")
        try? FileManager.default.removeItem(at: root.appendingPathComponent("\(prefix)-run.txt"))
        try log.joined(separator: "\n").write(to: root.appendingPathComponent("\(prefix)-run.txt"), atomically: true, encoding: .utf8)
    }

    // MARK: - Accessibility driving

    private enum RunError: Error { case notFound(String) }

    /// Turns on the in-process accessibility runtime, as UI test tools do, so SwiftUI builds its
    /// accessibility elements (simulator only).
    private func enableAccessibilityAutomation() {
        guard let handle = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW),
              let symbol = dlsym(handle, "_AXSSetAutomationEnabled") else { return }
        typealias SetEnabled = @convention(c) (Int32) -> Void
        unsafeBitCast(symbol, to: SetEnabled.self)(1)
    }

    /// Activates the first (or last) accessibility element whose label matches, across windows.
    private func activate(last: Bool = false, _ match: (String) -> Bool) throws {
        var found: [NSObject] = []
        for window in windows().reversed() {
            collect(window, match: match, into: &found)
            if !found.isEmpty { break }
        }
        guard let element = last ? found.last : found.first else {
            throw RunError.notFound(allLabels().joined(separator: " | "))
        }
        if !element.accessibilityActivate() {
            throw RunError.notFound("activate failed: \(element.accessibilityLabel ?? "")")
        }
    }

    private func windows() -> [UIWindow] {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).filter { !$0.isHidden }
    }

    private func collect(_ object: NSObject, match: (String) -> Bool, into found: inout [NSObject], depth: Int = 0) {
        guard depth < 80 else { return }
        if let label = object.accessibilityLabel, match(label), object.isAccessibilityElement {
            found.append(object)
        }
        if let elements = object.accessibilityElements as? [NSObject] {
            for element in elements { collect(element, match: match, into: &found, depth: depth + 1) }
        } else {
            // SwiftUI hosting views answer the indexed container protocol.
            let count = object.accessibilityElementCount()
            if count > 0, count != NSNotFound {
                for index in 0..<count {
                    if let element = object.accessibilityElement(at: index) as? NSObject {
                        collect(element, match: match, into: &found, depth: depth + 1)
                    }
                }
            }
        }
        if let view = object as? UIView {
            for sub in view.subviews { collect(sub, match: match, into: &found, depth: depth + 1) }
        }
    }

    private func allLabels() -> [String] {
        var labels: [NSObject] = []
        for window in windows() { collect(window, match: { _ in true }, into: &labels) }
        return labels.compactMap(\.accessibilityLabel)
    }

    private func saveScreen(to url: URL) throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let bounds = scene.screen.bounds
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(bounds: bounds, format: format).image { _ in
            for window in scene.windows where !window.isHidden {
                _ = window.drawHierarchy(in: window.frame, afterScreenUpdates: true)
            }
        }
        try #require(image.pngData()).write(to: url)
    }
}
