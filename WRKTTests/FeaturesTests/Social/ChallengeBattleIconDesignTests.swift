import Foundation
import Testing

struct ChallengeBattleIconDesignTests {
    @Test func challengeAndBattleViewsUseAngularAssets() throws {
        let challengeSource = try String(
            contentsOfFile: sourcePath("Features/Challenges/Views/ChallengesBrowseView.swift"),
            encoding: .utf8
        )
        let battleSource = try String(
            contentsOfFile: sourcePath("Features/Battles/Views/CreateBattleView.swift"),
            encoding: .utf8
        )

        #expect(challengeSource.contains("challenge-browse-icon"))
        #expect(challengeSource.contains("challenge-completed-icon"))
        #expect(challengeSource.contains("ChamferedRectangle"))
        #expect(challengeSource.contains("streak-icon"))
        #expect(!challengeSource.contains("challenge-active-icon"))
        #expect(!challengeSource.contains("NavigationStack"))
        #expect(!challengeSource.contains(".navigationTitle(\"Challenges\")"))
        #expect(!challengeSource.contains("Image(systemName:"))
        #expect(!challengeSource.contains("RoundedRectangle"))
        #expect(!challengeSource.contains("Capsule()"))

        #expect(battleSource.contains("battle-flags-icon"))
        #expect(battleSource.contains("battle-volume-icon"))
        #expect(battleSource.contains("battle-workout-count-icon"))
        #expect(battleSource.contains("case .consistency:\n            return \"tab-plan\""))
        #expect(battleSource.contains("ChamferedRectangle"))
        #expect(!battleSource.contains("Image(systemName:"))
        #expect(!battleSource.contains("RoundedRectangle"))
        #expect(!battleSource.contains("Circle()"))
        #expect(!battleSource.contains("ContentUnavailableView"))
    }

    @Test func angularIconAssetsExist() {
        let assetNames = [
            "angular-check-icon",
            "angular-chevron-right-icon",
            "battle-consistency-icon",
            "battle-flags-icon",
            "battle-opponent-icon",
            "battle-volume-icon",
            "battle-workout-count-icon",
            "tab-plan",
            "challenge-browse-icon",
            "challenge-clock-icon",
            "challenge-completed-icon",
            "challenge-people-icon",
            "challenge-trophy-icon"
        ]

        for assetName in assetNames {
            #expect(FileManager.default.fileExists(
                atPath: sourcePath("Resources/Assets.xcassets/\(assetName).imageset/\(assetName).svg")
            ))
        }
    }

    @Test func activeAndCompletedChallengeTabsReserveBottomNavigationClearance() throws {
        let challengeSource = try String(
            contentsOfFile: sourcePath("Features/Challenges/Views/ChallengesBrowseView.swift"),
            encoding: .utf8
        )

        #expect(challengeSource.contains("activeCompletedBottomNavigationClearance"))
        #expect(challengeSource.contains("case .active, .completed:"))
        #expect(challengeSource.contains(".padding(.bottom, tabContentBottomPadding)"))
    }

    @Test func battleArenaAndDetailUseAngularAppLanguage() throws {
        let arenaSource = try String(
            contentsOfFile: sourcePath("Features/Social/Views/Components/ActiveArena.swift"),
            encoding: .utf8
        )
        let detailSource = try String(
            contentsOfFile: sourcePath("Features/Battles/Views/BattleDetailView.swift"),
            encoding: .utf8
        )
        let battleArenaSource = arenaSource.section(
            from: "// MARK: - Battle Arena Card",
            to: "// MARK: - Challenge Arena Card"
        )

        #expect(battleArenaSource.contains("BattleArenaMetric"))
        #expect(battleArenaSource.contains("ChamferedRectangle"))
        #expect(battleArenaSource.contains("frame(width: 210"))
        #expect(battleArenaSource.contains("isOpponentLeading"))
        #expect(!battleArenaSource.contains("RoundedRectangle"))
        #expect(!battleArenaSource.contains("Circle()"))

        #expect(detailSource.contains("BattleScorePanel"))
        #expect(detailSource.contains("BattleDetailMetric"))
        #expect(detailSource.contains("ChamferedRectangle"))
        #expect(detailSource.contains("isOpponentLeading"))
        #expect(detailSource.contains("shouldShowScoreSummary"))
        #expect(detailSource.contains("battleExitSection"))
        #expect(detailSource.contains("showingBattleExitConfirmation"))
        #expect(detailSource.contains("performBattleExit"))
        #expect(!detailSource.contains("isLeading: !viewModel.isCurrentUserWinning"))
        #expect(!detailSource.contains("Text(scoreUnit)"))
        #expect(!detailSource.contains("RoundedRectangle"))
        #expect(!detailSource.contains("Circle()"))
    }

    @Test func competeOverviewUsesCompactStatTilesWithoutLargeIcons() throws {
        let competeSource = try String(
            contentsOfFile: sourcePath("Features/Compete/UnifiedCompeteView.swift"),
            encoding: .utf8
        )
        let tileSource = competeSource.section(
            from: "struct CompeteStatTile",
            to: "struct CompletedChallengeCard"
        )

        #expect(tileSource.contains("frame(maxWidth: .infinity, minHeight: 76"))
        #expect(tileSource.contains("RoundedRectangle(cornerRadius: 2)"))
        #expect(!tileSource.contains("Image(systemName: icon)"))
        #expect(!tileSource.contains(".dsFont(.title, weight: .bold)"))
    }

    @Test func competeActionTilesUsePairedChamfers() throws {
        let competeSource = try String(
            contentsOfFile: sourcePath("Features/Compete/UnifiedCompeteView.swift"),
            encoding: .utf8
        )
        let designSystemSource = try String(
            contentsOfFile: sourcePath("DesignSystem/Theme/DS.swift"),
            encoding: .utf8
        )
        let buttonSource = competeSource.section(
            from: "struct CreationGridButton",
            to: "// MARK: - Large Battle Card"
        )

        #expect(designSystemSource.contains("public struct PairedChamferedRectangle"))
        #expect(designSystemSource.contains("case leadingTile, trailingTile"))
        #expect(buttonSource.contains("PairedChamferedRectangle(pair: tilePair"))
        #expect(buttonSource.contains("color.opacity(0.2), lineWidth: 1.25"))
    }

    @Test func battleDetailUsesDesignSystemTypography() throws {
        let detailSource = try String(
            contentsOfFile: sourcePath("Features/Battles/Views/BattleDetailView.swift"),
            encoding: .utf8
        )

        #expect(!detailSource.contains(".font(.system"))
        #expect(detailSource.contains("DS.Typography.custom(size: 36"))
    }

    @Test func completedParticipantChallengesDoNotRemainActiveOrAvailable() throws {
        let viewModelSource = try String(
            contentsOfFile: sourcePath("Features/Challenges/ViewModels/ChallengesViewModel.swift"),
            encoding: .utf8
        )

        #expect(viewModelSource.contains("activeChallenges = userChallenges.filter { $0.challenge.isActive && !$0.isCompleted }"))
        #expect(viewModelSource.contains("completedChallenges = userChallenges.filter { $0.isCompleted }"))
        #expect(viewModelSource.contains("let joinedChallengeIds = Set(userChallenges.map { $0.challenge.id })"))
        #expect(viewModelSource.contains("availableChallenges = allAvailable.filter { !joinedChallengeIds.contains($0.challenge.id) }"))
    }

    @Test func completedChallengeRowsAndWinScreenUseRewardPreview() throws {
        let competeSource = try String(
            contentsOfFile: sourcePath("Features/Compete/UnifiedCompeteView.swift"),
            encoding: .utf8
        )
        let winScreenSource = try String(
            contentsOfFile: sourcePath("Features/Rewards/Views/WinScreen.swift"),
            encoding: .utf8
        )
        let rewardSummarySource = try String(
            contentsOfFile: sourcePath("Features/Rewards/Views/RewardSummary.swift"),
            encoding: .utf8
        )
        let completedCardSource = competeSource.section(
            from: "struct CompletedChallengeCard",
            to: "// MARK: - Preview"
        )
        let winChallengeCardSource = winScreenSource.section(
            from: "private struct ChallengeRewardCard",
            to: "private struct RealityPlatePreview"
        )

        #expect(competeSource.contains("CompletedChallengeCard(challenge: challenge, onTap:"))
        #expect(completedCardSource.contains("Button"))
        #expect(completedCardSource.contains("rewardPreview"))
        #expect(!completedCardSource.contains("Image(systemName: \"checkmark.seal.fill\")"))

        #expect(rewardSummarySource.contains("let rewardKind: ChallengeRewardPreviewKind"))
        #expect(rewardSummarySource.contains("rewardKind: ChallengeRewardPreviewKind(challenge: challenge)"))
        #expect(winChallengeCardSource.contains("rewardPreview"))
        #expect(winChallengeCardSource.contains("BarSkinPreviewTile"))
        #expect(winChallengeCardSource.contains("PlateFaceView"))
        #expect(!winChallengeCardSource.contains("Image(systemName: \"flag.checkered\")"))
    }

    @Test func battleDetailExitActionsUpdateBattleState() throws {
        let detailSource = try String(
            contentsOfFile: sourcePath("Features/Battles/Views/BattleDetailView.swift"),
            encoding: .utf8
        )
        let viewModelSource = try String(
            contentsOfFile: sourcePath("Features/Battles/ViewModels/BattleViewModel.swift"),
            encoding: .utf8
        )
        let repositorySource = try String(
            contentsOfFile: sourcePath("Features/Battles/Services/BattleRepository.swift"),
            encoding: .utf8
        )

        #expect(detailSource.contains("battleExitActionTitle"))
        #expect(detailSource.contains("Leave Battle"))
        #expect(detailSource.contains("Cancel Battle"))
        #expect(detailSource.contains("Decline Battle"))
        #expect(viewModelSource.contains("func cancelBattle(_ battle: Battle) async -> Bool"))
        #expect(viewModelSource.contains("AppNotificationManager.shared.showBattleCancelled()"))
        #expect(repositorySource.contains("battle.status == .pending || battle.status == .active"))
        #expect(repositorySource.contains("battle.challengerId == userId || battle.opponentId == userId"))
        #expect(repositorySource.contains("\"winner_id\": nil"))
    }

    @Test func battleChallengeRewardImplementationHooksExist() throws {
        let battleModelSource = try String(
            contentsOfFile: sourcePath("Features/Battles/Models/Battle.swift"),
            encoding: .utf8
        )
        let battleRepositorySource = try String(
            contentsOfFile: sourcePath("Features/Battles/Services/BattleRepository.swift"),
            encoding: .utf8
        )
        let challengeRepositorySource = try String(
            contentsOfFile: sourcePath("Features/Challenges/Services/ChallengeRepository.swift"),
            encoding: .utf8
        )

        #expect(battleModelSource.contains("case runningDistance = \"running_distance\""))
        #expect(battleModelSource.contains("var participationPlateTierID: Int"))
        #expect(battleModelSource.contains("case .runningDistance: return 29"))
        #expect(battleModelSource.contains("case .runningDistance: return 30"))
        #expect(battleRepositorySource.contains("case .runningDistance:"))
        #expect(battleRepositorySource.contains("metric: .distance"))
        #expect(battleRepositorySource.contains("func completeBattle(_ battleId: UUID, sourceWorkoutID: String? = nil) async throws"))
        #expect(battleRepositorySource.contains("BarbellProgressService.shared.awardPlates"))
        #expect(challengeRepositorySource.contains("isFirstRepChallenge"))
        #expect(challengeRepositorySource.contains("BarbellCustomizationService.shared.unlockSkin(id: \"volia\")"))
        #expect(challengeRepositorySource.contains("conditioning_minutes"))
        #expect(challengeRepositorySource.contains("min(rawMinutes, 90)"))
    }

    @Test func workoutWinScreenMergesChallengeAndBattleRewards() throws {
        let coordinatorSource = try String(
            contentsOfFile: sourcePath("Features/Rewards/Services/WinScreenCoordinator.swift"),
            encoding: .utf8
        )
        let rewardSummarySource = try String(
            contentsOfFile: sourcePath("Features/Rewards/Views/RewardSummary.swift"),
            encoding: .utf8
        )
        let battleRepositorySource = try String(
            contentsOfFile: sourcePath("Features/Battles/Services/BattleRepository.swift"),
            encoding: .utf8
        )
        let barbellProgressSource = try String(
            contentsOfFile: sourcePath("Features/Rewards/Services/BarbellProgressService.swift"),
            encoding: .utf8
        )
        let winScreenSource = try String(
            contentsOfFile: sourcePath("Features/Rewards/Views/WinScreen.swift"),
            encoding: .utf8
        )
        let appShellSource = try String(
            contentsOfFile: sourcePath("App/AppShellView.swift"),
            encoding: .utf8
        )

        #expect(coordinatorSource.contains("if var current = summary, currentWorkout != nil"))
        #expect(coordinatorSource.contains("current.merged(with: finalSummary)"))
        #expect(rewardSummarySource.contains("static func barbellRewards"))
        #expect(rewardSummarySource.contains("guard xp > 0 else { return self }"))
        #expect(battleRepositorySource.contains("func awardCompletionReward(for battle: Battle, userId: UUID, sourceWorkoutID: String? = nil)"))
        #expect(battleRepositorySource.contains("completeBattle(battle.id, sourceWorkoutID: workout.id.uuidString)"))
        #expect(barbellProgressSource.contains("WinScreenCoordinator.shared.enqueue(.barbellRewards(events))"))
        #expect(winScreenSource.contains("onChange(of: summary.earnedPlates.count)"))
        #expect(appShellSource.contains("presentPendingBattleRewardsOnLaunch"))
    }

    @Test func workoutWinScreenShowsCompletedChallengeRewards() throws {
        let challengeRepositorySource = try String(
            contentsOfFile: sourcePath("Features/Challenges/Services/ChallengeRepository.swift"),
            encoding: .utf8
        )
        let rewardSummarySource = try String(
            contentsOfFile: sourcePath("Features/Rewards/Views/RewardSummary.swift"),
            encoding: .utf8
        )
        let winScreenSource = try String(
            contentsOfFile: sourcePath("Features/Rewards/Views/WinScreen.swift"),
            encoding: .utf8
        )

        #expect(rewardSummarySource.contains("ChallengeCompletionReward"))
        #expect(rewardSummarySource.contains("static func challengeCompleted"))
        #expect(rewardSummarySource.contains("challengeCompletions: [ChallengeCompletionReward]"))
        #expect(challengeRepositorySource.contains("WinScreenCoordinator.shared.enqueue(.challengeCompleted"))
        #expect(winScreenSource.contains("Text(\"Challenges\")"))
        #expect(winScreenSource.contains("ChallengeRewardCard"))
    }

    @Test func profileBarbellShowcaseMapsVoliaSkin() throws {
        let socialProfileSource = try String(
            contentsOfFile: sourcePath("Features/Social/Views/SocialProfileView.swift"),
            encoding: .utf8
        )
        let showcaseSource = try String(
            contentsOfFile: sourcePath("Features/Social/Views/BarbellShowcaseCard.swift"),
            encoding: .utf8
        )

        #expect(socialProfileSource.contains("case \"volia\": return 4"))
        #expect(showcaseSource.contains("case \"volia\": return 4"))
    }

    @Test func completedChallengesDeleteControlIsDebugGated() throws {
        let browseSource = try String(
            contentsOfFile: sourcePath("Features/Challenges/Views/ChallengesBrowseView.swift"),
            encoding: .utf8
        )
        let viewModelSource = try String(
            contentsOfFile: sourcePath("Features/Challenges/ViewModels/ChallengesViewModel.swift"),
            encoding: .utf8
        )

        #expect(!browseSource.contains("Delete Completed Challenges"))
        #expect(!browseSource.contains("deleteCompletedChallengesForRetest"))
        #expect(viewModelSource.contains("#if DEBUG"))
        #expect(viewModelSource.contains("func deleteCompletedChallengesForRetest()"))
        #expect(viewModelSource.contains("try await challengeRepository.leaveChallenge(item.challenge)"))
    }

    @Test func firstRepChallengeCanSelfHealFromCompletedWorkoutHistory() throws {
        let viewModelSource = try String(
            contentsOfFile: sourcePath("Features/Challenges/ViewModels/ChallengesViewModel.swift"),
            encoding: .utf8
        )
        let repositorySource = try String(
            contentsOfFile: sourcePath("Features/Challenges/Services/ChallengeRepository.swift"),
            encoding: .utf8
        )
        let detailSource = try String(
            contentsOfFile: sourcePath("Features/Challenges/Views/ChallengeDetailView.swift"),
            encoding: .utf8
        )

        #expect(viewModelSource.contains("workoutStore: WorkoutStoreV2?"))
        #expect(viewModelSource.contains("repairFirstRepProgressFromWorkoutHistory"))
        #expect(viewModelSource.contains("workoutStore?.completedWorkouts"))
        #expect(viewModelSource.contains("shouldCompleteFirstRep(from: completedWorkouts)"))
        #expect(viewModelSource.contains("completedFirstRepFromWorkoutHistory"))
        #expect(detailSource.contains("displayedChallenge"))
        #expect(detailSource.contains("shouldCompleteFirstRep(from: deps.workoutStore.completedWorkouts)"))
        #expect(repositorySource.contains("func completeFirstRepChallenge"))
        #expect(repositorySource.contains("BarbellCustomizationService.shared.unlockSkin(id: \"volia\")"))
    }

    @Test func feedArenaUsesUserChallengesAndFirstRepChamferedOneBadge() throws {
        let feedSource = try String(
            contentsOfFile: sourcePath("Features/Social/Views/FeedView.swift"),
            encoding: .utf8
        )
        let arenaSource = try String(
            contentsOfFile: sourcePath("Features/Social/Views/Components/ActiveArena.swift"),
            encoding: .utf8
        )
        let challengeArenaCardSource = arenaSource.section(
            from: "private struct ChallengeArenaCard",
            to: "*** End Of File ***"
        )

        #expect(feedSource.contains("fetchUserChallenges(userId: userId)"))
        #expect(feedSource.contains("completedFirstRepFromWorkoutHistory"))
        #expect(challengeArenaCardSource.contains("Text(\"1\")"))
        #expect(challengeArenaCardSource.contains("ChamferedRectangle(.large)"))
        #expect(!challengeArenaCardSource.contains("RoundedRectangle(cornerRadius: 12)"))
    }

    @Test func challengeParticipantProgressHasSelfUpdatePolicy() throws {
        let migrationsDirectory = URL(fileURLWithPath: sourcePath("supabase/migrations"))
        let migrationFiles = try FileManager.default.contentsOfDirectory(
            at: migrationsDirectory,
            includingPropertiesForKeys: nil
        )
        let combinedSQL = try migrationFiles
            .filter { $0.lastPathComponent.hasSuffix(".sql") }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")

        #expect(combinedSQL.contains("challenge_participants_self_update"))
        #expect(combinedSQL.contains("on public.challenge_participants"))
        #expect(combinedSQL.contains("with check (auth.uid() = user_id)"))
    }

    @Test func activeChallengeCardUsesChallengeRewardBadge() throws {
        let competeSource = try String(
            contentsOfFile: sourcePath("Features/Compete/UnifiedCompeteView.swift"),
            encoding: .utf8
        )
        let largeChallengeCardSource = competeSource.section(
            from: "struct LargeChallengeCard",
            to: "// MARK: - Recommended Challenge Card"
        )

        #expect(largeChallengeCardSource.contains("rewardBadge"))
        #expect(!largeChallengeCardSource.contains("PlateFaceView(\n                        tierID: 24"))
    }

    @Test func supabaseBattleChallengeMigrationSeedsRewardsAndRls() throws {
        let migrationsDirectory = URL(fileURLWithPath: sourcePath("supabase/migrations"))
        let migrationFiles = try FileManager.default.contentsOfDirectory(
            at: migrationsDirectory,
            includingPropertiesForKeys: nil
        )
        let combinedSQL = try migrationFiles
            .filter { $0.lastPathComponent.hasSuffix(".sql") }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")

        #expect(combinedSQL.contains("First Rep"))
        #expect(combinedSQL.contains("HIIT Forge"))
        #expect(combinedSQL.contains("conditioning_minutes"))
        #expect(combinedSQL.contains("challenger_score_update"))
        #expect(combinedSQL.contains("opponent_score_update"))
    }

    @Test func battleHeaderLogoUsesRevisedCrossedFlagsAsset() throws {
        let flagAsset = try String(
            contentsOfFile: sourcePath("Resources/Assets.xcassets/battle-flags-icon.imageset/battle-flags-icon.svg"),
            encoding: .utf8
        )

        #expect(flagAsset.contains("id=\"left-flag-head\""))
        #expect(flagAsset.contains("id=\"right-flag-head\""))
        #expect(flagAsset.contains("id=\"crossed-poles\""))
        #expect(!flagAsset.contains("points=\"7 6 18 6 21 11 18 16 9 16 9 27 6 27 6 7 7 6\""))
    }

    @Test func battleOpponentPickerUsesFriendsListPresentation() throws {
        let battleSource = try String(
            contentsOfFile: sourcePath("Features/Battles/Views/CreateBattleView.swift"),
            encoding: .utf8
        )
        let friendsSource = try String(
            contentsOfFile: sourcePath("Features/Social/Views/FriendsListView.swift"),
            encoding: .utf8
        )

        #expect(battleSource.contains("FriendPickerSearchBar"))
        #expect(battleSource.contains("SelectableFriendRow"))
        #expect(!battleSource.contains("FriendRowButton"))
        #expect(friendsSource.contains("struct FriendPickerSearchBar"))
        #expect(friendsSource.contains("struct SelectableFriendRow"))
        #expect(friendsSource.contains("FriendRow(friend: friend)"))
    }

    private func sourcePath(_ relativePath: String) -> String {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.path != "/" {
            let candidate = directory.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate.path
            }
            directory.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: relativePath).path
    }
}

private extension String {
    func section(from startMarker: String, to endMarker: String) -> String {
        guard
            let start = range(of: startMarker)?.lowerBound,
            let end = range(of: endMarker, range: start..<endIndex)?.lowerBound
        else {
            return self
        }

        return String(self[start..<end])
    }
}
