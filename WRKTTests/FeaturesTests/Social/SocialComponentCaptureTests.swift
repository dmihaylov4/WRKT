import Foundation
import SwiftUI
import Testing
import UIKit
@testable import WRKT

@MainActor
struct SocialComponentCaptureTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_SOCIAL_COMPONENTS"] == "1"))
    func captureComponents() async throws {
        let phase = ProcessInfo.processInfo.environment["VOLIA_SOCIAL_CAPTURE_PHASE"] ?? "after"
        try #require(["baseline", "after"].contains(phase))
        let mode = DS.Redesign.roundedShapesEnabled ? "rounded" : "legacy"
        let root = URL(fileURLWithPath: "/private/tmp/volia-shape-redesign-05/\(mode)/\(phase)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let user = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let peer = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let summary = WorkoutPostSummaryPresentation(title: "Strength Session", badge: "2 workouts",
            stats: [.init(label: "Volume", value: "2400", unit: "KG"),
                    .init(label: "Exercises", value: "4", unit: "EX"),
                    .init(label: "Sets", value: "12", unit: "TOTAL"),
                    .init(label: "Duration", value: "45:00", unit: "TIME")],
            biometrics: ["145 BPM", "320 CAL"], previewLine: "Bench Press, Squat", breakdownRows: [])
        try save(WorkoutPostHeroSummaryCard(summary: summary, context: .feed), "hero-feed", root)
        try save(WorkoutPostHeroSummaryCard(summary: summary, context: .detail), "hero-detail", root)
        try save(WorkoutPostHeroSummaryCard(summary: summary, context: .carousel), "hero-carousel", root)

        let challenge = Challenge(id: id, title: "Workout Week", description: "Complete five workouts.",
            challengeType: .workoutCount, goalMetric: "workouts", goalValue: 5,
            startDate: date, endDate: date.addingTimeInterval(604800), creatorId: nil,
            isPublic: true, isPreset: false, difficulty: .beginner, participantLimit: nil,
            participantCount: 12, completionCount: 3, createdAt: date, updatedAt: date)
        let participation = ChallengeParticipant(id: id, challengeId: id, userId: user,
            currentProgress: 3, progressPercentage: 60, completed: false,
            completionDate: nil, lastActivityDate: date, joinedAt: date)
        let active = ChallengeWithProgress(id: id, challenge: challenge,
            participation: participation, topParticipants: [])
        let available = ChallengeWithProgress(id: id, challenge: challenge,
            participation: nil, topParticipants: [])
        try save(ChallengeCard(challenge: active, isActive: true, onTap: {}), "challenge-active", root)
        try save(ChallengeCard(challenge: available, isActive: false, onTap: {}), "challenge-available", root)
        let preset = PresetChallenge(title: "Workout Week", description: "Complete five workouts.",
            challengeType: .workoutCount, goalMetric: "workouts", goalValue: 5,
            difficulty: .beginner, duration: 7, icon: "figure.run")
        try save(PresetChallengeCard(preset: preset, onTap: {}), "challenge-preset", root)
        let battle = Battle(id: id, challengerId: user, opponentId: peer, battleType: .volume,
            targetMetric: nil, startDate: date, endDate: date.addingTimeInterval(604800), status: .active,
            winnerId: nil, challengerScore: 2400, opponentScore: 1800, customRules: nil,
            trashTalkEnabled: false, createdAt: date, updatedAt: date)
        let arenaBattle = BattleWithParticipants(id: id, battle: battle,
            challenger: UserProfile(id: user, username: "alex", createdAt: date, updatedAt: date),
            opponent: UserProfile(id: peer, username: "sam", createdAt: date, updatedAt: date),
            currentUserId: user)
        try await saveHosted(ActiveArena(activeBattles: [arenaBattle], activeChallenges: [active],
            onBattleTap: { _ in }, onChallengeTap: { _ in }), "arena", height: 144, root)

        try save(CreationGridButton(iconName: "battle-flags-icon", title: "Start Battle",
            subtitle: "Challenge a friend", color: DS.Semantic.brand), "compete-creation-leading", root)
        try save(CreationGridButton(iconName: "challenge-trophy-icon", title: "Find Challenge",
            subtitle: "Build momentum", color: DS.Semantic.brand, gridPosition: .rowTrailing),
            "compete-creation-trailing", root)
        try save(CompeteStatTile(icon: "", value: "12", label: "Completed", color: DS.Semantic.brand),
            "compete-stat", root)
        try save(CompletedChallengeCard(challenge: active, onTap: {}), "compete-completed", root)
        try save(ScoreColumn(label: "You", score: 2400, isWinning: true, battleType: .volume),
            "battle-score", root)
        for winner in [true, false] {
            let stats = BattlePostStats(battleId: id, battleType: .volume, myScore: 2400,
                opponentScore: 1800, myName: "Alex", opponentName: "Sam", opponentAvatarUrl: nil,
                scoreUnit: "kg", isWinner: winner, durationDays: 7, endDate: date)
            try save(BattlePostCard(stats: stats), winner ? "battle-post-won" : "battle-post-lost", root)
        }

        try await saveHosted(VStack(spacing: 12) {
            TextField("Email", text: .constant("alex@example.invalid"))
                .modifier(LoginFieldStyle(isFocused: false))
            SecureField("Password", text: .constant("fixture-password"))
                .modifier(LoginFieldStyle(isFocused: true))
        }, "login-fields", height: 160, root)
        try save(VStack(spacing: 12) {
            Button("Add Friend", action: {}).buttonStyle(PrimaryButtonStyle())
            Button("Cancel Request", action: {}).buttonStyle(SecondaryButtonStyle())
        }, "profile-buttons", root)
        try save(HStack(spacing: 4) {
            PillSegmentButton(title: "Feed", iconAsset: "social-feed-icon", isSelected: true,
                badge: nil, action: {})
            PillSegmentButton(title: "Compete", iconAsset: "challenge-trophy-icon", isSelected: false,
                badge: nil, action: {})
        }, "social-segments", root)
        try save(HStack(spacing: 4) {
            ChallengePillButton(title: "Active", iconAsset: "streak-icon", isSelected: true,
                badge: 2, action: {})
            ChallengePillButton(title: "Browse", iconAsset: "challenge-browse-icon", isSelected: false,
                action: {})
        }, "challenge-segments", root)
        let comment = PostComment(id: id, postId: id, userId: user,
            content: "Great session. Keep building momentum!", createdAt: date, updatedAt: date)
        try save(CommentRow(comment: comment, isReply: false, canDelete: false,
            onDelete: {}, onReply: {}), "comment", root)
        try save(CommentRow(comment: comment, isReply: true, canDelete: false,
            onDelete: {}, onReply: {}), "reply", root)
        try save(MentionAutocomplete(suggestions: [UserProfile(id: user, username: "alex",
            displayName: "Alex", createdAt: date, updatedAt: date)], onSelect: { _ in }), "mentions", root)
        try save(SkeletonPostCard(), "skeleton-post", root)
        try save(SkeletonBattleCard(), "skeleton-battle", root)
        try save(SkeletonChallengeCard(), "skeleton-challenge", root)
        try save(SkeletonProfileHeader(), "skeleton-profile", root)
        try save(SkeletonNotificationRow(), "skeleton-notification", root)
    }

    private func save<V: View>(_ view: V, _ name: String, _ root: URL) throws {
        // ImageRenderer evaluates leaf content without mounting lifecycle tasks.
        let renderer = ImageRenderer(content: view
            .frame(width: 370).padding(16).background(Color.black)
            .environment(\.colorScheme, .dark)
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            .environment(\.dynamicTypeSize, .large)
            .transaction { $0.disablesAnimations = true })
        renderer.scale = 2
        let data = try #require(renderer.uiImage?.pngData())
        try data.write(to: root.appendingPathComponent(name + ".png"))
    }

    private func saveHosted<V: View>(_ view: V, _ name: String, height: CGFloat, _ root: URL) async throws {
        // Native text inputs and ScrollView require a host rather than ImageRenderer.
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        let controller = UIHostingController(rootView: view.frame(width: 370).padding(16)
            .background(Color.black).environment(\.colorScheme, .dark)
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            .environment(\.dynamicTypeSize, .large)
            .transaction { $0.disablesAnimations = true }.ignoresSafeArea())
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: height)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = controller
        controller.view.backgroundColor = .black
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(350))
        controller.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        let data = renderer.pngData { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        try data.write(to: root.appendingPathComponent(name + ".png"))
    }
}
