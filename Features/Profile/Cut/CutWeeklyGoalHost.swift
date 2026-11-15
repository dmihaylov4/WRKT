//
//  CutWeeklyGoalHost.swift
//  WRKT
//
//  WeeklyGoalDetailView's flows behind the Cut page: the same week progress and goal it was
//  opened with, Start strength (reset Home to its root, then close), View cardio (CardioView),
//  Sync from Apple Health (the store's run import) and Edit (WeeklyGoalSetupView).
//

import SwiftUI

struct CutWeeklyGoalHost: View {
    let progress: WeeklyProgress
    let goal: WeeklyGoal

    @EnvironmentObject private var store: WorkoutStoreV2
    @Environment(\.dismiss) private var dismiss
    @State private var showsCardio = false
    @State private var showsSetup = false

    var body: some View {
        CutWeeklyGoalView(model: CutWeeklyGoalLogic.model(facts), actions: CutWeeklyGoalActions(
            startStrength: {
                AppBus.postResetHome(reason: .user_intent)
                dismiss()
            },
            viewCardio: { showsCardio = true },
            syncHealth: {
                Task { await store.importRunsFromHealth() }
            },
            edit: { showsSetup = true }
        ))
        .navigationDestination(isPresented: $showsCardio) { CardioView() }
        .navigationDestination(isPresented: $showsSetup) { WeeklyGoalSetupView(goal: goal) }
    }

    private var facts: CutWeeklyGoalFacts {
        CutWeeklyGoalFacts(
            mvpaDone: progress.mvpaDone,
            mvpaTarget: progress.mvpaTarget,
            strengthDaysDone: progress.strengthDaysDone,
            strengthTarget: progress.strengthTarget,
            minutesLeft: progress.minutesLeft,
            strengthDaysLeft: progress.strengthDaysLeft,
            paceStatus: progress.paceStatus,
            targetActiveMinutes: goal.targetActiveMinutes,
            targetStrengthDays: goal.targetStrengthDays,
            anchorWeekday: goal.anchorWeekday
        )
    }
}
