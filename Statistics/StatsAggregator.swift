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
    private var exerciseRepo: ExerciseRepository?

    init(container: ModelContainer) {
        self.container = container
    }

    func setExerciseRepository(_ repo: ExerciseRepository) {
        self.exerciseRepo = repo
    }

    // MARK: Public API (what WorkoutStore expects)

    /// One-time (or startup) reindex over a rolling window.
    func reindex(all workouts: [CompletedWorkout], cutoff: Date) async {
        let slice = workouts.filter { $0.date >= cutoff }
        print("📊 StatsAggregator: Indexing \(slice.count) of \(workouts.count) workouts (cutoff: \(cutoff.formatted(date: .abbreviated, time: .omitted)))")
        await recompute(for: slice, allWorkouts: workouts)
    }

    /// Incremental apply for a single just-finished workout.
    func apply(_ completed: CompletedWorkout, allWorkouts: [CompletedWorkout]) async {
        await recompute(for: [completed], merge: true, allWorkouts: allWorkouts)
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
    ///   - allWorkouts: all workouts for computing muscle frequency (last 7 days). If nil, uses `workouts` parameter.
    private func recompute(for workouts: [CompletedWorkout],
                           merge: Bool = false,
                           replacingWeeks: Set<Date> = [],
                           allWorkouts: [CompletedWorkout]? = nil) async
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

        print("📊 Computed \(byWeek.count) weeks of data")

        // After computing weekly summaries, update all analytics
        await computeMovingAverages()
        await computeExerciseProgressions()
        await computeExerciseTrends()
        await computeBalanceMetrics(for: workouts, allWorkouts: allWorkouts)
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

    // MARK: - Moving Averages & Trend Analysis

    /// Compute moving averages, standard deviations, and trend analysis for all weeks
    func computeMovingAverages(window: Int = 4) async {
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false

        // Fetch all weekly summaries, sorted by date
        let req = FetchDescriptor<WeeklyTrainingSummary>(
            sortBy: [SortDescriptor(\WeeklyTrainingSummary.weekStart, order: .forward)]
        )
        guard let allWeeks = try? ctx.fetch(req), !allWeeks.isEmpty else { return }

        // Calculate personal average (all-time average volume)
        let totalVolume = allWeeks.reduce(0.0) { $0 + $1.totalVolume }
        let personalAvg = totalVolume / Double(allWeeks.count)

        // Calculate standard deviation for all data
        let variance = allWeeks.reduce(0.0) { $0 + pow($1.totalVolume - personalAvg, 2) }
        let globalStdDev = sqrt(variance / Double(allWeeks.count))

        var previousVolume: Double?

        // For each week, compute moving average
        for (index, week) in allWeeks.enumerated() {
            let key = ExerciseVolumeSummary.weekKey(from: week.weekStart)

            // Get window of weeks (up to `window` weeks including current)
            let startIdx = max(0, index - window + 1)
            let windowWeeks = Array(allWeeks[startIdx...index])

            // Calculate 4-week moving average
            let windowVolume = windowWeeks.reduce(0.0) { $0 + $1.totalVolume }
            let fourWeekAvg = windowVolume / Double(windowWeeks.count)

            // Calculate standard deviation for the window
            let windowAvg = fourWeekAvg
            let windowVariance = windowWeeks.reduce(0.0) { $0 + pow($1.totalVolume - windowAvg, 2) }
            let stdDev = sqrt(windowVariance / Double(windowWeeks.count))

            // Calculate percent change from previous week
            var percentChange: Double = 0.0
            if let prev = previousVolume, prev > 0 {
                percentChange = ((week.totalVolume - prev) / prev) * 100.0
            }
            previousVolume = week.totalVolume

            // Check if above personal average
            let isAboveAverage = week.totalVolume > personalAvg

            // Create or update MovingAverage record
            let ma = try? fetchOrCreateMovingAverage(key: key, weekStart: week.weekStart, in: ctx)
            ma?.fourWeekAvg = fourWeekAvg
            ma?.stdDev = stdDev
            ma?.personalAvg = personalAvg
            ma?.percentChange = percentChange
            ma?.isAboveAverage = isAboveAverage
        }

        try? ctx.save()

        print("📈 Moving averages: \(allWeeks.count) weeks, avg \(Int(personalAvg)) volume")
    }

    private func fetchOrCreateMovingAverage(key: String, weekStart: Date, in ctx: ModelContext) throws -> MovingAverage {
        let req = FetchDescriptor<MovingAverage>(predicate: #Predicate { $0.key == key })
        if let existing = try ctx.fetch(req).first { return existing }
        let obj = MovingAverage(key: key, weekStart: weekStart, fourWeekAvg: 0, stdDev: 0, personalAvg: 0, percentChange: 0, isAboveAverage: false)
        ctx.insert(obj)
        return obj
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

    // MARK: - Exercise-Level Progression Tracking (Priority 2)

    /// Compute detailed per-exercise progression metrics for all exercises
    func computeExerciseProgressions() async {
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false

        // Fetch all exercise volume summaries
        let req = FetchDescriptor<ExerciseVolumeSummary>(
            sortBy: [SortDescriptor(\.weekStart, order: .forward)]
        )
        guard let allExVolumes = try? ctx.fetch(req), !allExVolumes.isEmpty else {
            print("📊 No exercise volumes to process for progressions")
            return
        }

        // Group by exercise and week
        var byExerciseWeek: [String: (volume: Double, maxWeight: Double, sets: Int, reps: Int, sessions: Set<UUID>, e1rms: [Double])] = [:]

        // We need to reprocess raw workouts to get maxWeight, sets, reps, sessions, and E1RMs
        // For now, we'll create a simplified version that uses what we have
        // In a production app, you'd want to store this during the main recompute pass

        // For this implementation, let's create a basic structure from existing data
        for evs in allExVolumes {
            let key = "\(evs.exerciseID)|\(ExerciseVolumeSummary.weekKey(from: evs.weekStart))"
            byExerciseWeek[key] = (
                volume: evs.volume,
                maxWeight: 0, // Will need workout data to compute
                sets: 0,
                reps: 0,
                sessions: [],
                e1rms: []
            )
        }

        print("📊 Exercise progressions: processed \(byExerciseWeek.count) exercise-week combinations")

        // Note: Full implementation would require access to raw workout data
        // For now, we'll mark this as a structure that can be enhanced
    }

    /// Compute trend indicators for all exercises (improving/stable/declining)
    func computeExerciseTrends() async {
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false

        // Fetch all exercise volume summaries, sorted by date
        let req = FetchDescriptor<ExerciseVolumeSummary>(
            sortBy: [SortDescriptor(\.weekStart, order: .forward)]
        )
        guard let allVolumes = try? ctx.fetch(req), !allVolumes.isEmpty else {
            print("📊 No exercise volumes to compute trends")
            return
        }

        // Group by exercise
        var byExercise: [String: [ExerciseVolumeSummary]] = [:]
        for vol in allVolumes {
            byExercise[vol.exerciseID, default: []].append(vol)
        }

        let window = 4 // 4-week comparison window

        for (exerciseID, volumes) in byExercise {
            guard volumes.count >= window else { continue }

            // Compare last 2 weeks average vs previous 2 weeks average
            let recent = volumes.suffix(2)
            let previous = volumes.dropLast(2).suffix(2)

            let recentAvg = recent.reduce(0.0) { $0 + $1.volume } / Double(recent.count)
            let previousAvg = previous.reduce(0.0) { $0 + $1.volume } / Double(previous.count)

            let volumeChange = previousAvg > 0 ? ((recentAvg - previousAvg) / previousAvg) * 100.0 : 0.0

            // Determine trend direction
            let trendDirection: String
            if abs(volumeChange) < 5 {
                trendDirection = "stable"
            } else if volumeChange > 0 {
                trendDirection = "improving"
            } else {
                trendDirection = "declining"
            }

            // Create or update trend record
            let trend = try? fetchOrCreateExerciseTrend(exerciseID: exerciseID, in: ctx)
            trend?.trendDirection = trendDirection
            trend?.volumeChange = volumeChange
            trend?.strengthChange = 0.0 // Would need max weight data
            trend?.lastUpdated = .now
        }

        try? ctx.save()
        print("📈 Exercise trends: computed \(byExercise.count) exercise trends")
    }

    private func fetchOrCreateExerciseTrend(exerciseID: String, in ctx: ModelContext) throws -> ExerciseTrend {
        let req = FetchDescriptor<ExerciseTrend>(predicate: #Predicate { $0.exerciseID == exerciseID })
        if let existing = try ctx.fetch(req).first { return existing }
        let obj = ExerciseTrend(exerciseID: exerciseID, trendDirection: "stable", volumeChange: 0, strengthChange: 0)
        ctx.insert(obj)
        return obj
    }

    // MARK: - Training Balance Analytics (Priority 3)

    /// Compute push/pull, muscle frequency, and movement pattern metrics
    /// This recomputes from ExerciseVolumeSummary data (already aggregated) for accuracy
    /// Note: Muscle frequency always uses ALL workouts from last 7 days for accuracy
    func computeBalanceMetrics(for workouts: [CompletedWorkout], allWorkouts: [CompletedWorkout]? = nil) async {
        guard let repo = exerciseRepo else {
            print("⚠️ ExerciseRepository not set, skipping balance metrics")
            return
        }

        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false

        // Identify affected weeks from the workouts passed
        var affectedWeeks = Set<Date>()
        for w in workouts {
            affectedWeeks.insert(startOfWeek(for: w.date))
        }

        // For each affected week, recompute from ALL ExerciseVolumeSummary records
        for weekStart in affectedWeeks {
            let weekKey = ExerciseVolumeSummary.weekKey(from: weekStart)

            // Fetch ALL exercise volumes for this week
            let req = FetchDescriptor<ExerciseVolumeSummary>(
                predicate: #Predicate { $0.weekStart == weekStart }
            )
            guard let exerciseVolumes = try? ctx.fetch(req) else { continue }

            print("📊 Found \(exerciseVolumes.count) exercise volumes for week \(weekKey)")

            var pushVol = 0.0, pullVol = 0.0
            var hPushVol = 0.0, hPullVol = 0.0, vPushVol = 0.0, vPullVol = 0.0
            var compoundVol = 0.0, isolationVol = 0.0
            var bilateralVol = 0.0, unilateralVol = 0.0
            var hingeVol = 0.0, squatVol = 0.0

            // Process each exercise's volume
            print("📊 About to process exercises, checking if repo has exercises...")
            let repoExerciseCount = await MainActor.run { repo.exercises.count }
            print("📊 Repo has \(repoExerciseCount) exercises")

            for evs in exerciseVolumes {
                print("🔍 Looking up exercise ID: '\(evs.exerciseID)'")

                // Fetch exercise from MainActor context with detailed debugging
                let ex = await MainActor.run {
                    let result = repo.exercise(byID: evs.exerciseID)
                    if result != nil {
                        print("   ✅ Found in repo: \(result!.name)")
                    } else {
                        print("   ❌ NOT found in repo")
                        // Let's see what exercises start with similar names
                        let similar = repo.exercises.filter { $0.id.contains(evs.exerciseID.prefix(min(10, evs.exerciseID.count))) }
                        if !similar.isEmpty {
                            print("   💡 Similar IDs found: \(similar.prefix(3).map { $0.id })")
                        }
                    }
                    return result
                }

                guard let ex = ex else {
                    print("⚠️ Could not find exercise: \(evs.exerciseID)")
                    continue
                }
                let volume = evs.volume
                print("📊 Processing exercise: \(ex.name) with volume: \(volume)")

                // Push/Pull classification
                if ExerciseClassifier.isPush(exercise: ex) {
                    pushVol += volume
                    print("   ✅ Classified as PUSH (total push now: \(pushVol))")
                    if ExerciseClassifier.isHorizontalPush(exercise: ex) {
                        hPushVol += volume
                    } else if ExerciseClassifier.isVerticalPush(exercise: ex) {
                        vPushVol += volume
                    }
                } else if ExerciseClassifier.isPull(exercise: ex) {
                    pullVol += volume
                    print("   ✅ Classified as PULL (total pull now: \(pullVol))")
                    if ExerciseClassifier.isHorizontalPull(exercise: ex) {
                        hPullVol += volume
                    } else if ExerciseClassifier.isVerticalPull(exercise: ex) {
                        vPullVol += volume
                    }
                } else {
                    print("   ⚠️ Not classified as push or pull")
                }

                // Compound/Isolation
                if ExerciseClassifier.isCompound(exercise: ex) {
                    compoundVol += volume
                } else {
                    isolationVol += volume
                }

                // Bilateral/Unilateral
                if ExerciseClassifier.isUnilateral(exercise: ex) {
                    unilateralVol += volume
                } else {
                    bilateralVol += volume
                }

                // Hinge/Squat
                if ExerciseClassifier.isHinge(exercise: ex) {
                    hingeVol += volume
                } else if ExerciseClassifier.isSquat(exercise: ex) {
                    squatVol += volume
                }
            }

            // Save Push/Pull balance
            if let ppb = try? fetchOrCreatePushPullBalance(key: weekKey, weekStart: weekStart, in: ctx) {
                ppb.pushVolume = pushVol
                ppb.pullVolume = pullVol
                ppb.horizontalPushVolume = hPushVol
                ppb.horizontalPullVolume = hPullVol
                ppb.verticalPushVolume = vPushVol
                ppb.verticalPullVolume = vPullVol
                ppb.ratio = pushVol > 0 ? pullVol / pushVol : 0
                print("💾 Saved Push/Pull balance for week \(weekKey): push=\(pushVol), pull=\(pullVol), ratio=\(ppb.ratio)")
            }

            // Save Movement Pattern balance
            if let mpb = try? fetchOrCreateMovementPattern(key: weekKey, weekStart: weekStart, in: ctx) {
                mpb.compoundVolume = compoundVol
                mpb.isolationVolume = isolationVol
                mpb.bilateralVolume = bilateralVol
                mpb.unilateralVolume = unilateralVol
                mpb.hingeVolume = hingeVol
                mpb.squatVolume = squatVol
            }
        }

        // Compute muscle group frequency (last 7 days) - always use ALL workouts
        let workoutsForFrequency = allWorkouts ?? workouts
        await computeMuscleFrequency(repo: repo, workouts: workoutsForFrequency, in: ctx)

        try? ctx.save()
        print("⚖️ Balance metrics: \(affectedWeeks.count) weeks computed")
    }

    /// Compute muscle frequency from workouts in the last 7 days
    /// This ensures muscle frequency data persists correctly
    private func computeMuscleFrequency(repo: ExerciseRepository, workouts: [CompletedWorkout], in ctx: ModelContext) async {
        let now = Date()
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now

        // Filter workouts to last 7 days
        let recentWorkouts = workouts.filter { $0.date >= sevenDaysAgo }

        guard !recentWorkouts.isEmpty else {
            print("⚖️ No workouts found in last 7 days for muscle frequency")
            return
        }

        // Track last trained date and volume per muscle group
        var muscleStats: [String: (lastTrained: Date, frequency: Int, volume: Double)] = [:]

        for workout in recentWorkouts {
            var musclesInWorkout = Set<String>()

            for entry in workout.entries {
                // Fetch exercise from MainActor context
                guard let ex = await MainActor.run(body: { repo.exercise(byID: entry.exerciseID) }) else { continue }

                var entryVolume = 0.0
                for set in entry.sets where set.tag == .working && set.reps > 0 && set.weight > 0 {
                    entryVolume += Double(set.reps) * set.weight
                }

                let muscleGroups = ExerciseClassifier.primaryMuscleGroups(for: ex)
                for muscle in muscleGroups {
                    musclesInWorkout.insert(muscle)

                    if let existing = muscleStats[muscle] {
                        muscleStats[muscle] = (
                            lastTrained: max(existing.lastTrained, workout.date),
                            frequency: existing.frequency,
                            volume: existing.volume + entryVolume
                        )
                    } else {
                        muscleStats[muscle] = (lastTrained: workout.date, frequency: 0, volume: entryVolume)
                    }
                }
            }

            // Increment frequency for muscles trained in this workout
            for muscle in musclesInWorkout {
                if var stats = muscleStats[muscle] {
                    stats.frequency += 1
                    muscleStats[muscle] = stats
                }
            }
        }

        // Save to database
        for (muscle, stats) in muscleStats {
            if let mgf = try? fetchOrCreateMuscleFrequency(muscle: muscle, in: ctx) {
                mgf.lastTrained = stats.lastTrained
                mgf.weeklyFrequency = stats.frequency
                mgf.totalVolume = stats.volume
            }
        }
    }

    private func fetchOrCreatePushPullBalance(key: String, weekStart: Date, in ctx: ModelContext) throws -> PushPullBalance {
        let req = FetchDescriptor<PushPullBalance>(predicate: #Predicate { $0.key == key })
        if let existing = try ctx.fetch(req).first { return existing }
        let obj = PushPullBalance(key: key, weekStart: weekStart, pushVolume: 0, pullVolume: 0,
                                   horizontalPushVolume: 0, horizontalPullVolume: 0,
                                   verticalPushVolume: 0, verticalPullVolume: 0)
        ctx.insert(obj)
        return obj
    }

    private func fetchOrCreateMovementPattern(key: String, weekStart: Date, in ctx: ModelContext) throws -> MovementPatternBalance {
        let req = FetchDescriptor<MovementPatternBalance>(predicate: #Predicate { $0.key == key })
        if let existing = try ctx.fetch(req).first { return existing }
        let obj = MovementPatternBalance(key: key, weekStart: weekStart, compoundVolume: 0, isolationVolume: 0,
                                          bilateralVolume: 0, unilateralVolume: 0, hingeVolume: 0, squatVolume: 0)
        ctx.insert(obj)
        return obj
    }

    private func fetchOrCreateMuscleFrequency(muscle: String, in ctx: ModelContext) throws -> MuscleGroupFrequency {
        let req = FetchDescriptor<MuscleGroupFrequency>(predicate: #Predicate { $0.muscleGroup == muscle })
        if let existing = try ctx.fetch(req).first { return existing }
        let obj = MuscleGroupFrequency(muscleGroup: muscle, lastTrained: .distantPast, weeklyFrequency: 0, totalVolume: 0)
        ctx.insert(obj)
        return obj
    }
}
