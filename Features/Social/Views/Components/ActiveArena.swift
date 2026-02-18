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
            .padding(.vertical, 12)
        }
        .frame(height: 100)
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
            VStack(spacing: 6) {
                // Battle avatars with VS badge
                ZStack {
                    HStack(spacing: -15) {
                        // User avatar
                        avatarView(url: battle.userProfile.avatarUrl, size: 44)
                            .overlay(
                                Circle()
                                    .strokeBorder(DS.Semantic.card, lineWidth: 3)
                            )

                        // Opponent avatar
                        avatarView(url: battle.opponentProfile.avatarUrl, size: 44)
                            .overlay(
                                Circle()
                                    .strokeBorder(DS.Semantic.card, lineWidth: 3)
                            )
                    }

                    // VS badge
                    Text("VS")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(DS.Semantic.textPrimary)
                        .clipShape(Capsule())
                        .offset(y: 20)
                }
                .frame(height: 50)

                // Progress indicator
                VStack(spacing: 2) {
                    Text(battle.battle.battleType.displayName)
                        .font(.caption2.bold())
                        .foregroundStyle(DS.Semantic.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        // Score comparison
                        Text("\(formatScore(battle.userScore))")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(battle.isUserLeading ? DS.Semantic.success : DS.Semantic.textSecondary)

                        Text("-")
                            .font(.system(size: 10))
                            .foregroundStyle(DS.Semantic.textPrimary)

                        Text("\(formatScore(battle.opponentScore))")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(!battle.isUserLeading ? DS.Semantic.warning : DS.Semantic.textSecondary)
                    }

                    // Days remaining
                    Text("\(battle.battle.daysRemaining)d left")
                        .font(.system(size: 9))
                        .foregroundStyle(DS.Semantic.textPrimary)
                }
            }
            .frame(width: 72)
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .background(DS.Semantic.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(battle.isUserLeading ? DS.Semantic.brand.opacity(0.2) : DS.Semantic.textSecondary.opacity(0.15), lineWidth: 1.5)
            )
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
                                    .font(.caption)
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
                            .font(.caption)
                            .foregroundStyle(DS.Semantic.brand)
                    )
            }
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
                    // Background circle
                    Circle()
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

                    // Icon
                    Image(systemName: challenge.challenge.challengeType.icon)
                        .font(.system(size: 16))
                        .foregroundStyle(DS.Semantic.brand)
                }

                // Challenge info
                VStack(spacing: 2) {
                    Text(challenge.challenge.title)
                        .font(.caption2.bold())
                        .foregroundStyle(DS.Semantic.textPrimary)
                        .lineLimit(1)

                    Text("\(challenge.userProgressPercentage)%")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(DS.Semantic.brand)

                    Text("\(challenge.challenge.daysRemaining)d left")
                        .font(.system(size: 9))
                        .foregroundStyle(DS.Semantic.textPrimary)
                }
            }
            .frame(width: 72)
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .background(DS.Semantic.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(DS.Semantic.brand.opacity(0.15), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

