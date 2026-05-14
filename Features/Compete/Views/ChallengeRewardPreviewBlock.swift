import SwiftUI

enum ChallengeRewardPreviewKind: Equatable {
    case firstRepBarSkin
    case conditioningPlate
    case none

    init(challenge: Challenge) {
        if challenge.isFirstRepChallenge {
            self = .firstRepBarSkin
        } else if challenge.goalMetric == "conditioning_minutes" {
            self = .conditioningPlate
        } else {
            self = .none
        }
    }
}

struct ChallengeRewardPreviewBlock: View {
    let rewardKind: ChallengeRewardPreviewKind

    init(challenge: Challenge) {
        self.rewardKind = ChallengeRewardPreviewKind(challenge: challenge)
    }

    init(rewardKind: ChallengeRewardPreviewKind) {
        self.rewardKind = rewardKind
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Reward")
                .dsFont(.title3, weight: .bold)
                .foregroundStyle(DS.Semantic.textPrimary)

            content
                .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(DS.Semantic.card, in: ChamferedRectangle(.large))
        .overlay(ChamferedRectangle(.large).stroke(DS.Semantic.border, lineWidth: 1))
    }

    @ViewBuilder
    private var content: some View {
        switch rewardKind {
        case .firstRepBarSkin:
            skinReward
        case .conditioningPlate:
            plateReward
        case .none:
            EmptyView()
        }
    }

    private var skinReward: some View {
        VStack(spacing: 8) {
            if let skin = BarSkin.all.first(where: { $0.id == 4 }) {
                BarSkinPreviewTile(skin: skin)
                    .frame(width: 120, height: 40)

                Text(skin.name)
                    .dsFont(.subheadline, weight: .black)
                    .foregroundStyle(DS.Semantic.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Text("Exclusive bar skin")
                .dsFont(.caption, weight: .bold)
                .foregroundStyle(DS.Semantic.textSecondary)

            Text("+200 XP")
                .dsFont(.caption, weight: .black)
                .foregroundStyle(DS.Semantic.brand)
        }
        .frame(maxWidth: .infinity)
    }

    private var plateReward: some View {
        let tierID = 24
        let tier = PlateTier.all.first { $0.id == tierID }

        return VStack(spacing: 8) {
            PlateFaceView(
                tierID: tierID,
                progressionTier: .iron,
                liftTypeID: nil,
                weightKg: 20
            )
            .frame(width: 100, height: 100)
            .clipped()

            Text(tier?.name ?? "Heat Forge")
                .dsFont(.subheadline, weight: .black)
                .foregroundStyle(DS.Semantic.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Text("20 kg")
                .dsFont(.caption, weight: .bold)
                .foregroundStyle(DS.Semantic.textSecondary)

            Text("+200 XP")
                .dsFont(.caption, weight: .black)
                .foregroundStyle(DS.Semantic.brand)
        }
        .frame(maxWidth: .infinity)
    }
}
