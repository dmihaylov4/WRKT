import SwiftUI

struct BattleRewardPreviewBlock: View {
    let battleType: BattleType
    let targetMetric: String?

    init(battleType: BattleType, targetMetric: String? = nil) {
        self.battleType = battleType
        self.targetMetric = targetMetric
    }

    private var participationTier: PlateTier? {
        PlateTier.all.first { $0.id == battleType.participationPlateTierID }
    }

    private var winnerTier: PlateTier? {
        PlateTier.all.first { $0.id == battleType.winnerPlateTierID }
    }

    private var exerciseLiftTypeID: String? {
        battleType == .exercise ? targetMetric : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Reward")
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(DS.Semantic.textPrimary)

            HStack(alignment: .top, spacing: 14) {
                rewardColumn(
                    title: "Complete",
                    tierID: battleType.participationPlateTierID,
                    tierName: participationTier?.name ?? "Participation Plate",
                    weightText: "20 kg",
                    xpText: "+200 XP",
                    liftTypeID: exerciseLiftTypeID,
                    isWinner: false
                )

                rewardColumn(
                    title: "Win",
                    tierID: battleType.winnerPlateTierID,
                    tierName: winnerTier?.name ?? "Winner Plate",
                    weightText: "35 kg",
                    xpText: "+400 XP",
                    liftTypeID: nil,
                    isWinner: true
                )
            }
        }
        .padding(16)
        .background(DS.Semantic.card, in: ChamferedRectangle(.large))
        .overlay(ChamferedRectangle(.large).stroke(DS.Semantic.border, lineWidth: 1))
    }

    private func rewardColumn(
        title: String,
        tierID: Int,
        tierName: String,
        weightText: String,
        xpText: String,
        liftTypeID: String?,
        isWinner: Bool
    ) -> some View {
        VStack(spacing: 7) {
            HStack(spacing: 4) {
                if isWinner {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(DS.Semantic.accentWarm)
                }
                Text(title)
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(isWinner ? DS.Semantic.accentWarm : DS.Semantic.textSecondary)
                    .lineLimit(1)
            }

            PlateFaceView(
                tierID: tierID,
                progressionTier: .iron,
                liftTypeID: liftTypeID,
                weightKg: isWinner ? 35 : 20
            )
            .frame(width: 88, height: 88)
            .clipped()

            Text(tierName)
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(DS.Semantic.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.82)

            Text(weightText)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(DS.Semantic.textSecondary)

            Text(xpText)
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(DS.Semantic.brand)
        }
        .frame(maxWidth: .infinity)
    }
}
