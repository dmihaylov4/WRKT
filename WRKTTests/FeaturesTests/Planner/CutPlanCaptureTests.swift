import Foundation
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// Opt-in captures of the Cut Plan tab. Writes to /private/tmp/volia-cut-plan, or VOLIA_CAPTURE_DIR.
///
/// VOLIA_CAPTURE_CUT_PLAN=1 (pass TEST_RUNNER_VOLIA_CAPTURE_CUT_PLAN=1 to xcodebuild) renders
/// CutPlanView from fixtures, one file per state: plan-<state>.png, plus a long workout name
/// and accessibility Dynamic Type.
///
/// VOLIA_CAPTURE_CUT_PLAN_APP=1 captures the running app's Plan tab (prefix app-cut- or
/// app-legacy- from the debug.useCut switch). With Cut on it also drives the tab through
/// VoiceOver activation: Weekly goal, a past day's Log a workout, a future day's Plan a workout,
/// Edit plan, next month and Go to today. Run on a dedicated capture simulator.
@MainActor
struct CutPlanCaptureTests {
    private typealias F = CutPlanFixtures

    private var root: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_DIR"] ?? "/private/tmp/volia-cut-plan")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_CUT_PLAN"] == "1"))
    func captureFixtureStates() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        var todayDone = F.monthFacts
        todayDone[F.day(11)] = CutPlanDayFacts(strength: [F.strength("Upper Body", minutes: 65)],
                                               planned: F.planned("Upper Body", status: .completed))
        var longName = F.monthFacts
        longName[F.day(11)] = CutPlanDayFacts(planned: F.planned("Posterior Chain and Single Leg Strength Accessories", exercises: 9))

        let states: [(String, CutPlanModel)] = [
            ("today-planned", F.model(selected: F.today)),
            ("today-done", F.model(selected: F.today, facts: todayDone)),
            ("past-strength", F.model(selected: F.day(6))),
            ("past-cardio", F.model(selected: F.day(7))),
            ("past-nothing", F.model(selected: F.day(5))),
            ("past-missed", F.model(selected: F.day(10))),
            ("future-planned", F.model(selected: F.day(13))),
            ("future-rest", F.model(selected: F.day(14))),
            ("month-no-plan", F.model(selected: F.day(1, month: 12), facts: [:], hasActivePlan: false)),
            ("today-long-name", F.model(selected: F.today, facts: longName))
        ]
        for (name, model) in states {
            try await capture(model, to: root.appendingPathComponent("plan-\(name).png"))
        }
        try await capture(F.model(selected: F.today, facts: longName), dynamicType: .accessibility3,
                          to: root.appendingPathComponent("plan-today-ax.png"))
        try await capture(F.model(selected: F.day(6)), dynamicType: .accessibility3,
                          to: root.appendingPathComponent("plan-past-strength-ax.png"))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_CUT_PLAN_APP"] == "1"))
    func captureRunningApp() async throws {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "has_completed_onboarding")
        defaults.set("9.9.9", forKey: "whats_new_last_seen_version")
        let sawTutorial = defaults.object(forKey: "tutorial_calendar")
        defaults.set(true, forKey: "tutorial_calendar")
        defer {
            if let sawTutorial { defaults.set(sawTutorial, forKey: "tutorial_calendar") } else { defaults.removeObject(forKey: "tutorial_calendar") }
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let prefix = DS.Redesign.cutEnabled ? "app-cut" : "app-legacy"

        try await Task.sleep(for: .seconds(4))
        let window = try keyWindow()
        // The shell's own route to Plan: a program invite selects the tab and opens the
        // program library, which is then popped back to the Plan root.
        let invite = AppNotification(id: UUID(), userId: UUID(), type: .programInvite, actorId: UUID(),
                                     targetId: nil, read: true, createdAt: .now, metadata: nil)
        NotificationCenter.default.post(name: .init("NavigateToNotification"), object: invite)
        try await Task.sleep(for: .seconds(3))
        if let navigation = navigationController(in: window.rootViewController), navigation.viewControllers.count > 1 {
            navigation.popToRootViewController(animated: false)
        }
        try await Task.sleep(for: .seconds(2))
        try save(window: window, to: root.appendingPathComponent("\(prefix)-plan.png"))
        guard DS.Redesign.cutEnabled else { return }

        var log: [String] = []
        func tap(_ label: String, exact: Bool = true) async throws -> Bool {
            guard let target = element(in: window, where: { node in
                guard let text = node.accessibilityLabel else { return false }
                return exact ? text == label : text.hasPrefix(label)
            }) else {
                log.append("missing: \(label)")
                return false
            }
            let activated = target.accessibilityActivate()
            log.append("\(activated ? "activated" : "not activated"): \(label)")
            try await Task.sleep(for: .seconds(2))
            return activated
        }
        func back() async throws {
            if let presented = topPresented(window) {
                presented.dismiss(animated: false)
            } else if let navigation = navigationController(in: window.rootViewController), navigation.viewControllers.count > 1 {
                navigation.popViewController(animated: false)
            }
            try await Task.sleep(for: .seconds(2))
        }

        if try await tap("Weekly goal") {
            try save(window: window, to: root.appendingPathComponent("app-cut-week.png"))
            try await back()
        }

        let calendar = Calendar.current
        let today = Date()
        func cellLabel(_ offset: Int) -> String? {
            guard let date = calendar.date(byAdding: .day, value: offset, to: today),
                  calendar.isDate(date, equalTo: today, toGranularity: .month) else { return nil }
            let weekday = calendar.weekdaySymbols[calendar.component(.weekday, from: date) - 1]
            let month = calendar.monthSymbols[calendar.component(.month, from: date) - 1]
            return "\(weekday) \(calendar.component(.day, from: date)) \(month)"
        }
        if let past = cellLabel(-2), try await tap(past, exact: false) {
            try save(window: window, to: root.appendingPathComponent("app-cut-past-day.png"))
            for action in ["Log a workout", "View day"] {
                guard try await tap(action) else { continue }
                try save(window: window, to: root.appendingPathComponent("app-cut-past-\(action.lowercased().replacingOccurrences(of: " ", with: "-")).png"))
                try await back()
                break
            }
        }
        if let future = cellLabel(3), try await tap(future, exact: false) {
            try save(window: window, to: root.appendingPathComponent("app-cut-future-day.png"))
            for action in ["Plan a workout", "Edit workout"] {
                guard try await tap(action) else { continue }
                try save(window: window, to: root.appendingPathComponent("app-cut-future-\(action.lowercased().replacingOccurrences(of: " ", with: "-")).png"))
                try await back()
                break
            }
        }
        if try await tap("Edit plan") {
            try save(window: window, to: root.appendingPathComponent("app-cut-edit-plan.png"))
            try await back()
        }
        if try await tap("Next month") {
            try save(window: window, to: root.appendingPathComponent("app-cut-next-month.png"))
            _ = try await tap("Go to today")
            try save(window: window, to: root.appendingPathComponent("app-cut-back-today.png"))
        }
        try log.joined(separator: "\n").appending("\n")
            .write(to: root.appendingPathComponent("app-cut-actions.txt"), atomically: true, encoding: .utf8)
    }

    // MARK: Helpers

    private func capture(_ model: CutPlanModel, dynamicType: DynamicTypeSize = .large, to url: URL) async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = UIHostingController(
            rootView: CutPlanCaptureShell(model: model).environment(\.dynamicTypeSize, dynamicType)
        )
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .seconds(2))
        try save(window: window, to: url)
    }

    private func keyWindow() throws -> UIWindow {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        return try #require(scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first)
    }

    /// Depth-first search of the accessibility tree (views and SwiftUI accessibility nodes).
    private func element(in root: NSObject, depth: Int = 0, where match: (NSObject) -> Bool) -> NSObject? {
        guard depth < 80 else { return nil }
        if root.isAccessibilityElement, match(root) { return root }
        var children: [NSObject] = []
        if let elements = root.accessibilityElements as? [NSObject] {
            children += elements
        } else {
            let count = root.accessibilityElementCount()
            if count != NSNotFound, count > 0 {
                children += (0..<count).compactMap { root.accessibilityElement(at: $0) as? NSObject }
            }
        }
        if let view = root as? UIView {
            children += view.subviews.filter { !$0.isHidden && $0.alpha > 0.01 }
        }
        for child in children {
            if let found = element(in: child, depth: depth + 1, where: match) { return found }
        }
        return nil
    }

    private func topPresented(_ window: UIWindow) -> UIViewController? {
        var top = window.rootViewController?.presentedViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }

    /// The deepest visible navigation controller (the selected tab's stack).
    private func navigationController(in controller: UIViewController?) -> UINavigationController? {
        guard let controller else { return nil }
        if let tabs = controller as? UITabBarController {
            return navigationController(in: tabs.selectedViewController)
        }
        for child in controller.children.reversed() where child.view.window != nil {
            if let found = navigationController(in: child) { return found }
        }
        return controller as? UINavigationController
    }

    private func save(window: UIWindow, to url: URL) throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try #require(image.pngData()).write(to: url)
    }
}

/// The Plan tab as the app shell hosts it: inside a NavigationStack in the second tab of a
/// system tab bar.
private struct CutPlanCaptureShell: View {
    let model: CutPlanModel
    @State private var tab = 1

    var body: some View {
        TabView(selection: $tab) {
            Tab("Train", image: "tab-train-inactive", value: 0) { Color.black }
            Tab("Plan", image: "tab-plan", value: 1) {
                NavigationStack {
                    CutPlanView(model: model)
                        .toolbar(.hidden, for: .navigationBar)
                }
            }
            Tab("Social", image: "tab-social-inactive", value: 2) { Color.black }
            Tab("Cardio", image: "tab-cardio-inactive", value: 3) { Color.black }
            Tab("Me", image: "tab-profile-inactive", value: 4) { Color.black }
        }
        .tint(DS.Palette.marone)
    }
}
