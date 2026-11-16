import Foundation
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// Opt-in fixture presentations. No app hosts, server callbacks or HealthKit operations.
@MainActor
@Suite(.serialized)
struct CutSheets2CaptureTests {
    nonisolated static let names = [
        "P060", "P060-ax", "P063", "P063-ax", "P064",
        "P064-ax", "P064-ax-bottom", "P064-push", "P065", "P065-ax",
        "P065-ax-bottom", "P065-new", "P065-new-ax", "P066", "P066-ax",
        "P066-ax-bottom", "P067", "P067-ax", "P072", "P072-ax",
        "P072-ax-bottom", "P073", "P073-ax", "P073-ax-bottom", "P111",
        "P111-ax", "P118", "P118-ax", "P119", "P119-ax",
        "P119-unset", "P120", "P120-ax", "P120-lb", "P120-lb-ax",
        "C-cardio", "C-cardio-ax", "C-replace", "C-replace-ax", "C-replace-ax-bottom",
        "C-restore", "C-restore-ax", "C-restore-ax-bottom"
    ]
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_SHEETS2"] == "1"), arguments: names)
    func capture(_ name: String) async throws {
        if let selected = ProcessInfo.processInfo.environment["VOLIA_CAPTURE_SHEETS2_CASE"],
           !selected.split(separator: ",").contains(Substring(name)) { return }
        let deadline = Date().addingTimeInterval(10)
        while UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).isEmpty, Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_DIR"] ?? "/private/tmp/volia-sheets-2")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let previous = scene.windows.first { $0.isKeyWindow }; previous?.isHidden = true
        let window = UIWindow(windowScene: scene)
        let size: DynamicTypeSize = name.contains("-ax") ? .accessibility5 : .large
        window.rootViewController = UIHostingController(rootView: sceneView(name).environment(\.dynamicTypeSize, size).preferredColorScheme(.dark))
        window.traitOverrides.preferredContentSizeCategory = name.contains("-ax") ? .accessibilityExtraExtraExtraLarge : .large
        window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.isHidden = false; previous?.makeKey() }
        try await Task.sleep(for: .seconds(3))
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
    private func size(_ name: String) -> DynamicTypeSize { name.contains("-ax") ? .accessibility5 : .large }

    private func sceneView(_ name: String) -> AnyView {
        if name == "P064-push" {
            return AnyView(plan.fullScreenCover(isPresented: .constant(true)) { CutSheets2BrowserPushFixture() })
        }
        if name.hasPrefix("P064") {
            return AnyView(plan.fullScreenCover(isPresented: .constant(true)) { destination(name).environment(\.dynamicTypeSize, size(name)) })
        }
        if name.hasPrefix("P072") || name.hasPrefix("P073") {
            return AnyView(plan.sheet(isPresented: .constant(true)) {
                destination("P065").environment(\.dynamicTypeSize, size(name)).sheet(isPresented: .constant(true)) {
                    destination(name).environment(\.cutSheetDepth, 1).environment(\.dynamicTypeSize, size(name))
                }
            })
        }
        let parent: AnyView
        if name.hasPrefix("P060") {
            // Service-free facsimile: SubregionDetailScreen requires repositories and stores
            // whose initializers load user data. This reproduces its legacy row context.
            parent = AnyView(CutSheets2MusclesPresenterFixture())
        } else if name.hasPrefix("P111") {
            parent = AnyView(NavigationStack { CutMeView(model: CutMeLogic.model(CutMeFixtures.full, now: CutMeFixtures.now, calendar: CutMeFixtures.calendar, locale: CutMeFixtures.locale)) })
        } else if ["P118", "P119", "P120"].contains(where: name.hasPrefix) {
            parent = AnyView(NavigationStack { CutPreferencesView(model: CutPreferencesLogic.model(CutPreferencesFixtures.signedIn), controls: .constant()) })
        } else if name.hasPrefix("C-cardio") {
            parent = AnyView(NavigationStack { CutCardioDetailView(model: CutCardioFixtures.detail()) { EmptyView() } })
        } else if name.hasPrefix("C-replace") {
            parent = AnyView(NavigationStack { CutDataPortabilityView(model: CutDataPortabilityLogic.model(isExporting: false, isImporting: false, last: nil), strategy: .constant("replace")) })
        } else if name.hasPrefix("C-restore") {
            parent = AnyView(NavigationStack { CutImportHistoryView(model: CutDataPortabilityLogic.history(CutDataPortabilityFixtures.records, isLoading: false)) })
        } else {
            parent = AnyView(plan)
        }
        return AnyView(parent.sheet(isPresented: .constant(true)) { destination(name).environment(\.dynamicTypeSize, size(name)) })
    }

    private var plan: some View {
        NavigationStack {
            CutPlanView(model: CutPlanFixtures.model(selected: CutPlanFixtures.day(5))) { EmptyView() }
        }
    }

    @ViewBuilder private func destination(_ name: String) -> some View {
        if name.hasPrefix("P060") {
            let state = CutSetLoggingFixtures.states[0]
            CutSetLoggingView(model: state.model, sets: .constant(state.sets), activeSetIndex: .constant(state.active), inSheet: true)
        } else if name.hasPrefix("P063") {
            CutStartSheetView(model: CutStartSheetFixtures.withoutPlan)
        } else if name.hasPrefix("P064") {
            NavigationStack { CutFilteredExerciseBrowserView(model: CutFilteredExerciseBrowserLogic.model(filter: .upperBody, title: "Upper Body"), select: { _ in }, done: {}) }
        } else if name.hasPrefix("P065") {
            CutPlannedEditorView(model: CutPlannedEditorLogic.model(isNew: name.contains("new"), drafts: CutPlannedEditorFixtures.drafts, plateaus: ["bench": 4], unit: .kg),
                name: .constant("Fixture workout"), date: .constant(CutPlanFixtures.day(13)))
        } else if name.hasPrefix("P066") {
            CutWorkoutLogView(model: .init(dayTitle: "Friday 13 Nov", rows: [], canSave: false, timeIssue: nil), name: .constant("Fixture workout"),
                start: .constant(CutWorkoutDetailFixtures.now), end: .constant(CutWorkoutDetailFixtures.end))
        } else if name.hasPrefix("P067") {
            CutWorkoutDetailView(model: CutWorkoutDetailFixtures.detail(), inSheet: true)
        } else if name.hasPrefix("P072") {
            CutExercisePickerView(model: CutExercisePickerLogic.model(exercises: CutExerciseFixtures.exercises, region: .all, query: "", favorites: ["bench"], displayedCount: 50))
        } else if name.hasPrefix("P073") {
            CutPlannedSetsView(model: CutPlannedEditorLogic.setsModel(CutPlannedEditorFixtures.drafts[0], unit: .kg), notes: .constant("Keep the pause controlled at the chest."))
        } else if name.hasPrefix("P111") {
            CutStreakRecoveryView(model: CutStreakRecoveryLogic.model(brokenStreak: 8))
        } else if name.hasPrefix("P118") {
            CutCreateExerciseView(model: CutCreateExerciseLogic.model(preselectedMuscle: "Chest", editing: CutExerciseFixtures.exercise("custom_fixture", "Fixture Press", muscle: "Chest", equipment: "Barbell")), change: { _ in }, save: {}, cancel: {})
        } else if name.hasPrefix("P119") {
            CutAgePickerView(saved: name.contains("unset") ? nil : 34)
        } else if name.hasPrefix("P120") {
            CutWeightPickerView(kg: 82.5, unit: name.contains("lb") ? .lb : .kg)
        } else if name.hasPrefix("C-cardio") {
            CutSheetConfirm("Delete workout?", message: "\(CutCardioFixtures.detail().deleteTitle)\n\nIt is removed from VOLIA and from Apple Health.", primaryTitle: "Delete workout", cancelTitle: "Keep workout", confirm: {}, cancel: {})
        } else if name.hasPrefix("C-replace") {
            CutSheetConfirm(CutDataPortabilityLogic.confirmTitle(.replace), message: "", primaryTitle: CutDataPortabilityLogic.confirmButton(.replace), cancelTitle: "Keep current data", confirm: {}, cancel: {})
        } else {
            let confirmation = CutDataPortabilityLogic.restoreConfirmation(records: CutDataPortabilityFixtures.records, restoring: CutDataPortabilityFixtures.records.first?.id)
            CutSheetConfirm(confirmation.title, message: confirmation.message, primaryTitle: "Restore", cancelTitle: "Keep current data", confirm: {}, cancel: {})
        }
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


private struct CutSheets2BrowserPushFixture: View {
    @State private var path: [String] = []
    var body: some View {
        NavigationStack(path: $path) {
            CutFilteredExerciseBrowserView(model: CutFilteredExerciseBrowserLogic.model(filter: .upperBody, title: "Upper Body"), select: { path.append($0) }, done: {})
                .navigationDestination(for: String.self) { _ in
                    CutExerciseBrowserView(model: CutExerciseBrowserLogic.model(exercises: CutExerciseFixtures.exercises, subregion: "Chest", muscleFilter: nil, filters: .init(), favorites: []))
                        .toolbar(.visible, for: .navigationBar)
                        .environment(\.cutSheetDepth, 1)
                }
                .onAppear { DispatchQueue.main.async { path = ["Chest"] } }
        }
    }
}

private struct CutSheets2MusclesPresenterFixture: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Filter", selection: .constant("All")) {
                    ForEach(["All", "Upper", "Mid", "Lower"], id: \.self) { Text($0) }
                }.pickerStyle(.segmented).padding(.horizontal)
                List {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Barbell Bench Press").dsFont(.body)
                        Text("Compound").font(DS.Typography.custom(size: 15, weight: .medium, relativeTo: .subheadline)).foregroundStyle(DS.Semantic.textSecondary)
                    }
                }
            }
            .navigationTitle("Chest").navigationBarTitleDisplayMode(.inline)
        }
    }
}
