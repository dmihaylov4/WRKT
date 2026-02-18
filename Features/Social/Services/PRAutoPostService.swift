//
//  PRAutoPostService.swift
//  WRKT
//
//  Service for automatically posting Personal Records (PRs) to social feed
//

import Foundation

@MainActor
final class PRAutoPostService {
    static let shared = PRAutoPostService()

    private let postRepository: PostRepository
    private let authService: SupabaseAuthService

    private init() {
        self.postRepository = PostRepository(client: SupabaseClientWrapper.shared.client)
        self.authService = SupabaseAuthService.shared
    }

    /// Check if user has auto-posting enabled and create PR posts if needed
    func handlePRsIfNeeded(prAchievements: [PRAchievement], workout: CompletedWorkout) async {
        guard let user = authService.currentUser,
              let profile = user.profile,
              profile.autoPostPRs else {
            AppLogger.info("⏭️ PR auto-post disabled or user not logged in", category: AppLogger.social)
            return
        }

        guard !prAchievements.isEmpty else {
            AppLogger.info("ℹ️ No PRs to post", category: AppLogger.social)
            return
        }

        AppLogger.info("🏆 Creating auto-post for \(prAchievements.count) PR(s)", category: AppLogger.social)

        // Create a post for the PRs
        await createPRPost(prAchievements: prAchievements, workout: workout, userId: user.id)
    }

    /// Create a celebratory post for PR achievements
    private func createPRPost(prAchievements: [PRAchievement], workout: CompletedWorkout, userId: UUID) async {
        do {
            let caption = generatePRCaption(prAchievements)

            let post = try await postRepository.createPost(
                workout: workout,
                caption: caption,
                images: nil,
                visibility: .friends,
                userId: userId
            )

            AppLogger.success("✅ PR auto-post created successfully: \(post.id)", category: AppLogger.social)

            // Show success haptic
            Haptics.success()

        } catch {
            AppLogger.error("❌ Failed to create PR auto-post", error: error, category: AppLogger.social)
        }
    }

    /// Generate a celebratory caption for PR achievements
    private func generatePRCaption(_ prAchievements: [PRAchievement]) -> String {
        if prAchievements.count == 1 {
            // Single PR
            let pr = prAchievements[0]
            return generateSinglePRCaption(pr)
        } else {
            // Multiple PRs
            return generateMultiplePRCaption(prAchievements)
        }
    }

    private func generateSinglePRCaption(_ pr: PRAchievement) -> String {
        let emoji = selectEmoji(for: pr)

        if pr.isFirstPR {
            // First time doing this exercise
            return """
            NEW PR: \(pr.exerciseName)!
            \(formatWeight(pr.weight))kg × \(pr.reps) reps

            First time crushing this exercise!
            """
        } else if let improvement = pr.improvementPercentage {
            // Improvement over previous
            return """
            NEW PR: \(pr.exerciseName)!
            \(formatWeight(pr.weight))kg × \(pr.reps) reps

            +\(improvement) from previous best!
            """
        } else {
            // Standard PR
            return """
            NEW PR: \(pr.exerciseName)!
            \(formatWeight(pr.weight))kg × \(pr.reps) reps
            """
        }
    }

    private func generateMultiplePRCaption(_ prAchievements: [PRAchievement]) -> String {
        let count = prAchievements.count

        let prList = prAchievements.prefix(3).map { pr in
            "• \(pr.exerciseName): \(formatWeight(pr.weight))kg × \(pr.reps)"
        }.joined(separator: "\n")

        let extraText = prAchievements.count > 3 ? "\n• +\(prAchievements.count - 3) more!" : ""

        return """
        \(count) NEW PRs TODAY!

        \(prList)\(extraText)

        Feeling unstoppable!
        """
    }

    private func selectEmoji(for pr: PRAchievement) -> String {
        // Return empty - no longer using emojis
        return ""
    }

    private func formatWeight(_ weight: Double) -> String {
        if weight.truncatingRemainder(dividingBy: 1) == 0 {
            return String(weight.safeInt)
        } else {
            return String(format: "%.1f", weight)
        }
    }
}
