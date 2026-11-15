import Foundation
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// Fixture renders, following CutWorkoutCaptureTests. Enable with
/// TEST_RUNNER_VOLIA_CAPTURE_EXERCISES=1 and TEST_RUNNER_VOLIA_CAPTURE_DIR.
/// VOLIA_CAPTURE_STATE optionally selects one fixture per app launch. With
/// VOLIA_CAPTURE_EXTERNAL=1, acknowledge each .capture-request after simctl
/// saves that named PNG, by creating .capture-complete in the output directory.
@MainActor
struct CutExerciseCaptureTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_EXERCISES"] == "1"))
    func captureExerciseScreens() async throws {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_DIR"] ?? "/private/tmp/volia-cut-exercises")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let renderer = CutExerciseCaptureRenderer()
        let exercises = CutExerciseFixtures.exercises + [
            CutExerciseFixtures.exercise("incline", "Incline Dumbbell Bench Press", muscle: "Chest", equipment: "Dumbbell"),
            CutExerciseFixtures.exercise("row", "Single Arm Bent Over Dumbbell Row", muscle: "Back", equipment: "Dumbbell"),
            CutExerciseFixtures.exercise("deadlift", "Romanian Deadlift", muscle: "Hamstrings", equipment: "Barbell")]
        func browser(_ filters: CutExerciseBrowserFilters, scope: String? = nil, region: MuscleFilter? = nil) -> CutExerciseBrowserModel {
            CutExerciseBrowserLogic.model(exercises: exercises, subregion: scope, muscleFilter: region, filters: filters,
                scopedIDs: scope == nil ? nil : Set(exercises.filter { $0.primaryMuscles.contains(scope!) }.map(\.id)),
                selectedMuscleIDs: filters.muscle == nil ? nil : Set(exercises.filter { $0.primaryMuscles.contains(filters.muscle!) }.map(\.id)),
                favorites: ["bench"])
        }
        let all = browser(.init())
        try await renderer.capture(NavigationStack { CutExerciseBrowserView(model: all) }, name: "browser-all")
        let upper = browser(.init(), region: .upperBody)
        try await renderer.capture(NavigationStack { CutExerciseBrowserView(model: upper) }, name: "browser-upper")
        let selected = browser(.init(muscle: "Chest", movement: .push), region: .upperBody)
        try await renderer.capture(NavigationStack { CutExerciseBrowserView(model: selected) }, name: "browser-upper-filtered")
        let long = browser(.init(muscle: "Hamstrings", equipment: .pullupbar, movement: .hinge), region: .lowerBody)
        try await renderer.capture(NavigationStack { CutExerciseBrowserView(model: long) }, name: "browser-long-choice")
        let scoped = browser(.init(equipment: .dumbbell), scope: "Chest", region: .upperBody)
        try await renderer.capture(NavigationStack { CutExerciseBrowserView(model: scoped) }, name: "browser-subregion")
        let noMatch = browser(.init(muscle: "Chest", equipment: .kettlebell), region: .upperBody)
        try await renderer.capture(NavigationStack { CutExerciseBrowserView(model: noMatch) }, name: "browser-filtered-no-results")
        let search = browser(.init(isSearching: true, query: "bench"))
        try await renderer.capture(NavigationStack { CutExerciseBrowserView(model: search, searchText: "bench") }, name: "browser-search")
        let none = browser(.init(isSearching: true, query: "curl"), scope: "Chest")
        try await renderer.capture(NavigationStack {
            CutExerciseBrowserView(model: none, searchText: "curl", expandedSuggestions: ["Biceps"])
        }, name: "browser-no-results")
        let empty = CutExerciseBrowserLogic.model(exercises: [], subregion: nil, muscleFilter: nil, filters: .init(), favorites: [])
        try await renderer.capture(NavigationStack { CutExerciseBrowserView(model: empty) }, name: "browser-empty")
        try await renderer.capture(NavigationStack { CutExerciseBrowserView(model: selected) }, name: "browser-ax", dynamicType: .accessibility5)
        try await renderer.capture(CutExerciseTutorialCapture(model: selected), name: "browser-tutorial")
        let picker = CutExercisePickerLogic.model(exercises: exercises, region: .all, query: "", favorites: ["bench"], displayedCount: 50)
        try await renderer.capture(NavigationStack { CutExercisePickerView(model: picker) }, name: "picker")
        try await renderer.capture(NavigationStack { CutExercisePickerView(model: picker) }, name: "picker-ax", dynamicType: .accessibility3)
        let filtered = CutFilteredExerciseBrowserLogic.model(filter: .upperBody, title: "Upper Body Exercises")
        try await renderer.capture(NavigationStack { CutFilteredExerciseBrowserView(model: filtered, select: { _ in }, done: {}) }, name: "filtered-browser")
        var infoExercise = exercises[0]
        infoExercise.secondaryMuscles = ["Triceps", "Shoulders"]
        let info = CutExerciseInfoFixtures.model(exercise: infoExercise)
        try await renderer.capture(NavigationStack { infoView(info) }, name: "info", scrolledName: "info-scrolled")
        try await renderer.capture(CutExerciseSheetCapture { infoView(info) }, name: "info-sheet")
        try await renderer.capture(NavigationStack { infoView(info) }, name: "info-ax", dynamicType: .accessibility3, scrolledName: "info-ax-scrolled")
        try await renderer.capture(NavigationStack { infoView(info, tab: .timer) }, name: "info-timer")
        try await renderer.capture(NavigationStack {
            CutExerciseTimerView(model: .init(minutes: 2, seconds: 0, hasOverride: true), minutes: { _ in }, seconds: { _ in }, save: {}, reset: {})
        }, name: "timer")
        let create = CutCreateExerciseLogic.model(preselectedMuscle: "Chest", editing: nil)
        try await renderer.capture(NavigationStack { CutCreateExerciseView(model: create, change: { _ in }, save: {}, cancel: {}) }, name: "create")
        let edit = CutCreateExerciseLogic.model(preselectedMuscle: "", editing: infoExercise)
        try await renderer.capture(NavigationStack { CutCreateExerciseView(model: edit, change: { _ in }, save: {}, cancel: {}) }, name: "edit")
        try await renderer.capture(NavigationStack { CutCreateExerciseView(model: edit, change: { _ in }, save: {}, cancel: {}) },
            name: "edit-ax", dynamicType: .accessibility3, scrolledName: "edit-ax-scrolled")
    }

    private func infoView(_ model: CutExerciseInfoModel, tab: CutExerciseInfoModel.Tab = .info) -> some View {
        CutExerciseInfoView(model: model, tab: tab, stats: { Text("Statistics") }, video: { EmptyView() }, anatomy: {
            HStack(spacing: 12) {
                SVGHumanBodyView(side: .front, focus: .full, primary: ["Chest"], secondary: ["Triceps", "Shoulders"])
                SVGHumanBodyView(side: .back, focus: .full, primary: ["Chest"], secondary: ["Triceps", "Shoulders"])
            }
            .aspectRatio(1.12, contentMode: .fit)
            .saturation(0)
        })
    }
}

private struct CutExerciseSheetCapture<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var presented = false
    var body: some View {
        Color.black.ignoresSafeArea()
            .sheet(isPresented: $presented) {
                NavigationStack { content() }
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .onAppear { presented = true }
    }
}

private struct CutExerciseTutorialCapture: View {
    let model: CutExerciseBrowserModel
    @State private var frames = CutExerciseTutorialFrames()
    var body: some View {
        NavigationStack {
            CutExerciseBrowserView(model: model,
                tutorial: frames.isReady ? CutExerciseTutorialLogic.step(0, frames: frames) : nil,
                actions: .init(frame: { frames.set($1, for: $0) }))
        }
    }
}

/// drawHierarchy can omit cached SwiftUI text on repeated captures. An opt-in
/// external capture handshake lets simctl photograph the simulator compositor.
@MainActor
private struct CutExerciseCaptureRenderer {
    private var root: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_DIR"] ?? "/private/tmp/volia-cut-exercises")
    }

    func capture<V: View>(_ content: V, name: String, dynamicType: DynamicTypeSize = .large,
                          scrolledName: String? = nil) async throws {
        if let state = ProcessInfo.processInfo.environment["VOLIA_CAPTURE_STATE"], state != name && state != scrolledName { return }
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = UIHostingController(rootView: content.environment(\.dynamicTypeSize, dynamicType))
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
        }
        try await Task.sleep(for: .seconds(2))
        try await save(window, name: name)
        if let scrolledName, let scroll = tallestScrollView(in: window) {
            let offset = scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height
            scroll.setContentOffset(CGPoint(x: 0, y: max(-scroll.adjustedContentInset.top, offset)), animated: false)
            try await Task.sleep(for: .seconds(1))
            try await save(window, name: scrolledName)
        }
    }

    private func save(_ window: UIWindow, name: String) async throws {
        if ProcessInfo.processInfo.environment["VOLIA_CAPTURE_EXTERNAL"] == "1" {
            let request = root.appendingPathComponent(".capture-request")
            let complete = root.appendingPathComponent(".capture-complete")
            try Data(name.utf8).write(to: request, options: .atomic)
            let deadline = ContinuousClock.now.advanced(by: .seconds(30))
            while !FileManager.default.fileExists(atPath: complete.path) && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(100))
            }
            try #require(FileManager.default.fileExists(atPath: complete.path), "Simulator capture was not acknowledged")
            try FileManager.default.removeItem(at: complete)
        } else {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 3
            let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            try #require(image.pngData()).write(to: root.appendingPathComponent(name + ".png"))
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
