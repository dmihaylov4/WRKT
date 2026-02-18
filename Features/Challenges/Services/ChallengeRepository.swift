import Foundation
import Supabase

@Observable
final class ChallengeRepository: Sendable {
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

    // MARK: - Fetch Challenges

    /// Fetch active public challenges
    func fetchActivePublicChallenges() async throws -> [ChallengeWithProgress] {
        guard let userId = authService.currentUser?.id else {
            throw SupabaseError.notAuthenticated
        }

        // Fetch active public challenges
        let challenges: [Challenge] = try await supabase.database
            .from("challenges")
            .select()
            .eq("is_public", value: true)
            .gte("end_date", value: Date())
            .order("participant_count", ascending: false)
            .limit(50)
            .execute()
            .value

        guard !challenges.isEmpty else { return [] }

        // Fetch user's participation for these challenges
        let challengeIds = challenges.map { $0.id }
        let participations: [ChallengeParticipant] = try await supabase.database
            .from("challenge_participants")
            .select()
            .in("challenge_id", values: challengeIds.map { $0.uuidString })
            .eq("user_id", value: userId)
            .execute()
            .value

        // Map challenges to ChallengeWithProgress
        return try await withThrowingTaskGroup(of: ChallengeWithProgress.self) { group in
            for challenge in challenges {
                group.addTask {
                    let participation = participations.first { $0.challengeId == challenge.id }
                    let topParticipants = try await self.fetchTopParticipants(
                        challengeId: challenge.id,
                        limit: 10
                    )
                    return ChallengeWithProgress(
                        id: challenge.id,
                        challenge: challenge,
                        participation: participation,
                        topParticipants: topParticipants
                    )
                }
            }

            var results: [ChallengeWithProgress] = []
            for try await result in group {
                results.append(result)
            }
            return results.sorted { $0.challenge.participantCount > $1.challenge.participantCount }
        }
    }

    /// Fetch user's active challenges
    func fetchUserChallenges(userId: UUID) async throws -> [ChallengeWithProgress] {
        // Fetch user's participations
        let participations: [ChallengeParticipant] = try await supabase.database
            .from("challenge_participants")
            .select()
            .eq("user_id", value: userId)
            .execute()
            .value

        guard !participations.isEmpty else { return [] }

        // Fetch challenges
        let challengeIds = participations.map { $0.challengeId }
        let challenges: [Challenge] = try await supabase.database
            .from("challenges")
            .select()
            .in("id", values: challengeIds.map { $0.uuidString })
            .execute()
            .value

        // Combine
        return try await withThrowingTaskGroup(of: ChallengeWithProgress.self) { group in
            for challenge in challenges {
                group.addTask {
                    let participation = participations.first { $0.challengeId == challenge.id }
                    let topParticipants = try await self.fetchTopParticipants(
                        challengeId: challenge.id,
                        limit: 10
                    )
                    return ChallengeWithProgress(
                        id: challenge.id,
                        challenge: challenge,
                        participation: participation,
                        topParticipants: topParticipants
                    )
                }
            }

            var results: [ChallengeWithProgress] = []
            for try await result in group {
                results.append(result)
            }
            // Sort: active first, then by end date
            return results.sorted { lhs, rhs in
                if lhs.challenge.isActive != rhs.challenge.isActive {
                    return lhs.challenge.isActive
                }
                return lhs.challenge.endDate < rhs.challenge.endDate
            }
        }
    }

    /// Fetch a single challenge by ID
    func fetchChallenge(id: UUID) async throws -> ChallengeWithProgress {
        guard let userId = authService.currentUser?.id else {
            throw SupabaseError.notAuthenticated
        }

        let challenges: [Challenge] = try await supabase.database
            .from("challenges")
            .select()
            .eq("id", value: id)
            .execute()
            .value

        guard let challenge = challenges.first else {
            throw SupabaseError.custom(message: "Challenge not found")
        }

        // Fetch user's participation
        let participations: [ChallengeParticipant] = try await supabase.database
            .from("challenge_participants")
            .select()
            .eq("challenge_id", value: id)
            .eq("user_id", value: userId)
            .execute()
            .value

        let participation = participations.first

        // Fetch top participants
        let topParticipants = try await fetchTopParticipants(challengeId: id, limit: 10)

        return ChallengeWithProgress(
            id: challenge.id,
            challenge: challenge,
            participation: participation,
            topParticipants: topParticipants
        )
    }

    // MARK: - Create Challenge

    /// Create a new custom challenge
    func createChallenge(
        title: String,
        description: String?,
        challengeType: ChallengeType,
        goalMetric: String,
        goalValue: Decimal,
        durationDays: Int,
        isPublic: Bool,
        difficulty: ChallengeDifficulty?
    ) async throws -> Challenge {
        guard let userId = authService.currentUser?.id else {
            throw SupabaseError.notAuthenticated
        }

        let now = Date()
        let endDate = Calendar.current.date(byAdding: .day, value: durationDays, to: now)!

        let challenge = Challenge(
            id: UUID(),
            title: title,
            description: description,
            challengeType: challengeType,
            goalMetric: goalMetric,
            goalValue: goalValue,
            startDate: now,
            endDate: endDate,
            creatorId: userId,
            isPublic: isPublic,
            isPreset: false,
            difficulty: difficulty,
            participantLimit: nil,
            participantCount: 0,
            completionCount: 0,
            createdAt: now,
            updatedAt: now
        )

        try await supabase.database
            .from("challenges")
            .insert(challenge)
            .execute()

        // Auto-join the challenge
        try await joinChallenge(challenge)

        return challenge
    }

    // MARK: - Join/Leave Challenge

    /// Join a challenge
    func joinChallenge(_ challenge: Challenge) async throws {
        guard let userId = authService.currentUser?.id else {
            throw SupabaseError.notAuthenticated
        }

        // Check if already participating
        let existing: [ChallengeParticipant] = try await supabase.database
            .from("challenge_participants")
            .select()
            .eq("challenge_id", value: challenge.id)
            .eq("user_id", value: userId)
            .execute()
            .value

        if !existing.isEmpty {
            // Already participating - silently return success
            return
        }

        let participant = ChallengeParticipant(
            id: UUID(),
            challengeId: challenge.id,
            userId: userId,
            currentProgress: 0,
            progressPercentage: 0,
            completed: false,
            completionDate: nil,
            lastActivityDate: Date(),
            joinedAt: Date()
        )

        try await supabase.database
            .from("challenge_participants")
            .insert(participant)
            .execute()

        // Log activity
        try await logActivity(
            challengeId: challenge.id,
            userId: userId,
            activityType: .joined,
            activityData: nil
        )
    }

    /// Leave a challenge
    func leaveChallenge(_ challenge: Challenge) async throws {
        guard let userId = authService.currentUser?.id else {
            throw SupabaseError.notAuthenticated
        }

        try await supabase.database
            .from("challenge_participants")
            .delete()
            .eq("challenge_id", value: challenge.id)
            .eq("user_id", value: userId)
            .execute()
    }

    // MARK: - Progress Updates

    /// Calculate and update user's progress for all active challenges after a workout
    func updateChallengeProgress(after workout: CompletedWorkout, userId: UUID) async throws {
        // Fetch user's active challenge participations
        let participations: [ChallengeParticipant] = try await supabase.database
            .from("challenge_participants")
            .select()
            .eq("user_id", value: userId)
            .eq("completed", value: false)
            .execute()
            .value

        guard !participations.isEmpty else { return }

        // Fetch challenges
        let challengeIds = participations.map { $0.challengeId }
        let challenges: [Challenge] = try await supabase.database
            .from("challenges")
            .select()
            .in("id", values: challengeIds.map { $0.uuidString })
            .gte("end_date", value: Date())
            .execute()
            .value

        // Update progress for each challenge
        for challenge in challenges {
            guard let participation = participations.first(where: { $0.challengeId == challenge.id }) else { continue }

            let progressIncrease = calculateProgress(
                for: challenge,
                currentProgress: participation.currentProgress,
                newWorkout: workout
            )

            if progressIncrease > 0 {
                let newProgress = participation.currentProgress + progressIncrease

                // Update progress (Decimal type)
                try await supabase.database
                    .from("challenge_participants")
                    .update(["current_progress": newProgress])
                    .eq("id", value: participation.id)
                    .execute()

                // Update last activity date (Date type)
                try await supabase.database
                    .from("challenge_participants")
                    .update(["last_activity_date": Date()])
                    .eq("id", value: participation.id)
                    .execute()

                // Log progress activity
                try await logActivity(
                    challengeId: challenge.id,
                    userId: userId,
                    activityType: .progress,
                    activityData: ChallengeActivity.ActivityData(
                        workoutName: workout.workoutName,
                        progressAmount: progressIncrease,
                        milestonePercent: nil
                    )
                )

                // Check for milestone
                let newPercentage = Int((Double(truncating: newProgress as NSDecimalNumber) / Double(truncating: challenge.goalValue as NSDecimalNumber)) * 100)
                let oldPercentage = participation.progressPercentage

                if (oldPercentage < 25 && newPercentage >= 25) ||
                   (oldPercentage < 50 && newPercentage >= 50) ||
                   (oldPercentage < 75 && newPercentage >= 75) ||
                   (oldPercentage < 100 && newPercentage >= 100) {
                    let milestone = (newPercentage / 25) * 25
                    try await logActivity(
                        challengeId: challenge.id,
                        userId: userId,
                        activityType: .milestone,
                        activityData: ChallengeActivity.ActivityData(
                            workoutName: nil,
                            progressAmount: nil,
                            milestonePercent: milestone
                        )
                    )

                    // Send milestone notification (database trigger also sends, but this gives immediate feedback)
                    Task {
                        try? await notificationService.createChallengeMilestoneNotification(
                            challengeId: challenge.id,
                            userId: userId,
                            milestone: milestone,
                            progress: newProgress,
                            goal: challenge.goalValue,
                            challengeTitle: challenge.title
                        )
                    }

                    AppLogger.success("Challenge milestone reached: \(milestone)%", category: AppLogger.challenges)
                }

                // Log completion
                if newPercentage >= 100 && oldPercentage < 100 {
                    try await logActivity(
                        challengeId: challenge.id,
                        userId: userId,
                        activityType: .completed,
                        activityData: nil
                    )
                }
            }
        }
    }

    private func calculateProgress(
        for challenge: Challenge,
        currentProgress: Decimal,
        newWorkout: CompletedWorkout
    ) -> Decimal {
        // Parse metric configuration from goalMetric (stored as JSON)
        // For backwards compatibility, fall back to challengeType-based calculation
        if let data = challenge.goalMetric.data(using: .utf8),
           let config = try? JSONDecoder().decode(MetricConfiguration.self, from: data) {
            // Use flexible metric calculator
            return MetricCalculator.calculate(
                metric: config.type,
                filter: config.filter,
                workout: newWorkout,
                userMaxHR: HRZoneCalculator.shared.maxHR
            )
        }

        // Fallback: Legacy challenge type calculation
        switch challenge.challengeType {
        case .workoutCount:
            return MetricCalculator.calculate(
                metric: .workoutCount,
                filter: nil,
                workout: newWorkout
            )

        case .totalVolume:
            return MetricCalculator.calculate(
                metric: .totalVolume,
                filter: nil,
                workout: newWorkout
            )

        case .specificExercise:
            // Use exercise name from goalMetric
            let filter = MetricFilter(exerciseName: challenge.goalMetric)
            return MetricCalculator.calculate(
                metric: .repsForExercise,
                filter: filter,
                workout: newWorkout
            )

        case .streak:
            // Streak calculation requires multiple workouts - handled at repository level
            return 0

        case .custom:
            // Custom calculation - for now return 0
            // In the future, parse custom metric config from goalMetric
            return 0
        }
    }

    // MARK: - Helper Methods

    private func fetchTopParticipants(challengeId: UUID, limit: Int) async throws -> [ChallengeParticipantProfile] {
        let participations: [ChallengeParticipant] = try await supabase.database
            .from("challenge_participants")
            .select()
            .eq("challenge_id", value: challengeId)
            .order("progress_percentage", ascending: false)
            .limit(limit)
            .execute()
            .value

        guard !participations.isEmpty else { return [] }

        let userIds = participations.map { $0.userId }
        let profiles: [UserProfile] = try await supabase.database
            .from("profiles")
            .select()
            .in("id", values: userIds.map { $0.uuidString })
            .execute()
            .value

        return participations.enumerated().compactMap { index, participation in
            guard let profile = profiles.first(where: { $0.id == participation.userId }) else { return nil }
            var result = ChallengeParticipantProfile(
                id: participation.id,
                participant: participation,
                profile: profile
            )
            result.rank = index + 1
            return result
        }
    }

    private func logActivity(
        challengeId: UUID,
        userId: UUID,
        activityType: ChallengeActivity.ActivityType,
        activityData: ChallengeActivity.ActivityData?
    ) async throws {
        let activity = ChallengeActivity(
            id: UUID(),
            challengeId: challengeId,
            userId: userId,
            activityType: activityType,
            activityData: activityData,
            createdAt: Date()
        )

        try await supabase.database
            .from("challenge_activities")
            .insert(activity)
            .execute()
    }
}
