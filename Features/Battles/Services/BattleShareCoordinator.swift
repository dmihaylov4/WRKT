import Foundation
import SwiftUI

/// Singleton that carries the pending battle share action to BarbellWelcomeView.
/// Set by AppShellView.presentPendingBattleRewardsOnLaunch() after battle completion,
/// cleared when the BarbellWelcomeView sheet dismisses.
@MainActor
final class BattleShareCoordinator: ObservableObject {
    static let shared = BattleShareCoordinator()

    @Published private(set) var pendingBattle: BattleWithParticipants?
    @Published private(set) var pendingUserId: UUID?
    @Published private(set) var isAlreadyShared: Bool = false
    @Published private(set) var isSharing: Bool = false

    private init() {}

    func set(battle: BattleWithParticipants, userId: UUID) {
        pendingBattle = battle
        pendingUserId = userId
        isAlreadyShared = battle.battle.sharedPostId != nil
    }

    func clear() {
        pendingBattle = nil
        pendingUserId = nil
        isAlreadyShared = false
        isSharing = false
    }

    func share() async {
        guard let battle = pendingBattle,
              let userId = pendingUserId,
              !isAlreadyShared,
              !isSharing else { return }

        isSharing = true

        let opponent = battle.opponentProfile
        let isWinner = battle.battle.winnerId == userId
        let myScore  = battle.battle.score(for: userId)
        let oppScore = battle.battle.opponentScore(for: userId)

        let stats = BattlePostStats(
            battleId: battle.id,
            battleType: battle.battle.battleType,
            myScore: myScore,
            opponentScore: oppScore,
            opponentName: opponent.displayName ?? opponent.username,
            opponentAvatarUrl: opponent.avatarUrl,
            scoreUnit: battle.battle.scoreUnit,
            isWinner: isWinner,
            durationDays: battle.battle.duration,
            endDate: battle.battle.endDate
        )

        let placeholder = CompletedWorkout(
            entries: [],
            date: battle.battle.endDate,
            startedAt: battle.battle.startDate
        )

        do {
            let client = SupabaseClientWrapper.shared.client
            let postRepo = PostRepository(client: client)

            let post = try await postRepo.createPost(
                workouts: [placeholder],
                caption: nil,
                images: nil,
                visibility: .friends,
                userId: userId,
                postType: .battle,
                battleStats: stats
            )

            struct ShareLock: Encodable {
                let shared_post_id: String
                let shared_by_user_id: String
            }
            try await client
                .from("battles")
                .update(ShareLock(
                    shared_post_id: post.id.uuidString,
                    shared_by_user_id: userId.uuidString
                ))
                .eq("id", value: battle.id.uuidString)
                .execute()

            isAlreadyShared = true
            Haptics.success()
        } catch {
            AppLogger.error(
                "Failed to share battle result \(battle.id): \(error.localizedDescription)",
                category: AppLogger.battles
            )
        }

        isSharing = false
    }
}
