import Foundation
import SwiftUI
import Testing
@testable import WRKT

/// Opt-in captures of batch 8b (weekly goal, goal setup, achievements) from fixtures. Runs only
/// with VOLIA_CAPTURE_SETTINGS=1; see CutSettingsCaptureTests for the output folder.
@MainActor
struct CutMeGoalsCaptureTests {
    private typealias G = CutWeeklyGoalFixtures

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_SETTINGS"] == "1"))
    func captureWeeklyGoal() async throws {
        for (name, facts) in [("weekly-goal-mid-week", G.midWeek), ("weekly-goal-cardio-done", G.cardioDone),
                              ("weekly-goal-complete", G.complete)] {
            try await settingsCapture(CutWeeklyGoalView(model: CutWeeklyGoalLogic.model(facts)), name: name)
        }
        try await settingsCapture(CutWeeklyGoalView(model: CutWeeklyGoalLogic.model(G.midWeek)),
                                  name: "weekly-goal-ax5", dynamicType: .accessibility5)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_SETTINGS"] == "1"))
    func captureGoalSetup() async throws {
        let controls = CutWeeklyGoalSetupControls(activity: .constant(150), activityRange: 30...600,
                                                  activityStep: 15, weekStart: .constant(2))
        var draft = CutWeeklyGoalSetupDraft()
        draft.age = AgeDraft(saved: 34)
        draft.targetStrengthDays = 3
        try await settingsCapture(
            CutWeeklyGoalSetupView(model: CutWeeklyGoalSetupLogic.model(draft), controls: controls),
            name: "goal-setup-minutes")
        var steps = draft
        steps.trackingMode = .steps
        try await settingsCapture(
            CutWeeklyGoalSetupView(model: CutWeeklyGoalSetupLogic.model(steps),
                                   controls: CutWeeklyGoalSetupControls(activity: .constant(10000), activityRange: 1000...30000,
                                                                        activityStep: 500, weekStart: .constant(2))),
            name: "goal-setup-steps")
        // The onboarding sheet: the page as the root of its own stack.
        try await settingsCapture(
            NavigationStack {
                CutWeeklyGoalSetupView(model: CutWeeklyGoalSetupLogic.model(CutWeeklyGoalSetupDraft()), controls: controls)
            },
            name: "goal-setup-onboarding-sheet", pushed: false)
        try await settingsCapture(
            CutWeeklyGoalSetupView(model: CutWeeklyGoalSetupLogic.model(draft), controls: controls),
            name: "goal-setup-ax5", dynamicType: .accessibility5)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_SETTINGS"] == "1"))
    func captureDex() async throws {
        let dex = CutAchievementsDexLogic.model(items: CutDexFixtures.items, unlocked: 3, total: 8, isSearching: false)
        try await settingsCapture(CutAchievementsDexView(model: dex), name: "dex")
        try await settingsCapture(CutAchievementsDexView(model: dex), name: "dex-ax5", dynamicType: .accessibility5)
        let searching = CutAchievementsDexLogic.model(items: [], unlocked: 3, total: 8, isSearching: true)
        try await settingsCapture(CutAchievementsDexView(model: searching), name: "dex-searching")
        let detail = CutDexDetailLogic.model(CutDexFixtures.detail)
        try await settingsCapture(CutDexDetailView(model: detail) { Color.clear.frame(height: 1) }, name: "dex-detail")
        try await settingsCapture(CutDexDetailView(model: detail) { Color.clear.frame(height: 1) },
                                  name: "dex-detail-ax5", dynamicType: .accessibility5)
        var locked = CutDexFixtures.detail
        locked.unlockedAt = nil
        locked.bestE1RMKg = nil
        locked.attempt = nil
        locked.ladder = (1...12).map { ($0, nil) }
        try await settingsCapture(CutDexDetailView(model: CutDexDetailLogic.model(locked)) { Color.clear.frame(height: 1) },
                                  name: "dex-detail-locked")
    }
}
