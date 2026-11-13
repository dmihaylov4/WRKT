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
        try await capture(SheetHost { CutStartSheetView(model: CutStartSheetFixtures.withPlan).environment(\.dynamicTypeSize, .accessibility3) },
                          name: "start-sheet-plan-ax", dynamicType: .accessibility3)
    }

    // MARK: - Helpers

    func capture<V: View>(_ content: V, name: String, dynamicType: DynamicTypeSize = .large,
                          wait: Duration = .seconds(2)) async throws {
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
    }
}

/// Presents content as a sheet over a lime-topped background, as the Train tab does.
struct SheetHost<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            DS.Cut.Colors.lime.frame(height: 260).ignoresSafeArea()
        }
        .sheet(isPresented: .constant(true)) { content() }
    }
}
