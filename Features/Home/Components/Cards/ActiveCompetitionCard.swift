//
//  ActiveCompetitionCard.swift
//  WRKT
//
//  Shows active battle or challenge status
//

import SwiftUI

struct ActiveCompetitionCard: View {
    let competition: CompetitionSummary

    private var icon: String {
        switch competition.type {
        case .battle:
            return "figure.strengthtraining.traditional"
        case .challenge:
            return "trophy.fill"
        }
    }

    private var iconColor: Color {
        switch competition.type {
        case .battle:
            return .orange
        case .challenge:
            return .yellow
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Text("Active Competition")
                .font(.headline)
                .foregroundStyle(.primary)

            // Competition details
            HStack(spacing: 12) {
                // Icon
                Image(systemName: icon)
                    .font(.title)
                    .foregroundStyle(iconColor)
                    .frame(width: 44, height: 44)
                    .background(iconColor.opacity(0.2))
                    .clipShape(Circle())

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(competition.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(competition.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            // Days remaining
            if competition.daysLeft > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text("\(competition.daysLeft) day\(competition.daysLeft == 1 ? "" : "s") remaining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            DS.card
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.yellow.opacity(0.05),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .clipShape(ChamferedRectangle(.large))
    }
}

// MARK: - Preview

#Preview("Battle - Winning") {
    VStack {
        ActiveCompetitionCard(
            competition: CompetitionSummary(
                name: "Battle vs John",
                type: .battle,
                status: "You're ahead by 500 lbs",
                daysLeft: 3
            )
        )
        Spacer()
    }
    .padding()
    .background(Color.black)
}

#Preview("Battle - Losing") {
    VStack {
        ActiveCompetitionCard(
            competition: CompetitionSummary(
                name: "Battle vs Sarah",
                type: .battle,
                status: "Down by 300 lbs • Time to push!",
                daysLeft: 1
            )
        )
        Spacer()
    }
    .padding()
    .background(Color.black)
}

#Preview("Challenge") {
    VStack {
        ActiveCompetitionCard(
            competition: CompetitionSummary(
                name: "November Volume Challenge",
                type: .challenge,
                status: "Rank #12 of 156 • 15,000 lbs total",
                daysLeft: 7
            )
        )
        Spacer()
    }
    .padding()
    .background(Color.black)
}
