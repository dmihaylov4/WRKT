//
//  HomeWidgetPublisher.swift
//  WRKT
//
//  Writes the home screen widgets' snapshot from the values the Train tab already shows
//  (CutTrainLogic.hero, getUnifiedWeeklyStatsWithStreak) and asks WidgetKit to reload.
//  HomeWidgetSnapshotSync is a zero-size leaf in HomeViewNew: it publishes when today's state,
//  the plan, the saved workouts or the weekly goal change, when the streak updates, when the
//  day changes and when the app goes to the background. Unchanged snapshots are not rewritten.
//

import SwiftUI
import SwiftData
import WidgetKit

// MARK: - Building

enum HomeWidgetSnapshotBuilder {
    /// Today's state as the widget stores it. The rest countdown is not shown on the widget,
    /// so resting counts as in progress.
    static func today(from hero: CutTrainHero) -> HomeWidgetSnapshot.Today {
        switch hero {
        case .resting: .inProgress(name: CutTrainLogic.liveWorkoutName)
        case .live(let name, _, _, _): .inProgress(name: name)
        case .planned(let name, let count): .planned(name: name, exerciseCount: count)
        case .doneToday: .doneToday
        case .restDay: .restDay
        case .noPlan: .noPlan
        }
    }

    /// When the goal week containing `now` ends (the next week's start).
    static func weekEnd(now: Date, anchorWeekday: Int, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfWeek(for: now, anchorWeekday: anchorWeekday)
        return calendar.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(7 * 86_400)
    }

    static func snapshot(
        hero: CutTrainHero,
        outlook: PlanOutlook,
        weeklyGoal: CutTrainWeeklyGoal?,
        streakWeeks: Int?,
        anchorWeekday: Int,
        now: Date,
        calendar: Calendar = .current
    ) -> HomeWidgetSnapshot {
        HomeWidgetSnapshot(
            writtenAt: now,
            day: calendar.startOfDay(for: now),
            today: today(from: hero),
            nextSession: outlook.hasActivePlan
                ? outlook.nextSession.map { .init(name: $0.name, date: $0.date) }
                : nil,
            week: weeklyGoal.map {
                .init(strengthDone: $0.strengthDone, strengthTarget: $0.strengthTarget,
                      cardioMinutes: $0.cardioMinutes, cardioTarget: $0.cardioTarget,
                      streakWeeks: max(0, streakWeeks ?? 0),
                      weekEnd: weekEnd(now: now, anchorWeekday: anchorWeekday, calendar: calendar))
            }
        )
    }

    /// Equal apart from when it was written.
    static func sameContent(_ a: HomeWidgetSnapshot, _ b: HomeWidgetSnapshot) -> Bool {
        var a = a
        a.writtenAt = b.writtenAt
        return a == b
    }
}

// MARK: - Publishing

@MainActor
final class HomeWidgetPublisher {
    static let shared = HomeWidgetPublisher()

    private let store: HomeWidgetSnapshotStore
    private let reload: @MainActor () -> Void
    private var lastWritten: HomeWidgetSnapshot?

    init(
        store: HomeWidgetSnapshotStore = HomeWidgetSnapshotStore(),
        reload: @escaping @MainActor () -> Void = {
            for kind in HomeWidgetShared.Kind.all { WidgetCenter.shared.reloadTimelines(ofKind: kind) }
        }
    ) {
        self.store = store
        self.reload = reload
    }

    /// Writes and reloads only when the content differs from what is on disk.
    /// Returns whether it wrote.
    @discardableResult
    func publish(_ snapshot: HomeWidgetSnapshot) -> Bool {
        if let previous = lastWritten ?? store.read(), HomeWidgetSnapshotBuilder.sameContent(previous, snapshot) {
            lastWritten = previous
            return false
        }
        guard store.write(snapshot) else { return false }
        lastWritten = snapshot
        reload()
        return true
    }
}

// MARK: - Sync leaf

/// Zero-size view owned by HomeViewNew. Reads the same inputs as CutTrainHost, without the rest
/// timer (the widget does not show the countdown) and without per-set changes.
struct HomeWidgetSnapshotSync: View {
    let viewModel: HomeViewModel
    let goal: WeeklyGoal?

    @EnvironmentObject private var store: WorkoutStoreV2
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    private struct Trigger: Equatable {
        let today: HomeWidgetSnapshot.Today
        let outlook: PlanOutlook
        let isStorageLoaded: Bool
        let completedWorkouts: Int
        let runs: Int
        let goalTargets: [Int]
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .task(id: trigger) { publish() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { publish() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .weeklyStreakUpdated)) { _ in publish() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                publish()
            }
    }

    private var hero: CutTrainHero {
        CutTrainLogic.hero(
            workout: store.currentWorkout.map {
                .init(entries: $0.entries, startDate: $0.startedAt, plannedWorkoutID: $0.plannedWorkoutID)
            },
            rest: nil,
            todaysPlan: viewModel.todaysPlan.map {
                .init(id: $0.id, name: $0.splitDayName, exerciseCount: $0.exercises.count)
            },
            outlook: viewModel.planOutlook,
            unit: .kg,
            countdown: .fixed(0)
        )
    }

    private var trigger: Trigger {
        Trigger(
            today: HomeWidgetSnapshotBuilder.today(from: hero),
            outlook: viewModel.planOutlook,
            isStorageLoaded: store.isStorageLoaded,
            completedWorkouts: store.completedWorkouts.count,
            runs: store.validRuns.count,
            goalTargets: goal.map { [$0.isSet ? 1 : 0, $0.targetStrengthDays, $0.targetActiveMinutes, $0.anchorWeekday] } ?? []
        )
    }

    private func publish() {
        guard store.isStorageLoaded else { return }
        let stats = viewModel.getUnifiedWeeklyStatsWithStreak(context: context)
        let snapshot = HomeWidgetSnapshotBuilder.snapshot(
            hero: hero,
            outlook: viewModel.planOutlook,
            weeklyGoal: stats.map {
                CutTrainWeeklyGoal(strengthDone: $0.strengthCompleted, strengthTarget: $0.strengthTarget,
                                   cardioMinutes: $0.cardioMinutes, cardioTarget: $0.cardioTarget)
            },
            streakWeeks: stats?.currentStreak,
            anchorWeekday: goal?.anchorWeekday ?? 2,
            now: .now
        )
        HomeWidgetPublisher.shared.publish(snapshot)
    }
}
