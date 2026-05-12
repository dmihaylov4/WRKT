import Testing
@testable import WRKT

struct WeeklyProgressPresentationTests {

    @Test func completedGoalUsesCompleteChipText() {
        let presentation = weeklyProgressGoalPresentation(
            completed: 3,
            target: 3,
            unitLabel: "workouts"
        )

        #expect(presentation.state == .complete)
        #expect(presentation.trailingText == "Complete")
        #expect(presentation.showsIcon == false)
    }

    @Test func incompleteGoalKeepsNumericProgressText() {
        let presentation = weeklyProgressGoalPresentation(
            completed: 2,
            target: 3,
            unitLabel: "workouts"
        )

        #expect(presentation.state == .inProgress)
        #expect(presentation.trailingText == "2/3 workouts")
    }

    @Test func completionFooterUsesBrandLanguage() {
        #expect(weeklyProgressCompletionMessage(strengthComplete: true, cardioComplete: true) == "All goals locked in")
        #expect(weeklyProgressCompletionMessage(strengthComplete: true, cardioComplete: false) == "Strength complete")
        #expect(weeklyProgressCompletionMessage(strengthComplete: false, cardioComplete: true) == "Cardio complete")
        #expect(weeklyProgressCompletionMessage(strengthComplete: false, cardioComplete: false) == nil)
    }

    @Test func planAdherenceLabelNamesScheduledProgress() {
        #expect(
            weeklyPlanAdherenceLabel(PlanAdherence(plannedSessions: 2, completedOnPlan: 0))
            == "Planned: 0/2"
        )

        #expect(
            weeklyPlanAdherenceLabel(PlanAdherence(plannedSessions: 2, completedOnPlan: 2))
            == "Plan complete"
        )
    }
}
