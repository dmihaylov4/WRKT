import Foundation
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// Fixture-only captures of the pure Cut statistics views. Every value comes from
/// CutStatsFixtures; nothing reads the account, SwiftData, HealthKit or the server.
/// TEST_RUNNER_VOLIA_CAPTURE_STATS=1, TEST_RUNNER_VOLIA_CAPTURE_DIR=<directory>,
/// optional TEST_RUNNER_VOLIA_CAPTURE_STATE=<name> for one state per pass.
@MainActor
@Suite(.serialized)
struct CutStatsCaptureTests {
    nonisolated static let names = [
        "trends-default", "trends-ax5", "trends-ax5-bottom", "trends-empty", "trends-lb",
        "balance-default", "balance-ax5", "balance-ax5-bottom", "balance-empty", "balance-lb",
        "exercise-default", "exercise-ax5", "exercise-ax5-bottom", "exercise-empty", "exercise-one", "exercise-lb",
        "exercise-volume", "exercise-sheet", "exercise-sheet-stacked", "exercise-sheet-ax5",
        "log", "log-ax5", "log-stacked"
    ]
    nonisolated static var selectedNames: [String] {
        guard let raw = ProcessInfo.processInfo.environment["VOLIA_CAPTURE_STATE"] else { return names }
        let wanted = raw.split(separator: ",").map(String.init)
        precondition(wanted.allSatisfy(names.contains), "Unknown capture fixture")
        return wanted
    }
    private var root: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_DIR"] ?? "/private/tmp/volia-cut-stats")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_STATS"] == "1"), arguments: selectedNames)
    func render(_ name: String) async throws {
        let deadline = Date().addingTimeInterval(10)
        while UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).isEmpty, Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let previous = scene.windows.first { $0.isKeyWindow }
        previous?.isHidden = true
        let window = UIWindow(windowScene: scene)
        let ax = name.contains("-ax5")
        window.rootViewController = UIHostingController(rootView: fixture(name)
            .environment(\.dynamicTypeSize, ax ? .accessibility5 : .large)
            .preferredColorScheme(.dark))
        window.traitOverrides.preferredContentSizeCategory = ax ? .accessibilityExtraExtraExtraLarge : .large
        window.overrideUserInterfaceStyle = .dark
        window.windowLevel = .alert + 1
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.isHidden = false
            previous?.makeKey()
        }
        try await Task.sleep(for: .seconds(3))
        if name.hasSuffix("-bottom"), let scroll = largestScroll(window) {
            for _ in 0..<4 {
                let bottom = max(-scroll.adjustedContentInset.top,
                                 scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height)
                scroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
                try await Task.sleep(for: .milliseconds(250))
            }
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try #require(image.pngData()).write(to: root.appendingPathComponent(name + ".png"))
    }

    private func largestScroll(_ window: UIWindow) -> UIScrollView? {
        var found: [UIScrollView] = []
        func visit(_ view: UIView) {
            if let scroll = view as? UIScrollView, scroll.contentSize.height > scroll.bounds.height + 1 { found.append(scroll) }
            view.subviews.forEach(visit)
        }
        var controller = window.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        visit(controller?.view ?? window)
        return found.max { $0.bounds.height < $1.bounds.height }
    }

    // MARK: Fixtures

    private typealias F = CutStatsFixtures

    private func fixture(_ name: String) -> AnyView {
        let unit: WeightUnit = name.hasSuffix("-lb") ? .lb : .kg
        if name.hasPrefix("trends") {
            var facts = name == "trends-empty" ? CutTrendsFacts() : F.trends
            facts.unit = unit
            return pushed(CutTrendsView(model: CutTrendsLogic.model(facts, now: F.now, calendar: F.calendar, locale: F.locale)))
        }
        if name.hasPrefix("balance") {
            var facts = name == "balance-empty" ? CutBalanceFacts() : F.balance
            facts.unit = unit
            return pushed(CutBalanceView(model: CutBalanceLogic.model(facts, now: F.now, calendar: F.calendar, locale: F.locale)))
        }
        let stats: ExerciseStatistics = name == "exercise-empty" ? F.neverLogged : name == "exercise-one" ? F.oneSession : F.bench
        let model = CutExerciseStatsLogic.model(stats, unit: unit, now: F.now, calendar: F.calendar, locale: F.locale)
        let metric: CutExerciseStatsModel.Metric? = name == "exercise-volume" ? .volume : nil
        if name.hasPrefix("exercise-sheet") {
            let sheet = NavigationStack {
                CutExerciseStatsView(title: stats.exerciseName, model: model, chrome: .presented, metric: metric)
            }
            if name == "exercise-sheet-stacked" {
                // Over a workout record sheet, as from the workout detail presented as a sheet.
                return AnyView(Color.black.ignoresSafeArea().sheet(isPresented: .constant(true)) {
                    CutSheet("Push Day", kind: .browser, close: {}) { Color.clear.frame(height: 400) }
                        .sheet(isPresented: .constant(true)) { sheet.environment(\.cutSheetDepth, 1) }
                })
            }
            return AnyView(pushedExercise(model, stats: stats).sheet(isPresented: .constant(true)) { sheet })
        }
        if name.hasPrefix("log") {
            let entry = stats.history.allWorkouts[0]
            let log = CutSessionLogLogic.log(entry, exerciseName: stats.exerciseName, trackingMode: stats.trackingMode,
                                             records: model.records, unit: unit, now: F.now, calendar: F.calendar, locale: F.locale)
            if name == "log-stacked" {
                return AnyView(Color.black.ignoresSafeArea().sheet(isPresented: .constant(true)) {
                    NavigationStack { CutExerciseStatsView(title: stats.exerciseName, model: model, chrome: .presented) }
                        .sheet(isPresented: .constant(true)) {
                            CutSessionLogView(model: log, close: {}).environment(\.cutSheetDepth, 1)
                        }
                })
            }
            return AnyView(pushedExercise(model, stats: stats).sheet(isPresented: .constant(true)) {
                CutSessionLogView(model: log, close: {})
            })
        }
        return pushed(CutExerciseStatsView(title: stats.exerciseName, model: model, chrome: .pushed, metric: metric))
    }

    private func pushedExercise(_ model: CutExerciseStatsModel, stats: ExerciseStatistics) -> some View {
        NavigationStack {
            CutExerciseStatsView(title: stats.exerciseName, model: model, chrome: .pushed).toolbar(.hidden, for: .navigationBar)
        }
    }

    private func pushed<Content: View>(_ content: Content) -> AnyView {
        AnyView(NavigationStack { content.toolbar(.hidden, for: .navigationBar) })
    }
}
