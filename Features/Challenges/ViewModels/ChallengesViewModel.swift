//
//  ChallengesViewModel.swift
//  WRKT
//
//  ViewModel for managing challenges - browsing, joining, leaving, and tracking progress
//

import Foundation

@MainActor
@Observable
final class ChallengesViewModel {
    // MARK: - State
    var activeChallenges: [ChallengeWithProgress] = []
    var availableChallenges: [ChallengeWithProgress] = []
    var completedChallenges: [ChallengeWithProgress] = []
    var presetChallenges: [PresetChallenge] = []

    var isLoading = false
    var isRefreshing = false
    var error: UserFriendlyError?

    var selectedChallenge: ChallengeWithProgress?
    var showChallengeDetail = false

    // MARK: - Dependencies
    private let challengeRepository: ChallengeRepository
    private let authService: SupabaseAuthService
    private weak var workoutStore: WorkoutStoreV2?
    private let errorHandler = ErrorHandler.shared

    // MARK: - Initialization
    init(
        challengeRepository: ChallengeRepository,
        authService: SupabaseAuthService,
        workoutStore: WorkoutStoreV2? = nil
    ) {
        self.challengeRepository = challengeRepository
        self.authService = authService
        self.workoutStore = workoutStore
    }

    // MARK: - Lifecycle
    func onAppear() async {
        guard activeChallenges.isEmpty && availableChallenges.isEmpty else {
            // Already loaded - just refresh
            await refresh()
            return
        }

        // Initial load
        await loadChallenges()
        loadPresets()
    }

    func refresh() async {
        guard !isRefreshing else { return }

        isRefreshing = true
        error = nil

        await loadChallenges()
        loadPresets()

        isRefreshing = false
        Haptics.soft()
    }

    // MARK: - Data Loading
    private func loadChallenges() async {
        guard let userId = authService.currentUser?.id else {
            error = UserFriendlyError(
                title: "Not Logged In",
                message: "You must be logged in to view challenges",
                suggestion: "Please log in to continue",
                isRetryable: false
            )
            return
        }

        if !isRefreshing {
            isLoading = true
        }

        do {
            // Load user's challenges (active and completed)
            let userChallenges = try await challengeRepository.fetchUserChallenges(userId: userId)

            // Separate participant state from challenge schedule state. Evergreen preset
            // challenges can stay active after the current user has completed them.
            activeChallenges = userChallenges.filter { $0.challenge.isActive && !$0.isCompleted }
            completedChallenges = userChallenges.filter { $0.isCompleted }

            await repairFirstRepProgressFromWorkoutHistory()

            // Load available public challenges (excluding ones user is already in)
            let joinedChallengeIds = Set(userChallenges.map { $0.challenge.id })
            let allAvailable = try await challengeRepository.fetchActivePublicChallenges()
            availableChallenges = allAvailable.filter { !joinedChallengeIds.contains($0.challenge.id) }

            error = nil
            isLoading = false
        } catch {
            
            self.error = errorHandler.handleError(error, context: .challenges)
            isLoading = false
            Haptics.error()
        }
    }

    private func repairFirstRepProgressFromWorkoutHistory() async {
        if workoutStore?.isStorageLoaded == false {
            try? await workoutStore?.reloadWorkouts()
        }
        guard let completedWorkouts = workoutStore?.completedWorkouts, !completedWorkouts.isEmpty else { return }
        guard let firstRep = activeChallenges.first(where: {
            $0.challenge.isFirstRepChallenge && !$0.isCompleted
        }) else { return }
        guard firstRep.shouldCompleteFirstRep(from: completedWorkouts) else { return }

        // Update local display state only — the DB write and win screen happen exclusively
        // via updateChallengeProgress (workout completion path). Writing to the DB here
        // races against that background task and causes it to skip the win screen.
        let locallyCompleted = firstRep.completedFirstRepFromWorkoutHistory()
        activeChallenges.removeAll { $0.id == firstRep.id }
        if !completedChallenges.contains(where: { $0.id == firstRep.id }) {
            completedChallenges.append(locallyCompleted)
        }
    }

    private func loadPresets() {
        presetChallenges = PresetChallenge.all
    }

    // MARK: - Challenge Actions
    func joinChallenge(_ challenge: Challenge) async {
        guard let userId = authService.currentUser?.id else {
            error = UserFriendlyError(
                title: "Not Logged In",
                message: "You must be logged in to join challenges",
                suggestion: "Please log in to continue",
                isRetryable: false
            )
            return
        }

        guard !isUserInChallenge(challenge) else { return }

        do {
            // Join the challenge
            try await challengeRepository.joinChallenge(challenge)

            // Refresh to get updated list
            await loadChallenges()

            Haptics.success()

            // Show success notification
            AppNotificationManager.shared.showChallengeJoined(challengeName: challenge.title)
        } catch {
           
            self.error = errorHandler.handleError(error, context: .challenges)
            Haptics.error()
        }
    }

    @discardableResult
    func leaveChallenge(_ challenge: Challenge) async -> Bool {
        guard let userId = authService.currentUser?.id else {
            error = UserFriendlyError(
                title: "Not Logged In",
                message: "You must be logged in to leave challenges",
                suggestion: "Please log in to continue",
                isRetryable: false
            )
            return false
        }

        do {
            // Leave the challenge
            try await challengeRepository.leaveChallenge(challenge)

            // Optimistically update UI
            activeChallenges.removeAll { $0.challenge.id == challenge.id }

            // Refresh to get updated list
            await loadChallenges()

            Haptics.soft()
            return true
        } catch {
            
            self.error = errorHandler.handleError(error, context: .challenges)
            Haptics.error()

            // Revert optimistic update on error
            await loadChallenges()
            return false
        }
    }

    #if DEBUG
    func deleteCompletedChallengesForRetest() async {
        let completed = completedChallenges
        guard !completed.isEmpty else { return }

        do {
            for item in completed {
                try await challengeRepository.leaveChallenge(item.challenge)
            }

            completedChallenges.removeAll()
            await loadChallenges()
            Haptics.soft()
        } catch {
            self.error = errorHandler.handleError(error, context: .challenges)
            Haptics.error()
            await loadChallenges()
        }
    }
    #endif

    func createChallengeFromPreset(_ preset: PresetChallenge) async {
        guard let userId = authService.currentUser?.id else {
            error = UserFriendlyError(
                title: "Not Logged In",
                message: "You must be logged in to create challenges",
                suggestion: "Please log in to continue",
                isRetryable: false
            )
            return
        }

        do {
            // Create the challenge
            let challenge = try await challengeRepository.createChallenge(
                title: preset.title,
                description: preset.description,
                challengeType: preset.challengeType,
                goalMetric: preset.goalMetric,
                goalValue: preset.goalValue,
                durationDays: preset.duration,
                isPublic: true,
                difficulty: preset.difficulty
            )

            // Auto-join the created challenge
            try await challengeRepository.joinChallenge(challenge)

            // Refresh to get updated list
            await loadChallenges()

            Haptics.success()

            // Show success notification
            AppNotificationManager.shared.showChallengeCreated(challengeName: preset.title)
        } catch {
            
            self.error = errorHandler.handleError(error, context: .challenges)
            Haptics.error()
        }
    }

    func openOrCreateChallengeFromPreset(_ preset: PresetChallenge) async {
        // Refresh first so active list is current
        await loadChallenges()

        // Already active — open that instance
        if let active = activeChallenges.first(where: { $0.challenge.title == preset.title }) {
            openChallengeDetail(active)
            return
        }

        // Shared seeded challenge exists — open it
        if let seeded = availableChallenges.first(where: {
            $0.challenge.title == preset.title && $0.challenge.isPreset
        }) {
            openChallengeDetail(seeded)
            return
        }

        // Any other existing public instance — open it
        if let existing = availableChallenges.first(where: { $0.challenge.title == preset.title }) {
            openChallengeDetail(existing)
            return
        }

        // Not found — challenge not yet seeded in Supabase. No-op.
    }

    // MARK: - Navigation
    func openChallengeDetail(_ challenge: ChallengeWithProgress) {
        selectedChallenge = challenge
        showChallengeDetail = true
    }

    func closeChallengeDetail() {
        showChallengeDetail = false
        selectedChallenge = nil
    }

    // MARK: - Helpers
    func isUserInChallenge(_ challenge: Challenge) -> Bool {
        activeChallenges.contains { $0.challenge.id == challenge.id }
    }

    func getFeaturedChallenges() -> [PresetChallenge] {
        PresetChallenge.featured
    }

    func getChallengesByDifficulty(_ difficulty: ChallengeDifficulty) -> [PresetChallenge] {
        PresetChallenge.challenges(forDifficulty: difficulty)
    }

    func getChallengesByType(_ type: ChallengeType) -> [PresetChallenge] {
        PresetChallenge.challenges(forType: type)
    }
}


// MARK: - Notification Extensions
extension AppNotificationManager {
    func showChallengeJoined(challengeName: String) {
        show(.success("Joined \(challengeName)!", title: nil))
    }

    func showChallengeCreated(challengeName: String) {
        show(.success("Challenge created: \(challengeName)", title: nil))
    }
}
