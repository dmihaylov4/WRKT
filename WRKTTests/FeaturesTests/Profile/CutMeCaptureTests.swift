import Foundation
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// Opt-in captures of the Cut Me tab. Writes to /private/tmp/volia-cut-me, or VOLIA_CAPTURE_DIR.
///
/// VOLIA_CAPTURE_CUT_ME=1 (pass TEST_RUNNER_VOLIA_CAPTURE_CUT_ME=1 to xcodebuild) renders the Cut Me
/// tab from fixtures, one file per state: me-<state>.png. A trained user with a goal and a plan,
/// no goal, a brand-new user, no progress at all, freeze active, large numbers, the scrolled
/// middle and end, and accessibility Dynamic Type.
@MainActor
struct CutMeCaptureTests {
    private typealias F = CutMeFixtures

    private var root: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_DIR"] ?? "/private/tmp/volia-cut-me")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_CUT_ME"] == "1"))
    func captureFixtureStates() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        var noGoal = F.full
        noGoal.goalIsSet = false
        noGoal.adherence = []
        var noProgress = F.fresh
        noProgress.progress = nil
        noProgress.freeze = nil
        var frozen = F.full
        frozen.progress?.weeklyFrozen = true
        frozen.freeze = CutMeFacts.Freeze(canActivate: false, reason: "Freeze already active")
        var olderWeek = F.full
        olderWeek.weeks = Array(F.weeks.dropLast(2))
        olderWeek.latestWeekChange = -4.6
        olderWeek.pushVolume = nil
        olderWeek.pullVolume = nil

        let states: [(String, CutMeFacts, UnitPoint)] = [
            ("full", F.full, .top),
            ("full-middle", F.full, .center),
            ("full-bottom", F.full, .bottom),
            ("no-goal", noGoal, .top),
            ("fresh", F.fresh, .top),
            ("fresh-bottom", F.fresh, .bottom),
            ("no-progress", noProgress, .top),
            ("freeze-active", frozen, .top),
            ("older-week", olderWeek, .center),
            ("large", F.large, .top),
            ("large-middle", F.large, .center),
            ("large-bottom", F.large, .bottom)
        ]
        for (name, facts, anchor) in states {
            try await capture(F.model(facts), anchor: anchor, to: root.appendingPathComponent("me-\(name).png"))
        }
        for (name, anchor) in [("top", UnitPoint.top), ("middle", .center), ("bottom", .bottom)] {
            try await capture(F.model(F.full), dynamicType: .xxxLarge, anchor: anchor,
                              to: root.appendingPathComponent("me-full-xxxl-\(name).png"))
        }
        try await capture(F.model(F.large), dynamicType: .xxxLarge, anchor: .top,
                          to: root.appendingPathComponent("me-large-xxxl.png"))
    }

    // MARK: Helpers

    private func capture(_ model: CutMeModel, dynamicType: DynamicTypeSize = .large,
                         anchor: UnitPoint, to url: URL) async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = UIHostingController(
            rootView: CutMeCaptureShell(model: model)
                .defaultScrollAnchor(anchor)
                .environment(\.dynamicTypeSize, dynamicType)
        )
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .seconds(2))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try #require(image.pngData()).write(to: url)
    }
}

/// The Me tab as the app shell hosts it: inside a NavigationStack in the fifth tab of a system tab bar.
private struct CutMeCaptureShell: View {
    let model: CutMeModel
    @State private var tab = 4

    var body: some View {
        TabView(selection: $tab) {
            Tab("Train", image: "tab-train-inactive", value: 0) { Color.black }
            Tab("Plan", image: "tab-plan-inactive", value: 1) { Color.black }
            Tab("Social", image: "tab-social-inactive", value: 2) { Color.black }
            Tab("Cardio", image: "tab-cardio-inactive", value: 3) { Color.black }
            Tab("Me", image: "tab-profile", value: 4) {
                NavigationStack {
                    CutMeView(model: model)
                        .toolbar(.hidden, for: .navigationBar)
                }
            }
        }
        .tint(DS.Palette.marone)
    }
}
