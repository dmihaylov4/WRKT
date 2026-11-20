import Foundation
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// Opt-in capture of the Train tab's Last workout row and the past workouts sheet from fixture
/// values. Runs only with VOLIA_CAPTURE_PAST_WORKOUTS=1 (pass
/// TEST_RUNNER_VOLIA_CAPTURE_PAST_WORKOUTS=1 to xcodebuild). Writes to
/// /private/tmp/volia-past-workouts, or to VOLIA_CAPTURE_DIR when set:
///   train-<state>.png        no plan hero with and without a workout to repeat
///   sheet-<count>-<page>.png the sheet with one, two or three workouts at a page
///   sheet-long(-bottom).png  sixteen exercises, at the top and scrolled to the end
///   sheet-mixed.png          warm-up, distance and timed sets
///   sheet-ax(-bottom).png    accessibility text size
@MainActor
@Suite(.serialized)
struct CutPastWorkoutsCaptureTests {
    nonisolated static let names = [
        "train-repeatable", "train-plain", "train-repeatable-ax",
        "sheet-1", "sheet-2-first", "sheet-2-last", "sheet-3-first", "sheet-3-middle", "sheet-3-last",
        "sheet-3-first-lb", "sheet-long", "sheet-long-bottom", "sheet-mixed", "sheet-ax", "sheet-ax-bottom"
    ]

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_PAST_WORKOUTS"] == "1"), arguments: names)
    func capture(_ name: String) async throws {
        let deadline = Date().addingTimeInterval(10)
        while UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).isEmpty, Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_DIR"] ?? "/private/tmp/volia-past-workouts")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let previous = scene.windows.first { $0.isKeyWindow }; previous?.isHidden = true
        let window = UIWindow(windowScene: scene)
        let size: DynamicTypeSize = name.hasPrefix("train") ? .accessibility3 : .accessibility5
        let dynamicType = name.contains("-ax") ? size : .large
        window.rootViewController = UIHostingController(rootView: sceneView(name, dynamicType: dynamicType)
            .environment(\.dynamicTypeSize, dynamicType).preferredColorScheme(.dark))
        window.overrideUserInterfaceStyle = .dark
        window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.isHidden = false; previous?.makeKey() }
        try await Task.sleep(for: .seconds(3))
        if name.hasSuffix("-bottom"), let scroll = largestScroll(window) {
            for _ in 0..<3 {
                let bottom = max(-scroll.adjustedContentInset.top,
                                 scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height)
                scroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
                try await Task.sleep(for: .milliseconds(300))
            }
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let rendered = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try #require(rendered.pngData()).write(to: directory.appendingPathComponent(name + ".png"))
    }

    private typealias F = CutPastWorkoutsFixtures

    private func sceneView(_ name: String, dynamicType: DynamicTypeSize) -> AnyView {
        if name.hasPrefix("train") {
            return AnyView(train(repeatable: name != "train-plain"))
        }
        let (model, index) = sheet(name)
        return AnyView(train(repeatable: true).sheet(isPresented: .constant(true)) {
            CutPastWorkoutsView(model: model, initialIndex: index).environment(\.dynamicTypeSize, dynamicType)
        })
    }

    private func sheet(_ name: String) -> (CutPastWorkoutsModel, Int) {
        switch name {
        case "sheet-1": (F.model([F.fullBody()]), 0)
        case "sheet-2-first": (F.model([F.fullBody(), F.upperBody()]), 0)
        case "sheet-2-last": (F.model([F.fullBody(), F.upperBody()]), 1)
        case "sheet-3-middle": (F.three, 1)
        case "sheet-3-last": (F.three, 2)
        case "sheet-3-first-lb": (F.model([F.fullBody(), F.upperBody(), F.lowerBody()], unit: .lb), 0)
        case "sheet-long", "sheet-long-bottom": (F.model([F.long(), F.fullBody()]), 0)
        case "sheet-mixed": (F.model([F.lowerBody()]), 0)
        default: (F.three, 0)
        }
    }

    /// The Train tab as the app shell hosts it, in the no plan state with the three rows.
    private func train(repeatable: Bool) -> some View {
        let lastDate = Calendar.current.date(byAdding: .day, value: -2, to: .now) ?? .now
        let model = CutTrainModel(
            hero: .noPlan,
            weeklyGoal: CutTrainFixtures.goal,
            rows: CutTrainLogic.rows(battle: nil, streakWeeks: 6, lastWorkout: ("Full Body", lastDate),
                                     lastWorkoutOpensPastWorkouts: repeatable)
        )
        return TabView {
            Tab("Train", image: "tab-train") {
                NavigationStack {
                    CutTrainView(model: model, actions: CutTrainActions(tappableRows: [.lastWorkout]))
                        .safeAreaInset(edge: .bottom) {
                            Color.clear.frame(height: DS.Redesign.tabBarClearance(legacy: 90, system: 70))
                        }
                        .toolbar(.hidden, for: .navigationBar)
                }
            }
            Tab("Plan", image: "tab-plan-inactive") { DS.Cut.Colors.background }
            Tab("Social", image: "tab-social-inactive") { DS.Cut.Colors.background }
            Tab("Cardio", image: "tab-cardio-inactive") { DS.Cut.Colors.background }
            Tab("Me", image: "tab-profile-inactive") { DS.Cut.Colors.background }
        }
        .tint(DS.Cut.Colors.lime)
    }

    private func largestScroll(_ view: UIView) -> UIScrollView? {
        var result: [UIScrollView] = []
        func visit(_ v: UIView) {
            if let scroll = v as? UIScrollView, scroll.contentSize.height > scroll.bounds.height { result.append(scroll) }
            v.subviews.forEach(visit)
        }
        var controller = (view as? UIWindow)?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        visit(controller?.view ?? view)
        return result.max { $0.bounds.height < $1.bounds.height }
    }
}
