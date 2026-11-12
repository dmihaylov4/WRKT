import Foundation
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// Opt-in capture of the running app shell (custom bar or system tab bar).
/// Run on a dedicated capture simulator: VOLIA_SHELL_PREPARE_LOCAL=1 switches that
/// simulator's app into local mode with onboarding complete so the shell shows without sign-in.
/// Set debug.useRoundedShapes to false on the simulator before launch for the legacy capture.
@MainActor
struct ShellCaptureTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_SHELL"] == "1"))
    func captureShell() async throws {
        if ProcessInfo.processInfo.environment["VOLIA_SHELL_PREPARE_LOCAL"] == "1" {
            let defaults = UserDefaults.standard
            defaults.set(true, forKey: "has_completed_onboarding")
            defaults.set("9.9.9", forKey: "whats_new_last_seen_version")
            if !AppSettings.shared.isLocalMode {
                AppSettings.shared.enableLocalMode()
            }
        }
        try #require(AppSettings.shared.isLocalMode, "Shell capture needs local mode (VOLIA_SHELL_PREPARE_LOCAL=1)")

        let mode = DS.Redesign.usesSystemShell ? "system" : "legacy"
        let root = URL(fileURLWithPath: "/private/tmp/volia-shape-redesign-09/\(mode)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        try await Task.sleep(for: .seconds(4))
        try save(to: root.appendingPathComponent("shell-train.png"))

        NotificationCenter.default.post(name: .hideShellTabBar, object: nil)
        try await Task.sleep(for: .seconds(1))
        try save(to: root.appendingPathComponent("shell-train-bar-hidden.png"))
        NotificationCenter.default.post(name: .showShellTabBar, object: nil)
        try await Task.sleep(for: .seconds(1))

        // Live workout card above the tab bar; the capture workout is discarded afterwards.
        let store = AppDependencies.shared.workoutStore
        let hadWorkout = store.currentWorkout != nil
        if !hadWorkout {
            store.addExerciseToCurrent(TestFixtures.benchPress)
        }
        try await Task.sleep(for: .seconds(1))
        NotificationCenter.default.post(name: .openLiveOverlay, object: nil)
        try await Task.sleep(for: .seconds(2))
        try save(to: root.appendingPathComponent("shell-live-card.png"))
        NotificationCenter.default.post(name: .dismissLiveOverlay, object: nil)
        if !hadWorkout {
            store.discardCurrentWorkout()
        }
        try await Task.sleep(for: .seconds(1))
    }

    private func save(to url: URL) throws {
        let scene = try #require(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first)
        let window = try #require(scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let data = try #require(image.pngData())
        try data.write(to: url)
    }
}
