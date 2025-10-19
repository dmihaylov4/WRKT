//
//  WeeklyProgressTypes.swift
//  WRKT
//// WorkoutStore+WeeklyProgress.swift
//  Created by Dimitar Mihaylov on 17.10.25.
//


import Foundation
import SwiftData

enum PaceStatus: String, Codable, Equatable {
    case ahead, onTrack, behind
}

struct WeeklyProgress: Equatable {
    // Week window
    let weekStart: Date
    let weekEnd: Date

    // Targets
    let mvpaTarget: Int               // minutes
    let strengthTarget: Int           // days

    // Actuals (this week so far)
    let mvpaDone: Int                 // minutes
    let strengthDaysDone: Int         // days

    // Derived
    let mvpaPct: Double               // 0...1
    let daysElapsedFrac: Double       // 0...1
    let expectedMinutesByNow: Int
    let expectedStrengthByNow: Int
    let minutesLeft: Int
    let strengthDaysLeft: Int
    let paceStatus: PaceStatus

    // Friendly strings you can show if you like
    var statusLine: String {
        switch paceStatus {
        case .ahead:   return "Ahead of pace"
        case .onTrack: return "On track"
        case .behind:  return "Behind pace"
        }
    }
}




extension WorkoutStore {
    /// Build this week's progress vs. goal, using your SwiftData summaries for minutes
    /// and your completedWorkouts for strength-day counting.
    func currentWeekProgress(goal: WeeklyGoal,
                             context: ModelContext,
                             healthKitMinutes: Int = 0,
                             now: Date = .now,
                             calendar: Calendar = .current) -> WeeklyProgress
    {
        // 1) Week window
        let start = calendar.startOfWeek(for: now, anchorWeekday: goal.anchorWeekday)
        let end   = calendar.date(byAdding: .day, value: 7, to: start)!

        // Fraction of the week elapsed (0...1)
        let weekSecs = end.timeIntervalSince(start)
        let secsElapsed = max(0, now.timeIntervalSince(start))
        let daysFrac = min(max(secsElapsed / weekSecs, 0), 1)

        // 2) Minutes done so far this week (from WeeklyTrainingSummary + HealthKit runs)
        //    (If your aggregator writes one row per week, this sums them anyway.)
        let fdMinutes = FetchDescriptor<WeeklyTrainingSummary>(
            predicate: #Predicate { $0.weekStart >= start && $0.weekStart < end }
        )
        let weeklyRows = (try? context.fetch(fdMinutes)) ?? []
        let minutesFromSummaries = weeklyRows.reduce(0) { $0 + $1.minutes }

        // Add HealthKit runs/walks that fall within this week
        let mvpaFromRuns = runs
            .filter { $0.date >= start && $0.date < end }
            .reduce(0) { $0 + ($1.durationSec / 60) }  // convert seconds to minutes

        // Add Apple Watch exercise minutes (MVPA) if provided
        let mvpaDone = minutesFromSummaries + mvpaFromRuns + healthKitMinutes

        // 3) Strength days done so far this week (distinct calendar days with any working set)
        let strengthDaysSet: Set<Date> = Set(
            completedWorkouts
                .filter { $0.date >= start && $0.date < end }
                .compactMap { w in
                    let didStrength = w.entries.contains { e in
                        e.sets.contains { $0.tag == .working && $0.reps > 0 }
                    }
                    return didStrength ? calendar.startOfDay(for: w.date) : nil
                }
        )
        let strengthDone = strengthDaysSet.count

        // 4) Targets
        let mvpaTarget = max(0, goal.targetActiveMinutes)
        let strengthTarget = max(0, goal.targetStrengthDays)

        // 5) Expected-by-now pace line (evenly spread through the week)
        let expectedM = Int(round(Double(mvpaTarget) * daysFrac))
        // For strength days, floor feels more fair (don’t expect a fraction of a day)
        let expectedS = min(strengthTarget, Int(floor(Double(strengthTarget) * daysFrac + 1e-6)))

        // 6) Left to hit the goal
        let minutesLeft = max(0, mvpaTarget - mvpaDone)
        let strengthLeft = max(0, strengthTarget - strengthDone)

        // 7) % complete and status with small grace
        let mvpaPct = (mvpaTarget > 0) ? min(1, Double(mvpaDone) / Double(mvpaTarget)) : 1
        let graceMinutes = 10  // don't penalize a small shortfall early in the week
        let graceDays    = 1   // similar grace for strength days
        let aheadM  = mvpaDone >= expectedM + graceMinutes
        let aheadS  = strengthDone >= expectedS + graceDays
        let behindM = mvpaDone  < max(0, expectedM - graceMinutes)
        let behindS = strengthDone < max(0, expectedS - graceDays)

        let status: PaceStatus = (aheadM || aheadS) ? .ahead : ((behindM || behindS) ? .behind : .onTrack)

        return WeeklyProgress(
            weekStart: start,
            weekEnd: end,
            mvpaTarget: mvpaTarget,
            strengthTarget: strengthTarget,
            mvpaDone: mvpaDone,
            strengthDaysDone: strengthDone,
            mvpaPct: mvpaPct,
            daysElapsedFrac: daysFrac,
            expectedMinutesByNow: expectedM,
            expectedStrengthByNow: expectedS,
            minutesLeft: minutesLeft,
            strengthDaysLeft: strengthLeft,
            paceStatus: status
        )
    }
}
