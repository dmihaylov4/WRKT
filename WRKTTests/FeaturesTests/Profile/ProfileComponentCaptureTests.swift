import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import WRKT

@MainActor
struct ProfileComponentCaptureTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_PROFILE_COMPONENTS"] == "1"))
    func captureComponents() async throws {
        let phase = ProcessInfo.processInfo.environment["VOLIA_PROFILE_CAPTURE_PHASE"] ?? "after"
        try #require(["baseline", "after"].contains(phase))
        let mode = DS.Redesign.roundedShapesEnabled ? "rounded" : "legacy"
        let root = URL(fileURLWithPath: "/private/tmp/volia-shape-redesign-07/\(mode)/\(phase)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let date = Date(timeIntervalSince1970: 1_794_398_400)

        // Plan adherence: value data only.
        let weeks = [PlanAdherence(plannedSessions: 3, completedOnPlan: 3, missedSessions: 0),
                     PlanAdherence(plannedSessions: 4, completedOnPlan: 3, missedSessions: 1),
                     PlanAdherence(plannedSessions: 3, completedOnPlan: 2, missedSessions: 1),
                     PlanAdherence(plannedSessions: 4, completedOnPlan: 2, missedSessions: 0)]
        try save(PlanAdherenceCard(weeklyAdherence: weeks, currentWeekEnded: false), "plan-adherence-ongoing", root)
        try save(PlanAdherenceCard(weeklyAdherence: weeks, currentWeekEnded: true), "plan-adherence-ended", root)

        // Progress overview card without a weekly goal (the goal branch reads RewardsEngine.shared).
        let progressSchema = Schema([RewardProgress.self])
        let progressContainer = try ModelContainer(for: progressSchema,
            configurations: ModelConfiguration(schema: progressSchema, isStoredInMemoryOnly: true))
        let progress = RewardProgress()
        progress.xp = 420
        progress.level = 4
        progress.prevLevelXP = 300
        progress.nextLevelXP = 550
        progress.weeklyGoalStreakCurrent = 3
        progressContainer.mainContext.insert(progress)
        try save(ProgressOverviewCard(level: 4, xp: 420, prevXP: 300, nextXP: 550, streak: 3, longest: 6,
            progress: progress, weekProgress: nil, goal: nil, onSettingsTapped: {})
            .modelContainer(progressContainer), "progress-overview-no-goal", root)

        // Dex tiles.
        try save(DexTile(item: DexItem(id: "bench", name: "Barbell Bench Press", short: "BB Bench",
            ruleId: "dex.bench", progress: 1, target: 1, unlockedAt: date)).frame(width: 120),
            "dex-tile-unlocked", root)
        try save(DexTile(item: DexItem(id: "squat", name: "Back Squat", short: "Back Squat",
            ruleId: "dex.squat", progress: 0, target: 1, unlockedAt: nil)).frame(width: 120),
            "dex-tile-locked", root)

        // Achievements list from an in-memory container.
        let achievementSchema = Schema([Achievement.self])
        let achievementContainer = try ModelContainer(for: achievementSchema,
            configurations: ModelConfiguration(schema: achievementSchema, isStoredInMemoryOnly: true))
        let first = Achievement(id: "fixture.first", title: "First Workout", desc: "Log your first workout", target: 1)
        first.progress = 1
        first.unlockedAt = date
        first.lastUpdatedAt = date
        let tenth = Achievement(id: "fixture.ten", title: "Ten Workouts", desc: "Log ten workouts", target: 10)
        tenth.progress = 4
        tenth.lastUpdatedAt = date.addingTimeInterval(-60)
        let volume = Achievement(id: "fixture.volume", title: "Ton Club", desc: "Lift 1,000 kg in one session", target: 1000)
        volume.progress = 650
        volume.lastUpdatedAt = date.addingTimeInterval(-120)
        for item in [first, tenth, volume] { achievementContainer.mainContext.insert(item) }
        try achievementContainer.mainContext.save()
        try await saveHosted(NavigationStack { AchievementsView() }.modelContainer(achievementContainer),
            "achievements-list", height: 820, root)

        // Training balance from an in-memory container, full and push/pull-empty variants.
        let today = Calendar.current.startOfDay(for: .now)
        let balanceSchema = Schema([PushPullBalance.self, MuscleGroupFrequency.self, MovementPatternBalance.self])
        let full = try ModelContainer(for: balanceSchema,
            configurations: ModelConfiguration(schema: balanceSchema, isStoredInMemoryOnly: true))
        full.mainContext.insert(PushPullBalance(key: "fixture", weekStart: today.addingTimeInterval(-86_400 * 3),
            pushVolume: 4200, pullVolume: 3600, horizontalPushVolume: 2600, horizontalPullVolume: 2000,
            verticalPushVolume: 1600, verticalPullVolume: 1600))
        full.mainContext.insert(MovementPatternBalance(key: "fixture", weekStart: today.addingTimeInterval(-86_400 * 3),
            compoundVolume: 6000, isolationVolume: 1800, bilateralVolume: 6500, unilateralVolume: 1300,
            hingeVolume: 2200, squatVolume: 2600))
        let empty = try ModelContainer(for: balanceSchema,
            configurations: ModelConfiguration(schema: balanceSchema, isStoredInMemoryOnly: true))
        for container in [full, empty] {
            for (name, days) in [("Chest", 1.0), ("Back", 2.0), ("Quads", 3.0), ("Shoulders", 5.0)] {
                container.mainContext.insert(MuscleGroupFrequency(muscleGroup: name,
                    lastTrained: today.addingTimeInterval(-86_400 * days), weeklyFrequency: 2, totalVolume: 3000))
            }
            try container.mainContext.save()
        }
        try await saveHosted(ScrollView { TrainingBalanceSection(weeks: 12) }.modelContainer(full),
            "training-balance-full", height: 1250, root)
        try await saveHosted(ScrollView { TrainingBalanceSection(weeks: 12) }.modelContainer(empty),
            "training-balance-empty-push-pull", height: 1100, root)
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
        // Queries, ScrollView and search fields require a host rather than ImageRenderer.
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
        try await Task.sleep(for: .milliseconds(500))
        controller.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        let data = renderer.pngData { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        try data.write(to: root.appendingPathComponent(name + ".png"))
    }
}
