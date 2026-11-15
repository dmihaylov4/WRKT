//
//  CutWeeklyGoalSetupHost.swift
//  WRKT
//
//  WeeklyGoalSetupView's state and save behind the Cut page, step for step: seeded on appear
//  from the goal (or the recommended tracking mode for a new one) and the zone calculator's
//  age; Save writes the goal (inserting a new one), commits the age only when it changed, saves
//  the context and closes. Works pushed from Me or the weekly goal page, and as the root of the
//  onboarding goal sheet.
//

import SwiftUI
import SwiftData

struct CutWeeklyGoalSetupHost: View {
    let goal: WeeklyGoal?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authService: SupabaseAuthService

    @State private var draft = CutWeeklyGoalSetupDraft()

    private typealias Logic = CutWeeklyGoalSetupLogic

    var body: some View {
        CutWeeklyGoalSetupView(model: Logic.model(draft), controls: controls, actions: CutWeeklyGoalSetupActions(
            stepAge: { delta in
                guard let next = Logic.stepped(draft.age.age, by: delta, in: AgeDraft.range) else { return }
                draft.age.age = next
                Haptics.light()
            },
            stepStrength: { delta in
                guard let next = Logic.stepped(draft.targetStrengthDays, by: delta, in: Logic.strengthRange) else { return }
                draft.targetStrengthDays = next
                Haptics.light()
            },
            save: save
        ))
        .onAppear(perform: seed)
    }

    private var controls: CutWeeklyGoalSetupControls {
        let minutesMode = draft.trackingMode == .exerciseMinutes
        let range = minutesMode ? Logic.minutesRange : Logic.stepsRange
        let step = minutesMode ? Logic.minutesStep : Logic.stepsStep
        return CutWeeklyGoalSetupControls(
            activity: Binding(
                get: { Double(minutesMode ? draft.targetMinutes : draft.targetDailySteps) },
                set: { value in
                    let snapped = Logic.snapped(value, step: step, in: range)
                    if minutesMode { draft.targetMinutes = snapped } else { draft.targetDailySteps = snapped }
                }
            ),
            activityRange: Double(range.lowerBound)...Double(range.upperBound),
            activityStep: Double(step),
            weekStart: $draft.weekStartDay
        )
    }

    private func seed() {
        draft.age = AgeDraft(saved: HRZoneCalculator.shared.userAge)
        if let g = goal {
            draft.targetMinutes = g.targetActiveMinutes
            draft.targetDailySteps = g.targetDailySteps
            draft.targetStrengthDays = g.targetStrengthDays
            draft.weekStartDay = g.anchorWeekday
            draft.trackingMode = g.mode
        } else {
            Task { draft.trackingMode = await DeviceCapability.recommendedTrackingMode() }
        }
    }

    private func save() {
        let g = goal ?? WeeklyGoal()
        Logic.apply(draft, to: g)
        if let age = draft.age.ageToCommit(confirmed: true) {
            AgeSetting.commit(age, auth: authService)
        }
        if goal == nil { context.insert(g) }
        try? context.save()
        dismiss()
    }
}
