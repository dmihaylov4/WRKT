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
}
