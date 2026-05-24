import SwiftUI

struct BattlePostCard: View {
    let stats: BattlePostStats

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            scoreRow
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(stats.battleType.customIconName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(DS.Semantic.brand)

            Text(stats.battleType.displayName)
                .dsFont(.subheadline, weight: .semibold)
                .foregroundStyle(DS.Semantic.textPrimary)

            Spacer()

            resultBadge
        }
    }

    private var resultBadge: some View {
        let label = stats.isWinner ? "Won" : "Lost"
        let color: Color = stats.isWinner ? DS.Semantic.accentWarm : DS.Semantic.textSecondary
        return Text(label)
            .dsFont(.caption, weight: .semibold)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                stats.isWinner ? DS.Semantic.accentWarm.opacity(0.12) : DS.Semantic.card,
                in: Capsule()
            )
    }

    private var scoreRow: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(formatScore(stats.myScore))
                    .dsFont(.title3, weight: .bold)
                    .foregroundStyle(stats.isWinner ? DS.Semantic.accentWarm : DS.Semantic.textPrimary)
                Text(stats.myName?.components(separatedBy: " ").first ?? "—")
                    .dsFont(.caption2)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(DS.Semantic.border)
                .frame(width: 1, height: 36)

            VStack(alignment: .trailing, spacing: 2) {
                Text(formatScore(stats.opponentScore))
                    .dsFont(.title3, weight: .bold)
                    .foregroundStyle(!stats.isWinner ? DS.Semantic.accentWarm : DS.Semantic.textPrimary)
                Text(stats.opponentName.components(separatedBy: " ").first ?? stats.opponentName)
                    .dsFont(.caption2)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var footer: some View {
        Text("\(stats.durationDays)-day battle - ended \(stats.endDate, format: .relative(presentation: .named))")
            .dsFont(.caption)
            .foregroundStyle(DS.Semantic.textSecondary)
    }

    private func formatScore(_ score: Decimal) -> String {
        let value = NSDecimalNumber(decimal: score).doubleValue
        switch stats.scoreUnit {
        case "kg":
            return WeightUnit.preferred.formatVolume(value)
        case "days":
            return "\(Int(value)) days"
        default:
            return "\(Int(value)) \(stats.scoreUnit)"
        }
    }
}
