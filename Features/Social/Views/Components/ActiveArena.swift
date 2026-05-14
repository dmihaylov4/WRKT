//
//  ActiveArena.swift
//  WRKT
//
//  Quick access horizontal scroll showing active battles and challenges
//

import SwiftUI
import Kingfisher

struct ActiveArena: View {
    let activeBattles: [BattleWithParticipants]
    let activeChallenges: [ChallengeWithProgress]
    let onBattleTap: (BattleWithParticipants) -> Void
    let onChallengeTap: (ChallengeWithProgress) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // Active battles
                ForEach(activeBattles) { battleItem in
                    BattleArenaCard(battle: battleItem) {
                        onBattleTap(battleItem)
                    }
                }

                // Active challenges
                ForEach(activeChallenges) { challengeItem in
                    ChallengeArenaCard(challenge: challengeItem) {
                        onChallengeTap(challengeItem)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .frame(height: 112)
    }
}

// MARK: - Battle Arena Card

private struct BattleArenaCard: View {
    let battle: BattleWithParticipants
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    avatarView(url: battle.opponentProfile.avatarUrl, size: 44)
                        .overlay(
                            ChamferedRectangleAlt(.small)
                                .stroke(DS.Semantic.border, lineWidth: 1)
                        )

                    Image(battleIconName)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 13, height: 13)
                        .foregroundStyle(.black)
                        .frame(width: 24, height: 24)
                        .background(DS.Semantic.brand, in: ChamferedRectangle(.micro))
                        .overlay(
                            ChamferedRectangle(.micro)
                                .stroke(DS.Semantic.surface, lineWidth: 2)
                        )
                        .offset(x: 4, y: 4)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(battle.battle.battleType.displayName)
                        .dsFont(.caption, weight: .bold)
                        .foregroundStyle(DS.Semantic.textPrimary)
                        .lineLimit(1)

                    Text(opponentName)
                        .dsFont(.caption2)
                        .foregroundStyle(DS.Semantic.textSecondary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        BattleArenaMetric(
                            label: "You",
                            value: formatScore(battle.userScore),
                            isHighlighted: battle.isUserLeading
                        )

                        Text("VS")
                            .dsFont(.caption2, weight: .black)
                            .foregroundStyle(DS.Semantic.textSecondary)

                        BattleArenaMetric(
                            label: "Them",
                            value: formatScore(battle.opponentScore),
                            isHighlighted: isOpponentLeading
                        )
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 6) {
                    Text("\(battle.battle.daysRemaining)d")
                        .dsFont(.headline, weight: .bold)
                        .foregroundStyle(DS.Semantic.brand)

                    Text("left")
                        .dsFont(.caption2)
                        .foregroundStyle(DS.Semantic.textSecondary)

                    Text(scoreUnit)
                        .dsFont(.caption2, weight: .bold)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }
            }
            .padding(.horizontal, 12)
            .frame(width: 210, height: 92, alignment: .leading)
            .background(DS.Semantic.card, in: ChamferedRectangle(.large))
            .overlay(
                ChamferedRectangle(.large)
                    .stroke(
                        battle.isUserLeading ? DS.Semantic.brand.opacity(0.45) : DS.Semantic.border,
                        lineWidth: 1.2
                    )
            )
            .contentShape(ChamferedRectangle(.large))
        }
        .buttonStyle(.plain)
    }

    private func formatScore(_ score: Decimal) -> String {
        let double = NSDecimalNumber(decimal: score).doubleValue
        if double >= 1000 {
            return String(format: "%.1fk", double / 1000)
        }
        return String(format: "%.0f", double)
    }

    private var opponentName: String {
        battle.opponentProfile.displayName ?? battle.opponentProfile.username
    }

    private var isOpponentLeading: Bool {
        battle.opponentScore > battle.userScore
    }

    private var scoreUnit: String {
        battle.battle.scoreUnit
    }

    private var battleIconName: String {
        switch battle.battle.battleType {
        case .volume:
            return "battle-volume-icon"
        case .consistency:
            return "battle-consistency-icon"
        case .workoutCount:
            return "battle-workout-count-icon"
        case .pr:
            return "battle-flags-icon"
        case .exercise:
            return "battle-opponent-icon"
        case .runningDistance:
            return "battle-workout-count-icon"
        }
    }

    private func avatarView(url: String?, size: CGFloat) -> some View {
        let chamferSize = size * 0.22 // ~22% of size for consistent proportions
        return Group {
            if let url = url, let imageUrl = URL(string: url) {
                KFImage(imageUrl)
                    .placeholder {
                        ChamferedRectangleAlt(chamferSize: chamferSize)
                            .fill(DS.Semantic.brandSoft)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .dsFont(.caption)
                                    .foregroundStyle(DS.Semantic.brand)
                            )
                    }
                    .fade(duration: 0.25)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(ChamferedRectangleAlt(chamferSize: chamferSize))
            } else {
                ChamferedRectangleAlt(chamferSize: chamferSize)
                    .fill(DS.Semantic.brandSoft)
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: "person.fill")
                            .dsFont(.caption)
                            .foregroundStyle(DS.Semantic.brand)
                    )
            }
        }
    }
}

private struct BattleArenaMetric: View {
    let label: String
    let value: String
    let isHighlighted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .dsFont(.caption2)
                .foregroundStyle(DS.Semantic.textSecondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Text(value)
                .dsFont(.caption, weight: .bold)
                .foregroundStyle(isHighlighted ? DS.Semantic.brand : DS.Semantic.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

// MARK: - Challenge Arena Card

private struct ChallengeArenaCard: View {
    let challenge: ChallengeWithProgress
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            VStack(spacing: 4) {
                // Challenge icon with progress ring
                ZStack {
                    ChamferedRectangle(.medium)
                        .stroke(DS.Semantic.surface50, lineWidth: 3)
                        .frame(width: 48, height: 48)

                    // Progress ring
                    Circle()
                        .trim(from: 0, to: CGFloat(challenge.userProgressPercentage) / 100)
                        .stroke(
                            LinearGradient(
                                colors: [DS.Semantic.brand, DS.Semantic.brand.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 48, height: 48)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(duration: 0.5), value: challenge.userProgressPercentage)

                    challengeIcon
                }

                // Challenge info
                VStack(spacing: 2) {
                    Text(challenge.challenge.title)
                        .dsFont(.caption2, weight: .bold)
                        .foregroundStyle(DS.Semantic.textPrimary)
                        .lineLimit(1)

                    Text("\(challenge.userProgressPercentage)%")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(DS.Semantic.brand)

                    Text(challenge.challenge.isEvergreen ? "Ongoing" : "\(challenge.challenge.daysRemaining)d left")
                        .font(.system(size: 9))
                        .foregroundStyle(DS.Semantic.textPrimary)
                }
            }
            .frame(width: 72)
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .background(DS.Semantic.card, in: ChamferedRectangle(.large))
            .overlay(
                ChamferedRectangle(.large)
                    .stroke(DS.Semantic.brand.opacity(0.15), lineWidth: 1.5)
            )
            .contentShape(ChamferedRectangle(.large))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var challengeIcon: some View {
        if challenge.challenge.isFirstRepChallenge {
            Text("1")
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(DS.Semantic.brand)
        } else {
            Image(systemName: challenge.challenge.challengeType.icon)
                .font(.system(size: 16))
                .foregroundStyle(DS.Semantic.brand)
        }
    }
}
