import Foundation
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// Opt-in captures of the Cut workout records (workout detail, Apple Health strength detail,
/// edit workout, log workout, set editor) from fixture values. Runs only with
/// VOLIA_CAPTURE_RECORDS=1 (pass TEST_RUNNER_VOLIA_CAPTURE_RECORDS=1 to xcodebuild). Writes to
/// /private/tmp/volia-cut-records, or to VOLIA_CAPTURE_DIR when set. Each state is captured at the
/// top and, when it scrolls, at its middle and end.
@MainActor
struct CutWorkoutRecordsCaptureTests {
    private typealias F = CutWorkoutDetailFixtures

    private var root: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_DIR"] ?? "/private/tmp/volia-cut-records")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_RECORDS"] == "1"))
    func captureWorkoutDetail() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        var long = F.full
        long.workoutName = "Heavy Lower Body With Paused Squats and Accessories"
        long.matchedHealthKitDuration = 5_412
        long.entries.append(WorkoutEntry(exerciseID: "rdl", exerciseName: "Romanian Deadlift With Deficit and Straps",
                                         muscleGroups: ["Hamstrings"], sets: [F.set(8, 102.5, tag: .backoff, work: 42, rest: 150)]))
        long.entries.append(F.plank)

        var empty = F.bare
        empty.entries = []

        var bodyweight = F.bare
        bodyweight.entries = [F.pullUps]
        bodyweight.workoutName = "Pull-Ups"

        let states: [(String, CutWorkoutDetailModel)] = [
            ("detail-full", F.detail(sessionIDs: ["squat"])),
            ("detail-no-health", F.detail(F.bare)),
            ("detail-no-exercises", F.detail(empty)),
            ("detail-bodyweight", F.detail(bodyweight)),
            ("detail-long", F.detail(long, unit: .lb))
        ]
        for (name, model) in states {
            try await capture(PushedHost { CutWorkoutDetailView(model: model) }, name: name)
        }
        try await capture(PushedHost { CutWorkoutDetailView(model: F.detail()) }, name: "detail-full-ax5",
                          dynamicType: .accessibility5)
        try await capture(SheetHost { CutWorkoutDetailView(model: F.detail()) }, name: "detail-sheet")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_RECORDS"] == "1"))
    func captureHealthStrength() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var existing = F.bare
        existing.workoutName = "Push Day"
        let states: [(String, CutHealthStrengthModel)] = [
            ("strength-add", F.strength()),
            ("strength-added-notes", F.strength(F.strengthRun(seconds: 3_725, notes: "Felt strong. New bench single at the end."),
                                                existing: existing)),
            ("strength-minimal", F.strength(F.strengthRun(name: nil, type: "Functional Strength Training",
                                                          calories: nil, heartRate: nil)))
        ]
        for (name, model) in states {
            try await capture(PushedHost { CutHealthStrengthView(model: model) }, name: name)
        }
        try await capture(PushedHost { CutHealthStrengthView(model: F.strength()) }, name: "strength-add-ax5",
                          dynamicType: .accessibility5)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_RECORDS"] == "1"))
    func captureEditors() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let full = F.full
        var many = full
        many.entries = [F.squat, F.pullUps, F.plank, F.squat, F.pullUps]
        func editor(_ workout: CompletedWorkout, name: String, entries: [WorkoutEntry]) -> CutWorkoutEditorModel {
            CutWorkoutEditorLogic.editor(workout, name: name, entries: entries, unit: .kg, now: F.now,
                                         calendar: F.calendar, locale: F.locale)
        }
        let edits: [(String, CutWorkoutEditorModel, String)] = [
            ("edit", editor(full, name: "Lower Body", entries: full.entries), "Lower Body"),
            ("edit-changed-many", editor(many, name: "", entries: many.entries.dropLast()), ""),
            ("edit-empty", editor(CutWorkoutDetailLogic.workout(from: F.strengthRun().summary), name: "", entries: []), "")
        ]
        for (name, model, text) in edits {
            try await capture(SheetHost { NavigationStack { CutWorkoutEditorView(model: model, name: .constant(text)) } },
                              name: name)
        }
        try await capture(SheetHost(dynamicType: .accessibility5) {
            NavigationStack { CutWorkoutEditorView(model: edits[0].1, name: .constant("Lower Body")) }
        }, name: "edit-ax5")

        let start = F.end.addingTimeInterval(-3000)
        func log(_ entries: [WorkoutEntry], start: Date, end: Date) -> CutWorkoutLogModel {
            CutWorkoutEditorLogic.log(date: F.end, start: start, end: end, entries: entries, unit: .kg, now: F.now,
                                      calendar: F.calendar, locale: F.locale)
        }
        let logs: [(String, CutWorkoutLogModel, Date, Date)] = [
            ("log-empty", log([], start: start, end: F.end), start, F.end),
            ("log-filled", log([F.squat, F.pullUps], start: start, end: F.end), start, F.end),
            ("log-bad-times", log([F.squat], start: F.end, end: start), F.end, start)
        ]
        for (name, model, from, to) in logs {
            try await capture(SheetHost {
                NavigationStack {
                    CutWorkoutLogView(model: model, name: .constant(""), start: .constant(from), end: .constant(to))
                }
            }, name: name)
        }

        let sets: [(String, WorkoutEntry, WeightUnit)] = [
            ("sets", F.squat, .kg),
            ("sets-one-lb", WorkoutEntry(exerciseID: "x", exerciseName: "Romanian Deadlift", muscleGroups: [],
                                         sets: [F.set(1, 102.5)]), .lb),
            ("sets-many", WorkoutEntry(exerciseID: "x", exerciseName: "Leg Press", muscleGroups: [],
                                       sets: (0..<8).map { F.set(10, 180 + Double($0) * 10) }), .kg)
        ]
        for (name, entry, unit) in sets {
            try await capture(SheetHost { NavigationStack { CutSetEditorView(model: CutSetEditorLogic.model(entry, unit: unit)) } },
                              name: name)
        }
        try await capture(SheetHost(dynamicType: .accessibility5) {
            NavigationStack { CutSetEditorView(model: CutSetEditorLogic.model(F.squat, unit: .kg)) }
        }, name: "sets-ax5")
    }

    // MARK: - Helpers

    func capture<V: View>(_ content: V, name: String, dynamicType: DynamicTypeSize = .large) async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = UIHostingController(rootView: content.environment(\.dynamicTypeSize, dynamicType))
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .seconds(2))
        try write(window, to: name)

        guard let scroll = tallestScrollView(in: window) else { return }
        let maxOffset = scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height
        guard maxOffset > 40 else { return }
        let top = -scroll.adjustedContentInset.top
        let stops: [(String, CGFloat)] = maxOffset > scroll.bounds.height * 1.2
            ? [("mid", top + (maxOffset - top) / 2), ("end", maxOffset)]
            : [("end", maxOffset)]
        for (suffix, offset) in stops {
            scroll.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
            try await Task.sleep(for: .seconds(1))
            try write(window, to: "\(name)-\(suffix)")
        }
    }

    private func write(_ window: UIWindow, to name: String) throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try #require(image.pngData()).write(to: root.appendingPathComponent(name + ".png"))
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

/// A record pushed onto a navigation stack, as the Plan day and day detail push it.
struct PushedHost<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        NavigationStack {
            Color.black
                .navigationDestination(isPresented: .constant(true)) {
                    content()
                        .navigationTitle(Text(verbatim: ""))
                        .navigationBarTitleDisplayMode(.inline)
                }
        }
    }
}
