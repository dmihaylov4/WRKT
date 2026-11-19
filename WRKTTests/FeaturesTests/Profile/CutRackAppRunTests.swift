import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// Opens the Cut rack in the running app (local mode, signed out): PlateWallView presented over the
/// app on its own container, as the Me tab presents it, then loads and unloads one tray plate through
/// VoiceOver activation, the real host, save path and live scene. VOLIA_CAPTURE_RACK_APP=1, on the dedicated capture simulator only. It adds three fixture
/// plates (ids "fixture-rackrun-") to the local store and deletes them at the end; it refuses to
/// run with a signed-in user, so nothing can reach the server. Each step writes <name>.ready into
/// VOLIA_CAPTURE_DIR and holds so an outside simctl screenshot can record the Metal scene.
@MainActor
struct CutRackAppRunTests {
    private enum RunError: Error { case notFound(String) }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_RACK_APP"] == "1"))
    func openRackLoadAndUnload() async throws {
        try #require(SupabaseAuthService.shared.currentUser == nil, "Signed in: refusing to touch a real account")
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "has_completed_onboarding")
        defaults.set("9.9.9", forKey: "whats_new_last_seen_version")
        if !AppSettings.shared.isLocalMode { AppSettings.shared.enableLocalMode() }
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_DIR"] ?? "/private/tmp/volia-cut-rack-app")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let hold = Double(ProcessInfo.processInfo.environment["VOLIA_CAPTURE_HOLD"] ?? "") ?? 5

        func shot(_ name: String) async throws {
            try await Task.sleep(for: .seconds(1.5))
            try Data().write(to: root.appendingPathComponent(name + ".ready"))
            try await Task.sleep(for: .seconds(hold))
        }

        try await Task.sleep(for: .seconds(4))
        let context = try #require(await WRKTApp.storage.openedContainer()?.mainContext)
        let fixtures = [
            EarnedPlate(id: "fixture-rackrun-lime", tierID: 22, weightKg: 20, engravingText: "", earnedByEvent: "fixture"),
            EarnedPlate(id: "fixture-rackrun-blue", tierID: 15, weightKg: 20, engravingText: "", earnedByEvent: "fixture"),
            EarnedPlate(id: "fixture-rackrun-gold", tierID: 6, weightKg: 45, engravingText: "", earnedByEvent: "fixture")
        ]
        fixtures.forEach(context.insert)
        try context.save()
        defer {
            for plate in fixtures {
                if plate.isRacked { BarbellProgressService.shared.removeFromBar(plate: plate) }
                context.delete(plate)
            }
            try? context.save()
        }

        enableAccessibilityAutomation()
        try await Task.sleep(for: .seconds(2))
        // The Me tab's custom tab buttons do not respond to accessibility activation, so the rack
        // is presented the way the Me tab does it: PlateWallView in a sheet over the running app,
        // on the app's own model container and dependencies.
        let presenter = try #require(windows().first { $0.isKeyWindow }?.rootViewController)
        var top = presenter
        while let next = top.presentedViewController { top = next }
        let container = try #require(WRKTApp.storage.container)
        top.present(UIHostingController(rootView: PlateWallView().modelContainer(container)
            .environmentObject(AppDependencies.shared.workoutStore)), animated: true)
        try await Task.sleep(for: .seconds(5))
        try await shot("app-01-rack")

        try activate { $0.hasPrefix("Lime Bumper, 20 kilograms") }
        try await Task.sleep(for: .seconds(1.2))
        try await shot("app-02-loaded")
        try await shot("app-02b-loaded-settled")

        try activate { $0.hasPrefix("Lime Bumper, 20 kilograms") }
        try await Task.sleep(for: .seconds(2))
        try await shot("app-03-unloaded")

        try activate { $0.hasPrefix("Show all") }
        try await Task.sleep(for: .seconds(2))
        try await shot("app-04-collection")
    }

    private func enableAccessibilityAutomation() {
        guard let handle = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW),
              let symbol = dlsym(handle, "_AXSSetAutomationEnabled") else { return }
        typealias SetEnabled = @convention(c) (Int32) -> Void
        unsafeBitCast(symbol, to: SetEnabled.self)(1)
    }

    private func activate(_ match: (String) -> Bool) throws {
        var found: [NSObject] = []
        for window in windows().reversed() {
            collect(window, match: match, into: &found)
            if !found.isEmpty { break }
        }
        guard !found.isEmpty else { throw RunError.notFound(allLabels().joined(separator: " | ")) }
        // A label can match an inner text as well as its button: try each until one activates.
        for element in found where element.accessibilityActivate() { return }
        throw RunError.notFound("activate failed: " + allLabels().joined(separator: " | "))
    }

    private func windows() -> [UIWindow] {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).filter { !$0.isHidden }
    }

    private func collect(_ object: NSObject, match: (String) -> Bool, into found: inout [NSObject], depth: Int = 0) {
        guard depth < 80 else { return }
        if let label = object.accessibilityLabel, match(label), object.isAccessibilityElement { found.append(object) }
        if let elements = object.accessibilityElements as? [NSObject] {
            for element in elements { collect(element, match: match, into: &found, depth: depth + 1) }
        }
        if let view = object as? UIView {
            for sub in view.subviews { collect(sub, match: match, into: &found, depth: depth + 1) }
        }
    }

    private func allLabels() -> [String] {
        var labels: [NSObject] = []
        for window in windows() { collect(window, match: { _ in true }, into: &labels) }
        return labels.compactMap(\.accessibilityLabel).prefix(80).map { $0 }
    }
}
