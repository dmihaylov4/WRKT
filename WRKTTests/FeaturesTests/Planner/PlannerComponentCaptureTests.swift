import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import WRKT

@MainActor
struct PlannerComponentCaptureTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_PLANNER_COMPONENTS"] == "1"))
    func captureComponents() async throws {
        let phase = ProcessInfo.processInfo.environment["VOLIA_PLANNER_CAPTURE_PHASE"] ?? "after"
        try #require(["baseline", "after"].contains(phase))
        let mode = DS.Redesign.roundedShapesEnabled ? "rounded" : "legacy"
        let root = URL(fileURLWithPath: "/private/tmp/volia-shape-redesign-06/\(mode)/\(phase)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let date = Date(timeIntervalSince1970: 1_794_398_400)
        let exercise = ExerciseTemplate(exerciseID: "fixture-bench", exerciseName: "Bench Press",
            sets: 3, reps: 8, startingWeight: 60, progressionStrategy: .static)
        let template = SplitTemplate(id: "fixture", name: "Upper / Lower", shortName: "UL",
            description: "Alternate upper and lower body training.",
            days: [DayTemplate(id: "upper", name: "Upper", exercises: [exercise], isRestDay: false)],
            recommendedFrequency: 4, difficulty: .intermediate, focus: "Balanced strength", icon: "dumbbell.fill")
        let config = PlanConfig()
        config.selectedTemplate = template
        config.trainingDaysPerWeek = 4
        config.restDayPlacement = .weekends
        config.programWeeks = 8
        config.includeDeload = true
        config.startDate = Date(timeIntervalSince1970: 1_811_808_000)
        config.customSplitName = "Fixture Split"
        config.numberOfParts = 3
        config.partNames = ["Push", "Pull", "Legs"]
        config.partExercises = ["Push": [exercise]]

        try save(WeeklyStreakBanner(streak: 4), "weekly-streak", root)
        let progress = WeeklyProgress(weekStart: date, weekEnd: date.addingTimeInterval(604800),
            mvpaTarget: 150, strengthTarget: 3, mvpaDone: 90, strengthDaysDone: 2,
            mvpaPct: 0.6, daysElapsedFrac: 0.5, expectedMinutesByNow: 75,
            expectedStrengthByNow: 2, minutesLeft: 60, strengthDaysLeft: 1, paceStatus: .onTrack)
        try save(CurrentWeekProgressBanner(progress: progress, isFrozenWeek: false), "week-progress", root)
        try save(CurrentWeekProgressBanner(progress: progress, isFrozenWeek: true), "week-progress-frozen", root)
        let schema = Schema([PushPullBalance.self])
        let container = try ModelContainer(for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        container.mainContext.insert(PushPullBalance(key: "fixture", weekStart: .now,
            pushVolume: 100, pullVolume: 400, horizontalPushVolume: 100,
            horizontalPullVolume: 400, verticalPushVolume: 0, verticalPullVolume: 0))
        try container.mainContext.save()
        try await saveHosted(PushPullBanner().modelContainer(container), "push-pull", height: 180, root)

        for (name, day) in [("past", date.addingTimeInterval(-604800)), ("today", date),
                            ("future", date.addingTimeInterval(604800))] {
            try save(DayActionCard(date: day, plannedWorkout: nil, hasCompletedWorkouts: false,
                selectedAction: .constant(nil)), "day-action-" + name, root)
        }
        let planned = PlannedWorkout(scheduledDate: date, splitDayName: "Upper", exercises: [])
        try save(DayActionCard(date: date, plannedWorkout: planned, hasCompletedWorkouts: false,
            selectedAction: .constant(nil)), "day-action-planned", root)

        for selected in [false, true] {
            let suffix = selected ? "selected" : "idle"
            try save(SplitTemplateCard(template: template, isSelected: selected, onTap: {}), "template-" + suffix, root)
            try save(CreateCustomSplitCard(isSelected: selected, onTap: {}), "create-custom-" + suffix, root)
            try save(RestDayOptionCard(icon: "calendar", title: "Weekends",
                description: "Rest on Saturday and Sunday", isSelected: selected, onTap: {}), "rest-option-" + suffix, root)
            try save(FrequencyButton(days: 4, isSelected: selected, onTap: {}, onAutoAdvance: nil)
                .frame(width: 110), "frequency-" + suffix, root)
            try save(ProgramLengthButton(weeks: 8, isSelected: selected, isRecommended: true, onTap: {})
                .frame(width: 160), "length-" + suffix, root)
            try save(PartsOptionButton(number: 3, isSelected: selected, onTap: {}), "parts-" + suffix, root)
            try save(DayTab(title: "Upper", isSelected: selected, onTap: {}), "day-tab-" + suffix, root)
            try save(SelectChip(title: "All", selected: selected, tap: {}, clear: {}), "all-chip-" + suffix, root)
        }
        try save(ExerciseRowEditable(exercise: exercise, onRemove: {}, onEdit: { _, _, _ in }), "exercise-editable", root)
        try save(ExerciseRowPreview(exercise: exercise), "exercise-preview", root)
        try save(ExercisePickerCard(config: config, partName: "Push"), "exercise-picker-filled", root)
        try save(ExercisePickerCard(config: config, partName: "Pull"), "exercise-picker-empty", root)
        try await saveHosted(VStack(spacing: 12) {
            TextField("Split name", text: .constant("Fixture Split")).textFieldStyle(PlannerTextFieldStyle())
            TextField("Part name", text: .constant("Push")).textFieldStyle(PlannerTextFieldStyle())
        }, "planner-fields", height: 160, root)
        try await saveHosted(Step2TrainingFrequency(config: config, onAutoAdvance: {}), "frequency-step", height: 700, root)
        try await saveHosted(Step3RestDays(config: config, onAutoAdvance: {}), "rest-step", height: 700, root)
        try await saveHosted(Step5ProgramLength(config: config, onAutoAdvance: {}), "length-step", height: 700, root)
        try await saveHosted(Step6Review(config: config, onGenerate: {}), "review-step", height: 1100, root)
        try await saveHosted(CustomSplitStep3FrequencyAndRest(config: config, onAutoAdvance: {}),
            "custom-frequency-rest", height: 1000, root)
    }

    private func save<V: View>(_ view: V, _ name: String, _ root: URL) throws {
        // ImageRenderer evaluates leaf content without mounting lifecycle tasks.
        let renderer = ImageRenderer(content: view
            .frame(width: 370).padding(16).background(Color.black)
            .environment(\.colorScheme, .dark)
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            .environment(\.dynamicTypeSize, .large)
            .transaction { $0.disablesAnimations = true })
        renderer.scale = 2
        let data = try #require(renderer.uiImage?.pngData())
        try data.write(to: root.appendingPathComponent(name + ".png"))
    }

    private func saveHosted<V: View>(_ view: V, _ name: String, height: CGFloat, _ root: URL) async throws {
        // Native text inputs and ScrollView require a host rather than ImageRenderer.
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        let controller = UIHostingController(rootView: view.frame(width: 370).padding(16)
            .background(Color.black).environment(\.colorScheme, .dark)
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            .environment(\.dynamicTypeSize, .large)
            .transaction { $0.disablesAnimations = true }.ignoresSafeArea())
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: height)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = controller
        controller.view.backgroundColor = .black
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(350))
        controller.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        let data = renderer.pngData { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        try data.write(to: root.appendingPathComponent(name + ".png"))
    }
}
