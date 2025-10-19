// WorkoutStore.swift

import Foundation
import Combine
import SwiftUI
import HealthKit

@MainActor
final class WorkoutStore: ObservableObject {
    // MARK: - Published State
    @Published var currentWorkout: CurrentWorkout?
    @Published var completedWorkouts: [CompletedWorkout] = []
    @Published private(set) var lastHealthImportEndDate: Date? = nil
    @Published private(set) var runs: [Run] = []
    
    private var prIndex: [String: ExercisePRs] = [:]

    // MARK: - Dependencies
    private let repo: ExerciseRepository
    private var cancellables = Set<AnyCancellable>()

    // MARK: - UserDefaults keys
    private let defaults = UserDefaults.standard
    private let lastImportKey = "health.lastImport.endDate"

    // MARK: - File locations
    private var appSupportDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = dir.appendingPathComponent("WRKT", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir
    }
    private var fileURL: URL { appSupportDir.appendingPathComponent("completed_workouts.json") }
    private var currentFileURL: URL { appSupportDir.appendingPathComponent("current_workout.json") }
    private var runsFileURL: URL { appSupportDir.appendingPathComponent("runs.json") }

    private var _stats: StatsAggregator?   // actor ref; safe to store

    var stats: StatsAggregator? { _stats }  // public getter

     func installStats(_ stats: StatsAggregator) {
         self._stats = stats
     }
    // MARK: - Init
    // init(repo:)
    init(repo: ExerciseRepository = .shared) {
        self.repo = repo

        Task {
            loadFromDisk()
            loadRunsFromDisk()
            lastHealthImportEndDate = defaults.object(forKey: lastImportKey) as? Date
            loadCurrentWorkout()

            // Load PR index *after* history is in memory
            loadPRIndex()
            // Build it if missing or empty
            if prIndex.isEmpty { recomputePRIndexFromHistory() }

            self.completedWorkouts = await Persistence.shared.loadWorkouts()
            self.currentWorkout = await Persistence.shared.loadCurrentWorkout()
            // Recompute again if Persistence returned more
            if prIndex.isEmpty { recomputePRIndexFromHistory() }
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
            saveCurrentWorkout()
        }
    }

    func discardCurrentWorkout() {
        currentWorkout = nil
        Task { await Persistence.shared.deleteCurrentWorkout() }
    }
    // finishCurrentWorkout()
    func finishCurrentWorkout() {
        guard let w = currentWorkout, !w.entries.isEmpty else { return }
        let completed = CompletedWorkout(date: .now, entries: w.entries)
        completedWorkouts.insert(completed, at: 0)

        // 👉 Persist PRs immediately when a workout is finished
        updatePRIndex(with: completed)
        Task.detached(priority: .utility) { [_stats, completedWorkouts] in
                   await _stats?.apply(completed, allWorkouts: completedWorkouts)
               }

        Task {
            await Persistence.shared.saveWorkouts(self.completedWorkouts)
            await Persistence.shared.deleteCurrentWorkout()
        }
        currentWorkout = nil
        
        for e in completed.entries {
            let didWork = e.sets.contains { $0.tag == .working && $0.reps > 0 }
            if didWork {
                RewardsEngine.shared.ensureDexUnlocked(exerciseKey: canonicalExerciseKey(from: e.exerciseID))
            }
        }
    }
    
    // After any sets change, reflect "last working" live.
    func updateEntrySets(entryID: UUID, sets: [SetInput]) {
        guard var w = currentWorkout else { return }
        guard let idx = w.entries.firstIndex(where: { $0.id == entryID }) else { return }
        w.entries[idx].sets = sets
        currentWorkout = w
        persistCurrent()
        updateLastWorkingFromCurrent()      // 👈 keep memory warm during the session

        let entry = w.entries[idx]
        let hasWorking = entry.sets.contains { $0.tag == .working && $0.reps > 0 }
        if hasWorking {
            let key = canonicalExerciseKey(from: entry.exerciseID)   // from DexKeying.swift
            RewardsEngine.shared.ensureDexUnlocked(exerciseKey: key)
        }
    }

    // MARK: - HealthKit Workout Matching

    /// Matches a completed workout with HealthKit data within ±10 minutes
    /// Returns true if a match was found and updated
    @discardableResult
    func matchWithHealthKit(_ workout: CompletedWorkout) -> Bool {
        // Skip if already matched
        guard workout.matchedHealthKitUUID == nil else {
            print("⏭️ Workout already matched, skipping")
            return false
        }

        // Find strength training workouts from HealthKit within ±10 minutes
        let matchWindow: TimeInterval = 10 * 60  // 10 minutes in seconds
        let workoutEndTime = workout.date  // The time workout was finished
        let startWindow = workoutEndTime.addingTimeInterval(-matchWindow)
        let endWindow = workoutEndTime.addingTimeInterval(matchWindow)

        print("🔍 Matching workout at \(workoutEndTime.formatted(date: .abbreviated, time: .shortened))")
        print("   Window: \(startWindow.formatted(date: .omitted, time: .shortened)) - \(endWindow.formatted(date: .omitted, time: .shortened))")
        print("   Total runs available: \(runs.count)")

        // Look for strength training workouts in runs (HealthKit imports)
        let strengthTypes = ["Strength Training", "Functional Training", "Core Training"]
        let strengthRuns = runs.filter { run in
            guard let type = run.workoutType else { return false }
            return strengthTypes.contains(type)
        }

        print("   Strength training runs found: \(strengthRuns.count)")

        let candidates = strengthRuns.filter { run in
            let inWindow = run.date >= startWindow && run.date <= endWindow
            if inWindow {
                print("   ✓ Candidate: \(run.workoutType ?? "Unknown") at \(run.date.formatted(date: .omitted, time: .shortened))")
            }
            return inWindow
        }

        print("   Candidates in window: \(candidates.count)")

        // If we found a match, pick the closest one
        guard let match = candidates.min(by: { abs($0.date.timeIntervalSince(workoutEndTime)) < abs($1.date.timeIntervalSince(workoutEndTime)) }) else {
            print("   ❌ No match found")
            return false
        }

        // Fetch detailed heart rate data in background
        Task {
            await fetchAndStoreHeartRateData(for: workout.id, healthKitUUID: match.healthKitUUID)
        }

        // Update the workout with matched data
        if let idx = completedWorkouts.firstIndex(where: { $0.id == workout.id }) {
            completedWorkouts[idx].matchedHealthKitUUID = match.healthKitUUID
            completedWorkouts[idx].matchedHealthKitCalories = match.calories
            completedWorkouts[idx].matchedHealthKitHeartRate = match.avgHeartRate
            completedWorkouts[idx].matchedHealthKitDuration = match.durationSec
            saveToDisk()

            print("   ✅ Matched with HealthKit workout at \(match.date.formatted(date: .omitted, time: .shortened))")
            print("      Duration: \(match.durationSec)s, Calories: \(match.calories ?? 0), HR: \(match.avgHeartRate ?? 0)")
            return true
        }

        return false
    }

    /// Fetches detailed heart rate samples for a matched workout
    private func fetchAndStoreHeartRateData(for workoutID: UUID, healthKitUUID: UUID?) async {
        guard let hkUUID = healthKitUUID else { return }

        print("   📈 Fetching heart rate samples for workout...")

        do {
            // Find the HealthKit workout
            let workouts = try await HealthKitManager.shared.fetchWorkoutByUUID(hkUUID)
            guard let hkWorkout = workouts.first else {
                print("   ⚠️ Could not find HealthKit workout")
                return
            }

            // Fetch heart rate samples
            let (samples, avg, max, min) = try await HealthKitManager.shared.fetchHeartRateSamples(for: hkWorkout)

            print("   ✅ Fetched \(samples.count) heart rate samples")
            print("      Avg: \(Int(avg)) bpm, Max: \(Int(max)) bpm, Min: \(Int(min)) bpm")

            // Update workout with HR data
            await MainActor.run {
                if let idx = completedWorkouts.firstIndex(where: { $0.id == workoutID }) {
                    completedWorkouts[idx].matchedHealthKitHeartRate = avg
                    completedWorkouts[idx].matchedHealthKitMaxHeartRate = max
                    completedWorkouts[idx].matchedHealthKitMinHeartRate = min
                    completedWorkouts[idx].matchedHealthKitHeartRateSamples = samples
                    saveToDisk()
                }
            }
        } catch {
            print("   ❌ Failed to fetch heart rate samples: \(error)")
        }
    }

    /// Attempts to match all unmatched workouts with HealthKit data
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

    // MARK: - Entries (add / update / remove)
    @discardableResult
    func addExerciseToCurrent(_ exercise: Exercise) -> UUID {
        if currentWorkout == nil {
            currentWorkout = CurrentWorkout(startedAt: .now, entries: [])
        }
        let entry = WorkoutEntry(
            exerciseID: exercise.id,
            exerciseName: exercise.name, // snapshot name for history stability
            muscleGroups: exercise.primaryMuscles + exercise.secondaryMuscles,
            sets: []
        )
        currentWorkout!.entries.append(entry)
        persistCurrent()
        return entry.id
    }

    /// Convenience: add by exercise ID (or slug). Nice when your list uses the slim catalog.
    @discardableResult
    func addExerciseToCurrent(id: String) -> UUID? {
        guard let ex = repo.exercise(byID: id) else { return nil }
        return addExerciseToCurrent(ex)
    }

    /// Convenience: add by slug (same as id in our mapping).
    @discardableResult
    func addExerciseToCurrent(slug: String) -> UUID? {
        addExerciseToCurrent(id: slug)
    }



    func removeEntry(entryID: UUID) {
        guard var w = currentWorkout else { return }
        w.entries.removeAll { $0.id == entryID }
        currentWorkout = w.entries.isEmpty ? w : w
        persistCurrent()
    }

    // Replace an entry’s exercise (handy if you want to swap variants).
    func replaceEntryExercise(entryID: UUID, newExerciseID: String) {
        guard var w = currentWorkout else { return }
        guard let idx = w.entries.firstIndex(where: { $0.id == entryID }) else { return }
        guard let ex = repo.exercise(byID: newExerciseID) else { return }
        w.entries[idx].exerciseID = ex.id
        w.entries[idx].exerciseName = ex.name
        w.entries[idx].muscleGroups = ex.primaryMuscles + ex.secondaryMuscles
        currentWorkout = w
        persistCurrent()
    }

    // MARK: - Reading exercises for entries
    func exerciseForEntry(_ e: WorkoutEntry) -> Exercise? {
        repo.exercise(byID: e.exerciseID)
    }

    // Update current entries’ names once the repo has loaded (don’t touch completed history).
    private func refreshCurrentWorkoutEntryNames() {
        guard var w = currentWorkout, !repo.exercises.isEmpty else { return }
        var changed = false
        for i in w.entries.indices {
            if let ex = repo.exercise(byID: w.entries[i].exerciseID) {
                // Only update if name is empty or obviously different
                if w.entries[i].exerciseName.isEmpty || w.entries[i].exerciseName != ex.name {
                    w.entries[i].exerciseName = ex.name
                    changed = true
                }
                // Optionally refresh muscleGroups as well (useful if taxonomy normalizes names)
                let mg = ex.primaryMuscles + ex.secondaryMuscles
                if mg != w.entries[i].muscleGroups {
                    w.entries[i].muscleGroups = mg
                    changed = true
                }
            }
        }
        if changed {
            currentWorkout = w
            persistCurrent()
        }
    }

    // MARK: - Completed workouts CRUD
    func addWorkout(_ workout: CompletedWorkout) {
        completedWorkouts.insert(workout, at: 0)
        saveToDisk()
    }

    func deleteWorkouts(at offsets: IndexSet) {
        let removed = offsets.map { completedWorkouts[$0] }

         completedWorkouts.remove(atOffsets: offsets)
         saveToDisk()

         let weeks = Set(removed.map { startOfWeek(for: $0.date) })
         Task.detached(priority: .utility) { [_stats, completedWorkouts] in
             await _stats?.invalidate(weeks: weeks, from: completedWorkouts)
         }
    }

    func updateWorkout(_ workout: CompletedWorkout) {
        if let idx = completedWorkouts.firstIndex(where: { $0.id == workout.id }) {
            completedWorkouts[idx] = workout
            saveToDisk()
            let week = startOfWeek(for: workout.date)
                       Task.detached(priority: .utility) { [_stats, completedWorkouts] in
                           await _stats?.invalidate(weeks: [week], from: completedWorkouts)
                       }
        }
    }
    
    private func startOfWeek(for date: Date) -> Date {
            let cal = Calendar.current
            return cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date))!
        }

    func clearAllWorkouts() {
        completedWorkouts.removeAll()
        saveToDisk()
    }

    func workouts(on date: Date, calendar: Calendar = .current) -> [CompletedWorkout] {
        let day = calendar.startOfDay(for: date)
        return completedWorkouts.filter { calendar.isDate($0.date, inSameDayAs: day) }
    }

    func runs(on date: Date, calendar: Calendar = .current) -> [Run] {
        let day = calendar.startOfDay(for: date)
        return runs.filter { calendar.isDate($0.date, inSameDayAs: day) }
    }

    /// Simple streak: number of **consecutive days up to today** that have at least one workout.
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
        saveRunsToDisk()
    }

    func updateRun(_ run: Run) {
        if let index = runs.firstIndex(where: { $0.id == run.id }) {
            let oldType = runs[index].workoutType

            // Force @Published to trigger by reassigning the entire array
            var updatedRuns = runs
            updatedRuns[index] = run
            runs = updatedRuns

            print("    🔄 Updated run: \(oldType ?? "nil") → \(run.workoutType ?? "nil")")
            saveRunsToDisk()
        } else {
            print("    ⚠️ Could not find run with id \(run.id) to update")
        }
    }

    /// Batch update multiple runs at once (more efficient for bulk updates)
    func batchUpdateRuns(_ updatedRuns: [Run]) {
        print("📦 batchUpdateRuns called with \(updatedRuns.count) runs")

        var runsCopy = runs
        var updateCount = 0
        var typeUpdateCount = 0

        for run in updatedRuns {
            if let index = runsCopy.firstIndex(where: { $0.id == run.id }) {
                let oldType = runsCopy[index].workoutType
                runsCopy[index] = run

                if run.workoutType != nil && oldType == nil {
                    typeUpdateCount += 1
                }

                updateCount += 1

                if updateCount <= 3 {
                    print("   [\(updateCount)] \(oldType ?? "nil") → \(run.workoutType ?? "nil")")
                }
            }
        }

        runs = runsCopy
        print("📦 Batch updated \(updateCount)/\(updatedRuns.count) runs")
        print("   Type field populated for \(typeUpdateCount) runs")
        saveRunsToDisk()
    }

    func removeRun(withId id: UUID) {
        runs.removeAll(where: { $0.id == id })
        saveRunsToDisk()
    }

    func deleteRuns(at offsets: IndexSet) {
        runs.remove(atOffsets: offsets)
        saveRunsToDisk()
    }

    func persist() {
        saveRunsToDisk()
    }

    func importRunsFromHealth() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do {
            // Request authorization if needed
            if HealthKitManager.shared.connectionState != .connected {
                try await HealthKitManager.shared.requestAuthorization()
                await HealthKitManager.shared.setupBackgroundObservers()
            }

            // Trigger incremental sync using the new unified pipeline
            await HealthKitManager.shared.syncWorkoutsIncremental()

            // Update last import date
            if let latest = runs.map({ $0.date }).max() {
                lastHealthImportEndDate = latest
                defaults.set(latest, forKey: lastImportKey)
            }

            // Match workouts with HealthKit data
            matchAllWorkoutsWithHealthKit()
        } catch {
            print("⚠️ Health import failed: \(error)")
        }
    }

    // MARK: - Persistence (local JSON)
    private func loadCurrentWorkout() {
        let url = currentFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { currentWorkout = nil; return }
        do {
            let data = try Data(contentsOf: url)
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            currentWorkout = try dec.decode(CurrentWorkout.self, from: data)
        } catch {
            currentWorkout = nil
        }
    }

    private func saveCurrentWorkout() {
        let url = currentFileURL
        let payload = currentWorkout
        Task.detached(priority: .utility) {
            do {
                let enc = JSONEncoder()
                enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
                enc.dateEncodingStrategy = .iso8601
                let data = try enc.encode(payload)
                try data.write(to: url, options: [.atomic])
            } catch {
                print("⚠️ Failed to save current workout: \(error)")
            }
        }
    }

    private func persistCurrent() {
        Task { await Persistence.shared.saveCurrentWorkout(self.currentWorkout) }
    }

    private func loadFromDisk() {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            completedWorkouts = []
            return
        }
        do {
            let data = try Data(contentsOf: url)
            // Try decode new format first
            if let decoded = try? JSONDecoder().decode([CompletedWorkout].self, from: data) {
                completedWorkouts = decoded
                return
            }
            // Migration path: legacy format without `date`
            struct LegacyCompletedWorkoutNoDate: Codable { var entries: [WorkoutEntry] }
            if let legacy = try? JSONDecoder().decode([LegacyCompletedWorkoutNoDate].self, from: data) {
                completedWorkouts = legacy.map { CompletedWorkout(entries: $0.entries) }
                saveToDisk() // write back migrated format
                return
            }
            completedWorkouts = []
        } catch {
            print("⚠️ Failed to load workouts: \(error)")
            completedWorkouts = []
        }
    }

    private func saveToDisk() {
        let toSave = completedWorkouts
        let url = fileURL
        Task.detached(priority: .utility) {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(toSave)
                try data.write(to: url, options: [.atomic])
            } catch {
                print("⚠️ Failed to save workouts: \(error)")
            }
        }
    }

    private func loadRunsFromDisk() {
        let url = runsFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { runs = []; return }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            runs = (try? decoder.decode([Run].self, from: data)) ?? []
        } catch {
            print("⚠️ Failed to load runs: \(error)")
            runs = []
        }
    }

    private func saveRunsToDisk() {
        let toSave = runs
        let url = runsFileURL
        print("💾 Saving \(toSave.count) runs to disk...")
        Task.detached(priority: .utility) {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(toSave)
                try data.write(to: url, options: [.atomic])
                print("✅ Saved runs to disk successfully")
            } catch {
                print("⚠️ Failed to save runs: \(error)")
            }
        }
    }
}

// WorkoutStore.swift — implement suggestion helpers (near your TODOs)

extension WorkoutStore {

    // Walk completed history (and optionally current) once per query.
    // For scale: this is O(N) over past sets; if you outgrow it,
    // introduce a per-exercise index cache updated when workouts change.

    private func allWorkingSets(for exerciseID: String) -> [(date: Date, set: SetInput)] {
        var out: [(Date, SetInput)] = []

        // Completed history (most recent first in your array)
        for w in completedWorkouts {
            if let entry = w.entries.first(where: { $0.exerciseID == exerciseID }) {
                for s in entry.sets where s.tag == .working && s.weight > 0 && s.reps > 0 {
                    out.append((w.date, s))
                }
            }
        }

        // (Optional) include current workout so suggestions react during the same session:
        if let w = currentWorkout,
           let entry = w.entries.first(where: { $0.exerciseID == exerciseID })
        {
            for s in entry.sets where s.tag == .working && s.weight > 0 && s.reps > 0 {
                // use .now for recency ordering
                out.append((Date(), s))
            }
        }

        return out
    }

    func lastWorkingSet(exercise: Exercise) -> (reps: Int, weightKg: Double)? {
        if let last = prIndex[exercise.id]?.lastWorking {
            return (last.reps, last.weightKg)            // ✅ O(1)
        }
        // Fallback to scan (legacy)
        let sets = allWorkingSets(for: exercise.id).sorted { $0.date > $1.date }
        return sets.first.map { ($0.set.reps, $0.set.weight) }
    }

    func bestWeightForExactReps(exercise: Exercise, reps: Int) -> Double? {
        if let w = prIndex[exercise.id]?.bestPerReps[reps] { return w }   // ✅ O(1)
        // Fallback
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
        // Fallback
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
        if let e = prIndex[exercise.id]?.bestE1RM { return e }            // ✅ O(1)
        // Fallback
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
    // Main API — unchanged, now powered by the helpers above.
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


//MARK: MEMORY

// MARK: - PR Index (persisted memory)

private struct LastSet: Codable {
    var date: Date
    var reps: Int
    var weightKg: Double
}

private struct ExercisePRs: Codable {
    // Best working weight per exact rep count (kg)
    var bestPerReps: [Int: Double] = [:]
    // Best estimated 1RM (kg)
    var bestE1RM: Double?
    // Most recent working set snapshot
    var lastWorking: LastSet?
}

extension WorkoutStore {
    // Persisted index: exerciseID -> PRs
    

    private var prFileURL: URL { appSupportDir.appendingPathComponent("pr_index.json") }

    private func loadPRIndex() {
        guard FileManager.default.fileExists(atPath: prFileURL.path) else {
            prIndex = [:]
            return
        }
        do {
            let data = try Data(contentsOf: prFileURL)
            prIndex = (try? JSONDecoder().decode([String: ExercisePRs].self, from: data)) ?? [:]
        } catch {
            print("⚠️ Failed to load PR index: \(error)")
            prIndex = [:]
        }
    }

    private func savePRIndex() {
        let toSave = prIndex
        let url = prFileURL
        Task.detached(priority: .utility) {
            do {
                let enc = JSONEncoder()
                enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
                enc.dateEncodingStrategy = .iso8601
                let data = try enc.encode(toSave)
                try data.write(to: url, options: [.atomic])
            } catch {
                print("⚠️ Failed to save PR index: \(error)")
            }
        }
    }

    /// Rebuild PRs from completed history (useful on first launch or if file is missing).
    private func recomputePRIndexFromHistory() {
        var fresh: [String: ExercisePRs] = [:]
        for w in completedWorkouts.sorted(by: { $0.date < $1.date }) {         // oldest -> newest
            for e in w.entries {
                var pr = fresh[e.exerciseID, default: ExercisePRs()]
                // Only *working* sets count toward PRs
                for s in e.sets where s.tag == .working && s.reps > 0 && s.weight > 0 {
                    // exact reps
                    pr.bestPerReps[s.reps] = max(pr.bestPerReps[s.reps] ?? 0, s.weight)
                    // 1RM candidate (Epley)
                    let e1rm = s.weight * (1.0 + Double(s.reps)/30.0)
                    pr.bestE1RM = max(pr.bestE1RM ?? 0, e1rm)
                    // last working (overwrite as we move forward in time)
                    pr.lastWorking = LastSet(date: w.date, reps: s.reps, weightKg: s.weight)
                }
                fresh[e.exerciseID] = pr
            }
        }
        prIndex = fresh
        savePRIndex()
    }

    /// Update PRs incrementally with one completed workout.
    private func updatePRIndex(with completed: CompletedWorkout) {
        for e in completed.entries {
            var pr = prIndex[e.exerciseID, default: ExercisePRs()]
            for s in e.sets where s.tag == .working && s.reps > 0 && s.weight > 0 {
                pr.bestPerReps[s.reps] = max(pr.bestPerReps[s.reps] ?? 0, s.weight)
                let e1rm = s.weight * (1.0 + Double(s.reps)/30.0)
                pr.bestE1RM = max(pr.bestE1RM ?? 0, e1rm)
                pr.lastWorking = LastSet(date: completed.date, reps: s.reps, weightKg: s.weight)
            }
            prIndex[e.exerciseID] = pr
        }
        savePRIndex()
    }

    /// (Optional) let the *current* workout keep "last" fresh during a session.
    private func updateLastWorkingFromCurrent() {
        guard let w = currentWorkout else { return }
        for e in w.entries {
            let workingSets = e.sets.filter { $0.tag == .working && $0.reps > 0 && $0.weight > 0 }
            guard let last = workingSets.last else { continue }
            var pr = prIndex[e.exerciseID, default: ExercisePRs()]
            pr.lastWorking = LastSet(date: Date(), reps: last.reps, weightKg: last.weight)
            prIndex[e.exerciseID] = pr
        }
        savePRIndex()
    }
}

extension WorkoutStore {
    /// Finishes the current workout and returns an ID + PR count for rewards.
    func finishCurrentWorkoutAndReturnPRs() -> (workoutId: String, prCount: Int) {
          guard let w = currentWorkout, !w.entries.isEmpty else { return ("none", 0) }

          let completed = CompletedWorkout(date: .now, entries: w.entries)

          // 🔖 Stamp DEX for each exercised movement that had work
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
          Task {
              await Persistence.shared.saveWorkouts(self.completedWorkouts)
              await Persistence.shared.deleteCurrentWorkout()
          }
          currentWorkout = nil
        Task.detached(priority: .utility) { [_stats, completedWorkouts] in
                   await _stats?.apply(completed, allWorkouts: completedWorkouts)
               }
          return (completed.id.uuidString, newPRs)
      }

    /// Count unique exercises that have a new PR (not individual sets)
    private func countPRs(in workout: CompletedWorkout) -> Int {
        var exercisesWithPR = Set<String>()
        for e in workout.entries {
            let existing = prIndex[e.exerciseID] ?? ExercisePRs()
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



