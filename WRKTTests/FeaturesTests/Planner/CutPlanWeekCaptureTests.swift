import Foundation
import SwiftUI
import Testing
@testable import WRKT

/// Opt-in captures of the Cut "Weekly goal" page (see CutPlanDayCaptureTests for the switch).
@MainActor
struct CutPlanWeekCaptureTests {
    private typealias F = CutPlanWeekFixtures

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_PLAN_PAGES"] == "1"))
    func captureWeekStates() async throws {
        let states: [(String, CutPlanWeekInput)] = [
            ("week-progress", F.input()),
            ("week-super", F.input(streak: 14, progress: F.progress(5, cardio: 180))),
            ("week-frozen", F.input(progress: F.progress(1, cardio: 20), frozen: true)),
            ("week-one-met-balance", F.input(streak: 2, progress: F.progress(4, cardio: 40), push: 1000, pull: 2600)),
            ("week-past", F.input(progress: F.progress(1, cardio: 60, week: CutPlanFixtures.day(2)))),
            ("week-streak-only", F.input(streak: 3, progress: nil)),
            ("week-empty", F.input(streak: 0, progress: nil))
        ]
        for (name, input) in states {
            try await planPageCapture(PushedHost { CutPlanWeekView(model: F.model(input)) }, name: name)
        }
        try await planPageCapture(PushedHost {
            CutPlanWeekView(model: F.model(F.input(streak: 2, progress: F.progress(4, cardio: 40), push: 1000, pull: 2600)))
        }, name: "week-ax5", dynamicType: .accessibility5)
    }
}
