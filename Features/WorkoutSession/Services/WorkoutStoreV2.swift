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
    @Published private(set) var lastCompletedWorkout: CompletedWorkout?
    @Published private(set) var lastHealthImportEndDate: Date? = nil
    /// Every run with its detail arrays. Private: history-wide code reads `runSummaries`, one
    /// workout's detail comes through `runDetail(id:)` or `loadRun(id:)`, and changes go through
    /// `addRun`, `editRun(s)` and `removeRun`. Not published itself: every mutation also updates
    /// `runSummaries`, once, which publishes the change.
    private var runs: [Run] = [] {
        didSet { runsSave.changed() }
    }
    /// One summary per run, in the same order, updated in the same mutation as `runs`. History
    /// order is not date order: new runs are inserted first.
    @Published private(set) var runSummaries: [RunSummary] = []
    /// Live detail handles, by workout id. Weak: a handle lives as long as a screen holds it.
    private var runDetailHandles: [UUID: WeakRunDetail] = [:]
    /// The per-workout history (runs_v3), set at load only when the storage found it active.
    /// nil means today's path: `runs` holds every run and one file stores them. Every run
    /// method below branches on this once, at its top.
    private var runsV3: RunsV3History?
    private var runsV3Observers: [NSObjectProtocol] = []
    private var protectedDataObserver: NSObjectProtocol?
    private let protectedDataAvailable: @MainActor () -> Bool
    /// Whether a migration to runs_v3 may start (RunHistoryConfiguration.migrationMayStart:
    /// false in every Release build). Injectable for tests only.
    private let migrationGate: @MainActor () -> Bool
    private let isHealthImportRunning: @MainActor () -> Bool
    private var migrationTask: Task<Void, Never>?
    /// Seconds after a clean load before a permitted migration starts.
    var migrationDelay: Duration = .seconds(20)
    /// Stored summaries that did not match memory after a drain (tests expect none).
    private(set) var runsV3SummaryMismatches = 0
    /// Full runs held in memory by the per-workout history (0 on today's path, which holds them all).
    var runsV3CachedRunCount: Int { runsV3?.cachedCount ?? 0 }

    // Store last discarded workout for undo functionality
    private var lastDiscardedWorkout: CurrentWorkout?

    // Track HealthKit UUIDs that should be ignored (from discarded workouts)
    private(set) var ignoredHealthKitUUIDs: Set<UUID> = [] {
        didSet { ignoredSave.changed() }
    }
    private var runsSave = SaveTracker()
    private var ignoredSave = SaveTracker()
    private var discardedWorkoutWindows: [DiscardedWorkoutWindow] = []

    /// Only valid cardio activities: strength training and invalid data left out.
    var validRunSummaries: [RunSummary] {
        runSummaries.filter(\.isValidCardio)
    }

    func runSummary(id: UUID) -> RunSummary? {
        runSummaries.first { $0.id == id }
    }

    func runSummary(healthKitUUID: UUID) -> RunSummary? {
        runSummaries.first { $0.healthKitUUID == healthKitUUID }
    }

    /// The full run with this id, from memory. Screens read it through `runDetail(id:)`.
    private func fullRun(id: UUID) -> Run? {
        runs.first { $0.id == id }
    }

    // MARK: - Run detail

    /// The live handle for one workout's full record. While any caller holds it, every caller
    /// gets the same instance, and every change to that workout updates it in the same
    /// main-actor turn as `runSummaries`. Returned already loaded, from memory.
    func runDetail(id: UUID) -> RunDetail {
        if let live = runDetailHandles[id]?.detail { return live }
        if let runsV3 { return makeRunsV3Detail(id: id, history: runsV3) }
        let detail = RunDetail(id: id, phase: fullRun(id: id).map(RunDetail.Phase.loaded) ?? .unavailable(.removed))
        runDetailHandles = runDetailHandles.filter { $0.value.detail != nil }
        runDetailHandles[id] = WeakRunDetail(detail: detail)
        return detail
    }

    /// One workout's full record, for code that is not a view (sharing, posting). Waits for the
    /// history to load; throws if it could not load, or if the task is cancelled.
    func loadRun(id: UUID) async throws -> RunLoadResult {
        try Task.checkCancellation()
        try await waitForStorage()
        try Task.checkCancellation()
        if let runsV3 { return try await loadRunsV3(id, history: runsV3) }
        return fullRun(id: id).map(RunLoadResult.loaded) ?? .removed
    }

    /// Several workouts' full records at once.
    func loadRuns(ids: [UUID]) async throws -> [UUID: RunLoadResult] {
        try Task.checkCancellation()
        try await waitForStorage()
        try Task.checkCancellation()
        var results: [UUID: RunLoadResult] = [:]
        if let runsV3 {
            for id in ids { results[id] = try await loadRunsV3(id, history: runsV3) }
            return results
        }
        for id in ids { results[id] = fullRun(id: id).map(RunLoadResult.loaded) ?? .removed }
        return results
    }

    /// Brings the live handles for these ids up to date with `runs`; nil means every live handle.
    private func refreshRunDetails(_ ids: [UUID]?) {
        guard !runDetailHandles.isEmpty else { return }
        let targets = ids ?? Array(runDetailHandles.keys)
        if let runsV3 {
            refreshRunsV3Details(targets, history: runsV3)
            return
        }
        for id in targets {
            guard let detail = runDetailHandles[id]?.detail else {
                runDetailHandles[id] = nil
                continue
            }
            if let run = fullRun(id: id) {
                detail.setLoaded(run)
            } else if detail.phase != .unavailable(.removed) {
                detail.setUnavailable(.removed)
            }
        }
    }

    private var prIndex: [String: ExercisePRsV2] = [:]

    /// Guard flag: true only after storage has been successfully loaded.
    /// persistWorkouts/persistRuns/persistCurrentWorkout refuse to write while false,
    /// preventing a failed load (e.g. device locked during background task) from
    /// overwriting good data with an empty array.
    @Published private(set) var isStorageLoaded = false
    @Published private(set) var storageLoadError: Error?
    private var isLoadingStorage = false

    // MARK: - Dependencies
    private let storage: WorkoutStorage
    private let rewardsEngine: RewardsEngine
    private var storageLoadTask: Task<Void, Never>?
    private var pendingSave: Task<Void, Error>?
    private let repo: ExerciseRepository
    private var cancellables = Set<AnyCancellable>()

    // Optional competitive features
    weak var battleRepository: BattleRepository?
    weak var challengeRepository: ChallengeRepository?
    weak var authService: SupabaseAuthService?
    private var plannedWorkoutCompletionHandler: ((UUID, CompletedWorkout) -> Void)?

    /// Receives the PRs found when a workout finishes. Tests replace it to observe them.
    var prAutoPostSink: ([PRAchievement], CompletedWorkout) -> Void = { prAchievements, workout in
        Task.detached(priority: .utility) {
            await PRAutoPostService.shared.handlePRsIfNeeded(
                prAchievements: prAchievements,
                workout: workout
            )
        }
    }

    // MARK: - UserDefaults keys
    private let defaults: UserDefaults
    private let lastImportKey = "health.lastImport.endDate"

    private var _stats: StatsAggregator?
    var stats: StatsAggregator? { _stats }

    func waitForStorage() async throws {
        await storageLoadTask?.value
        guard isStorageLoaded else {
            throw StorageError.validationFailed("Workout history could not be loaded")
        }
    }

    func installStats(_ stats: StatsAggregator) {
        self._stats = stats
    }

    func installPlannedWorkoutCompletionHandler(_ handler: @escaping (UUID, CompletedWorkout) -> Void) {
        plannedWorkoutCompletionHandler = handler
    }

    // MARK: - Init
    init(
        repo: ExerciseRepository = .shared,
        storage: WorkoutStorage = .shared,
        defaults: UserDefaults = .standard,
        rewardsEngine: RewardsEngine = .shared,
        protectedDataAvailable: (@MainActor () -> Bool)? = nil,
        migrationGate: (@MainActor () -> Bool)? = nil,
        isHealthImportRunning: (@MainActor () -> Bool)? = nil
    ) {
        self.repo = repo
        self.storage = storage
        self.defaults = defaults
        self.rewardsEngine = rewardsEngine
        self.protectedDataAvailable = protectedDataAvailable ?? { UIApplication.shared.isProtectedDataAvailable }
        self.migrationGate = migrationGate ?? { RunHistoryConfiguration.migrationMayStart }
        self.isHealthImportRunning = isHealthImportRunning ?? { HealthKitManager.shared.isSyncing }

        retryStorageLoad()

        repo.$exercises
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshCurrentWorkoutEntryNames() }
            .store(in: &cancellables)


    }

    func retryStorageLoad() {
        guard !isStorageLoaded, !isLoadingStorage else { return }
        isLoadingStorage = true
        storageLoadError = nil
        storageLoadTask = Task {
            defer { isLoadingStorage = false }
            do {
                // Check if migration is needed
                if await storage.needsMigration() {
                    AppLogger.info("Migration needed, performing one-time migration...", category: AppLogger.storage)
                    try await storage.migrateFromLegacyStorage()
                }

                // Restore saved work regardless of how the previous process ended.
                // Load all data from unified storage
                let (workouts, prIndex) = try await storage.loadWorkouts()
                // The one place that decides: runs_v3 when its entry exists, else runs_v2.json
                // exactly as before (WorkoutStorage.openRunHistory).
                let runHistory = try await storage.openRunHistory(isProtectedDataAvailable: protectedDataAvailable())
                let currentWorkout = try await storage.loadCurrentWorkout()
                let (ignoredUUIDs, ignoredStamp) = try await storage.loadIgnoredHealthKitUUIDsWithStamp()
                let discardWindows = try await storage.loadDiscardedWorkoutWindows()

                let runCount: Int
                switch runHistory {
                case .v2(let runs, let runsStamp):
                    // Exactly what is on disk, so clean. Anything applied after this (deduplication
                    // below) changes the revision and is written.
                    setRuns(runs)
                    runsSave.markSaved(runsSave.revision, stamp: runsStamp)
                    runCount = runs.count
                case .v3(let opened):
                    activateRunsV3(opened)
                    runCount = runSummaries.count
                }

                // IMPORTANT: Sort workouts by date to ensure proper ordering
                self.currentWorkout = currentWorkout
                self.ignoredHealthKitUUIDs = ignoredUUIDs
                ignoredSave.markSaved(ignoredSave.revision, stamp: ignoredStamp)
                self.discardedWorkoutWindows = discardWindows
                self.lastHealthImportEndDate = defaults.object(forKey: lastImportKey) as? Date

                // A decoded empty collection is a committed deletion, not corruption.
                self.completedWorkouts = workouts.sorted(by: { $0.date < $1.date })
                self.prIndex = prIndex

                // Storage is confirmed loaded — allow writes from this point
                self.isStorageLoaded = true

                // One-time deduplication of runs (fix for duplicate HealthKit imports)
                let deduplicationFlag = "runs.deduplication.v1"
                if !defaults.bool(forKey: deduplicationFlag) {
                    deduplicateRuns()
                    defaults.set(true, forKey: deduplicationFlag)
                    AppLogger.info("Completed one-time run deduplication", category: AppLogger.health)
                }

                // Repair low-value HealthKit operational SwiftData state from durable runs.
                await HealthKitManager.shared.repairOperationalStateIfNeeded(runs: self.runSummaries)

                AppLogger.success("Loaded from unified storage - Workouts: \(self.completedWorkouts.count), Runs: \(runCount), PR entries: \(self.prIndex.count), Current workout: \(currentWorkout != nil ? "Yes" : "No")", category: AppLogger.storage)

                // Match workouts with HealthKit data if available
                matchAllWorkoutsWithHealthKit()

                // Off unless the migration is permitted (never in Release): then nothing happens.
                scheduleRunHistoryMigration()

            } catch StorageError.runHistoryDeferred {
                // Before the first unlock: nothing was concluded. Load again once protected data
                // is available; until then the launch screen stays and nothing is written.
                isStorageLoaded = false
                AppLogger.info("Workout history waits for the device to be unlocked", category: AppLogger.storage)
                retryWhenProtectedDataIsAvailable()
            } catch {
                isStorageLoaded = false
                storageLoadError = error
                AppLogger.error("Failed to load from storage: \(error)", category: AppLogger.storage)
                // Leave isStorageLoaded = false so persistWorkouts() won't overwrite good data.
                // State stays as empty defaults; HealthKit sync will add data once storage is accessible.
            }
        }
    }

    // MARK: - Current Workout lifecycle

    func startWorkoutIfNeeded() {
        if currentWorkout == nil {
            currentWorkout = CurrentWorkout()
            persistCurrentWorkout()
            AppLogger.debug("Started new workout", category: AppLogger.workout)
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
                sets: ghostSets,
                plannedExerciseID: plannedEx.id
            )
        }

        currentWorkout = CurrentWorkout(
            startedAt: .now,
            entries: entries,
            plannedWorkoutID: planned.id,
            activeEntryID: entries.first?.id  // Set first exercise as active
        )
        persistCurrentWorkout()
        AppLogger.info("Started planned workout: \(planned.splitDayName)", category: AppLogger.workout)
    }

    func discardCurrentWorkout() {
        // Notify Watch to discard HKWorkoutSession (don't save to HealthKit)
        WatchConnectivityManager.shared.sendDiscardWatchWorkout()

        // Track the discard window to prevent re-importing from HealthKit
        if let workout = currentWorkout {
            let startedAt = workout.startedAt
            let window = DiscardedWorkoutWindow(workoutStartedAt: startedAt, discardedAt: Date())
            discardedWorkoutWindows.append(window)
            let windows = discardedWorkoutWindows
            enqueueSave { try await $0.saveDiscardedWorkoutWindows(windows) }
            AppLogger.info("Tracked discard window: \(startedAt) to now", category: AppLogger.workout)
        }

        // Save workout for undo
        lastDiscardedWorkout = currentWorkout

        currentWorkout = nil
        RestTimerManager.shared.stopTimer()

        // Queued behind any pending current-workout save so that save cannot land after the delete.
        enqueueSave { try await $0.deleteCurrentWorkout() }

        // Show undo notification
        AppNotificationManager.shared.showWorkoutDiscarded {
            self.undoDiscardWorkout()
        }
    }

    /// Restore discarded workout (undo operation)
    private func undoDiscardWorkout() {
        guard let workout = lastDiscardedWorkout else { return }

        currentWorkout = workout
        lastDiscardedWorkout = nil

        enqueueSave { try await $0.saveCurrentWorkout(workout) }

        Haptics.soft()
    }

    func finishCurrentWorkout() {
        guard let w = currentWorkout, !w.entries.isEmpty else { return }
        var completed = CompletedWorkout(date: .now, startedAt: w.startedAt, entries: w.entries, plannedWorkoutID: w.plannedWorkoutID, excusedPlannedExerciseIDs: w.excusedPlannedExerciseIDs)

        // Find PRs for auto-posting before the index includes this workout
        let prAchievements = extractPRDetails(in: completed)

        // Update PR index and get count of new PRs
        let prCount = updatePRIndex(with: completed)
        completed.detectedPRCount = prCount

        // Store workout for social sharing on win screen
        Task { @MainActor in
            WinScreenCoordinator.shared.setCompletedWorkout(completed)
        }

        // Add workout and keep array sorted by date
        completedWorkouts.append(completed)
        completedWorkouts.sort(by: { $0.date < $1.date })

        refreshSmartNotificationLearningAfterWorkoutCompletion()

        // Handle PR auto-posting
        handlePRAutoPost(prAchievements, for: completed)

        // Persist to storage
        persistWorkouts()

        if let plannedWorkoutID = completed.plannedWorkoutID {
            plannedWorkoutCompletionHandler?(plannedWorkoutID, completed)
        }

        // Update battles and challenges (non-blocking)
        updateCompetitiveFeatures(for: completed)

        // Update stats
        Task.detached(priority: .utility) { [_stats, completedWorkouts] in
            await _stats?.apply(completed, allWorkouts: completedWorkouts)
        }

        // Notify Watch to end HKWorkoutSession
        WatchConnectivityManager.shared.sendEndWatchWorkout()

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
                rewardsEngine.ensureDexUnlocked(exerciseKey: canonicalExerciseKey(from: e.exerciseID))
            }
        }

        // Match with HealthKit workout (if available)
        // Use delays to allow Apple Watch to finish syncing to HealthKit
        Task { [weak self] in
            guard let self = self else { return }

            // First attempt: Wait 10 seconds for Apple Watch to sync
            try? await Task.sleep(nanoseconds: 10_000_000_000)

            let firstAttemptSuccess = await MainActor.run {
                if self.matchWithHealthKit(completed) {
                    AppLogger.success("Workout matched with HealthKit data (1st attempt)", category: AppLogger.health)
                    self.objectWillChange.send()
                    return true
                }
                return false
            }

            if firstAttemptSuccess { return }

            // Second attempt: Wait another 20 seconds (total 30 sec)
            AppLogger.debug("No match found on 1st attempt, retrying in 20 seconds...", category: AppLogger.health)
            try? await Task.sleep(nanoseconds: 20_000_000_000)

            let secondAttemptSuccess = await MainActor.run {
                // Refresh runs from HealthKit before matching
                if self.matchWithHealthKit(completed) {
                    AppLogger.success("Workout matched with HealthKit data (2nd attempt)", category: AppLogger.health)
                    self.objectWillChange.send()
                    return true
                }
                return false
            }

            if secondAttemptSuccess { return }

            // Third attempt: Wait another 30 seconds (total 60 sec)
            AppLogger.debug("No match found on 2nd attempt, final retry in 30 seconds...", category: AppLogger.health)
            try? await Task.sleep(nanoseconds: 30_000_000_000)

            await MainActor.run {
                if self.matchWithHealthKit(completed) {
                    AppLogger.success("Workout matched with HealthKit data (3rd attempt)", category: AppLogger.health)
                    self.objectWillChange.send()
                } else {
                    AppLogger.warning("No matching HealthKit workout found after 3 attempts (checked ±10 min window)", category: AppLogger.health)
                }
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
        guard let entry = currentWorkout?.entries.first(where: { $0.id == entryID }) else { return }
        updateEntrySetsAndActiveIndex(entryID: entryID, sets: sets, activeSetIndex: entry.activeSetIndex)
    }

    func updateEntrySetsAndActiveIndex(entryID: UUID, sets: [SetInput], activeSetIndex: Int,
                                      receipt: SetLogReceipt? = nil) {
        guard var w = currentWorkout else { return }
        guard let idx = w.entries.firstIndex(where: { $0.id == entryID }) else { return }

        // Check if this is the first completed set
        let hadCompletedSets = w.entries[idx].sets.contains { $0.isCompleted }
        let willHaveCompletedSets = sets.contains { $0.isCompleted }

        w.entries[idx].sets = sets
        w.entries[idx].activeSetIndex = activeSetIndex
        if let receipt { w.setLogReceipts.append(receipt) }

        // Auto-set as active when logging first completed set
        if !hadCompletedSets && willHaveCompletedSets {
            w.activeEntryID = entryID
        }

        // Auto-advance with superset support
        if w.activeEntryID == entryID && !sets.isEmpty {
            let entry = w.entries[idx]
            let completedCount = sets.filter { $0.isCompleted }.count
            let allCompleted = sets.allSatisfy { $0.isCompleted }

            if let groupID = entry.supersetGroupID {
                // SUPERSET: Switch to next exercise in group after each completed set
                if let nextEntry = w.nextSupersetEntry(after: entryID) {
                    let nextCompletedCount = nextEntry.sets.filter { $0.isCompleted }.count
                    // Switch if next exercise has fewer completed sets
                    if nextCompletedCount < completedCount {
                        w.activeEntryID = nextEntry.id
                    }
                }

                // If all superset exercises are fully complete, advance outside group
                let allSupersetComplete = w.entriesInSuperset(groupID).allSatisfy { e in
                    e.sets.allSatisfy { $0.isCompleted }
                }
                if allSupersetComplete {
                    if let nextEntry = w.entries.first(where: { e in
                        e.supersetGroupID != groupID && !e.sets.allSatisfy { $0.isCompleted }
                    }) {
                        w.activeEntryID = nextEntry.id
                    }
                }
            } else {
                // STANDALONE: Original logic - advance when all sets completed
                if allCompleted {
                    if let nextEntry = w.entries.first(where: { entry in
                        entry.id != entryID && !entry.sets.contains(where: { $0.isCompleted })
                    }) {
                        w.activeEntryID = nextEntry.id
                    }
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
            rewardsEngine.ensureDexUnlocked(exerciseKey: key)
        }
    }

    // MARK: - Entries Management

    @discardableResult
    func addExerciseToCurrent(_ exercise: Exercise) -> UUID {
        let isFirstExercise = currentWorkout == nil || currentWorkout?.entries.isEmpty == true

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

        // Show success notification for first exercise (confirms workout started)
        if isFirstExercise {
            AppNotificationManager.shared.showWorkoutStarted(exerciseName: exercise.name)
            // Notify Watch to start HKWorkoutSession
            WatchConnectivityManager.shared.sendStartWatchWorkout()
        }

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

        // Get the entry before removal (need superset group + planned exercise tracking)
        let removedEntry = w.entries.first(where: { $0.id == entryID })
        let supersetGroupID = removedEntry?.supersetGroupID

        // Record intentional removal so the planner treats this as excused, not missed
        if let pid = removedEntry?.plannedExerciseID {
            w.excusedPlannedExerciseIDs.insert(pid)
        }

        w.entries.removeAll { $0.id == entryID }

        // Dissolve superset if only 1 entry remains after removal
        if let gid = supersetGroupID {
            let remaining = w.entries.filter { $0.supersetGroupID == gid }
            if remaining.count == 1,
               let lastIdx = w.entries.firstIndex(where: { $0.id == remaining[0].id }) {
                w.entries[lastIdx].supersetGroupID = nil
                w.entries[lastIdx].orderInSuperset = nil
                AppLogger.info("Dissolved superset after entry removal - only 1 entry remained", category: AppLogger.workout)
            }
        }

        // If we removed the active entry, update activeEntryID
        if w.activeEntryID == entryID {
            // Set to first remaining entry, or nil if none
            w.activeEntryID = w.entries.first?.id
        }

        if w.entries.isEmpty {
            currentWorkout = nil
            RestTimerManager.shared.stopTimer()
            WatchConnectivityManager.shared.sendDiscardWatchWorkout()
        } else {
            currentWorkout = w
        }
        persistCurrentWorkout()
    }

    func setActiveEntry(_ entryID: UUID) {
        guard var w = currentWorkout else { return }
        guard w.entries.contains(where: { $0.id == entryID }) else { return }
        w.activeEntryID = entryID
        currentWorkout = w
        persistCurrentWorkout()
    }

    // MARK: - Superset Management

    /// Add exercise to superset with the specified entry
    /// Creates a new superset group if the target entry isn't already in one
    /// If the exercise already exists in the workout, it updates the existing entry
    @discardableResult
    func addExerciseToSuperset(_ exercise: Exercise, withEntryID targetEntryID: UUID) -> UUID {
        guard var w = currentWorkout else { return UUID() }

        // Get or create superset group ID
        let targetEntry = w.entries.first(where: { $0.id == targetEntryID })
        let groupID = targetEntry?.supersetGroupID ?? UUID()

        // Update target entry if not already in superset
        if let idx = w.entries.firstIndex(where: { $0.id == targetEntryID }),
           w.entries[idx].supersetGroupID == nil {
            w.entries[idx].supersetGroupID = groupID
            w.entries[idx].orderInSuperset = 0
        }

        // Check if this exercise already exists in the workout
        if let existingIdx = w.entries.firstIndex(where: { $0.exerciseID == exercise.id }) {
            // Update existing entry to join the superset
            let existingCount = w.entries.filter { $0.supersetGroupID == groupID }.count
            w.entries[existingIdx].supersetGroupID = groupID
            w.entries[existingIdx].orderInSuperset = existingCount

            let entryID = w.entries[existingIdx].id
            w.activeEntryID = entryID
            currentWorkout = w
            persistCurrentWorkout()
            AppLogger.info("Added existing '\(exercise.name)' to superset with entry \(targetEntryID)", category: AppLogger.workout)
            return entryID
        }

        // Count existing entries in superset for ordering
        let existingCount = w.entries.filter { $0.supersetGroupID == groupID }.count

        // Create new entry in superset
        let newEntry = WorkoutEntry(
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            muscleGroups: exercise.primaryMuscles + exercise.secondaryMuscles,
            sets: [],
            supersetGroupID: groupID,
            orderInSuperset: existingCount
        )

        // Insert after the last entry in this superset
        if let lastIdx = w.entries.lastIndex(where: { $0.supersetGroupID == groupID }) {
            w.entries.insert(newEntry, at: lastIdx + 1)
        } else {
            w.entries.append(newEntry)
        }

        w.activeEntryID = newEntry.id
        currentWorkout = w
        persistCurrentWorkout()
        AppLogger.info("Added '\(exercise.name)' to superset with entry \(targetEntryID)", category: AppLogger.workout)
        return newEntry.id
    }

    /// Remove entry from superset (dissolves superset if only 1 entry remains)
    func removeFromSuperset(entryID: UUID) {
        guard var w = currentWorkout,
              let idx = w.entries.firstIndex(where: { $0.id == entryID }) else { return }

        let groupID = w.entries[idx].supersetGroupID
        w.entries[idx].supersetGroupID = nil
        w.entries[idx].orderInSuperset = nil

        // Dissolve superset if only 1 entry remains
        if let gid = groupID {
            let remaining = w.entries.filter { $0.supersetGroupID == gid }
            if remaining.count == 1,
               let lastIdx = w.entries.firstIndex(where: { $0.id == remaining[0].id }) {
                w.entries[lastIdx].supersetGroupID = nil
                w.entries[lastIdx].orderInSuperset = nil
                AppLogger.info("Dissolved superset - only 1 entry remained", category: AppLogger.workout)
            }
        }

        currentWorkout = w
        persistCurrentWorkout()
        AppLogger.info("Removed entry \(entryID) from superset", category: AppLogger.workout)
    }

    /// Toggle superset status for an entry with the previous exercise
    /// - If entry is in a superset: removes it
    /// - If entry is NOT in a superset: joins the previous exercise's superset group (or creates one)
    /// - Returns: true if now in superset, false if removed from superset, nil if operation failed
    @discardableResult
    func toggleSupersetWithPrevious(entryID: UUID) -> Bool? {
        guard var w = currentWorkout,
              let idx = w.entries.firstIndex(where: { $0.id == entryID }) else { return nil }

        let entry = w.entries[idx]

        // If already in a superset, remove it
        if entry.supersetGroupID != nil {
            removeFromSuperset(entryID: entryID)
            return false
        }

        // Find the previous exercise in the workout (by array order)
        guard idx > 0 else {
            AppLogger.debug("Cannot superset first exercise in workout", category: AppLogger.workout)
            return nil
        }

        let previousEntry = w.entries[idx - 1]

        // Determine the superset group ID
        // If previous is already in a superset, join that group (tri-set/giant-set)
        // Otherwise, create a new group
        let groupID: UUID
        if let existingGroupID = previousEntry.supersetGroupID {
            groupID = existingGroupID
        } else {
            // Create new group and add previous entry to it
            groupID = UUID()
            w.entries[idx - 1].supersetGroupID = groupID
            w.entries[idx - 1].orderInSuperset = 0
        }

        // Count existing entries in superset for ordering
        let existingCount = w.entries.filter { $0.supersetGroupID == groupID }.count

        // Add current entry to superset
        w.entries[idx].supersetGroupID = groupID
        w.entries[idx].orderInSuperset = existingCount

        currentWorkout = w
        persistCurrentWorkout()
        AppLogger.info("Toggled entry \(entryID) into superset with group \(groupID)", category: AppLogger.workout)
        return true
    }

    /// Check if an entry can be added to a superset (i.e., it's not the first exercise)
    func canSuperset(entryID: UUID) -> Bool {
        guard let w = currentWorkout,
              let idx = w.entries.firstIndex(where: { $0.id == entryID }) else { return false }
        return idx > 0
    }

    /// Check if an entry is currently in a superset
    func isInSuperset(entryID: UUID) -> Bool {
        guard let w = currentWorkout,
              let entry = w.entries.first(where: { $0.id == entryID }) else { return false }
        return entry.supersetGroupID != nil
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

    /// Explicit logging records the action receipt alongside the set before acknowledging it.
    /// A failed write can be retried with the same ID, including after process restart.
    func logNextSet(workoutID: UUID, entryID: UUID, exerciseID: String, operationID: UUID,
                    restDuration: TimeInterval) async throws -> SetLogReceipt {
        guard restDuration.isFinite, restDuration > 0, restDuration <= 86_400 else {
            throw StorageError.validationFailed("The rest duration is invalid.")
        }
        try await waitForStorage()
        guard let workout = currentWorkout, workout.id == workoutID,
              let entry = workout.entries.first(where: { $0.id == entryID && $0.exerciseID == exerciseID }) else {
            throw StorageError.validationFailed("This workout or exercise is no longer available.")
        }
        let receipt: SetLogReceipt
        if let existing = workout.setLogReceipts.first(where: { $0.operationID == operationID }) {
            guard existing.entryID == entryID else {
                throw StorageError.validationFailed("This action belongs to another exercise.")
            }
            receipt = existing
            // The earlier attempt may still be in memory after a write failure.
            persistCurrentWorkout()
        } else {
            var updated = entry
            guard let index = prepareNextSet(in: &updated, shouldLogSet: true) else {
                throw StorageError.validationFailed("The next set could not be prepared.")
            }
            updated.sets[index].completionTime = .now
            updated.sets[index].restAfterSeconds = Int(restDuration)
            receipt = SetLogReceipt(operationID: operationID, entryID: entryID, setIndex: index)
            updateEntrySetsAndActiveIndex(entryID: entryID, sets: updated.sets,
                activeSetIndex: updated.activeSetIndex, receipt: receipt)
        }
        // Capture this exact write, not whichever operation becomes latest while awaiting.
        guard let save = pendingSave else {
            throw StorageError.validationFailed("The workout could not be saved.")
        }
        try await save.value
        return receipt
    }

    func handleGeneratePendingSet(exerciseID: String, shouldLogSet: Bool) {
        let manager = RestTimerManager.shared
        guard manager.hasPendingSetGeneration(for: exerciseID) else { return }
        defer { manager.clearPendingSetGeneration(for: exerciseID) }
        guard var entry = existingEntry(for: exerciseID) else { return }
        guard prepareNextSet(in: &entry, shouldLogSet: shouldLogSet) != nil else { return }
        updateEntrySetsAndActiveIndex(entryID: entry.id, sets: entry.sets, activeSetIndex: entry.activeSetIndex)
    }

    private func prepareNextSet(in entry: inout WorkoutEntry, shouldLogSet: Bool) -> Int? {
        let incomplete = entry.sets.indices.first {
            $0 >= entry.activeSetIndex && !entry.sets[$0].isCompleted
        } ?? entry.sets.firstIndex { !$0.isCompleted }
        if let index = incomplete {
            guard shouldLogSet else { return nil }
            entry.sets[index].isCompleted = true
            entry.activeSetIndex = min(index + 1, entry.sets.count - 1)
            return index
        }
        let completedCount = entry.sets.filter { $0.isCompleted }.count
        guard shouldLogSet || completedCount < 4 else {
            AppNotificationManager.shared.showSetsCompleted(count: completedCount)
            return nil
        }
        let template = entry.sets.last(where: { $0.isCompleted }) ?? entry.sets.last
        entry.sets.append(SetInput(
            reps: template?.reps ?? 10, weight: template?.weight ?? 0,
            tag: template?.tag ?? .working, autoWeight: template == nil,
            didSeedFromMemory: false, isCompleted: shouldLogSet, isGhost: false,
            isAutoGeneratedPlaceholder: !shouldLogSet,
            durationSeconds: template?.durationSeconds ?? 0,
            distanceMeters: template?.distanceMeters ?? 0,
            trackingMode: template?.trackingMode ?? .weighted
        ))
        entry.activeSetIndex = entry.sets.count - 1
        return entry.activeSetIndex
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
        completedWorkouts.append(workout)
        completedWorkouts.sort(by: { $0.date < $1.date })
        rebuildPRIndexFromCompletedWorkouts()
        persistWorkouts()

        let week = startOfWeek(for: workout.date)
        Task.detached(priority: .utility) { [_stats, completedWorkouts] in
            await _stats?.invalidate(weeks: [week], from: completedWorkouts)
        }
    }

    func deleteWorkouts(at offsets: IndexSet) {
        let removed = offsets.map { completedWorkouts[$0] }
        completedWorkouts.remove(atOffsets: offsets)
        rebuildPRIndexFromCompletedWorkouts()
        persistWorkouts()

        let weeks = Set(removed.map { startOfWeek(for: $0.date) })
        Task.detached(priority: .utility) { [_stats, completedWorkouts] in
            await _stats?.invalidate(weeks: weeks, from: completedWorkouts)
        }

        // Show undo notification
        AppNotificationManager.shared.showWorkoutDeleted(count: removed.count) {
            self.undoDeleteWorkouts(removed, at: offsets)
        }
    }

    /// Restore deleted workouts (undo operation)
    private func undoDeleteWorkouts(_ workouts: [CompletedWorkout], at offsets: IndexSet) {
        // Add workouts back and maintain sorted order
        completedWorkouts.append(contentsOf: workouts)
        completedWorkouts.sort(by: { $0.date < $1.date })
        rebuildPRIndexFromCompletedWorkouts()
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
            rebuildPRIndexFromCompletedWorkouts()
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

    /// Reloads completed workouts and PR index from disk into in-memory state,
    /// then fully rebuilds strength-derived stats from the replaced workout source of truth.
    /// Call after any external write to WorkoutStorage (e.g., data import or restore).
    /// HealthKit-owned weekly fields are preserved during the rebuild.
    func reloadWorkouts() async throws {
        let (workouts, prIndex) = try await storage.loadWorkouts()
        self.completedWorkouts = workouts.sorted(by: { $0.date < $1.date })
        self.prIndex = prIndex
        let snapshot = self.completedWorkouts
        Task.detached(priority: .utility) { [_stats] in
            await _stats?.rebuildAfterExternalWorkoutReplace(all: snapshot)
        }
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
        if let runsV3 {
            addRunsV3(run, history: runsV3)
            return
        }
        // Check for duplicates by healthKitUUID (if present)
        if let hkUUID = run.healthKitUUID {
            // If a run with this healthKitUUID already exists, don't add a duplicate
            if runs.contains(where: { $0.healthKitUUID == hkUUID }) {
                AppLogger.debug("Skipping duplicate run with healthKitUUID: \(hkUUID)", category: AppLogger.health)
                return
            }
        }

        runs.insert(run, at: 0)
        runSummaries.insert(RunSummary(run), at: 0)
        checkRunSummaries(touched: [0])
        refreshRunDetails([run.id])
        persistRuns()
    }

    /// Remove duplicate runs that have the same healthKitUUID
    /// This is a one-time cleanup function to remove any existing duplicates
    func deduplicateRuns() {
        if let runsV3 {
            deduplicateRunsV3(history: runsV3)
            return
        }
        var seenUUIDs: Set<UUID> = []
        var uniqueRuns: [Run] = []

        for run in runs {
            if let hkUUID = run.healthKitUUID {
                // If we've seen this healthKitUUID before, skip this run (it's a duplicate)
                if seenUUIDs.contains(hkUUID) {
                    AppLogger.debug("Removing duplicate run with healthKitUUID: \(hkUUID)", category: AppLogger.health)
                    continue
                }
                seenUUIDs.insert(hkUUID)
            }
            uniqueRuns.append(run)
        }

        let removedCount = runs.count - uniqueRuns.count
        if removedCount > 0 {
            AppLogger.info("Removed \(removedCount) duplicate run(s)", category: AppLogger.health)
            setRuns(uniqueRuns)
            persistRuns()
        }
    }

    // Mutations that would change nothing return early: every assignment to `runs` bumps its
    // save revision, which would rewrite the whole file for nothing.

    /// Stores `newRuns`, whose `touched` indices changed, in one change: summaries, handles and
    /// the queued save follow.
    private func commitRuns(_ newRuns: [Run], touched: Set<Int>) {
        runs = newRuns
        var summaries = runSummaries
        for index in touched { summaries[index] = RunSummary(newRuns[index]) }
        runSummaries = summaries
        checkRunSummaries(touched: touched)
        refreshRunDetails(touched.map { newRuns[$0].id })
        persistRuns()
    }

    // MARK: - Edits

    /// Applies one edit to the stored workout, synchronously. Returns whether the workout
    /// changed; an edit that changes nothing, or whose workout is gone, writes nothing.
    @discardableResult
    func editRun(_ edit: RunEdit) -> Bool {
        !editRuns([edit]).isEmpty
    }

    /// Applies edits in order, each to the workout as the previous edits left it, in one change.
    /// Edits whose workout is gone are dropped (an intervening delete is never undone); edits
    /// that change nothing write nothing. Returns the ids that changed.
    @discardableResult
    func editRuns(_ edits: [RunEdit]) -> Set<UUID> {
        if let runsV3 { return editRunsV3(edits, history: runsV3) }
        var runsCopy = runs
        var touched: Set<Int> = []
        for edit in edits {
            guard let index = runsCopy.firstIndex(where: { $0.id == edit.id }) else { continue }
            let updated = edit.applied(to: runsCopy[index])
            if updated != runsCopy[index] {
                runsCopy[index] = updated
                touched.insert(index)
            }
        }
        AppLogger.debug("Edited \(touched.count)/\(edits.count) runs", category: AppLogger.health)
        guard !touched.isEmpty else { return [] }
        commitRuns(runsCopy, touched: touched)
        return Set(touched.map { runsCopy[$0].id })
    }

    /// `editRuns`, leaving alone each workout whose edited form would encode to the bytes the
    /// file already holds for it (a re-read of unchanged HealthKit data differs in memory only
    /// below the file's precision). Encoding runs off the main thread; a workout that changed
    /// meanwhile gets its edit applied to its current form and is written.
    @discardableResult
    func editRunsIfStoredFormChanges(_ edits: [RunEdit]) async -> Set<UUID> {
        if let runsV3 { return await editRunsV3IfStoredFormChanges(edits, history: runsV3) }
        let candidates = edits.compactMap { edit in fullRun(id: edit.id).map { (edit, $0, edit.applied(to: $0)) } }
        guard !candidates.isEmpty else { return [] }
        let identical = await runsEncodeIdentically(candidates.map { ($0.1, $0.2) })
        let updates = zip(candidates, identical).compactMap { candidate, identical -> RunEdit? in
            let (edit, stored, _) = candidate
            guard let current = fullRun(id: edit.id) else { return nil }
            // Changed during the comparison: apply the edit to the current run and write it.
            guard current == stored else { return edit }
            // Unchanged: the edit gives the compared form, written only if its bytes differ.
            return identical ? nil : edit
        }
        return editRuns(updates)
    }

    /// Whether replacing each first run with its second would leave the runs file unchanged.
    /// Unequal pairs are encoded on the storage actor, off the main thread, with the encoder
    /// the file is written with.
    private func runsEncodeIdentically(_ pairs: [(Run, Run)]) async -> [Bool] {
        var identical = pairs.map { $0.0 == $0.1 }
        let unequal = identical.indices.filter { !identical[$0] }
        guard !unequal.isEmpty else { return identical }
        let encoded = await storage.runsEncodeIdentically(unequal.map { pairs[$0] })
        for (index, match) in zip(unequal, encoded) { identical[index] = match }
        return identical
    }

    func removeRun(withId id: UUID) {
        if let runsV3 {
            removeRunsV3(ids: [id], history: runsV3)
            return
        }
        guard runs.contains(where: { $0.id == id }) else { return }
        runs.removeAll(where: { $0.id == id })
        runSummaries.removeAll(where: { $0.id == id })
        checkRunSummaries(touched: [])
        refreshRunDetails([id])
        persistRuns()
    }

    func clearAllRuns() {
        if let runsV3 {
            removeRunsV3(ids: runSummaries.map(\.id), history: runsV3)
            return
        }
        guard !runs.isEmpty else { return }
        setRuns([])
        persistRuns()
    }

    /// Every workout that day, in history order.
    func runSummaries(on date: Date, calendar: Calendar = .current) -> [RunSummary] {
        let day = calendar.startOfDay(for: date)
        return runSummaries.filter { calendar.isDate($0.date, inSameDayAs: day) }
    }

    /// Replaces every run and derives every summary: loading and whole-history changes only.
    private func setRuns(_ newRuns: [Run]) {
        runs = newRuns
        runSummaries = newRuns.map(RunSummary.init)
        refreshRunDetails(nil)
    }

    /// DEBUG only: the summaries list the runs' ids in order, and each touched summary equals
    /// its run. Mutations update both in step; this catches one that forgets.
    private func checkRunSummaries(touched: Set<Int>) {
        #if DEBUG
        assert(runSummaries.count == runs.count
               && zip(runSummaries, runs).allSatisfy { $0.id == $1.id }, "Run summaries out of step with runs")
        assert(touched.allSatisfy { runSummaries[$0] == RunSummary(runs[$0]) }, "A changed run's summary is stale")
        #endif
    }


    func importRunsFromHealth() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do {
            if HealthKitManager.shared.connectionState != .connected {
                try await HealthKitManager.shared.requestAuthorization()
                await HealthKitManager.shared.setupBackgroundObservers()
            }

            await HealthKitManager.shared.syncWorkoutsIncremental()

            if let latest = runSummaries.map({ $0.date }).max() {
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

        let strengthTypes = ["Strength Training", "Functional Training", "Core Training", "Traditional Strength Training", "High Intensity Interval Training"]
        let strengthRuns = runSummaries.filter { run in
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

    /// Match only recent workouts with HealthKit data (much faster than matchAllWorkoutsWithHealthKit)
    /// Use this when syncing new data to avoid re-processing old workouts
    func matchRecentWorkoutsWithHealthKit(days: Int = 30) {
        let cal = Calendar.current
        guard let cutoffDate = cal.date(byAdding: .day, value: -days, to: .now) else { return }

        var matchCount = 0
        for workout in completedWorkouts where workout.matchedHealthKitUUID == nil && workout.date >= cutoffDate {
            if matchWithHealthKit(workout) {
                matchCount += 1
            }
        }
        if matchCount > 0 {
            AppLogger.success("Matched \(matchCount) recent workouts with HealthKit data", category: AppLogger.health)
        }
    }

    // MARK: - Ignored HealthKit UUIDs

    /// Check if a HealthKit workout should be ignored (was from a discarded app workout)
    func shouldIgnoreHealthKitWorkout(uuid: UUID, startDate: Date, endDate: Date) -> Bool {
        // Check if UUID is explicitly ignored
        if ignoredHealthKitUUIDs.contains(uuid) {
            return true
        }

        // Check if the workout falls within a discarded workout window
        for window in discardedWorkoutWindows {
            if window.contains(workoutStart: startDate, workoutEnd: endDate) {
                return true
            }
        }

        return false
    }

    /// Add a HealthKit UUID to the ignore list (used when matching discarded workout windows)
    func addIgnoredHealthKitUUID(_ uuid: UUID) {
        ignoredHealthKitUUIDs.insert(uuid)
        persistIgnoredHealthKitUUIDs()
        AppLogger.info("Added \(uuid) to ignored HealthKit UUIDs", category: AppLogger.health)
    }

    /// Remove a HealthKit UUID from the ignore list
    func removeIgnoredHealthKitUUID(_ uuid: UUID) {
        ignoredHealthKitUUIDs.remove(uuid)
        persistIgnoredHealthKitUUIDs()
    }

    // MARK: - Persistence Helpers

    func flushPendingSaves() async throws {
        try await pendingSave?.value
    }

    /// Runs saves one at a time, in the order they were queued, on the main actor.
    @discardableResult
    private func enqueueSave(_ operation: @escaping @MainActor (WorkoutStorage) async throws -> Void) -> Task<Void, Error> {
        let previous = pendingSave
        let save = Task { [storage] in
            _ = try? await previous?.value
            do {
                try await operation(storage)
            } catch {
                AppLogger.error("Failed to persist workout data: \(error)", category: AppLogger.storage)
                throw error
            }
        }
        pendingSave = save
        return save
    }

    /// A later save of another collection must not mask an earlier failed run write: a failed
    /// write leaves its collection unsaved, so this writes it again and reports that outcome.
    /// Returning means both files hold the current state and, after the barrier, survive a
    /// power loss, so the Health anchor may advance. A failed barrier throws like a failed write.
    func flushHealthKitChanges() async throws {
        try await waitForStorage()
        let save = enqueueSave { storage in
            if self.runsV3 != nil {
                try await self.drainRunsV3(requireDurable: true)
            } else {
                try await self.saveRunsIfChanged(to: storage)
            }
            try await self.saveIgnoredHealthKitUUIDsIfChanged(to: storage)
            try await storage.makeWritesDurable()
        }
        try await save.value
    }

    private func persistWorkouts() {
        guard isStorageLoaded else { return }
        let workouts = completedWorkouts
        let prIndex = prIndex
        enqueueSave { try await $0.saveWorkouts(workouts, prIndex: prIndex) }
    }

    private func persistCurrentWorkout() {
        guard isStorageLoaded else { return }
        let current = currentWorkout
        enqueueSave { try await $0.saveCurrentWorkout(current) }
    }

    private func persistRuns() {
        guard isStorageLoaded else { return }
        if runsV3 != nil {
            enqueueSave { _ in try await self.drainRunsV3(requireDurable: false) }
            return
        }
        enqueueSave { try await self.saveRunsIfChanged(to: $0) }
    }

    private func persistIgnoredHealthKitUUIDs() {
        guard isStorageLoaded else { return }
        enqueueSave { try await self.saveIgnoredHealthKitUUIDsIfChanged(to: $0) }
    }

    // Both run inside the save queue, so they see the outcome of every earlier save. Each
    // writes the latest state, which also lets a burst of queued saves collapse into one write.

    private func saveRunsIfChanged(to storage: WorkoutStorage) async throws {
        // A whole-file save queued before the migration switched the history: dropped. The
        // change it would have saved was carried over to runs_v3 at the switch.
        guard runsV3 == nil else { return }
        // Read the stamp first so the revision is compared after the suspension, not before.
        let onDisk = await storage.runsFileStamp()
        if runsSave.isSaved(asOnDisk: onDisk) { return }
        let revision = runsSave.revision
        runsSave.markUnsaved()
        let stamp = try await storage.saveRuns(runs)
        runsSave.markSaved(revision, stamp: stamp)
    }

    private func saveIgnoredHealthKitUUIDsIfChanged(to storage: WorkoutStorage) async throws {
        let onDisk = await storage.ignoredHealthKitUUIDsFileStamp()
        if ignoredSave.isSaved(asOnDisk: onDisk) { return }
        let revision = ignoredSave.revision
        ignoredSave.markUnsaved()
        let stamp = try await storage.saveIgnoredHealthKitUUIDs(ignoredHealthKitUUIDs)
        ignoredSave.markSaved(revision, stamp: stamp)
    }

    private func startOfWeek(for date: Date) -> Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date))!
    }
}

// MARK: - Weight Suggestions

struct PersonalRecordAttempt: Equatable {
    let reps: Int
    let weightKg: Double
    let previousWeightAtReps: Double?
    let previousE1RM: Double?

    var estimatedOneRepMax: Double {
        weightKg * (1.0 + Double(reps) / 30.0)
    }
}

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

    /// Get all working sets excluding the current active workout
    /// Use this for PR calculations during active workout sessions to show only historical PRs
    private func completedWorkingSets(for exerciseID: String) -> [(date: Date, set: SetInput)] {
        var out: [(Date, SetInput)] = []

        // Only include completed workouts (not current workout)
        for w in completedWorkouts {
            if let entry = w.entries.first(where: { $0.exerciseID == exerciseID }) {
                for s in entry.sets where s.tag == .working && s.reps > 0 {
                    out.append((w.date, s))
                }
            }
        }

        return out
    }

    /// Number of consecutive completed sessions where the heaviest working set weight was the same.
    /// Returns 0 when fewer than 3 sessions exist or the weight has varied.
    func consecutiveSessionsAtSameWeight(for exerciseID: String) -> Int {
        let sessionMaxWeights: [Double] = completedWorkouts.compactMap { workout in
            guard let entry = workout.entries.first(where: { $0.exerciseID == exerciseID }) else { return nil }
            let weights = entry.sets.filter { $0.tag == .working && $0.weight > 0 && $0.isCompleted }.map { $0.weight }
            return weights.max()
        }
        guard sessionMaxWeights.count >= 3, let last = sessionMaxWeights.last else { return 0 }
        var count = 0
        for weight in sessionMaxWeights.reversed() {
            if abs(weight - last) < 0.5 { count += 1 } else { break }
        }
        return count
    }

    func lastWorkingSet(exercise: Exercise) -> (reps: Int, weightKg: Double)? {
        let sets = completedWorkingSets(for: exercise.id).sorted { $0.date > $1.date }
        return sets.first.map { ($0.set.reps, $0.set.weight) }
    }

    func bestWeightForExactReps(exercise: Exercise, reps: Int) -> Double? {
        let sets = completedWorkingSets(for: exercise.id)
            .filter { $0.set.reps == reps }
            .map { $0.set.weight }
        return sets.max()
    }

    func bestWeightForNearbyReps(exercise: Exercise, targetReps: Int, window: Int = 2) -> (reps: Int, weightKg: Double)? {
        let candidates = completedWorkingSets(for: exercise.id).map { $0.set }
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
        let sets = completedWorkingSets(for: exercise.id).map { $0.set }
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

    func personalRecordAttempt(for exercise: Exercise, incrementKg: Double = 2.5) -> PersonalRecordAttempt? {
        guard let last = lastWorkingSet(exercise: exercise) else { return nil }
        guard let baseWeight = suggestedWorkingWeight(for: exercise, targetReps: last.reps) else { return nil }

        let proposedWeight = baseWeight + incrementKg
        let previousWeightAtReps = bestWeightForExactReps(exercise: exercise, reps: last.reps)
        let previousE1RM = bestE1RM(exercise: exercise)
        let proposedE1RM = proposedWeight * (1.0 + Double(last.reps) / 30.0)

        let beatsExactRepRecord = previousWeightAtReps.map { proposedWeight > $0 } ?? true
        let beatsEstimatedOneRepMax = previousE1RM.map { proposedE1RM > $0 } ?? false

        guard beatsExactRepRecord || beatsEstimatedOneRepMax else { return nil }

        return PersonalRecordAttempt(
            reps: last.reps,
            weightKg: proposedWeight,
            previousWeightAtReps: previousWeightAtReps,
            previousE1RM: previousE1RM
        )
    }

    /// Personal best reps for bodyweight exercises (max reps achieved)
    /// Excludes current workout to show only historical PRs
    func personalBestReps(for exercise: Exercise) -> Int? {
        if let pr = prIndex[exercise.id]?.bestReps {
            return pr
        }
        // Use completedWorkingSets instead of allWorkingSets to exclude current workout
        let sets = completedWorkingSets(for: exercise.id).map { $0.set }
        return sets.map { $0.reps }.max()
    }
}

// MARK: - PR Index Management

extension WorkoutStoreV2 {

    /// Updates PR index and returns the count of new PRs detected
    @discardableResult
    private func updatePRIndex(with completed: CompletedWorkout) -> Int {
        var prCount = 0

        for e in completed.entries {
            let existingPR = prIndex[e.exerciseID]
            var pr = existingPR ?? ExercisePRsV2()

            for s in e.sets where s.tag == .working {
                // Determine tracking mode
                let trackingMode = s.trackingMode

                switch trackingMode {
                case .weighted:
                    // Weighted exercises: track weight-based PRs
                    guard s.reps > 0 && s.weight > 0 else { continue }

                    // Check for new best per reps PR
                    let previousBestForReps = pr.bestPerReps[s.reps] ?? 0
                    if s.weight > previousBestForReps {
                        pr.bestPerReps[s.reps] = s.weight
                        if existingPR != nil && previousBestForReps > 0 {
                            prCount += 1  // Only count if we had a previous record to beat
                        }
                    }

                    // Best E1RM (Epley formula)
                    let e1rm = s.weight * (1.0 + Double(s.reps) / 30.0)
                    let previousE1RM = pr.bestE1RM ?? 0
                    if e1rm > previousE1RM {
                        pr.bestE1RM = e1rm
                        // E1RM PR counted separately only if significant improvement (>2%)
                        if existingPR != nil && previousE1RM > 0 && e1rm > previousE1RM * 1.02 {
                            prCount += 1
                        }
                    }

                    // All-time best weight
                    pr.allTimeBest = max(pr.allTimeBest ?? 0, s.weight)

                    // Last working set
                    pr.lastWorking = LastSetV2(date: completed.date, reps: s.reps, weightKg: s.weight)

                case .bodyweight:
                    // Bodyweight exercises: track best reps
                    guard s.reps > 0 else { continue }
                    let previousBestReps = pr.bestReps ?? 0
                    if s.reps > previousBestReps {
                        pr.bestReps = s.reps
                        if existingPR != nil && previousBestReps > 0 {
                            prCount += 1
                        }
                    }

                    // Last working set (weight is always 0)
                    pr.lastWorking = LastSetV2(date: completed.date, reps: s.reps, weightKg: 0)

                case .timed:
                    // Timed exercises: track best duration
                    guard s.durationSeconds > 0 else { continue }
                    let previousBestDuration = pr.bestDuration ?? 0
                    if s.durationSeconds > previousBestDuration {
                        pr.bestDuration = s.durationSeconds
                        if existingPR != nil && previousBestDuration > 0 {
                            prCount += 1
                        }
                    }

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

        return prCount
    }

    private func rebuildPRIndexFromCompletedWorkouts() {
        prIndex.removeAll()
        for workout in completedWorkouts.sorted(by: { $0.date < $1.date }) {
            updatePRIndex(with: workout)
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

        var completed = CompletedWorkout(date: .now, startedAt: w.startedAt, entries: w.entries, plannedWorkoutID: w.plannedWorkoutID, excusedPlannedExerciseIDs: w.excusedPlannedExerciseIDs)

        // Store workout for social sharing on win screen
        Task { @MainActor in
            WinScreenCoordinator.shared.setCompletedWorkout(completed)
        }

        var dexKeysToUnlock: [String] = []
        for e in completed.entries {
            let didWork = e.sets.contains { set in
                guard set.tag == .working && set.isCompleted else { return false }
                return isValidSetForDex(set)
            }
            if didWork {
                let key = canonicalExerciseKey(from: e.exerciseID)
                dexKeysToUnlock.append(key)
            }
        }
        let dexUnlockDate = completed.date
        let uniqueDexKeysToUnlock = Array(Set(dexKeysToUnlock))
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            for key in uniqueDexKeysToUnlock {
                rewardsEngine.ensureDexUnlocked(exerciseKey: key, date: dexUnlockDate)
            }
        }

        // Count PRs before updating the index
        let newPRs = countPRs(in: completed)
        completed.detectedPRCount = newPRs
        let prAchievements = extractPRDetails(in: completed)

        // Normal finish logic - add workout and keep array sorted by date
        completedWorkouts.append(completed)
        lastCompletedWorkout = completed
        completedWorkouts.sort(by: { $0.date < $1.date })
        updatePRIndex(with: completed)
        refreshSmartNotificationLearningAfterWorkoutCompletion()

        // Handle PR auto-posting
        handlePRAutoPost(prAchievements, for: completed)

        persistWorkouts()

        if let plannedWorkoutID = completed.plannedWorkoutID {
            plannedWorkoutCompletionHandler?(plannedWorkoutID, completed)
        }

        // Update battles and challenges (non-blocking)
        updateCompetitiveFeatures(for: completed)

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

    private func refreshSmartNotificationLearningAfterWorkoutCompletion() {
        let workouts = completedWorkouts

        Task {
            await WorkoutPatternAnalyzer.shared.analyzeAndUpdatePattern(workouts: workouts)
            await SmartNudgeManager.shared.scheduleDailyStreakCheck()
        }
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

    /// Extract detailed PR information for auto-posting
    private func extractPRDetails(in workout: CompletedWorkout) -> [PRAchievement] {
        var prAchievements: [PRAchievement] = []

        for e in workout.entries {
            let existing = prIndex[e.exerciseID] ?? ExercisePRsV2()
            var bestPRInWorkout: PRAchievement?

            for s in e.sets where s.tag == .working && s.reps > 0 && s.weight > 0 {
                let prevBestAtReps = existing.bestPerReps[s.reps] ?? 0
                let previousE1RM = existing.bestE1RM

                // Check if this is a PR at this rep count
                if s.weight > prevBestAtReps {
                    let improvement = prevBestAtReps > 0 ? (s.weight - prevBestAtReps) / prevBestAtReps : nil
                    let isFirst = prevBestAtReps == 0

                    let pr = PRAchievement(
                        exerciseId: e.exerciseID,
                        exerciseName: e.exerciseName,
                        previousBest: prevBestAtReps > 0 ? prevBestAtReps : nil,
                        newBest: s.weight,
                        reps: s.reps,
                        weight: s.weight,
                        improvement: improvement,
                        isFirstPR: isFirst
                    )

                    // Keep only the best PR for this exercise in this workout
                    if bestPRInWorkout == nil || s.weight > bestPRInWorkout!.weight {
                        bestPRInWorkout = pr
                    }
                }
            }

            if let pr = bestPRInWorkout {
                prAchievements.append(pr)
            }
        }

        return prAchievements
    }

    /// Handle PR auto-posting after workout completion
    /// `prAchievements` must be extracted before `updatePRIndex` includes this workout.
    private func handlePRAutoPost(_ prAchievements: [PRAchievement], for workout: CompletedWorkout) {
        guard !prAchievements.isEmpty else { return }

        prAutoPostSink(prAchievements, workout)
    }

    // MARK: - Competitive Features Integration

    /// Update battle scores and challenge progress after workout completion
    /// Non-blocking - runs in background, failures are logged but don't affect workout completion
    private func updateCompetitiveFeatures(for workout: CompletedWorkout) {
        guard let userId = authService?.currentUser?.id else {
            // User not logged in - skip competitive feature updates
            return
        }

        // Run updates in background task - don't block workout completion
        Task.detached(priority: .utility) { [battleRepository, challengeRepository] in
            // Update battle scores
            if let battleRepo = battleRepository {
                do {
                    try await battleRepo.updateBattleScores(after: workout, userId: userId)
                    AppLogger.success("Updated battle scores for workout \(workout.id)", category: AppLogger.workout)
                    NotificationCenter.default.post(name: .battleScoresDidUpdate, object: nil)
                } catch {
                    AppLogger.error("Failed to update battle scores: \(error.localizedDescription)", category: AppLogger.workout)
                }
            } else {
                AppLogger.warning("Battle repository not available - skipping battle score update", category: AppLogger.workout)
            }

            // Update challenge progress
            if let challengeRepo = challengeRepository {
                do {
                    try await challengeRepo.updateChallengeProgress(after: workout, userId: userId)
                    AppLogger.success("Updated challenge progress for workout \(workout.id)", category: AppLogger.workout)
                } catch {
                    AppLogger.error("Failed to update challenge progress: \(error.localizedDescription)", category: AppLogger.workout)
                }
            }
        }
    }
}

// MARK: - Save Tracking

// MARK: - Migration to the per-workout history (spec 7.1)

enum RunHistoryMigrationResult: Equatable {
    /// The gate is closed (every Release build, and Debug without the opt-in).
    case notAllowed
    /// A precondition does not hold; not an attempt.
    case skipped(String)
    case migrated
    /// An attempt that failed before the switch; the app stays on runs_v2.json.
    case failed(String)
}

extension WorkoutStoreV2 {
    /// Whether the history is the per-workout one (for the Debug row).
    var isOnPerWorkoutHistory: Bool { runsV3 != nil }

    fileprivate func scheduleRunHistoryMigration() {
        guard migrationGate(), migrationTask == nil else { return }
        let delay = migrationDelay
        migrationTask = Task(priority: .background) { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            let result = await self.migrateRunHistoryIfAllowed()
            AppLogger.info("Run history migration: \(result)", category: AppLogger.storage)
            self.migrationTask = nil
        }
    }

    private final class MigrationBox { var result: RunHistoryMigrationResult = .skipped("did not run") }

    /// Spec 7.1. Checks every precondition, then runs as one operation of the save queue: any
    /// unsaved run change is saved first (or the migration is skipped), the history is taken in
    /// that same turn, the storage actor migrates it, and the store switches to runs_v3 in the
    /// main-actor turn the migration returns in. Changes made while it ran are carried over;
    /// whole-file saves queued meanwhile are dropped.
    @discardableResult
    func migrateRunHistoryIfAllowed() async -> RunHistoryMigrationResult {
        guard migrationGate() else { return .notAllowed }
        if let reason = migrationBlocker() { return .skipped(reason) }
        if let refusal = await storage.migrationPreconditions() { return .skipped("\(refusal)") }
        let box = MigrationBox()
        let task = enqueueSave { storage in
            if let reason = self.migrationBlocker() { box.result = .skipped(reason); return }
            let onDisk = await storage.runsFileStamp()
            if !self.runsSave.isSaved(asOnDisk: onDisk) {
                do { try await self.saveRunsIfChanged(to: storage) } catch {
                    box.result = .skipped("unsaved run changes could not be saved: \(error)")
                    return
                }
            }
            let snapshot = self.runs
            let build = RunHistoryConfiguration.currentBuild
            let key = RunHistoryConfiguration.attemptsKey(build: build)
            self.defaults.set(self.defaults.integer(forKey: key) + 1, forKey: key)
            self.recordMigration("started", build: build)
            do {
                let result = try await storage.migrateRunHistoryToV3(snapshot)
                self.switchToRunsV3(result.opened, migrated: snapshot)
                self.defaults.removeObject(forKey: key)
                self.recordMigration("migrated", build: build)
                box.result = .migrated
            } catch {
                self.recordMigration("failed: \(error)", build: build)
                AppLogger.error("Run history migration failed; staying on runs_v2.json: \(error)", category: AppLogger.storage)
                box.result = .failed("\(error)")
            }
        }
        _ = try? await task.value
        return box.result
    }

    /// Why a migration may not start now (spec 7.1), or nil.
    private func migrationBlocker() -> String? {
        guard isStorageLoaded, storageLoadError == nil else { return "history not loaded" }
        guard runsV3 == nil else { return "already on runs_v3" }
        guard protectedDataAvailable() else { return "protected data unavailable" }
        guard !isHealthImportRunning() else { return "a Health import is running" }
        guard currentWorkout == nil else { return "a workout is in progress" }
        let attempts = defaults.integer(forKey: RunHistoryConfiguration.attemptsKey(build: RunHistoryConfiguration.currentBuild))
        guard attempts < RunHistoryConfiguration.maximumAttempts else { return "attempt limit reached for this build" }
        guard Set(runs.map(\.id)).count == runs.count else { return "duplicate workout ids" }
        return nil
    }

    private func recordMigration(_ result: String, build: String) {
        let record = RunHistoryMigrationRecord(date: .now, build: build, result: result)
        defaults.set(try? JSONEncoder().encode(record), forKey: RunHistoryConfiguration.lastAttemptKey)
    }

    /// The last attempt, for the Debug row.
    var lastRunHistoryMigration: RunHistoryMigrationRecord? {
        defaults.data(forKey: RunHistoryConfiguration.lastAttemptKey).flatMap { try? JSONDecoder().decode(RunHistoryMigrationRecord.self, from: $0) }
    }

    var runHistoryMigrationAttempts: Int {
        defaults.integer(forKey: RunHistoryConfiguration.attemptsKey(build: RunHistoryConfiguration.currentBuild))
    }

    /// The switch, in one main-actor turn: the store continues on runs_v3, carrying every change
    /// made to the in-memory history since `migrated` was taken (adds, edits, deletes), then
    /// lets the full runs go.
    fileprivate func switchToRunsV3(_ opened: WorkoutStorage.RunsV3Opened, migrated: [Run]) {
        let current = runs
        activateRunsV3(opened)
        guard let history = runsV3 else { return }
        let before = Dictionary(migrated.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let now = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for run in migrated where now[run.id] == nil { history.enqueue(.delete, for: run.id) }
        for run in current { if let old = before[run.id], old != run { history.enqueue(.replace(run), for: run.id) } }
        // Oldest addition first, so the newest gets the highest position, as addRun inserts.
        for run in current.reversed() where before[run.id] == nil { history.enqueue(.add(run, seq: history.takeSeq()), for: run.id) }
        for (id, handle) in runDetailHandles where handle.detail != nil {
            if let run = now[id] { history.remember(run) }
        }
        runSummaries = current.map(RunSummary.init)
        runs = []
        refreshRunDetails(nil)
        persistRuns()
    }
}

// MARK: - Per-workout history (runs_v3)

/// The runs_v3 half of the run API. Reached only after `activateRunsV3`, which only a load that
/// found an active runs_v3 directory calls; with no runs_v3 entry on disk nothing here runs.
extension WorkoutStoreV2 {
    private final class ReadBox { var result: RunsV3ReadResult? }

    fileprivate func activateRunsV3(_ opened: WorkoutStorage.RunsV3Opened) {
        let history = RunsV3History(storage: storage, opened: opened)
        history.isObserved = { [weak self] id in self?.runDetailHandles[id]?.detail != nil }
        history.enqueueIndexWrite = { [weak self] operation in _ = self?.enqueueSave(operation) }
        runsV3 = history
        runSummaries = opened.entries.map(\.summary)
        refreshRunDetails(nil)
        runsV3Observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.runsV3?.trim(keepRecent: 0) }
        })
        runsV3Observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshRunDetails(nil) }
        })
        if history.isWritable {
            enqueueSave { storage in
                do { try await storage.runsV3PurgeTrash() } catch {
                    AppLogger.warning("runs_v3 trash purge skipped: \(error)", category: AppLogger.storage)
                }
            }
        }
        AppLogger.info("Run history: runs_v3 (\(opened.mode == .writable ? "writable" : "read-only"), \(opened.entries.count) workouts)",
                       category: AppLogger.storage)
    }

    fileprivate func retryWhenProtectedDataIsAvailable() {
        guard protectedDataObserver == nil else { return }
        protectedDataObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let observer = self.protectedDataObserver { NotificationCenter.default.removeObserver(observer) }
                self.protectedDataObserver = nil
                self.retryStorageLoad()
            }
        }
    }

    private func refuseRunChange(_ what: String) {
        AppLogger.warning("Run history is read-only in this version of the app: \(what) was not saved", category: AppLogger.storage)
    }

    // Reads

    /// Reads one workout inside the save queue, so it sees every queued change and no drain runs
    /// meanwhile. `wanted` is checked when the read's turn comes: a handle that went away is
    /// not read for.
    fileprivate func readRunsV3(_ id: UUID, history: RunsV3History, wanted: @escaping @MainActor () -> Bool = { true }) async -> RunsV3ReadResult? {
        let box = ReadBox()
        let task = enqueueSave { _ in
            guard wanted() else { return }
            box.result = await history.read(id)
        }
        _ = try? await task.value
        return box.result
    }

    fileprivate func loadRunsV3(_ id: UUID, history: RunsV3History) async throws -> RunLoadResult {
        if let cached = history.cachedRun(id) { return .loaded(cached) }
        guard runSummary(id: id) != nil else { return .removed }
        let result = await readRunsV3(id, history: history)
        try Task.checkCancellation()
        switch result {
        case .loaded(let run)?: return .loaded(run)
        case .removed?: return .removed
        case .unreadable?: return .unreadable
        case .temporarilyUnavailable?, nil: throw StorageError.runHistoryDeferred
        }
    }

    fileprivate func makeRunsV3Detail(id: UUID, history: RunsV3History) -> RunDetail {
        let phase: RunDetail.Phase
        if let run = history.cachedRun(id) {
            phase = .loaded(run)
        } else if runSummary(id: id) == nil {
            phase = .unavailable(.removed)
        } else {
            phase = .loading
        }
        let detail = RunDetail(id: id, phase: phase)
        runDetailHandles = runDetailHandles.filter { $0.value.detail != nil }
        runDetailHandles[id] = WeakRunDetail(detail: detail)
        if case .loading = phase { startRunsV3Load(detail, history: history) }
        return detail
    }

    /// Loads off the main thread (the storage actor decodes); cancelled with the handle.
    private func startRunsV3Load(_ detail: RunDetail, history: RunsV3History) {
        let id = detail.id
        detail.loadTask?.cancel()
        detail.loadTask = Task { [weak self, weak detail] in
            guard let self else { return }
            let result = await self.readRunsV3(id, history: history, wanted: { [weak detail] in detail != nil })
            guard !Task.isCancelled, let detail else { return }
            switch result {
            case .loaded(let run)?:
                detail.setLoaded(run)
            case .removed?:
                if detail.phase != .unavailable(.removed) { detail.setUnavailable(.removed) }
            case .unreadable?:
                detail.setUnavailable(.unreadable)
            case .temporarilyUnavailable?, nil:
                break   // Stays loading; protected data becoming available refreshes it.
            }
        }
    }

    fileprivate func refreshRunsV3Details(_ ids: [UUID], history: RunsV3History) {
        for id in ids {
            guard let detail = runDetailHandles[id]?.detail else {
                runDetailHandles[id] = nil
                continue
            }
            if let run = history.cachedRun(id) {
                detail.setLoaded(run)
            } else if runSummary(id: id) == nil {
                if detail.phase != .unavailable(.removed) { detail.setUnavailable(.removed) }
            } else if detail.isLoading || detail.phase == .unavailable(.unreadable) {
                startRunsV3Load(detail, history: history)
            } else {
                // Shown but no longer in memory (a memory warning): load the current record.
                startRunsV3Load(detail, history: history)
            }
        }
    }

    // Writes

    fileprivate func addRunsV3(_ run: Run, history: RunsV3History) {
        if let hkUUID = run.healthKitUUID, runSummaries.contains(where: { $0.healthKitUUID == hkUUID }) {
            AppLogger.debug("Skipping duplicate run with healthKitUUID: \(hkUUID)", category: AppLogger.health)
            return
        }
        guard !runSummaries.contains(where: { $0.id == run.id }) else { return }
        guard history.isWritable else { return refuseRunChange("a new workout") }
        history.enqueue(.add(run, seq: history.takeSeq()), for: run.id)
        runSummaries.insert(RunSummary(run), at: 0)
        refreshRunDetails([run.id])
        persistRuns()
    }

    fileprivate func deduplicateRunsV3(history: RunsV3History) {
        var seen: Set<UUID> = []
        var duplicates: [UUID] = []
        for summary in runSummaries {
            guard let hkUUID = summary.healthKitUUID else { continue }
            if seen.contains(hkUUID) { duplicates.append(summary.id) } else { seen.insert(hkUUID) }
        }
        guard !duplicates.isEmpty else { return }
        AppLogger.info("Removed \(duplicates.count) duplicate run(s)", category: AppLogger.health)
        removeRunsV3(ids: duplicates, history: history)
    }

    fileprivate func editRunsV3(_ edits: [RunEdit], history: RunsV3History) -> Set<UUID> {
        guard history.isWritable else {
            if !edits.isEmpty { refuseRunChange("\(edits.count) workout edit(s)") }
            return []
        }
        var summaries = runSummaries
        var changed: Set<UUID> = []
        for edit in edits {
            guard let index = summaries.firstIndex(where: { $0.id == edit.id }) else { continue }
            if let cached = history.cachedRun(edit.id) {
                // The full run is in memory: exactly today's test.
                let updated = edit.applied(to: cached)
                guard updated != cached else { continue }
                history.enqueue(.edit(edit), for: edit.id)
                summaries[index] = RunSummary(updated)
            } else {
                // Without the full run: the summary shows the edit at once; an edit that may
                // change only its arrays is queued, and the drain writes nothing if the stored
                // form does not change.
                let updated = summaries[index].updated(by: edit)
                guard updated != summaries[index] || RunSummary.replacesDetail(edit) else { continue }
                history.enqueue(.edit(edit), for: edit.id)
                summaries[index] = updated
            }
            changed.insert(edit.id)
        }
        AppLogger.debug("Edited \(changed.count)/\(edits.count) runs", category: AppLogger.health)
        guard !changed.isEmpty else { return [] }
        runSummaries = summaries
        refreshRunDetails(Array(changed))
        persistRuns()
        return changed
    }

    fileprivate func editRunsV3IfStoredFormChanges(_ edits: [RunEdit], history: RunsV3History) async -> Set<UUID> {
        var candidates: [(edit: RunEdit, stored: Run, serial: Int)] = []
        for edit in edits {
            guard runSummary(id: edit.id) != nil,
                  case .loaded(let stored)? = try? await loadRunsV3(edit.id, history: history) else { continue }
            candidates.append((edit, stored, history.serial(of: edit.id)))
        }
        guard !candidates.isEmpty else { return [] }
        let identical = await runsEncodeIdentically(candidates.map { ($0.stored, $0.edit.applied(to: $0.stored)) })
        let updates = zip(candidates, identical).compactMap { candidate, identical -> RunEdit? in
            guard runSummary(id: candidate.edit.id) != nil else { return nil }
            // Changed during the comparison: apply the edit to its current form and write it.
            guard history.serial(of: candidate.edit.id) == candidate.serial else { return candidate.edit }
            return identical ? nil : candidate.edit
        }
        return editRunsV3(updates, history: history)
    }

    fileprivate func removeRunsV3(ids: [UUID], history: RunsV3History) {
        let present = Set(ids).intersection(runSummaries.map(\.id))
        guard !present.isEmpty else { return }
        guard history.isWritable else { return refuseRunChange("removing \(present.count) workout(s)") }
        for id in ids where present.contains(id) { history.enqueue(.delete, for: id) }
        runSummaries.removeAll { present.contains($0.id) }
        refreshRunDetails(Array(present))
        persistRuns()
    }

    /// Drains every queued change (inside the save queue). With `requireDurable` (the Health
    /// anchor's flush), throws unless everything queued is durable and the history is writable.
    fileprivate func drainRunsV3(requireDurable: Bool) async throws {
        guard let history = runsV3 else { return }
        if requireDurable && !history.isWritable { throw StorageError.runHistoryReadOnly }
        guard history.hasPendingChanges || requireDurable else { return }
        let report = await history.drain()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        for (id, stored) in report.settled {
            // Memory and the file must agree at the file's precision (whole-second dates).
            guard let memory = runSummary(id: id) else { continue }
            if (try? encoder.encode(memory)) != (try? encoder.encode(stored)) {
                runsV3SummaryMismatches += 1
                AppLogger.error("runs_v3: the stored summary of \(id) differs from memory", category: AppLogger.storage)
            }
        }
        for (id, reason) in report.dropped {
            AppLogger.warning("runs_v3: changes to \(id) were dropped: \(reason)", category: AppLogger.storage)
        }
        if !report.isFullyDurable {
            let message = "\(report.failed.count) failed, \(report.awaitingBarrier.count) awaiting a barrier"
                + (report.barrierError.map { ", barrier: \($0)" } ?? "")
            if requireDurable || !report.failed.isEmpty { throw StorageError.runHistoryNotDurable(message) }
        }
    }
}

/// Whether a saved collection still matches the file it was last written to or loaded from.
/// Any doubt means unsaved: no successful write yet, a failed write, a later change, or a file
/// replaced or removed behind the store's back.
private struct SaveTracker {
    /// Bumped by every mutation of the collection.
    private(set) var revision = 0
    private var saved: (revision: Int, stamp: FileStamp)?

    mutating func changed() { revision &+= 1 }

    mutating func markUnsaved() { saved = nil }

    mutating func markSaved(_ revision: Int, stamp: FileStamp?) {
        saved = stamp.map { (revision, $0) }
    }

    func isSaved(asOnDisk stamp: FileStamp?) -> Bool {
        guard let saved, let stamp else { return false }
        return saved.revision == revision && saved.stamp == stamp
    }
}
