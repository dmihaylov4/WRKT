//
//  CutPlanWeekHost.swift
//  WRKT
//
//  Feeds CutPlanWeekView from what the legacy MonthHeader banners read: the weekly goal streak
//  and the selected week's progress and freeze state (from CutPlanHost), and the last four
//  weeks of push and pull volume (the same query as PushPullBanner). Dismissing the push and
//  pull note lasts while the page is open, as before.
//

import SwiftUI
import SwiftData

struct CutPlanWeekHost: View {
    let streak: Int
    let progress: WeeklyProgress?
    let isFrozen: Bool
    let currentWeekStart: Date?

    @Query private var pushPull: [PushPullBalance]
    @State private var balanceDismissed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(streak: Int, progress: WeeklyProgress?, isFrozen: Bool, currentWeekStart: Date?) {
        self.streak = streak
        self.progress = progress
        self.isFrozen = isFrozen
        self.currentWeekStart = currentWeekStart
        let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -4, to: .now) ?? .distantPast
        _pushPull = Query(
            filter: #Predicate<PushPullBalance> { $0.weekStart >= cutoff },
            sort: \PushPullBalance.weekStart,
            order: .forward
        )
    }

    var body: some View {
        CutPlanWeekView(model: model) {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { balanceDismissed = true }
        }
        .workoutDetailScrollEdge()
        .navigationTitle(Text(verbatim: ""))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var model: CutPlanWeekModel {
        let recent = pushPull.suffix(4)
        let input = CutPlanWeekInput(
            streak: streak,
            progress: progress.map {
                .init(weekStart: $0.weekStart, strengthDone: $0.strengthDaysDone, strengthTarget: $0.strengthTarget,
                      cardioMinutes: $0.mvpaDone, cardioTarget: $0.mvpaTarget)
            },
            isFrozen: isFrozen,
            currentWeekStart: currentWeekStart,
            pushVolume: balanceDismissed ? 0 : recent.reduce(0) { $0 + $1.pushVolume },
            pullVolume: balanceDismissed ? 0 : recent.reduce(0) { $0 + $1.pullVolume }
        )
        return CutPlanWeekLogic.model(input, calendar: .current)
    }
}
