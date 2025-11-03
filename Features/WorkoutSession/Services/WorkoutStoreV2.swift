// WorkoutStoreV2.swift
// Refactored to use unified WorkoutStorage

import Foundation
import Combine
import SwiftUI
import HealthKit
import OSLog

@MainActor
final class WorkoutStoreV2: ObservableObject {
    // MARK: - Published State
    @Published var currentWorkout: CurrentWorkout?
    @Published var completedWorkouts: [CompletedWorkout] = []
    @Published private(set) var lastHealthImportEndDate: Date? = nil
    @Published private(set) var runs: [Run] = []

    // Store last discarded workout for undo functionality
    private var lastDiscardedWorkout: CurrentWorkout?

    /// Returns only valid cardio activities (filters out strength training and invalid data)
    var validRuns: [Run] {
        runs.filter { run in
            // Filter out invalid runs:
            // 1. Runs with 0 distance (likely misclassified strength training)
            //    Exception: Allow 0 distance if it's a valid cardio type with duration (e.g., stationary bike, elliptical)
            if run.distanceKm <= 0 {
                // If no workout type specified and 0 distance, filter it out
                guard let workoutType = run.workoutType else { return false }

                // Valid cardio types that might have 0 distance
                let validZeroDistanceTypes = [
                    "Elliptical",
                    "Stair Climbing",
                    "Rowing",
                    "High Intensity Interval Training",
                    "Dance",
                    "Kickboxing",
                    "Boxing"
                ]

                // If it's not a valid zero-distance type, filter it out
                if !validZeroDistanceTypes.contains(workoutType) {
                    return false
                }
            }

            // 2. Exclude traditional strength training and other non-cardio activities
            let excludedWorkoutTypes = [
                "Traditional Strength Training",
                "Functional Strength Training",
                "Core Training",
                "Flexibility",
                "Mind and Body",
                "Yoga"
            ]

            if let workoutType = run.workoutType, excludedWorkoutTypes.contains(workoutType) {
                return false
            }

            // 3. Filter out activities with 0 duration (invalid data)
            if run.durationSec <= 0 {
                return false
            }

            return true
        }
    }

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
                    AppLogger.info("Migration needed, performing one-time migration...", category: AppLogger.storage)
                    try await storage.migrateFromLegacyStorage()
                }

                // Check if app was force quit - discard any active workout
                let wasCleanExit = defaults.didExitCleanly
                AppLogger.info("App launch - didExitCleanly: \(wasCleanExit)", category: AppLogger.storage)

                if !wasCleanExit {
                    AppLogger.warning("App was force quit or crashed - discarding active workout", category: AppLogger.storage)
                    try? await storage.deleteCurrentWorkout()
                    // Clean up rest timer notifications and haptics
                    await MainActor.run {
                        RestTimerManager.shared.stopTimer()
                    }
                } else {
                    AppLogger.info("App exited cleanly last time - preserving active workout if exists", category: AppLogger.storage)
                }

                // Mark that app has launched and is now running
                defaults.markAppLaunched()
                defaults.didExitCleanly = false

                // Load all data from unified storage
                let (workouts, prIndex) = try await storage.loadWorkouts()
                let runs = try await storage.loadRuns()
                let currentWorkout = try await storage.loadCurrentWorkout()

                self.completedWorkouts = workouts
                self.prIndex = prIndex
                self.runs = runs
                self.currentWorkout = currentWorkout
                self.lastHealthImportEndDate = defaults.object(forKey: lastImportKey) as? Date

                AppLogger.success("Loaded from unified storage - Workouts: \(workouts.count), Runs: \(runs.count), PR entries: \(prIndex.count), Current workout: \(currentWorkout != nil ? "Yes" : "No")", category: AppLogger.storage)

                // Match workouts with HealthKit data if available
                matchAllWorkoutsWithHealthKit()

            } catch {
                AppLogger.error("Failed to load from storage: \(error)", category: AppLogger.storage)
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

        // Listen for set generation requests from widget (even when ExerciseSessionView is not open)
        NotificationCenter.default.publisher(for: NSNotification.Name("GeneratePendingSetBeforeTimer"))
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self = self else { return }
                if let exerciseID = notification.userInfo?["exerciseID"] as? String,
                   let shouldLogSet = notification.userInfo?["shouldLogSet"] as? Bool {
                    self.handleGeneratePendingSet(exerciseID: exerciseID, shouldLogSet: shouldLogSet)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Current Workout lifecycle

    func startWorkoutIfNeeded() {
        if currentWorkout == nil {
            currentWorkout = CurrentWorkout()
            // Mark app as having active state (force quit detection)
            defaults.didExitCleanly = false
            persistCurrentWorkout()
            AppLogger.debug("Started new workout - marked didExitCleanly = false", category: AppLogger.workout)
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
            plannedWorkoutID: planned.id,
            activeEntryID: entries.first?.id  // Set first exercise as active
        )
        // Mark app as having active state (force quit detection)
        defaults.didExitCleanly = false
        persistCurrentWorkout()
        AppLogger.info("Started planned workout: \(planned.splitDayName) - marked didExitCleanly = false", category: AppLogger.workout)
    }

    func discardCurrentWorkout() {
        // Save workout for undo
        lastDiscardedWorkout = currentWorkout

        currentWorkout = nil
        RestTimerManager.shared.stopTimer()

        Task {
            try? await storage.deleteCurrentWorkout()
        }

        // Show undo toast
        Task { @MainActor in
            UndoToastManager.shared.show(message: "Workout discarded") {
                Task { @MainActor in
                    self.undoDiscardWorkout()
                }
            }
        }
    }

    /// Restore discarded workout (undo operation)
    private func undoDiscardWorkout() {
        guard let workout = lastDiscardedWorkout else { return }

        currentWorkout = workout
        lastDiscardedWorkout = nil

        Task {
            try? await storage.saveCurrentWorkout(workout)
        }

        Haptics.soft()
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
            let didWork = e.sets.contains { set in
                guard set.tag == .working && set.isCompleted else { return false }
                return isValidSetForDex(set)
            }
            if didWork {
                RewardsEngine.shared.ensureDexUnlocked(exerciseKey: canonicalExerciseKey(from: e.exerciseID))
            }
        }
    }

    /// Check if a set is valid for unlocking dex based on tracking mode
    private func isValidSetForDex(_ set: SetInput) -> Bool {
        switch set.trackingMode {
        case .weighted, .bodyweight:
            return set.reps > 0
        case .timed:
            return set.durationSeconds > 0
        case .distance:
            return false // Future implementation
        }
    }

    func updateEntrySets(entryID: UUID, sets: [SetInput]) {
        guard var w = currentWorkout else { return }
        guard let idx = w.entries.firstIndex(where: { $0.id == entryID }) else { return }

        // Check if this is the first completed set
        let hadCompletedSets = w.entries[idx].sets.contains { $0.isCompleted }
        let willHaveCompletedSets = sets.contains { $0.isCompleted }

        w.entries[idx].sets = sets

        // Auto-set as active when logging first completed set
        if !hadCompletedSets && willHaveCompletedSets {
            w.activeEntryID = entryID
        }

        // Auto-advance: if this is the active exercise and all sets are now completed,
        // advance to the next "up next" exercise (one with no completed sets)
        if w.activeEntryID == entryID && !sets.isEmpty {
            let allCompleted = sets.allSatisfy { $0.isCompleted }
            if allCompleted {
                // Find first exercise with no completed sets
                if let nextEntry = w.entries.first(where: { entry in
                    entry.id != entryID && !entry.sets.contains(where: { $0.isCompleted })
                }) {
                    w.activeEntryID = nextEntry.id
                }
            }
        }

        currentWorkout = w
        persistCurrentWorkout()
        updateLastWorkingFromCurrent()

        let entry = w.entries[idx]
        let hasCompletedWorking = entry.sets.contains { set in
            guard set.tag == .working && set.isCompleted else { return false }
            return isValidSetForDex(set)
        }
        if hasCompletedWorking {
            let key = canonicalExerciseKey(from: entry.exerciseID)
            RewardsEngine.shared.ensureDexUnlocked(exerciseKey: key)
        }
    }

    func updateEntrySetsAndActiveIndex(entryID: UUID, sets: [SetInput], activeSetIndex: Int) {
        guard var w = currentWorkout else { return }
        guard let idx = w.entries.firstIndex(where: { $0.id == entryID }) else { return }

        // Check if this is the first completed set
        let hadCompletedSets = w.entries[idx].sets.contains { $0.isCompleted }
        let willHaveCompletedSets = sets.contains { $0.isCompleted }

        w.entries[idx].sets = sets
        w.entries[idx].activeSetIndex = activeSetIndex

        // Auto-set as active when logging first completed set
        if !hadCompletedSets && willHaveCompletedSets {
            w.activeEntryID = entryID
        }

        // Auto-advance: if this is the active exercise and all sets are now completed,
        // advance to the next "up next" exercise (one with no completed sets)
        if w.activeEntryID == entryID && !sets.isEmpty {
            let allCompleted = sets.allSatisfy { $0.isCompleted }
            if allCompleted {
                // Find first exercise with no completed sets
                if let nextEntry = w.entries.first(where: { entry in
                    entry.id != entryID && !entry.sets.contains(where: { $0.isCompleted })
                }) {
                    w.activeEntryID = nextEntry.id
                }
            }
        }

        currentWorkout = w
        persistCurrentWorkout()
        updateLastWorkingFromCurrent()

        let entry = w.entries[idx]
        let hasCompletedWorking = entry.sets.contains { set in
            guard set.tag == .working && set.isCompleted else { return false }
            return isValidSetForDex(set)
        }
        if hasCompletedWorking {
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
        workout.activeEntryID = entry.id  // Set newly added exercise as active
        currentWorkout = workout
        persistCurrentWorkout()
        AppLogger.debug("Added exercise '\(exercise.name)' to current workout (\(workout.entries.count) exercises total)", category: AppLogger.workout)
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

        // If we removed the active entry, update activeEntryID
        if w.activeEntryID == entryID {
            // Set to first remaining entry, or nil if none
            w.activeEntryID = w.entries.first?.id
        }

        currentWorkout = w.entries.isEmpty ? w : w
        persistCurrentWorkout()
    }

    func setActiveEntry(_ entryID: UUID) {
        guard var w = currentWorkout else { return }
        guard w.entries.contains(where: { $0.id == entryID }) else { return }
        w.activeEntryID = entryID
        currentWorkout = w
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
        let result = repo.exercise(byID: e.exerciseID)
        if result == nil {
            AppLogger.error("❌ Exercise not found for ID: '\(e.exerciseID)' (name: '\(e.exerciseName)')", category: AppLogger.app)
            AppLogger.debug("🔍 Total exercises in byID: \(repo.byID.count)", category: AppLogger.app)

            // Check for similar IDs (case-insensitive or substring matches)
            let similarIDs = repo.byID.keys.filter { $0.lowercased().contains(e.exerciseID.lowercased()) || e.exerciseID.lowercased().contains($0.lowercased()) }
            if !similarIDs.isEmpty {
                AppLogger.debug("🔍 Found similar IDs: \(similarIDs.joined(separator: ", "))", category: AppLogger.app)
            }

            // Check if the exact ID exists (debugging any whitespace/encoding issues)
            AppLogger.debug("🔍 Looking for ID: [\(e.exerciseID)] (length: \(e.exerciseID.count))", category: AppLogger.app)
        }
        return result
    }

    // Find existing entry for an exercise in current workout (to prevent duplicates)
    func existingEntry(for exerciseID: String) -> WorkoutEntry? {
        currentWorkout?.entries.first(where: { $0.exerciseID == exerciseID })
    }

    /// Handle set generation request from widget (works even when ExerciseSessionView is not open)
    /// - Parameters:
    ///   - exerciseID: The exercise to generate a set for
    ///   - shouldLogSet: If true, marks the generated set as completed
    private func handleGeneratePendingSet(exerciseID: String, shouldLogSet: Bool) {
        // Only generate if there's a pending flag for this exercise
        let manager = RestTimerManager.shared
        guard manager.hasPendingSetGeneration(for: exerciseID) else {
            AppLogger.debug("No pending set for exercise \(exerciseID), skipping generation", category: AppLogger.workout)
            return
        }

        // Find the entry for this exercise
        guard let entry = existingEntry(for: exerciseID) else {
            AppLogger.warning("Cannot generate set - exercise not in workout: \(exerciseID)", category: AppLogger.workout)
            manager.clearPendingSetGeneration(for: exerciseID)
            return
        }

        var sets = entry.sets
        var activeSetIndex = entry.activeSetIndex

        // Find last completed set to use as template (or last set if none completed)
        let templateSet = sets.last(where: { $0.isCompleted }) ?? sets.last

        // Find the next incomplete set to log, respecting activeSetIndex for prefilled workouts
        // First, try to find the first incomplete set starting from activeSetIndex
        let nextIncompleteIndex = sets.indices.first { index in
            index >= activeSetIndex && !sets[index].isCompleted
        } ?? sets.firstIndex { !$0.isCompleted }

        // If we have an incomplete set, mark it as completed (if shouldLogSet)
        if let index = nextIncompleteIndex {
            if shouldLogSet {
                sets[index].isCompleted = true
                // Update activeSetIndex to the next set (or stay at current if it's the last one)
                activeSetIndex = min(index + 1, sets.count - 1)
                updateEntrySetsAndActiveIndex(entryID: entry.id, sets: sets, activeSetIndex: activeSetIndex)
                AppLogger.info("Logged existing incomplete set #\(index + 1) from widget for \(entry.exerciseName)", category: AppLogger.workout)
            } else {
                AppLogger.debug("Set already exists and not logging, skipping generation", category: AppLogger.workout)
            }
            manager.clearPendingSetGeneration(for: exerciseID)
            return
        }

        // Generate a new set based on template
        let newSet: SetInput
        if let template = templateSet {
            newSet = SetInput(
                reps: template.reps,
                weight: template.weight,
                tag: template.tag,
                autoWeight: false,
                didSeedFromMemory: false,
                isCompleted: shouldLogSet,  // Mark as completed if requested
                isGhost: false,
                isAutoGeneratedPlaceholder: !shouldLogSet  // Mark as auto-generated if not logging
            )
        } else {
            // No template - create default set
            newSet = SetInput(
                reps: 10,
                weight: 0,
                tag: .working,
                autoWeight: true,
                didSeedFromMemory: false,
                isCompleted: shouldLogSet,
                isGhost: false,
                isAutoGeneratedPlaceholder: !shouldLogSet
            )
        }

        sets.append(newSet)

        // Update the workout with new sets
        updateEntrySets(entryID: entry.id, sets: sets)

        let action = shouldLogSet ? "Logged" : "Generated"
        AppLogger.info("\(action) set from widget for \(entry.exerciseName)", category: AppLogger.workout)

        // Clear the pending flag
        manager.clearPendingSetGeneration(for: exerciseID)
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

        // Show undo toast
        Task { @MainActor in
            UndoToastManager.shared.show(message: "Workout\(removed.count > 1 ? "s" : "") deleted") {
                Task { @MainActor in
                    self.undoDeleteWorkouts(removed, at: offsets)
                }
            }
        }
    }

    /// Restore deleted workouts (undo operation)
    private func undoDeleteWorkouts(_ workouts: [CompletedWorkout], at offsets: IndexSet) {
        // Insert workouts back at their original positions
        for (offset, workout) in zip(offsets, workouts) {
            if offset <= completedWorkouts.count {
                completedWorkouts.insert(workout, at: offset)
            } else {
                completedWorkouts.append(workout)
            }
        }
        persistWorkouts()

        // Re-aggregate stats for affected weeks
        let weeks = Set(workouts.map { startOfWeek(for: $0.date) })
        Task.detached(priority: .utility) { [_stats, completedWorkouts] in
            await _stats?.invalidate(weeks: weeks, from: completedWorkouts)
        }

        Haptics.soft()
    }

    /// Delete a single workout by ID
    func deleteWorkout(_ workout: CompletedWorkout) {
        guard let index = completedWorkouts.firstIndex(where: { $0.id == workout.id }) else { return }
        deleteWorkouts(at: IndexSet(integer: index))
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
        AppLogger.debug("Batch updated \(updateCount)/\(updatedRuns.count) runs", category: AppLogger.health)
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
        // Return ALL runs (including strength workouts) - let callers filter as needed
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
            AppLogger.warning("Health import failed: \(error)", category: AppLogger.health)
        }
    }

    // MARK: - HealthKit Matching

    @discardableResult
    func matchWithHealthKit(_ workout: CompletedWorkout) -> Bool {
        guard workout.matchedHealthKitUUID == nil else {
            AppLogger.debug("Workout already matched, skipping", category: AppLogger.health)
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
            AppLogger.warning("Failed to fetch heart rate samples: \(error)", category: AppLogger.health)
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
            AppLogger.success("Matched \(matchCount) workouts with HealthKit data", category: AppLogger.health)
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
                AppLogger.error("Failed to persist workouts: \(error)", category: AppLogger.storage)
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
                for s in entry.sets where s.tag == .working && s.reps > 0 {
                    out.append((w.date, s))
                }
            }
        }

        if let w = currentWorkout,
           let entry = w.entries.first(where: { $0.exerciseID == exerciseID })
        {
            for s in entry.sets where s.tag == .working && s.reps > 0 {
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
                if let currentBest = best {
                    if d < currentBest.d || (d == currentBest.d && w > currentBest.w) {
                        best = (r, w, d)
                    }
                } else {
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
            if let currentBest = best {
                if d < currentBest.delta || (d == currentBest.delta && s.weight > currentBest.weight) {
                    best = (s.reps, s.weight, d)
                }
            } else {
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

    /// Personal best reps for bodyweight exercises (max reps achieved)
    func personalBestReps(for exercise: Exercise) -> Int? {
        if let pr = prIndex[exercise.id]?.bestReps {
            return pr
        }
        let sets = allWorkingSets(for: exercise.id).map { $0.set }
        return sets.map { $0.reps }.max()
    }
}

// MARK: - PR Index Management

extension WorkoutStoreV2 {

    private func updatePRIndex(with completed: CompletedWorkout) {
        for e in completed.entries {
            var pr = prIndex[e.exerciseID, default: ExercisePRsV2()]

            for s in e.sets where s.tag == .working {
                // Determine tracking mode
                let trackingMode = s.trackingMode

                switch trackingMode {
                case .weighted:
                    // Weighted exercises: track weight-based PRs
                    guard s.reps > 0 && s.weight > 0 else { continue }

                    // Best per reps
                    pr.bestPerReps[s.reps] = max(pr.bestPerReps[s.reps] ?? 0, s.weight)

                    // Best E1RM (Epley formula)
                    let e1rm = s.weight * (1.0 + Double(s.reps) / 30.0)
                    pr.bestE1RM = max(pr.bestE1RM ?? 0, e1rm)

                    // All-time best
                    pr.allTimeBest = max(pr.allTimeBest ?? 0, s.weight)

                    // Last working set
                    pr.lastWorking = LastSetV2(date: completed.date, reps: s.reps, weightKg: s.weight)

                case .bodyweight:
                    // Bodyweight exercises: track best reps
                    guard s.reps > 0 else { continue }
                    pr.bestReps = max(pr.bestReps ?? 0, s.reps)

                    // Last working set (weight is always 0)
                    pr.lastWorking = LastSetV2(date: completed.date, reps: s.reps, weightKg: 0)

                case .timed:
                    // Timed exercises: track best duration
                    guard s.durationSeconds > 0 else { continue }
                    pr.bestDuration = max(pr.bestDuration ?? 0, s.durationSeconds)

                    // Last working set (store duration in reps field for now, weight is 0)
                    pr.lastWorking = LastSetV2(date: completed.date, reps: s.durationSeconds, weightKg: 0)

                case .distance:
                    // Future: distance-based tracking
                    break
                }

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
            let workingSets = e.sets.filter { $0.tag == .working }
            guard let last = workingSets.last else { continue }

            // Skip empty sets based on tracking mode
            switch last.trackingMode {
            case .weighted:
                guard last.reps > 0 && last.weight > 0 else { continue }
            case .bodyweight:
                guard last.reps > 0 else { continue }
            case .timed:
                guard last.durationSeconds > 0 else { continue }
            case .distance:
                continue // Future implementation
            }

            var pr = prIndex[e.exerciseID, default: ExercisePRsV2()]

            // Update last working set based on tracking mode
            switch last.trackingMode {
            case .weighted:
                pr.lastWorking = LastSetV2(date: Date(), reps: last.reps, weightKg: last.weight)
            case .bodyweight:
                pr.lastWorking = LastSetV2(date: Date(), reps: last.reps, weightKg: 0)
            case .timed:
                pr.lastWorking = LastSetV2(date: Date(), reps: last.durationSeconds, weightKg: 0)
            case .distance:
                break
            }

            prIndex[e.exerciseID] = pr
        }
    }

    func finishCurrentWorkoutAndReturnPRs() -> (workoutId: String, prCount: Int) {
        guard let w = currentWorkout, !w.entries.isEmpty else { return ("none", 0) }

        let completed = CompletedWorkout(date: .now, entries: w.entries, plannedWorkoutID: w.plannedWorkoutID)

        // Unlock dex entries
        for e in completed.entries {
            let didWork = e.sets.contains { set in
                guard set.tag == .working && set.isCompleted else { return false }
                return isValidSetForDex(set)
            }
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
