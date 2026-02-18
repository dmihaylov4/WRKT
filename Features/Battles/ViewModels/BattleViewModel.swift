//
//  BattleViewModel.swift
//  WRKT
//
//  ViewModel for managing 1v1 battles - creating, accepting, declining, and tracking
//

import Foundation

@MainActor
@Observable
final class BattleViewModel {
    // MARK: - State
    var activeBattles: [BattleWithParticipants] = []
    var pendingBattles: [BattleWithParticipants] = [] // Battles waiting for acceptance
    var completedBattles: [BattleWithParticipants] = []

    var isLoading = false
    var isRefreshing = false
    var error: UserFriendlyError?

    var selectedBattle: BattleWithParticipants?
    var showBattleDetail = false

    // Battle creation state
    var showCreateBattle = false
    var selectedOpponentId: String?

    // MARK: - Dependencies
    private let battleRepository: BattleRepository
    private let authService: SupabaseAuthService
    private let errorHandler = ErrorHandler.shared

    // MARK: - Initialization
    init(battleRepository: BattleRepository, authService: SupabaseAuthService) {
        self.battleRepository = battleRepository
        self.authService = authService
    }

    // MARK: - Lifecycle
    func onAppear() async {
        guard activeBattles.isEmpty && pendingBattles.isEmpty else {
            // Already loaded - just refresh
            await refresh()
            return
        }

        // Initial load
        await loadBattles()
    }

    func refresh() async {
        guard !isRefreshing else { return }

        isRefreshing = true
        error = nil

        await loadBattles()

        isRefreshing = false
        Haptics.soft()
    }

    // MARK: - Data Loading
    private func loadBattles() async {
        guard let userId = authService.currentUser?.id else {
            error = UserFriendlyError(
                title: "Not Logged In",
                message: "You must be logged in to view battles",
                suggestion: "Please log in to continue",
                isRetryable: false
            )
            return
        }

        if !isRefreshing {
            isLoading = true
        }

        do {
            // Load all user's battles
            let allBattles = try await battleRepository.fetchUserBattles()

            // Separate by status
            activeBattles = allBattles.filter { $0.battle.isActive }
            pendingBattles = allBattles.filter { $0.battle.isPending }
            completedBattles = allBattles.filter { $0.battle.isCompleted }

            error = nil
            isLoading = false
        } catch {
            
            self.error = errorHandler.handleError(error, context: .battles)
            isLoading = false
            Haptics.error()
        }
    }

    // MARK: - Battle Actions
    func createBattle(opponentId: String, battleType: BattleType, durationDays: Int) async {
        guard let userId = authService.currentUser?.id else {
            error = UserFriendlyError(
                title: "Not Logged In",
                message: "You must be logged in to create battles",
                suggestion: "Please log in to continue",
                isRetryable: false
            )
            return
        }

        do {
            // Convert String to UUID
            guard let opponentUUID = UUID(uuidString: opponentId) else {
                error = UserFriendlyError(
                    title: "Invalid Opponent",
                    message: "The opponent ID is invalid",
                    suggestion: "Please select a valid opponent",
                    isRetryable: false
                )
                return
            }

            // Create the battle
            let battle = try await battleRepository.createBattle(
                opponentId: opponentUUID,
                battleType: battleType,
                durationDays: durationDays
            )

            // Refresh to get updated list
            await loadBattles()

            Haptics.success()

            // Show success notification
            AppNotificationManager.shared.showBattleCreated()

            // Close create sheet
            showCreateBattle = false
        } catch {
            self.error = errorHandler.handleError(error, context: .battles)
            Haptics.error()
        }
    }

    func acceptBattle(_ battle: Battle) async {
        guard let userId = authService.currentUser?.id else {
            error = UserFriendlyError(
                title: "Not Logged In",
                message: "You must be logged in to accept battles",
                suggestion: "Please log in to continue",
                isRetryable: false
            )
            return
        }

        do {
            // Accept the battle
            try await battleRepository.acceptBattle(battle)

            // Refresh to get updated data
            await loadBattles()

            Haptics.success()

            // Show success notification
            AppNotificationManager.shared.showBattleAccepted()
        } catch {
            
            self.error = errorHandler.handleError(error, context: .battles)
            Haptics.error()
        }
    }

    func declineBattle(_ battle: Battle) async {
        guard let userId = authService.currentUser?.id else {
            error = UserFriendlyError(
                title: "Not Logged In",
                message: "You must be logged in to decline battles",
                suggestion: "Please log in to continue",
                isRetryable: false
            )
            return
        }

        do {
            // Decline the battle
            try await battleRepository.declineBattle(battle)

            // Refresh to get updated list
            await loadBattles()

            Haptics.soft()

            // Show notification
            AppNotificationManager.shared.showBattleDeclined()
        } catch {
            self.error = errorHandler.handleError(error, context: .battles)
            Haptics.error()
        }
    }

    // MARK: - Navigation
    func openBattleDetail(_ battle: BattleWithParticipants) {
        selectedBattle = battle
        showBattleDetail = true
    }

    func closeBattleDetail() {
        showBattleDetail = false
        selectedBattle = nil
    }

    func openCreateBattle(opponentId: String? = nil) {
        selectedOpponentId = opponentId
        showCreateBattle = true
    }

    func closeCreateBattle() {
        showCreateBattle = false
        selectedOpponentId = nil
    }

    // MARK: - Helpers
    func getWinner(for battle: BattleWithParticipants) -> UserProfile? {
        guard battle.battle.status == .completed else { return nil }

        let challengerScore = battle.battle.challengerScore
        let opponentScore = battle.battle.opponentScore

        if challengerScore > opponentScore {
            return battle.challenger
        } else if opponentScore > challengerScore {
            return battle.opponent
        }
        return nil // Tie
    }

    func getCurrentUserScore(for battle: BattleWithParticipants) -> Double {
        guard let userId = authService.currentUser?.id else { return 0 }
        let score = battle.battle.score(for: userId)
        return NSDecimalNumber(decimal: score).doubleValue
    }

    func getOpponentScore(for battle: BattleWithParticipants) -> Double {
        guard let userId = authService.currentUser?.id else { return 0 }
        let score = battle.battle.opponentScore(for: userId)
        return NSDecimalNumber(decimal: score).doubleValue
    }

    func getOpponent(for battle: BattleWithParticipants) -> UserProfile {
        return battle.opponentProfile
    }

    func isCurrentUserWinning(for battle: BattleWithParticipants) -> Bool {
        return battle.isUserLeading
    }

    func isCurrentUserWinner(winner: UserProfile, battle: BattleWithParticipants) -> Bool {
        guard let userId = authService.currentUser?.id else { return false }
        return winner.id == userId
    }

    func isPendingAction(for battle: BattleWithParticipants) -> Bool {
        guard let userId = authService.currentUser?.id else { return false }

        // If battle is pending and user is the opponent (not challenger), action is needed
        if battle.battle.status == .pending {
            return battle.battle.opponentId == userId
        }

        return false
    }
}


// MARK: - Notification Extensions
extension AppNotificationManager {
    func showBattleCreated() {
        show(.success("Battle challenge sent!", title: nil))
    }

    func showBattleAccepted() {
        show(.success("Battle accepted! Let's go!", title: nil))
    }

    func showBattleDeclined() {
        show(.info("Battle declined", title: nil))
    }
}
