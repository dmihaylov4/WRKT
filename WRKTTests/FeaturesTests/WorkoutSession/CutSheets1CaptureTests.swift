import Foundation
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// Opt-in fixtures only: no hosts, accounts, network services or mutation callbacks.
@MainActor
@Suite(.serialized)
struct CutSheets1CaptureTests {
    nonisolated static let names = [
        "start", "start-ax", "create", "create-ax", "create-ax-bottom",
        "picker", "picker-ax", "picker-ax-bottom", "info", "info-ax", "info-ax-bottom", "info-timer", "info-stats", "info-stats-ax", "info-stats-ax-bottom",
        "edit", "edit-ax", "edit-ax-bottom", "log", "log-ax", "log-ax-bottom",
        "sets", "sets-ax", "sets-ax-bottom", "detail", "detail-ax", "detail-ax-bottom",
        "logging", "logging-ax", "logging-ax-bottom", "delete", "delete-ax",
        "stack", "stack-ax", "stack-ax-bottom", "pushed-detail", "pushed-logging",
        "create-edit", "create-edit-ax", "create-edit-ax-bottom", "delete-health", "delete-health-ax"
    ]
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_SHEETS1"] == "1"), arguments: names)
    func capture(_ name: String) async throws {
        if let selected = ProcessInfo.processInfo.environment["VOLIA_CAPTURE_SHEETS1_CASE"],
           !selected.split(separator: ",").contains(Substring(name)) { return }
        let deadline = Date().addingTimeInterval(10)
        while UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).isEmpty, Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_DIR"] ?? "/private/tmp/volia-sheets-1")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let previous = scene.windows.first { $0.isKeyWindow }; previous?.isHidden = true
        let window = UIWindow(windowScene: scene)
        let size: DynamicTypeSize = name.contains("-ax") ? .accessibility5 : .large
        window.rootViewController = UIHostingController(rootView: sceneView(name).environment(\.dynamicTypeSize, size).preferredColorScheme(.dark))
        window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.isHidden = false; previous?.makeKey() }
        try await Task.sleep(for: .seconds(3))
        if name.hasPrefix("info-stats") {
            #expect(try #require(largestScroll(window, requiringOverflow: false)).bounds.height > 100)
        }
        if name.hasSuffix("-bottom"), let scroll = largestScroll(window) {
            // Native List estimates offscreen row heights. Settle those estimates before
            // recording the footer, especially when accessibility rows become much taller.
            for _ in 0..<4 {
                let bottom = max(-scroll.adjustedContentInset.top, scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height)
                scroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
                try await Task.sleep(for: .milliseconds(250))
            }
        }
        let rendered = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        try #require(rendered.pngData()).write(to: directory.appendingPathComponent(name + ".png"))
        if let path = ProcessInfo.processInfo.environment["VOLIA_CAPTURE_SIGNALS"] {
            let signals = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: signals, withIntermediateDirectories: true)
            try Data().write(to: signals.appendingPathComponent(name + ".ready"))
            let acknowledgement = signals.appendingPathComponent(name + ".ack")
            let deadline = Date().addingTimeInterval(30)
            while !FileManager.default.fileExists(atPath: acknowledgement.path), Date() < deadline {
                try await Task.sleep(for: .milliseconds(100))
            }
            #expect(FileManager.default.fileExists(atPath: acknowledgement.path))
        }
    }
    private func sceneView(_ name: String) -> AnyView {
        if name.hasPrefix("pushed-") {
            return AnyView(CutSheets1PushedFixture(destination: AnyView(sheet(name))))
        }
        if name.hasPrefix("stack") {
            return AnyView(presenter.sheet(isPresented: .constant(true)) {
                sheet("detail").environment(\.dynamicTypeSize, size(name)).sheet(isPresented: .constant(true)) {
                    sheet("edit").environment(\.cutSheetDepth, 1).environment(\.dynamicTypeSize, size(name))
                        .sheet(isPresented: .constant(true)) {
                            sheet("picker").environment(\.cutSheetDepth, 2).environment(\.dynamicTypeSize, size(name))
                        }
                }
            })
        }
        if name.hasPrefix("picker") || name.hasPrefix("sets") {
            return AnyView(presenter.sheet(isPresented: .constant(true)) {
                sheet("edit").environment(\.dynamicTypeSize, size(name)).sheet(isPresented: .constant(true)) {
                    sheet(name)
                        .environment(\.cutSheetDepth, 1).environment(\.dynamicTypeSize, size(name))
                }
            })
        }
        if name.hasPrefix("edit") || name.hasPrefix("delete") && !name.hasPrefix("delete-health") {
            return AnyView(presenter.sheet(isPresented: .constant(true)) {
                sheet("detail").environment(\.dynamicTypeSize, size(name)).sheet(isPresented: .constant(true)) {
                    sheet(name).environment(\.cutSheetDepth, 1).environment(\.dynamicTypeSize, size(name))
                }
            })
        }
        if name.hasPrefix("create-edit") {
            return AnyView(presenter.sheet(isPresented: .constant(true)) {
                sheet("info").environment(\.dynamicTypeSize, size(name)).sheet(isPresented: .constant(true)) {
                    sheet(name).environment(\.cutSheetDepth, 1).environment(\.dynamicTypeSize, size(name))
                }
            })
        }
        if name.hasPrefix("info") {
            return AnyView(presenter.sheet(isPresented: .constant(true)) {
                sheet("logging").environment(\.dynamicTypeSize, size(name)).sheet(isPresented: .constant(true)) {
                    sheet(name).environment(\.cutSheetDepth, 1).environment(\.dynamicTypeSize, size(name))
                }
            })
        }
        if name.hasPrefix("delete-health") {
            return AnyView(NavigationStack {
                CutHealthStrengthView(model: CutWorkoutDetailFixtures.strength())
                    .sheet(isPresented: .constant(true)) { sheet(name).environment(\.dynamicTypeSize, size(name)) }
            })
        }
        if name.hasPrefix("create") {
            return AnyView(NavigationStack {
                CutExerciseBrowserView(model: CutExerciseBrowserLogic.model(exercises: CutExerciseFixtures.exercises,
                    subregion: nil, muscleFilter: nil, filters: .init(), favorites: []))
                    .sheet(isPresented: .constant(true)) { sheet(name).environment(\.dynamicTypeSize, size(name)) }
            })
        }
        if name.hasPrefix("log") && !name.hasPrefix("logging") {
            return AnyView(NavigationStack {
                CutPlanView(model: CutPlanFixtures.model(selected: CutPlanFixtures.day(5))) { EmptyView() }
                    .sheet(isPresented: .constant(true)) { sheet(name).environment(\.dynamicTypeSize, size(name)) }
            })
        }
        if name.hasPrefix("logging") {
            return AnyView(NavigationStack {
                CutLiveOverviewView(model: .init(title: "Fixture workout", startDate: CutWorkoutDetailFixtures.now,
                    summaryLine: "7 sets, 4260 kg", segments: [.current, .toDo], now: nil, nowPartners: [],
                    allDone: false, sections: [], canFinish: false), rest: .none, fixedElapsed: 120)
                    .sheet(isPresented: .constant(true)) { sheet(name).environment(\.dynamicTypeSize, size(name)) }
            })
        }
        return AnyView(presenter.sheet(isPresented: .constant(true)) { sheet(name).environment(\.dynamicTypeSize, size(name)) })
    }
    private func size(_ name: String) -> DynamicTypeSize { name.contains("-ax") ? .accessibility5 : .large }
    private var presenter: some View {
        TabView {
            Tab("Train", image: "tab-train") {
                NavigationStack {
                    CutTrainView(model: CutTrainFixtures.model(.planned(name: "Fixture workout", exerciseCount: 3)))
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
    @ViewBuilder private func sheet(_ name: String) -> some View {
        if name.hasPrefix("start") {
            CutStartSheetView(model: CutStartSheetFixtures.withPlan)
        } else if name.hasPrefix("create") {
            let form = CutCreateExerciseLogic.model(preselectedMuscle: "Chest", editing: name.hasPrefix("create-edit") ? CutExerciseFixtures.exercise("custom_fixture", "Fixture Press", muscle: "Chest", equipment: "Barbell") : nil)
            CutCreateExerciseView(model: form, change: { _ in }, save: {}, cancel: {})
        } else if name.hasPrefix("picker") {
            CutExercisePickerView(model: CutExercisePickerLogic.model(exercises: CutExerciseFixtures.exercises,
                region: .all, query: "", favorites: ["bench"], displayedCount: 50))
        } else if name.hasPrefix("info") {
            CutExerciseInfoView(model: CutExerciseInfoFixtures.model(), tab: name == "info-timer" ? .timer : name.hasPrefix("info-stats") ? .stats : .info,
                stats: {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            ForEach(0..<12) { index in Text("Fixture history \(index + 1)").cutFont(.body) }
                        }.padding(24)
                    }.background(DS.Cut.Colors.background)
                }, video: { EmptyView() }, anatomy: {
                    Text("Chest, Triceps, Shoulders").cutFont(.body).frame(minHeight: 100)
                })
        } else if name.hasPrefix("edit") {
            CutWorkoutEditorView(model: .init(dateLine: "Friday 13 Nov", isSyncedWithWatch: false, rows: fixtureRows, canSave: true), name: .constant("Fixture workout"))
        } else if name.hasPrefix("log") && !name.hasPrefix("logging") {
            CutWorkoutLogView(model: .init(dayTitle: "Friday 13 Nov", rows: fixtureRows, canSave: true, timeIssue: nil),
                name: .constant("Fixture workout"), start: .constant(CutWorkoutDetailFixtures.now), end: .constant(CutWorkoutDetailFixtures.end))
        } else if name.hasPrefix("sets") {
            CutSetEditorView(model: CutSetEditorLogic.model(CutWorkoutDetailFixtures.squat, unit: .kg))
        } else if name.hasPrefix("detail") || name == "pushed-detail" {
            CutWorkoutDetailView(model: CutWorkoutDetailFixtures.detail(), inSheet: name != "pushed-detail")
        } else if name.hasPrefix("logging") || name == "pushed-logging" {
            let state = CutSetLoggingFixtures.states[0]
            CutSetLoggingView(model: state.model, sets: .constant(state.sets), activeSetIndex: .constant(state.active), inSheet: name != "pushed-logging")
        } else {
            CutSheetConfirm("Delete workout?", message: "Your logged workout will be deleted. You can undo this.",
                primaryTitle: "Delete workout", cancelTitle: "Keep workout", confirm: {}, cancel: {})
        }
    }
    private var fixtureRows: [CutWorkoutEditorRow] {
        [.init(id: UUID(), name: "Back Squat", preview: "4 sets, 5 reps, 60-100 kg"),
         .init(id: UUID(), name: "Pull-Up", preview: "2 sets, 10-12 reps")]
    }
    private func largestScroll(_ view: UIView, requiringOverflow: Bool = true) -> UIScrollView? {
        var result: [UIScrollView] = []
        func visit(_ v: UIView) {
            if let scroll = v as? UIScrollView, !requiringOverflow || scroll.contentSize.height > scroll.bounds.height { result.append(scroll) }
            v.subviews.forEach(visit)
        }
        var controller = view.window?.rootViewController ?? (view as? UIWindow)?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        visit(controller?.view ?? view)
        return result.max { $0.bounds.height < $1.bounds.height }
    }
}

/// A real push inside a navigation stack, rather than a root styled to resemble one.
private struct CutSheets1PushedFixture: View {
    let destination: AnyView
    @State private var path: [Int] = []
    var body: some View {
        NavigationStack(path: $path) {
            Text("Fixture workout").navigationTitle("Train")
                .navigationDestination(for: Int.self) { _ in destination }
                .onAppear { if path.isEmpty { DispatchQueue.main.async { path = [1] } } }
        }
    }
}
