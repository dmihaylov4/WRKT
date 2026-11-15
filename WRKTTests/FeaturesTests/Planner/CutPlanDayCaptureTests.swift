import Foundation
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// Opt-in captures of the Cut Plan pages (View day, Weekly goal, Plan workout) from fixture
/// values. Runs only with VOLIA_CAPTURE_PLAN_PAGES=1 (pass TEST_RUNNER_VOLIA_CAPTURE_PLAN_PAGES=1
/// to xcodebuild). Writes to /private/tmp/volia-cut-plan-pages, or to VOLIA_CAPTURE_DIR when set.
/// Each state is captured at the top and, when it scrolls, at its end.
@MainActor
struct CutPlanDayCaptureTests {
    private typealias F = CutPlanDayFixtures

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_PLAN_PAGES"] == "1"))
    func captureDayStates() async throws {
        let todayPlanned = F.planned()
        let busy = CutPlanDayInput(
            workouts: [F.workout(day: 6, health: true),
                       F.workout("Arms and Shoulders Finisher", day: 6, hour: 7, minute: 42, exercises: 3, sets: 9, reps: 96)],
            watchStrength: [F.watch(day: 6)],
            cardio: [F.cardio(day: 6), F.cardio("Evening ride", day: 6, km: 41.3, seconds: 5_460)],
            runCount: 3
        )
        let todayDone = CutPlanDayInput(
            workouts: [F.workout(health: true)],
            cardio: [F.cardio()],
            runCount: 1,
            planned: F.planned(status: .completed, completedID: UUID())
        )
        let long = CutPlanDayInput(
            workouts: [F.workout("Posterior Chain and Single Leg Strength Accessories", health: true)],
            runCount: 0,
            planned: F.planned("Posterior Chain and Single Leg Strength Accessories", exercises: 9)
        )
        let states: [(String, CutPlanDayModel, Bool)] = [
            ("day-today-empty", F.model(F.day(11)), false),
            ("day-today-planned", F.model(F.day(11), CutPlanDayInput(planned: todayPlanned)), true),
            ("day-today-done", F.model(F.day(11), todayDone), true),
            ("day-past-busy", F.model(F.day(6), busy), true),
            ("day-past-busy-closed", F.model(F.day(6), busy), false),
            ("day-past-missed", F.model(F.day(10), CutPlanDayInput(planned: F.planned("Pull day", status: .skipped))), false),
            ("day-past-nothing", F.model(F.day(5)), false),
            ("day-future-planned", F.model(F.day(13), CutPlanDayInput(planned: F.planned("Lower Body"))), true),
            ("day-future-empty", F.model(F.day(14)), false),
            ("day-long-names", F.model(F.day(11), long), true)
        ]
        for (name, model, expanded) in states {
            try await planPageCapture(PushedHost { CutPlanDayView(model: model, startsExpanded: expanded) }, name: name)
        }
        try await planPageCapture(PushedHost { CutPlanDayView(model: F.model(F.day(6), busy), startsExpanded: true) },
                                  name: "day-past-busy-ax5", dynamicType: .accessibility5)
        try await planPageCapture(PushedHost {
            CutPlanDayView(model: F.model(F.day(11), CutPlanDayInput(planned: todayPlanned)), startsExpanded: true)
        }, name: "day-today-planned-ax5", dynamicType: .accessibility5)
    }
}

// MARK: - Capture helpers

private var planPagesRoot: URL {
    URL(fileURLWithPath: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_DIR"] ?? "/private/tmp/volia-cut-plan-pages")
}

/// Renders `content` in a dark window at the iPhone's scale, then once more scrolled to the end
/// when the content scrolls.
@MainActor
func planPageCapture<V: View>(_ content: V, name: String, dynamicType: DynamicTypeSize = .large) async throws {
    try FileManager.default.createDirectory(at: planPagesRoot, withIntermediateDirectories: true)
    let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let window = UIWindow(windowScene: scene)
    window.windowLevel = .alert + 1
    window.overrideUserInterfaceStyle = .dark
    window.rootViewController = UIHostingController(rootView: content.environment(\.dynamicTypeSize, dynamicType))
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    try await Task.sleep(for: .seconds(2))
    try planPageWrite(window, to: name)

    guard let scroll = planPageTallestScroll(in: window) else { return }
    let maxOffset = scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height
    guard maxOffset > 40 else { return }
    scroll.setContentOffset(CGPoint(x: 0, y: maxOffset), animated: false)
    try await Task.sleep(for: .seconds(1))
    try planPageWrite(window, to: "\(name)-end")
}

@MainActor
private func planPageWrite(_ window: UIWindow, to name: String) throws {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 3
    let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
        _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
    }
    try #require(image.pngData()).write(to: planPagesRoot.appendingPathComponent(name + ".png"))
}

@MainActor
private func planPageTallestScroll(in view: UIView) -> UIScrollView? {
    var best: UIScrollView?
    func visit(_ view: UIView) {
        if let scroll = view as? UIScrollView, scroll.contentSize.height > scroll.bounds.height,
           scroll.contentSize.height - scroll.bounds.height > (best.map { $0.contentSize.height - $0.bounds.height } ?? 0) {
            best = scroll
        }
        view.subviews.forEach(visit)
    }
    visit(view)
    return best
}
