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
        #expect(battleArenaSource.contains("frame(width: 188"))
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
        #expect(battleRepositorySource.contains("func completeBattle(_ battleId: UUID) async throws"))
        #expect(battleRepositorySource.contains("BarbellProgressService.shared.awardPlates"))
        #expect(challengeRepositorySource.contains("isFirstRepChallenge"))
        #expect(challengeRepositorySource.contains("BarbellCustomizationService.shared.unlockSkin(id: \"volia\")"))
        #expect(challengeRepositorySource.contains("conditioning_minutes"))
        #expect(challengeRepositorySource.contains("min(rawMinutes, 90)"))
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
