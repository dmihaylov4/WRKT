import Foundation
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// Opt-in captures of the Cut Cardio tab and detail. Writes to /private/tmp/volia-cut-cardio, or VOLIA_CAPTURE_DIR.
///
/// VOLIA_CAPTURE_CUT_CARDIO=1 (pass TEST_RUNNER_VOLIA_CAPTURE_CUT_CARDIO=1 to xcodebuild) renders
/// the Cut Cardio screens from fixtures, one file per state: cardio-<state>.png and
/// cardio-detail-<state>.png. Every activity type, empty, Health off, loading, syncing, long
/// names, durations over an hour, scrolled ends and accessibility Dynamic Type.
@MainActor
struct CutCardioCaptureTests {
    private typealias F = CutCardioFixtures

    private var root: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_DIR"] ?? "/private/tmp/volia-cut-cardio")
    }

    /// Long names and sessions over an hour.
    private static var longRuns: [Run] {
        [
            F.run("Sunday Long Run Along the River Through Both Parks and Back Home", day: 0, km: 24.6, seconds: 8_412),
            F.run("Marathon Pace Progression With Strides", day: -2, km: 18.2, seconds: 5_530),
            F.run("Recovery", day: -3, km: 6.0, seconds: 2_230)
        ]
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_CUT_CARDIO"] == "1"))
    func captureFixtureStates() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let tabs: [(String, CutCardioTabModel, Bool)] = [
            ("running", F.tab(), false),
            ("running-rows", F.tab(), true),
            ("walking", F.tab(type: .walking), false),
            ("cycling", F.tab(type: .cycling), false),
            ("other", F.tab(type: .other), false),
            ("past-week-empty", F.tab(week: 2), false),
            ("empty", F.tab([], connection: .connected), false),
            ("health-off", F.tab([], connection: .disconnected), false),
            ("health-off-with-data", F.tab(connection: .disconnected), false),
            ("loading", F.tab(nil), false),
            ("syncing", F.tab(syncing: true), false),
            ("long", F.tab(Self.longRuns), false),
            ("long-rows", F.tab(Self.longRuns), true)
        ]
        for (name, model, bottom) in tabs {
            try await capture(.tab(model), scrolledToBottom: bottom, to: root.appendingPathComponent("cardio-\(name).png"))
        }
        try await capture(.tab(F.tab()), dynamicType: .xxxLarge, to: root.appendingPathComponent("cardio-running-xxxl.png"))
        try await capture(.tab(F.tab(Self.longRuns)), dynamicType: .xxxLarge, scrolledToBottom: true,
                          to: root.appendingPathComponent("cardio-long-rows-xxxl.png"))

        var longNamed = F.fullRun
        longNamed.workoutName = "Sunday Long Run Along the River Through Both Parks"
        longNamed.distanceKm = 24.6
        longNamed.durationSec = 8_412
        var bare = F.run("Lunch Run", day: -1, km: 5, seconds: 1_600, heartRate: nil)
        bare.calories = nil
        let rowing = F.run(nil, type: "Rowing", day: -1, km: 0, seconds: 3_900)
        let details: [(String, CutCardioDetailModel, Bool?)] = [
            ("full", F.detail(), false),
            ("full-bottom", F.detail(), true),
            ("full-middle", F.detail(), nil),
            ("no-route", CutCardioLogic.detail(bare, zones: [], hrSamples: nil, now: F.now, calendar: F.calendar, locale: F.locale), false),
            ("long", F.detail(longNamed), false),
            ("other", CutCardioLogic.detail(rowing, zones: [], hrSamples: nil, now: F.now, calendar: F.calendar, locale: F.locale), false)
        ]
        for (name, model, bottom) in details {
            try await capture(.detail(model), anchor: bottom.map { $0 ? .bottom : .top } ?? .center, to: root.appendingPathComponent("cardio-detail-\(name).png"))
        }
        try await capture(.detail(F.detail(longNamed)), dynamicType: .xxxLarge,
                          to: root.appendingPathComponent("cardio-detail-long-xxxl.png"))
        try await capture(.detail(F.detail()), dynamicType: .xxxLarge, scrolledToBottom: true,
                          to: root.appendingPathComponent("cardio-detail-bottom-xxxl.png"))
    }

    // MARK: Helpers

    private func capture(_ screen: CutCardioCaptureShell.Screen, dynamicType: DynamicTypeSize = .large,
                         scrolledToBottom: Bool = false, to url: URL) async throws {
        try await capture(screen, dynamicType: dynamicType, anchor: scrolledToBottom ? .bottom : .top, to: url)
    }

    private func capture(_ screen: CutCardioCaptureShell.Screen, dynamicType: DynamicTypeSize = .large,
                         anchor: UnitPoint, to url: URL) async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = UIHostingController(
            rootView: CutCardioCaptureShell(screen: screen)
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

/// The Cardio screens as the app shell hosts them: inside a NavigationStack in the fourth tab
/// of a system tab bar.
private struct CutCardioCaptureShell: View {
    enum Screen {
        case tab(CutCardioTabModel)
        case detail(CutCardioDetailModel)
    }

    let screen: Screen
    @State private var tab = 3

    var body: some View {
        TabView(selection: $tab) {
            Tab("Train", image: "tab-train-inactive", value: 0) { Color.black }
            Tab("Plan", image: "tab-plan-inactive", value: 1) { Color.black }
            Tab("Social", image: "tab-social-inactive", value: 2) { Color.black }
            Tab("Cardio", image: "tab-cardio", value: 3) {
                NavigationStack { content }
            }
            Tab("Me", image: "tab-profile-inactive", value: 4) { Color.black }
        }
        .tint(DS.Palette.marone)
    }

    @ViewBuilder
    private var content: some View {
        switch screen {
        case .tab(let model):
            CutCardioView(model: model)
                .toolbar(.hidden, for: .navigationBar)
        case .detail(let model):
            CutCardioDetailView(model: model) {
                // Stands in for the route map: the host draws the real one.
                Rectangle()
                    .fill(DS.Cut.Colors.darkField)
                    .overlay(Image(systemName: "map").font(.system(size: 34)).foregroundStyle(DS.Cut.Colors.textSecondary))
            }
            .navigationTitle(model.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Share workout", systemImage: "square.and.arrow.up") {}
                    } label: {
                        Label("More", systemImage: "ellipsis")
                    }
                }
            }
        }
    }
}
