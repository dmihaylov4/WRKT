import Foundation
import Supabase

@Observable
final class BattleRepository: Sendable {
    private let supabase: SupabaseClient
    private let authService: SupabaseAuthService
    private let notificationService: NotificationService

    init(
        supabase: SupabaseClient,
        authService: SupabaseAuthService,
        notificationService: NotificationService = .shared
    ) {
        self.supabase = supabase
        self.authService = authService
        self.notificationService = notificationService
    }

    // MARK: - Fetch Battles

    /// Fetch all battles for current user (active, pending, completed)
    func fetchUserBattles() async throws -> [BattleWithParticipants] {
        guard let userId = authService.currentUser?.id else {
            throw SupabaseError.notAuthenticated
        }

        // Fetch battles where user is participant
        let battles: [Battle] = try await supabase.database
            .from("battles")
            .select()
            .or("challenger_id.eq.\(userId.uuidString),opponent_id.eq.\(userId.uuidString)")
            .order("created_at", ascending: false)
            .limit(50)
            .execute()
            .value

        guard !battles.isEmpty else { return [] }

        // Fetch all participant profiles
        let participantIds = Set(battles.flatMap { [$0.challengerId, $0.opponentId] })
        let profiles: [UserProfile] = try await supabase.database
            .from("profiles")
            .select()
            .in("id", values: Array(participantIds).map { $0.uuidString })
            .execute()
            .value

        // Combine
        return battles.compactMap { battle in
            guard let challenger = profiles.first(where: { $0.id == battle.challengerId }),
                  let opponent = profiles.first(where: { $0.id == battle.opponentId }) else {
                return nil
            }

            var result = BattleWithParticipants(
                id: battle.id,
                battle: battle,
                challenger: challenger,
                opponent: opponent
            )
            result.currentUserId = userId
            return result
        }
    }

    /// Fetch active battles only
    func fetchActiveBattles() async throws -> [BattleWithParticipants] {
        // Check for battles ending soon (sends notifications if needed)
        await checkBattlesEndingSoon()

        let allBattles = try await fetchUserBattles()
        return allBattles.filter { $0.battle.isActive }
    }

    /// Check for battles ending within 24 hours and send notifications
    private func checkBattlesEndingSoon() async {
        do {
            // Early return if task was cancelled (e.g., user navigated away)
            if Task.isCancelled { return }

            // Call database function to check and send ending soon notifications
            // Function returns TABLE(battle_id UUID, notifications_sent INTEGER)
            struct BattleEndingSoonResult: Codable {
                let battleId: UUID?
                let notificationsSent: Int

                enum CodingKeys: String, CodingKey {
                    case battleId = "battle_id"
                    case notificationsSent = "notifications_sent"
                }
            }

            let results: [BattleEndingSoonResult] = try await supabase.database
                .rpc("send_battle_ending_soon_notifications")
                .execute()
                .value

            let totalNotifications = results.reduce(0) { $0 + $1.notificationsSent }
            AppLogger.info("✅ Checked battles ending soon - sent \(totalNotifications) notifications", category: AppLogger.battles)
        } catch is CancellationError {
            // Task was cancelled - this is normal, don't log as error
            return
        } catch {
            // Don't fail the entire fetch if this check fails
            AppLogger.error("⚠️ Failed to check battles ending soon", error: error, category: AppLogger.battles)
        }
    }

    /// Fetch pending battle invitations
    func fetchPendingBattles() async throws -> [BattleWithParticipants] {
        let allBattles = try await fetchUserBattles()
        return allBattles.filter { $0.battle.isPending }
    }

    /// Fetch a single battle by ID
    func fetchBattle(id: UUID) async throws -> BattleWithParticipants {
        guard let userId = authService.currentUser?.id else {
            throw SupabaseError.notAuthenticated
        }

        AppLogger.info("🔍 Fetching battle with ID: \(id), currentUserId: \(userId)", category: AppLogger.battles)

        let battles: [Battle] = try await supabase.database
            .from("battles")
            .select()
            .eq("id", value: id)
            .execute()
            .value

        AppLogger.info("📦 Query returned \(battles.count) battles", category: AppLogger.battles)

        guard let battle = battles.first else {
            AppLogger.error("❌ No battle found with ID: \(id)", category: AppLogger.battles)
            throw SupabaseError.custom(message: "Battle not found")
        }

        AppLogger.info("✅ Battle found: challengerId=\(battle.challengerId), opponentId=\(battle.opponentId), status=\(battle.status)", category: AppLogger.battles)

        // Verify user is participant
        guard battle.challengerId == userId || battle.opponentId == userId else {
            AppLogger.error("❌ User \(userId) is not a participant in battle \(id)", category: AppLogger.battles)
            throw SupabaseError.custom(message: "Not authorized to view this battle")
        }

        // Fetch profiles
        let profiles: [UserProfile] = try await supabase.database
            .from("profiles")
            .select()
            .in("id", values: [battle.challengerId.uuidString, battle.opponentId.uuidString])
            .execute()
            .value

        guard let challenger = profiles.first(where: { $0.id == battle.challengerId }),
              let opponent = profiles.first(where: { $0.id == battle.opponentId }) else {
            throw SupabaseError.custom(message: "Could not load battle participants")
        }

        var result = BattleWithParticipants(
            id: battle.id,
            battle: battle,
            challenger: challenger,
            opponent: opponent
        )
        result.currentUserId = userId
        return result
    }

    // MARK: - Create Battle

    /// Challenge a friend to a battle
    func createBattle(
        opponentId: UUID,
        battleType: BattleType,
        durationDays: Int,
        targetMetric: String? = nil
    ) async throws -> Battle {
        guard let userId = authService.currentUser?.id else {
            throw SupabaseError.notAuthenticated
        }

        // Validate opponent is different
        guard opponentId != userId else {
            throw SupabaseError.custom(message: "Cannot battle yourself")
        }

        let now = Date()
        let endDate = Calendar.current.date(byAdding: .day, value: durationDays, to: now)!

        let battle = Battle(
            id: UUID(),
            challengerId: userId,
            opponentId: opponentId,
            battleType: battleType,
            targetMetric: targetMetric,
            startDate: now,
            endDate: endDate,
            status: .pending,
            winnerId: nil,
            challengerScore: 0,
            opponentScore: 0,
            customRules: nil,
            trashTalkEnabled: true,
            createdAt: now,
            updatedAt: now
        )

        AppLogger.info("🎯 Creating battle: id=\(battle.id), challenger=\(userId), opponent=\(opponentId), type=\(battleType)", category: AppLogger.battles)

        do {
            try await supabase.database
                .from("battles")
                .insert(battle)
                .execute()

            AppLogger.success("✅ Battle inserted into database successfully: \(battle.id)", category: AppLogger.battles)
        } catch {
            AppLogger.error("❌ Failed to insert battle into database", error: error, category: AppLogger.battles)
            throw error
        }

        // Verify the battle was actually created by fetching it back
        do {
            let verifyBattle = try await fetchBattle(id: battle.id)
            AppLogger.success("✅ Battle verified in database: \(verifyBattle.battle.id), status=\(verifyBattle.battle.status)", category: AppLogger.battles)
        } catch {
            AppLogger.error("⚠️ Battle insert succeeded but verification fetch failed - this is suspicious!", error: error, category: AppLogger.battles)
        }

        // Show a simple success toast to the creator
        // The actual battle invite toast will be shown to the opponent via realtime notifications
        Task { @MainActor in
            AppNotificationManager.shared.showSuccess(
                "Battle challenge sent to \(try? await authService.fetchProfile(userId: opponentId).displayName ?? "opponent")",
                title: "Challenge Sent!"
            )
        }

        AppLogger.success("Battle created: \(battle.id)", category: AppLogger.battles)

        return battle
    }

    // MARK: - Accept/Decline Battle

    /// Accept a battle invitation
    func acceptBattle(_ battle: Battle) async throws {
        guard let userId = authService.currentUser?.id else {
            throw SupabaseError.notAuthenticated
        }

        guard battle.opponentId == userId, battle.status == .pending else {
            throw SupabaseError.custom(message: "Cannot accept this battle")
        }

        try await supabase.database
            .from("battles")
            .update(["status": BattleStatus.active.rawValue])
            .eq("id", value: battle.id)
            .execute()

        // Log activity
        try await logActivity(
            battleId: battle.id,
            userId: userId,
            activityType: .accepted,
            activityData: nil
        )

        // Notification sent automatically by database trigger
        AppLogger.success("Battle accepted: \(battle.id)", category: AppLogger.battles)
    }

    /// Decline a battle invitation
    func declineBattle(_ battle: Battle) async throws {
        guard let userId = authService.currentUser?.id else {
            throw SupabaseError.notAuthenticated
        }

        guard battle.opponentId == userId, battle.status == .pending else {
            throw SupabaseError.custom(message: "Cannot decline this battle")
        }

        try await supabase.database
            .from("battles")
            .update(["status": BattleStatus.declined.rawValue])
            .eq("id", value: battle.id)
            .execute()

        // Notification sent automatically by database trigger
        AppLogger.success("Battle declined: \(battle.id)", category: AppLogger.battles)
    }

    /// Cancel a battle (creator only, before acceptance)
    func cancelBattle(_ battle: Battle) async throws {
        guard let userId = authService.currentUser?.id else {
            throw SupabaseError.notAuthenticated
        }

        guard battle.challengerId == userId, battle.status == .pending else {
            throw SupabaseError.custom(message: "Cannot cancel this battle")
        }

        try await supabase.database
            .from("battles")
            .update(["status": BattleStatus.cancelled.rawValue])
            .eq("id", value: battle.id)
            .execute()
    }

    // MARK: - Update Battle Scores

    /// Recalculate and update battle scores after a workout
    func updateBattleScores(after workout: CompletedWorkout, userId: UUID) async throws {
        // Fetch active battles for user
        let battles: [Battle] = try await supabase.database
            .from("battles")
            .select()
            .eq("status", value: BattleStatus.active.rawValue)
            .or("challenger_id.eq.\(userId.uuidString),opponent_id.eq.\(userId.uuidString)")
            .gte("end_date", value: Date())
            .execute()
            .value

        guard !battles.isEmpty else { return }

        // Update scores for each battle
        for battle in battles {
            let scoreIncrease = calculateBattleScore(
                for: battle,
                workout: workout
            )

            if scoreIncrease > 0 {
                try await updateScore(
                    battle: battle,
                    userId: userId,
                    scoreIncrease: scoreIncrease,
                    workout: workout
                )
            }
        }
    }

    private func calculateBattleScore(
        for battle: Battle,
        workout: CompletedWorkout
    ) -> Decimal {
        // Parse metric configuration from targetMetric (stored as JSON)
        // For backwards compatibility, fall back to battleType-based calculation
        if let targetMetric = battle.targetMetric,
           let data = targetMetric.data(using: .utf8),
           let config = try? JSONDecoder().decode(MetricConfiguration.self, from: data) {
            // Use flexible metric calculator
            return MetricCalculator.calculate(
                metric: config.type,
                filter: config.filter,
                workout: workout,
                userMaxHR: HRZoneCalculator.shared.maxHR
            )
        }

        // Fallback: Legacy battle type calculation
        switch battle.battleType {
        case .volume:
            return MetricCalculator.calculate(
                metric: .totalVolume,
                filter: nil,
                workout: workout
            )

        case .consistency, .workoutCount:
            return MetricCalculator.calculate(
                metric: .workoutCount,
                filter: nil,
                workout: workout
            )

        case .pr:
            return MetricCalculator.calculate(
                metric: .prCount,
                filter: nil,
                workout: workout
            )

        case .exercise:
            // Use exercise name from targetMetric
            let filter = battle.targetMetric.map {
                MetricFilter(exerciseName: $0)
            }
            return MetricCalculator.calculate(
                metric: .repsForExercise,
                filter: filter,
                workout: workout
            )
        }
    }

    private func updateScore(
        battle: Battle,
        userId: UUID,
        scoreIncrease: Decimal,
        workout: CompletedWorkout
    ) async throws {
        let isChallenger = battle.challengerId == userId
        let currentScore = isChallenger ? battle.challengerScore : battle.opponentScore
        let opponentCurrentScore = isChallenger ? battle.opponentScore : battle.challengerScore
        let newScore = currentScore + scoreIncrease

        let field = isChallenger ? "challenger_score" : "opponent_score"

        try await supabase.database
            .from("battles")
            .update([field: newScore])
            .eq("id", value: battle.id)
            .execute()

        // Log activity
        try await logActivity(
            battleId: battle.id,
            userId: userId,
            activityType: .workoutLogged,
            activityData: BattleActivity.ActivityData(
                workoutName: workout.workoutName,
                scoreChange: scoreIncrease,
                newScore: newScore,
                milestone: nil
            )
        )

        // Send opponent activity notification
        let opponentId = isChallenger ? battle.opponentId : battle.challengerId
        Task {
            try? await notificationService.createBattleOpponentActivityNotification(
                battleId: battle.id,
                actorId: userId,
                recipientId: opponentId
            )
        }

        // Check if user took the lead
        let wasLosing = currentScore <= opponentCurrentScore
        let isWinning = newScore > opponentCurrentScore

        if wasLosing && isWinning {
            try await logActivity(
                battleId: battle.id,
                userId: userId,
                activityType: .tookLead,
                activityData: nil
            )
            // Lead change notifications sent automatically by database trigger
            // Show immediate in-app toast
            Task { @MainActor in
                await notificationService.showBattleLeadTakenToast(
                    opponentName: isChallenger ? "your opponent" : "your challenger"
                )
            }
        }

        AppLogger.success("Battle score updated: +\(scoreIncrease)", category: AppLogger.battles)
    }

    // MARK: - Battle Activities

    /// Fetch recent activities for a battle
    func fetchBattleActivities(battleId: UUID, limit: Int = 20) async throws -> [BattleActivity] {
        let activities: [BattleActivity] = try await supabase.database
            .from("battle_activities")
            .select()
            .eq("battle_id", value: battleId)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        return activities
    }

    // MARK: - Helper Methods

    private func logActivity(
        battleId: UUID,
        userId: UUID,
        activityType: BattleActivity.ActivityType,
        activityData: BattleActivity.ActivityData?
    ) async throws {
        let activity = BattleActivity(
            id: UUID(),
            battleId: battleId,
            userId: userId,
            activityType: activityType,
            activityData: activityData,
            createdAt: Date()
        )

        try await supabase.database
            .from("battle_activities")
            .insert(activity)
            .execute()
    }
}
