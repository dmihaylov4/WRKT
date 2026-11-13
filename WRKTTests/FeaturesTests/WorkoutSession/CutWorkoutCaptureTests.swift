import Foundation
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// Opt-in capture of the Cut workout flow from fixture values. Runs only with
/// VOLIA_CAPTURE_WORKOUT=1 (pass TEST_RUNNER_VOLIA_CAPTURE_WORKOUT=1 to xcodebuild). Writes to
/// /private/tmp/volia-cut-workout, or to VOLIA_CAPTURE_DIR when set. Run on the dedicated
/// capture simulator only.
@MainActor
struct CutWorkoutCaptureTests {
    private var root: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_DIR"] ?? "/private/tmp/volia-cut-workout")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_WORKOUT"] == "1"))
    func captureStartSheet() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let states: [(String, CutStartSheetModel)] = [
            ("start-sheet-plan", CutStartSheetFixtures.withPlan),
            ("start-sheet-no-plan", CutStartSheetFixtures.withoutPlan),
            ("start-sheet-add-exercise", CutStartSheetFixtures.addExercise)
        ]
        for (name, model) in states {
            try await capture(SheetHost { CutStartSheetView(model: model) }, name: name)
        }
        try await capture(SheetHost(dynamicType: .accessibility3) { CutStartSheetView(model: CutStartSheetFixtures.withPlan) },
                          name: "start-sheet-plan-ax")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_WORKOUT"] == "1"))
    func captureSetLogging() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for state in CutSetLoggingFixtures.states {
            try await capture(SetLoggingHost(state: state), name: "set-logging-\(state.name)",
                              scrolledName: ["mid", "bodyweight"].contains(state.name) ? "set-logging-\(state.name)-scrolled" : nil)
        }
        try await capture(SetLoggingHost(state: CutSetLoggingFixtures.states[1], dynamicType: .accessibility3),
                          name: "set-logging-mid-ax")
    }

    // MARK: - Helpers

    func capture<V: View>(_ content: V, name: String, dynamicType: DynamicTypeSize = .large,
                          wait: Duration = .seconds(2), scrolledName: String? = nil) async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = UIHostingController(
            rootView: content.environment(\.dynamicTypeSize, dynamicType)
        )
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: wait)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try #require(image.pngData()).write(to: root.appendingPathComponent(name + ".png"))

        if let scrolledName, let scroll = tallestScrollView(in: window) {
            let maxOffset = scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height
            scroll.setContentOffset(CGPoint(x: 0, y: max(-scroll.adjustedContentInset.top, maxOffset)), animated: false)
            try await Task.sleep(for: .seconds(1))
            let scrolled = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
                _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            try #require(scrolled.pngData()).write(to: root.appendingPathComponent(scrolledName + ".png"))
        }
    }

    private func tallestScrollView(in view: UIView) -> UIScrollView? {
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
}

/// Set logging as the live overview presents it: in a sheet.
struct SetLoggingHost: View {
    let state: CutSetLoggingFixtures.State
    var dynamicType: DynamicTypeSize = .large

    var body: some View {
        SheetHost(dynamicType: dynamicType) { SetLoggingStateHost(state: state) }
    }
}

private struct SetLoggingStateHost: View {
    let state: CutSetLoggingFixtures.State
    @State private var sets: [SetInput]
    @State private var active: Int

    init(state: CutSetLoggingFixtures.State) {
        self.state = state
        _sets = State(initialValue: state.sets)
        _active = State(initialValue: state.active)
    }

    var body: some View {
        CutSetLoggingView(model: state.model, sets: $sets, activeSetIndex: $active, rest: state.rest)
    }
}

/// Presents content as a sheet over a lime-topped background, as the Train tab does.
struct SheetHost<Content: View>: View {
    /// Applied inside the sheet: a sheet does not take the presenter's Dynamic Type size.
    var dynamicType: DynamicTypeSize = .large
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            DS.Cut.Colors.lime.frame(height: 260).ignoresSafeArea()
        }
        .sheet(isPresented: .constant(true)) { content().environment(\.dynamicTypeSize, dynamicType) }
    }
}
