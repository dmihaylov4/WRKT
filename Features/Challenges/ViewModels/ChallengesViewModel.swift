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
    private let errorHandler = ErrorHandler.shared

    // MARK: - Initialization
    init(challengeRepository: ChallengeRepository, authService: SupabaseAuthService) {
        self.challengeRepository = challengeRepository
        self.authService = authService
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

            // Separate active and completed
            activeChallenges = userChallenges.filter { $0.challenge.isActive }
            completedChallenges = userChallenges.filter { $0.challenge.isCompleted }

            // Load available public challenges (excluding ones user is already in)
            let activeIds = Set(activeChallenges.map { $0.challenge.id })
            let allAvailable = try await challengeRepository.fetchActivePublicChallenges()
            availableChallenges = allAvailable.filter { !activeIds.contains($0.challenge.id) }

            error = nil
            isLoading = false
        } catch {
            
            self.error = errorHandler.handleError(error, context: .challenges)
            isLoading = false
            Haptics.error()
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

    func leaveChallenge(_ challenge: Challenge) async {
        guard let userId = authService.currentUser?.id else {
            error = UserFriendlyError(
                title: "Not Logged In",
                message: "You must be logged in to leave challenges",
                suggestion: "Please log in to continue",
                isRetryable: false
            )
            return
        }

        do {
            // Leave the challenge
            try await challengeRepository.leaveChallenge(challenge)

            // Optimistically update UI
            activeChallenges.removeAll { $0.challenge.id == challenge.id }

            // Refresh to get updated list
            await loadChallenges()

            Haptics.soft()
        } catch {
            
            self.error = errorHandler.handleError(error, context: .challenges)
            Haptics.error()

            // Revert optimistic update on error
            await loadChallenges()
        }
    }

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
