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
    /// The past workouts sheet, presented by its values. Presenting by item hands the sheet the
    /// values it was opened with: a Boolean flag beside a separate optional showed an empty,
    /// full-height sheet the first time, because the content was built before the values arrived.
    @State private var pastWorkouts: PastWorkoutsSheet?
    /// The hex portal in the field's cut corner (HomeHexPortalFlag: debug builds only).
    @State private var portal = HomeHexPortalCoordinator()

    private struct PastWorkoutsSheet: Identifiable {
        let id = UUID()
        let model: CutPastWorkoutsModel
    }

    private enum PlanSetupDestination: Hashable {
        case create, library
    }

    var body: some View {
        let model = model
        CutTrainView(model: model, actions: actions) {
            if HomeHexPortalLogic.isShown(for: model.hero) {
                HomeHexPortalHost(coordinator: portal, workoutBusy: hasActiveWorkout)
            }
        }
            .navigationDestination(item: $planSetup) { destination in
                switch destination {
                case .create: PlannerSetupCarouselView(launchMode: .create)
                case .library: ProgramLibraryView()
                }
            }
            .sheet(item: $pastWorkouts) { sheet in
                CutPastWorkoutsView(model: sheet.model, onStart: startPastWorkout, onCancel: { pastWorkouts = nil })
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
                lastWorkout: lastWorkout.map { (CutTrainLogic.displayName(for: $0), $0.date) },
                lastWorkoutOpensPastWorkouts: opensPastWorkouts
            )
        )
    }

    // MARK: Past workouts

    /// A workout with exercises is running: starting another would replace it.
    private var hasActiveWorkout: Bool {
        !(store.currentWorkout?.entries.isEmpty ?? true)
    }

    private func isInLibrary(_ exerciseID: String) -> Bool {
        ExerciseRepository.shared.exercise(byID: exerciseID) != nil
    }

    private var repeatableWorkouts: [CompletedWorkout] {
        CutPastWorkoutsLogic.repeatable(store.completedWorkouts, isAvailable: isInLibrary)
    }

    /// The Last workout row opens the past workouts sheet when there is a workout to repeat
    /// and none is running; otherwise it keeps opening the last workout's record.
    private var opensPastWorkouts: Bool {
        !hasActiveWorkout && !repeatableWorkouts.isEmpty
    }

    private func openPastWorkouts() {
        pastWorkouts = PastWorkoutsSheet(model: CutPastWorkoutsLogic.model(repeatableWorkouts,
                                                                           unit: WeightUnit(rawValue: weightUnitRaw) ?? .kg,
                                                                           isAvailable: isInLibrary))
    }

    /// Closes the sheet, then starts the workout the way a planned one starts (HomeViewNew's
    /// handleHeroTap): the store builds the pre-filled workout and the live workout opens.
    /// A workout that started meanwhile is never replaced; it is shown instead.
    private func startPastWorkout(_ id: UUID) {
        pastWorkouts = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard let workout = store.completedWorkouts.first(where: { $0.id == id }) else { return }
            if store.startRepeatedWorkout(workout) {
                NotificationCenter.default.post(name: .openLiveWorkoutTab, object: nil)
            } else if hasActiveWorkout {
                NotificationCenter.default.post(name: .openLiveOverlay, object: nil)
            }
        }
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
            startWorkout: {
                portal.workoutStartedAt = .now
                startWorkout()
            },
            chooseWorkout: chooseWorkout,
            browseExercises: browseExercises,
            setUpPlan: openPlanSetup,
            viewWorkout: { NotificationCenter.default.post(name: .openLiveOverlay, object: nil) },
            addExercise: chooseWorkout,
            extendRest: { RestTimerManager.shared.adjustTime(by: 15) },
            skipRest: { RestTimerManager.shared.skipTimer() },
            openRow: { kind in
                guard kind == .lastWorkout else { return }
                if opensPastWorkouts {
                    openPastWorkouts()
                } else if let workout = viewModel.getLastWorkout() {
                    openWorkoutDetail(workout)
                }
            },
            // Battle and streak were informational on the legacy tab and stay so.
            tappableRows: [.lastWorkout],
            scrollingChanged: { portal.isScrolling = $0 }
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
