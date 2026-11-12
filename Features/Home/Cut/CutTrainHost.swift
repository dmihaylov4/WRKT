//
//  CutTrainHost.swift
//  WRKT
//
//  Feeds CutTrainView from what the Train tab already loads: HomeViewModel (today's plan,
//  carousel data, weekly stats), the workout store and the rest timer state. Owned by
//  HomeViewNew inside its NavigationStack; adds no refresh triggers of its own.
//

import SwiftUI
import SwiftData

struct CutTrainHost: View {
    let viewModel: HomeViewModel
    /// HomeViewNew's flows: start (plan or selector), selector, exercise browsing, workout detail.
    let startWorkout: () -> Void
    let chooseWorkout: () -> Void
    let browseExercises: () -> Void
    let openWorkoutDetail: (CompletedWorkout) -> Void

    @EnvironmentObject private var store: WorkoutStoreV2
    @Environment(\.modelContext) private var context
    @Environment(\.dependencies) private var deps
    /// State transitions only; the per-second countdown lives in RestTimerManager.ticker,
    /// which only the countdown leaf observes.
    @ObservedObject private var restTimer = RestTimerManager.shared
    @AppStorage("weight_unit") private var weightUnitRaw: String = WeightUnit.kg.rawValue

    @State private var planSetup: PlanSetupDestination?

    private enum PlanSetupDestination: Hashable {
        case create, library
    }

    var body: some View {
        CutTrainView(model: model, actions: actions)
            .navigationDestination(item: $planSetup) { destination in
                switch destination {
                case .create: PlannerSetupCarouselView(launchMode: .create)
                case .library: ProgramLibraryView()
                }
            }
    }

    // MARK: Model

    private var model: CutTrainModel {
        let stats = viewModel.getUnifiedWeeklyStatsWithStreak(context: context)
        let lastWorkout = viewModel.getLastWorkout()
        return CutTrainModel(
            hero: CutTrainLogic.hero(
                workout: store.currentWorkout.map {
                    .init(entries: $0.entries, startDate: $0.startedAt, plannedWorkoutID: $0.plannedWorkoutID)
                },
                rest: runningRest,
                todaysPlan: viewModel.todaysPlan.map {
                    .init(id: $0.id, name: $0.splitDayName, exerciseCount: $0.exercises.count)
                },
                outlook: viewModel.planOutlook,
                unit: WeightUnit(rawValue: weightUnitRaw) ?? .kg
            ),
            weeklyGoal: stats.map {
                CutTrainWeeklyGoal(strengthDone: $0.strengthCompleted, strengthTarget: $0.strengthTarget,
                                   cardioMinutes: $0.cardioMinutes, cardioTarget: $0.cardioTarget)
            },
            rows: CutTrainLogic.rows(
                battle: competition.map { ($0.name, $0.status) },
                streakWeeks: stats?.currentStreak,
                lastWorkout: lastWorkout.map { (CutTrainLogic.displayName(for: $0), $0.date) }
            )
        )
    }

    private var runningRest: CutTrainLogic.RunningRest? {
        guard case .running(_, let exerciseID, _, _, _) = restTimer.state else { return nil }
        return .init(exerciseID: exerciseID)
    }

    /// The legacy carousel's competition card. HomeViewModel does not load battles yet,
    /// so this is nil today and the row stays hidden.
    private var competition: CompetitionSummary? {
        for card in viewModel.carouselCards {
            if case .activeCompetition(let summary) = card { return summary }
        }
        return nil
    }

    // MARK: Actions

    private var actions: CutTrainActions {
        CutTrainActions(
            startWorkout: startWorkout,
            chooseWorkout: chooseWorkout,
            browseExercises: browseExercises,
            setUpPlan: openPlanSetup,
            viewWorkout: { NotificationCenter.default.post(name: .openLiveOverlay, object: nil) },
            addExercise: chooseWorkout,
            extendRest: { RestTimerManager.shared.adjustTime(by: 15) },
            skipRest: { RestTimerManager.shared.skipTimer() },
            openRow: { kind in
                if kind == .lastWorkout, let workout = viewModel.getLastWorkout() {
                    openWorkoutDetail(workout)
                }
            },
            // Battle and streak were informational on the legacy tab and stay so.
            tappableRows: [.lastWorkout]
        )
    }

    /// The Plan tab's header action: create a plan when none exists, else the program library.
    private func openPlanSetup() {
        let hasExistingPlans = !((try? deps.plannerStore.splitLibrary()) ?? []).isEmpty
        switch PlanHeaderAction.primaryAction(hasExistingPlans: hasExistingPlans) {
        case .createPlan: planSetup = .create
        case .openProgramLibrary: planSetup = .library
        }
    }
}
