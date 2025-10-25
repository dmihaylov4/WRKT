// WorkoutStoreV2.swift
// Refactored to use unified WorkoutStorage

import Foundation
import Combine
import SwiftUI
import HealthKit

@MainActor
final class WorkoutStoreV2: ObservableObject {
    // MARK: - Published State
    @Published var currentWorkout: CurrentWorkout?
    @Published var completedWorkouts: [CompletedWorkout] = []
    @Published private(set) var lastHealthImportEndDate: Date? = nil
    @Published private(set) var runs: [Run] = []

    private var prIndex: [String: ExercisePRsV2] = [:]

    // MARK: - Dependencies
    private let storage = WorkoutStorage.shared
    private let repo: ExerciseRepository
    private var cancellables = Set<AnyCancellable>()

    // MARK: - UserDefaults keys
    private let defaults = UserDefaults.standard
    private let lastImportKey = "health.lastImport.endDate"

    private var _stats: StatsAggregator?
    var stats: StatsAggregator? { _stats }

    func installStats(_ stats: StatsAggregator) {
        self._stats = stats
    }

    // MARK: - Init
    init(repo: ExerciseRepository = .shared) {
        self.repo = repo

        Task {
            do {
                // Check if migration is needed
                if await storage.needsMigration() {
                    print("🔄 Migration needed, performing one-time migration...")
                    try await storage.migrateFromLegacyStorage()
                }

                // Load all data from unified storage
                let (workouts, prIndex) = try await storage.loadWorkouts()
                let runs = try await storage.loadRuns()
                let currentWorkout = try await storage.loadCurrentWorkout()

                self.completedWorkouts = workouts
                self.prIndex = prIndex
                self.runs = runs
                self.currentWorkout = currentWorkout
                self.lastHealthImportEndDate = defaults.object(forKey: lastImportKey) as? Date

                print("✅ Loaded from unified storage:")
                print("   Workouts: \(workouts.count)")
                print("   Runs: \(runs.count)")
                print("   PR entries: \(prIndex.count)")
                print("   Current workout: \(currentWorkout != nil ? "Yes" : "No")")

                // Match workouts with HealthKit data if available
                matchAllWorkoutsWithHealthKit()

            } catch {
                print("❌ Failed to load from storage: \(error)")
                // Initialize with empty state
                self.completedWorkouts = []
                self.prIndex = [:]
                self.runs = []
                self.currentWorkout = nil
            }
        }

        repo.$exercises
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshCurrentWorkoutEntryNames() }
            .store(in: &cancellables)
    }

    // MARK: - Current Workout lifecycle

    func startWorkoutIfNeeded() {
        if currentWorkout == nil {
            currentWorkout = CurrentWorkout()
            persistCurrentWorkout()
        }
    }

    func startPlannedWorkout(_ planned: PlannedWorkout) {
        let entries = planned.exercises.map { plannedEx -> WorkoutEntry in
            let ghostSets = plannedEx.ghostSets.map { ghost in
                SetInput(
                    reps: ghost.reps,
                    weight: ghost.weight,
                    tag: ghost.setTag,
                    autoWeight: false,
                    isGhost: false  // Make sets editable so users can modify reps/weight and log them
                )
            }

            let exercise = repo.exercise(byID: plannedEx.exerciseID)
            let muscleGroups = exercise?.primaryMuscles ?? []

            return WorkoutEntry(
                exerciseID: plannedEx.exerciseID,
                exerciseName: plannedEx.exerciseName,
                muscleGroups: muscleGroups,
                sets: ghostSets
            )
        }

        currentWorkout = CurrentWorkout(
            startedAt: .now,
            entries: entries,
            plannedWorkoutID: planned.id
        )
        persistCurrentWorkout()
        print("🏋️ Started planned workout: \(planned.splitDayName)")
    }

    func discardCurrentWorkout() {
        currentWorkout = nil
        RestTimerManager.shared.stopTimer()

        Task {
            try? await storage.deleteCurrentWorkout()
        }
    }

    func finishCurrentWorkout() {
        guard let w = currentWorkout, !w.entries.isEmpty else { return }
        let completed = CompletedWorkout(date: .now, entries: w.entries, plannedWorkoutID: w.plannedWorkoutID)
        completedWorkouts.insert(completed, at: 0)

        // Update PR index
        updatePRIndex(with: completed)

        // Persist to storage
        persistWorkouts()

        // Update stats
        Task.detached(priority: .utility) { [_stats, completedWorkouts] in
            await _stats?.apply(completed, allWorkouts: completedWorkouts)
        }

        // Cancel rest timer
        RestTimerManager.shared.stopTimer()
        currentWorkout = nil

        // Persist the nil state to disk so it doesn't resurrect on app restart
        persistCurrentWorkout()

        // Unlock dex entries
        for e in completed.entries {
            let didWork = e.sets.contains { $0.tag == .working && $0.reps > 0 }
            if didWork {
                RewardsEngine.shared.ensureDexUnlocked(exerciseKey: canonicalExerciseKey(from: e.exerciseID))
            }
        }
    }

    func updateEntrySets(entryID: UUID, sets: [SetInput]) {
        guard var w = currentWorkout else { return }
        guard let idx = w.entries.firstIndex(where: { $0.id == entryID }) else { return }
        w.entries[idx].sets = sets
        currentWorkout = w
        persistCurrentWorkout()
        updateLastWorkingFromCurrent()

        let entry = w.entries[idx]
        let hasWorking = entry.sets.contains { $0.tag == .working && $0.reps > 0 }
        if hasWorking {
            let key = canonicalExerciseKey(from: entry.exerciseID)
            RewardsEngine.shared.ensureDexUnlocked(exerciseKey: key)
        }
    }

    func updateEntrySetsAndActiveIndex(entryID: UUID, sets: [SetInput], activeSetIndex: Int) {
        guard var w = currentWorkout else { return }
        guard let idx = w.entries.firstIndex(where: { $0.id == entryID }) else { return }
        w.entries[idx].sets = sets
        w.entries[idx].activeSetIndex = activeSetIndex
        currentWorkout = w
        persistCurrentWorkout()
        updateLastWorkingFromCurrent()

        let entry = w.entries[idx]
        let hasWorking = entry.sets.contains { $0.tag == .working && $0.reps > 0 }
        if hasWorking {
            let key = canonicalExerciseKey(from: entry.exerciseID)
            RewardsEngine.shared.ensureDexUnlocked(exerciseKey: key)
        }
    }

    // MARK: - Entries Management

    @discardableResult
    func addExerciseToCurrent(_ exercise: Exercise) -> UUID {
        if currentWorkout == nil {
            currentWorkout = CurrentWorkout(startedAt: .now, entries: [])
        }

        var workout = currentWorkout!
        let entry = WorkoutEntry(
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            muscleGroups: exercise.primaryMuscles + exercise.secondaryMuscles,
            sets: []
        )
        workout.entries.append(entry)
        currentWorkout = workout
        persistCurrentWorkout()
        print("✅ Added exercise '\(exercise.name)' to current workout (\(workout.entries.count) exercises total)")
        return entry.id
    }

    @discardableResult
    func addExerciseToCurrent(id: String) -> UUID? {
        guard let ex = repo.exercise(byID: id) else { return nil }
        return addExerciseToCurrent(ex)
    }

    @discardableResult
    func addExerciseToCurrent(slug: String) -> UUID? {
        addExerciseToCurrent(id: slug)
    }

    func removeEntry(entryID: UUID) {
        guard var w = currentWorkout else { return }
        w.entries.removeAll { $0.id == entryID }
        currentWorkout = w.entries.isEmpty ? w : w
        persistCurrentWorkout()
    }

    func replaceEntryExercise(entryID: UUID, newExerciseID: String) {
        guard var w = currentWorkout else { return }
        guard let idx = w.entries.firstIndex(where: { $0.id == entryID }) else { return }
        guard let ex = repo.exercise(byID: newExerciseID) else { return }
        w.entries[idx].exerciseID = ex.id
        w.entries[idx].exerciseName = ex.name
        w.entries[idx].muscleGroups = ex.primaryMuscles + ex.secondaryMuscles
        currentWorkout = w
        persistCurrentWorkout()
    }

    func exerciseForEntry(_ e: WorkoutEntry) -> Exercise? {
        repo.exercise(byID: e.exerciseID)
    }

    // Find existing entry for an exercise in current workout (to prevent duplicates)
    func existingEntry(for exerciseID: String) -> WorkoutEntry? {
        currentWorkout?.entries.first(where: { $0.exerciseID == exerciseID })
    }

    private func refreshCurrentWorkoutEntryNames() {
        guard var w = currentWorkout, !repo.exercises.isEmpty else { return }
        var changed = false
        for i in w.entries.indices {
            if let ex = repo.exercise(byID: w.entries[i].exerciseID) {
                if w.entries[i].exerciseName.isEmpty || w.entries[i].exerciseName != ex.name {
                    w.entries[i].exerciseName = ex.name
                    changed = true
                }
                let mg = ex.primaryMuscles + ex.secondaryMuscles
                if mg != w.entries[i].muscleGroups {
                    w.entries[i].muscleGroups = mg
                    changed = true
                }
            }
        }
        if changed {
            currentWorkout = w
            persistCurrentWorkout()
        }
    }

    // MARK: - Completed Workouts CRUD

    func addWorkout(_ workout: CompletedWorkout) {
        completedWorkouts.insert(workout, at: 0)
        persistWorkouts()
    }

    func deleteWorkouts(at offsets: IndexSet) {
        let removed = offsets.map { completedWorkouts[$0] }
        completedWorkouts.remove(atOffsets: offsets)
        persistWorkouts()

        let weeks = Set(removed.map { startOfWeek(for: $0.date) })
        Task.detached(priority: .utility) { [_stats, completedWorkouts] in
            await _stats?.invalidate(weeks: weeks, from: completedWorkouts)
        }
    }

    func updateWorkout(_ workout: CompletedWorkout) {
        if let idx = completedWorkouts.firstIndex(where: { $0.id == workout.id }) {
            completedWorkouts[idx] = workout
            persistWorkouts()
            let week = startOfWeek(for: workout.date)
            Task.detached(priority: .utility) { [_stats, completedWorkouts] in
                await _stats?.invalidate(weeks: [week], from: completedWorkouts)
            }
        }
    }

    func clearAllWorkouts() {
        completedWorkouts.removeAll()
        prIndex.removeAll()
        persistWorkouts()
    }

    func workouts(on date: Date, calendar: Calendar = .current) -> [CompletedWorkout] {
        let day = calendar.startOfDay(for: date)
        return completedWorkouts.filter { calendar.isDate($0.date, inSameDayAs: day) }
    }

    func streak(referenceDate: Date = .now, calendar: Calendar = .current) -> Int {
        let days: Set<Date> = Set(completedWorkouts.map { calendar.startOfDay(for: $0.date) })
        var count = 0
        var current = calendar.startOfDay(for: referenceDate)
        while days.contains(current) {
            count += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: current) else { break }
            current = prev
        }
        return count
    }

    // MARK: - Runs

    func addRun(_ run: Run) {
        runs.insert(run, at: 0)
        persistRuns()
    }

    func updateRun(_ run: Run) {
        if let index = runs.firstIndex(where: { $0.id == run.id }) {
            var updatedRuns = runs
            updatedRuns[index] = run
            runs = updatedRuns
            persistRuns()
        }
    }

    func batchUpdateRuns(_ updatedRuns: [Run]) {
        var runsCopy = runs
        var updateCount = 0

        for run in updatedRuns {
            if let index = runsCopy.firstIndex(where: { $0.id == run.id }) {
                runsCopy[index] = run
                updateCount += 1
            }
        }

        runs = runsCopy
        print("📦 Batch updated \(updateCount)/\(updatedRuns.count) runs")
        persistRuns()
    }

    func removeRun(withId id: UUID) {
        runs.removeAll(where: { $0.id == id })
        persistRuns()
    }

    func deleteRuns(at offsets: IndexSet) {
        runs.remove(atOffsets: offsets)
        persistRuns()
    }

    func clearAllRuns() {
        runs.removeAll()
        persistRuns()
    }

    func runs(on date: Date, calendar: Calendar = .current) -> [Run] {
        let day = calendar.startOfDay(for: date)
        return runs.filter { calendar.isDate($0.date, inSameDayAs: day) }
    }

    func persist() {
        persistRuns()
    }

    func importRunsFromHealth() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do {
            if HealthKitManager.shared.connectionState != .connected {
                try await HealthKitManager.shared.requestAuthorization()
                await HealthKitManager.shared.setupBackgroundObservers()
            }

            await HealthKitManager.shared.syncWorkoutsIncremental()

            if let latest = runs.map({ $0.date }).max() {
                lastHealthImportEndDate = latest
                defaults.set(latest, forKey: lastImportKey)
            }

            matchAllWorkoutsWithHealthKit()
        } catch {
            print("⚠️ Health import failed: \(error)")
        }
    }

    // MARK: - HealthKit Matching

    @discardableResult
    func matchWithHealthKit(_ workout: CompletedWorkout) -> Bool {
        guard workout.matchedHealthKitUUID == nil else {
            print("⏭️ Workout already matched, skipping")
            return false
        }

        let matchWindow: TimeInterval = 10 * 60
        let workoutEndTime = workout.date
        let startWindow = workoutEndTime.addingTimeInterval(-matchWindow)
        let endWindow = workoutEndTime.addingTimeInterval(matchWindow)

        let strengthTypes = ["Strength Training", "Functional Training", "Core Training"]
        let strengthRuns = runs.filter { run in
            guard let type = run.workoutType else { return false }
            return strengthTypes.contains(type)
        }

        let candidates = strengthRuns.filter { run in
            run.date >= startWindow && run.date <= endWindow
        }

        guard let match = candidates.min(by: { abs($0.date.timeIntervalSince(workoutEndTime)) < abs($1.date.timeIntervalSince(workoutEndTime)) }) else {
            return false
        }

        Task {
            await fetchAndStoreHeartRateData(for: workout.id, healthKitUUID: match.healthKitUUID)
        }

        if let idx = completedWorkouts.firstIndex(where: { $0.id == workout.id }) {
            completedWorkouts[idx].matchedHealthKitUUID = match.healthKitUUID
            completedWorkouts[idx].matchedHealthKitCalories = match.calories
            completedWorkouts[idx].matchedHealthKitHeartRate = match.avgHeartRate
            completedWorkouts[idx].matchedHealthKitDuration = match.durationSec
            persistWorkouts()
            return true
        }

        return false
    }

    private func fetchAndStoreHeartRateData(for workoutID: UUID, healthKitUUID: UUID?) async {
        guard let hkUUID = healthKitUUID else { return }

        do {
            let workouts = try await HealthKitManager.shared.fetchWorkoutByUUID(hkUUID)
            guard let hkWorkout = workouts.first else { return }

            let (samples, avg, max, min) = try await HealthKitManager.shared.fetchHeartRateSamples(for: hkWorkout)

            await MainActor.run {
                if let idx = completedWorkouts.firstIndex(where: { $0.id == workoutID }) {
                    completedWorkouts[idx].matchedHealthKitHeartRate = avg
                    completedWorkouts[idx].matchedHealthKitMaxHeartRate = max
                    completedWorkouts[idx].matchedHealthKitMinHeartRate = min
                    completedWorkouts[idx].matchedHealthKitHeartRateSamples = samples
                    persistWorkouts()
                }
            }
        } catch {
            print("   ❌ Failed to fetch heart rate samples: \(error)")
        }
    }

    func matchAllWorkoutsWithHealthKit() {
        var matchCount = 0
        for workout in completedWorkouts where workout.matchedHealthKitUUID == nil {
            if matchWithHealthKit(workout) {
                matchCount += 1
            }
        }
        if matchCount > 0 {
            print("✅ Matched \(matchCount) workouts with HealthKit data")
        }
    }

    // MARK: - Persistence Helpers

    private func persistWorkouts() {
        let workouts = completedWorkouts
        let prIndex = prIndex
        Task.detached(priority: .utility) {
            do {
                try await WorkoutStorage.shared.saveWorkouts(workouts, prIndex: prIndex)
            } catch {
                print("❌ Failed to persist workouts: \(error)")
            }
        }
    }

    private func persistCurrentWorkout() {
        let current = currentWorkout
        Task.detached(priority: .utility) {
            try? await WorkoutStorage.shared.saveCurrentWorkout(current)
        }
    }

    private func persistRuns() {
        let runs = runs
        Task.detached(priority: .utility) {
            try? await WorkoutStorage.shared.saveRuns(runs)
        }
    }

    private func startOfWeek(for date: Date) -> Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date))!
    }
}

// MARK: - Weight Suggestions

extension WorkoutStoreV2 {

    private func allWorkingSets(for exerciseID: String) -> [(date: Date, set: SetInput)] {
        var out: [(Date, SetInput)] = []

        for w in completedWorkouts {
            if let entry = w.entries.first(where: { $0.exerciseID == exerciseID }) {
                for s in entry.sets where s.tag == .working && s.weight > 0 && s.reps > 0 {
                    out.append((w.date, s))
                }
            }
        }

        if let w = currentWorkout,
           let entry = w.entries.first(where: { $0.exerciseID == exerciseID })
        {
            for s in entry.sets where s.tag == .working && s.weight > 0 && s.reps > 0 {
                out.append((Date(), s))
            }
        }

        return out
    }

    func lastWorkingSet(exercise: Exercise) -> (reps: Int, weightKg: Double)? {
        if let last = prIndex[exercise.id]?.lastWorking {
            return (last.reps, last.weightKg)
        }
        let sets = allWorkingSets(for: exercise.id).sorted { $0.date > $1.date }
        return sets.first.map { ($0.set.reps, $0.set.weight) }
    }

    func bestWeightForExactReps(exercise: Exercise, reps: Int) -> Double? {
        if let w = prIndex[exercise.id]?.bestPerReps[reps] { return w }
        let sets = allWorkingSets(for: exercise.id)
            .filter { $0.set.reps == reps }
            .map { $0.set.weight }
        return sets.max()
    }

    func bestWeightForNearbyReps(exercise: Exercise, targetReps: Int, window: Int = 2) -> (reps: Int, weightKg: Double)? {
        if let dict = prIndex[exercise.id]?.bestPerReps {
            var best: (r: Int, w: Double, d: Int)? = nil
            for (r, w) in dict {
                let d = abs(r - targetReps)
                guard d <= window else { continue }
                if best == nil || d < best!.d || (d == best!.d && w > best!.w) {
                    best = (r, w, d)
                }
            }
            if let b = best { return (b.r, b.w) }
        }
        let candidates = allWorkingSets(for: exercise.id).map { $0.set }
        var best: (reps: Int, weight: Double, delta: Int)? = nil
        for s in candidates {
            let d = abs(s.reps - targetReps)
            guard d <= window else { continue }
            if best == nil || d < best!.delta || (d == best!.delta && s.weight > best!.weight) {
                best = (s.reps, s.weight, d)
            }
        }
        return best.map { ($0.reps, $0.weight) }
    }

    func bestE1RM(exercise: Exercise) -> Double? {
        if let e = prIndex[exercise.id]?.bestE1RM { return e }
        let sets = allWorkingSets(for: exercise.id).map { $0.set }
        let e1rms = sets.map { s in s.weight * (1.0 + Double(s.reps) / 30.0) }
        return e1rms.max()
    }

    private func weight(forE1RM e1rm: Double, reps: Int) -> Double {
        e1rm / (1.0 + Double(reps)/30.0)
    }

    func lastWorkingWeight(exercise: Exercise) -> Double? {
        lastWorkingSet(exercise: exercise)?.weightKg
    }

    func suggestedWorkingWeight(for exercise: Exercise, targetReps: Int) -> Double? {
        if let exact = bestWeightForExactReps(exercise: exercise, reps: targetReps) { return exact }
        if let near = bestWeightForNearbyReps(exercise: exercise, targetReps: targetReps) {
            let e1rm = near.weightKg * (1.0 + Double(near.reps)/30.0)
            return weight(forE1RM: e1rm, reps: targetReps)
        }
        if let last = lastWorkingWeight(exercise: exercise) { return last }
        if let e1rm = bestE1RM(exercise: exercise) { return weight(forE1RM: e1rm, reps: targetReps) }
        return nil
    }
}

// MARK: - PR Index Management

extension WorkoutStoreV2 {

    private func updatePRIndex(with completed: CompletedWorkout) {
        for e in completed.entries {
            var pr = prIndex[e.exerciseID, default: ExercisePRsV2()]

            for s in e.sets where s.tag == .working && s.reps > 0 && s.weight > 0 {
                // Best per reps
                pr.bestPerReps[s.reps] = max(pr.bestPerReps[s.reps] ?? 0, s.weight)

                // Best E1RM (Epley formula)
                let e1rm = s.weight * (1.0 + Double(s.reps) / 30.0)
                pr.bestE1RM = max(pr.bestE1RM ?? 0, e1rm)

                // All-time best
                pr.allTimeBest = max(pr.allTimeBest ?? 0, s.weight)

                // Last working set
                pr.lastWorking = LastSetV2(date: completed.date, reps: s.reps, weightKg: s.weight)

                // First recorded (don't overwrite if already set)
                if pr.firstRecorded == nil {
                    pr.firstRecorded = completed.date
                }
            }

            prIndex[e.exerciseID] = pr
        }
    }

    private func updateLastWorkingFromCurrent() {
        guard let w = currentWorkout else { return }
        for e in w.entries {
            let workingSets = e.sets.filter { $0.tag == .working && $0.reps > 0 && $0.weight > 0 }
            guard let last = workingSets.last else { continue }
            var pr = prIndex[e.exerciseID, default: ExercisePRsV2()]
            pr.lastWorking = LastSetV2(date: Date(), reps: last.reps, weightKg: last.weight)
            prIndex[e.exerciseID] = pr
        }
    }

    func finishCurrentWorkoutAndReturnPRs() -> (workoutId: String, prCount: Int) {
        guard let w = currentWorkout, !w.entries.isEmpty else { return ("none", 0) }

        let completed = CompletedWorkout(date: .now, entries: w.entries, plannedWorkoutID: w.plannedWorkoutID)

        // Unlock dex entries
        for e in completed.entries {
            let didWork = e.sets.contains { $0.tag == .working && $0.reps > 0 }
            if didWork {
                let key = canonicalExerciseKey(from: e.exerciseID)
                RewardsEngine.shared.ensureDexUnlocked(exerciseKey: key, date: completed.date)
            }
        }

        // Count PRs before updating the index
        let newPRs = countPRs(in: completed)

        // Normal finish logic
        completedWorkouts.insert(completed, at: 0)
        updatePRIndex(with: completed)
        persistWorkouts()

        // Update stats
        Task.detached(priority: .utility) { [_stats, completedWorkouts] in
            await _stats?.apply(completed, allWorkouts: completedWorkouts)
        }

        // Cancel rest timer
        RestTimerManager.shared.stopTimer()
        currentWorkout = nil

        // Persist the nil state to disk so it doesn't resurrect on app restart
        persistCurrentWorkout()

        return (completed.id.uuidString, newPRs)
    }

    private func countPRs(in workout: CompletedWorkout) -> Int {
        var exercisesWithPR = Set<String>()
        for e in workout.entries {
            let existing = prIndex[e.exerciseID] ?? ExercisePRsV2()
            for s in e.sets where s.tag == .working && s.reps > 0 && s.weight > 0 {
                let prevBestAtReps = existing.bestPerReps[s.reps] ?? 0
                if s.weight > prevBestAtReps {
                    exercisesWithPR.insert(e.exerciseID)
                    break
                }

                let e1rm = s.weight * (1.0 + Double(s.reps)/30.0)
                if let prevE1 = existing.bestE1RM, e1rm > prevE1 {
                    exercisesWithPR.insert(e.exerciseID)
                    break
                } else if existing.bestE1RM == nil {
                    exercisesWithPR.insert(e.exerciseID)
                    break
                }
            }
        }
        return exercisesWithPR.count
    }
}
