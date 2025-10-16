//
//  StatsAggregator.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 15.10.25.
//


// StatsAggregator.swift
import Foundation
import SwiftData

// StatsAggregator.swift
import Foundation
import SwiftData

actor StatsAggregator {
    private let container: ModelContainer
    private let cal = Calendar.current

    init(container: ModelContainer) {
        self.container = container
    }

    // MARK: Public API (what WorkoutStore expects)

    /// One-time (or startup) reindex over a rolling window.
    func reindex(all workouts: [CompletedWorkout], cutoff: Date) async {
        let slice = workouts.filter { $0.date >= cutoff }
        await recompute(for: slice)
    }

    /// Incremental apply for a single just-finished workout.
    func apply(_ completed: CompletedWorkout) async {
        await recompute(for: [completed], merge: true)
    }

    /// Recompute specific weeks from the given source (e.g., after edits/deletes).
    func invalidate(weeks: Set<Date>, from workouts: [CompletedWorkout]) async {
        guard !weeks.isEmpty else { return }
        let starts = weeks.map { startOfWeek(for: $0) }
        let slice = workouts.filter { starts.contains(startOfWeek(for: $0.date)) }
        await recompute(for: slice, replacingWeeks: Set(starts))
    }

    // MARK: Core recompute

    /// Recompute summaries for the passed workouts.
    /// - Parameters:
    ///   - merge: if true, upsert on top of existing weeks; if false & replacingWeeks provided, old rows for those weeks are purged then written fresh.
    private func recompute(for workouts: [CompletedWorkout],
                           merge: Bool = false,
                           replacingWeeks: Set<Date> = []) async
    {
        guard !workouts.isEmpty else { return }
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false

        // Accumulators
        struct Acc {
            var volume: Double = 0
            var sessions: Set<UUID> = []
            var sets: Int = 0
            var reps: Int = 0
            var minutes: Int = 0
        }
        var byWeek: [Date: Acc] = [:]                    // weekStart -> sums
        var volByExWeek: [String: Double] = [:]          // "exID|yyyy-WW" -> volume

        // Fold
        for w in workouts {
            let weekStart = startOfWeek(for: w.date)
            var acc = byWeek[weekStart, default: .init()]
            acc.sessions.insert(w.id)
            // If you have workout duration, use it; else leave minutes at 0
            // acc.minutes += Int(w.durationMinutes)

            for e in w.entries {
                for s in e.sets where s.tag == .working && s.reps > 0 && s.weight > 0 {
                    let vol = Double(s.reps) * s.weight
                    acc.volume += vol
                    acc.sets += 1
                    acc.reps += s.reps

                    let wk = ExerciseVolumeSummary.weekKey(from: weekStart)
                    let key = "\(e.exerciseID)|\(wk)"
                    volByExWeek[key, default: 0] += vol
                }
            }
            byWeek[weekStart] = acc
        }

        // If we’re replacing certain weeks, purge those weeks first
        if !merge, !replacingWeeks.isEmpty {
            try? purgeWeeks(replacingWeeks, in: ctx)
        }

        // Upsert weekly totals
        for (weekStart, acc) in byWeek {
            let key = ExerciseVolumeSummary.weekKey(from: weekStart)
            let weekly = try? fetchOrCreateWeekly(key: key, weekStart: weekStart, in: ctx)
            weekly?.totalVolume = acc.volume
            weekly?.sessions = acc.sessions.count
            weekly?.totalSets = acc.sets
            weekly?.totalReps = acc.reps
            weekly?.minutes = acc.minutes
        }

        // Upsert per-exercise volume per week
        // Also track which keys we touched this pass for optional cleanup
        var touchedExKeys = Set<String>()
        for (key, volume) in volByExWeek {
            let parts = key.split(separator: "|")
            guard parts.count == 2 else { continue }
            let exID = String(parts[0])
            let weekKey = String(parts[1])
            let weekStart = weekStartFromWeekKey(weekKey)
            let evs = try? fetchOrCreateExerciseVolume(exID: exID, weekStart: weekStart, in: ctx)
            evs?.volume = volume
            touchedExKeys.insert(key)
        }

        // If replacing specific weeks (not merging), remove stale ExerciseVolume rows for those weeks
        if !merge, !replacingWeeks.isEmpty {
            try? purgeUntouchedExerciseVolumes(inWeeks: replacingWeeks, keepKeys: touchedExKeys, in: ctx)
        }

        try? ctx.save()
    }

    // MARK: Fetch/Upsert helpers

    private func fetchOrCreateWeekly(key: String, weekStart: Date, in ctx: ModelContext) throws -> WeeklyTrainingSummary {
        let req = FetchDescriptor<WeeklyTrainingSummary>(predicate: #Predicate { $0.key == key })
        if let existing = try ctx.fetch(req).first { return existing }
        let obj = WeeklyTrainingSummary(key: key, weekStart: weekStart, totalVolume: 0, sessions: 0, totalSets: 0, totalReps: 0, minutes: 0)
        ctx.insert(obj)
        return obj
    }

    private func fetchOrCreateExerciseVolume(exID: String, weekStart: Date, in ctx: ModelContext) throws -> ExerciseVolumeSummary {
        let wk = ExerciseVolumeSummary.weekKey(from: weekStart)
        let key = "\(exID)|\(wk)"
        let req = FetchDescriptor<ExerciseVolumeSummary>(predicate: #Predicate { $0.key == key })
        if let existing = try ctx.fetch(req).first { return existing }
        let obj = ExerciseVolumeSummary(exerciseID: exID, weekStart: weekStart, volume: 0)
        ctx.insert(obj)
        return obj
    }

    // MARK: Purge helpers (no helper calls inside #Predicate)

    private func purgeWeeks(_ weeks: Set<Date>, in ctx: ModelContext) throws {
        // Ensure these are EXACT week-start dates (same normalization you use when writing)
        let weekStarts = Array(weeks)

        // 1) Weekly totals
        let wReq = FetchDescriptor<WeeklyTrainingSummary>(
            predicate: #Predicate { weekStarts.contains($0.weekStart) }
        )
        for row in try ctx.fetch(wReq) {
            ctx.delete(row)
        }

        // 2) Per-exercise volumes
        let eReq = FetchDescriptor<ExerciseVolumeSummary>(
            predicate: #Predicate { weekStarts.contains($0.weekStart) }
        )
        for row in try ctx.fetch(eReq) {
            ctx.delete(row)
        }
    }

    private func purgeUntouchedExerciseVolumes(
        inWeeks weeks: Set<Date>,
        keepKeys: Set<String>,                // e.g. "exerciseID|YYYY-WW"
        in ctx: ModelContext
    ) throws {
        // Again, capture raw dates outside the predicate
        let weekStarts = Array(weeks)

        // Fetch only rows from those weeks (pure predicate)
        let req = FetchDescriptor<ExerciseVolumeSummary>(
            predicate: #Predicate { weekStarts.contains($0.weekStart) }
        )
        let rows = try ctx.fetch(req)

        // Then do any string/key math OUTSIDE the predicate (this is fine)
        for r in rows {
            // If you don't have a stored weekKey, it's OK to compute it here (not in predicate)
            let wk = ExerciseVolumeSummary.weekKey(from: r.weekStart)
            let key = "\(r.exerciseID)|\(wk)"
            if !keepKeys.contains(key) {
                ctx.delete(r)
            }
        }
    }

    // MARK: Date helpers

    private func startOfWeek(for date: Date) -> Date {
        cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date))!
    }

    private func weekStartFromWeekKey(_ key: String) -> Date {
        let parts = key.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let w = Int(parts[1]) else { return Date() }
        var c = DateComponents(); c.weekOfYear = w; c.yearForWeekOfYear = y
        return cal.date(from: c) ?? Date()
    }
}
