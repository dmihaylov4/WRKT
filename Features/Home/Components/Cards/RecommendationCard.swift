//
//  RecommendationCard.swift
//  WRKT
//
//  Shows smart workout recommendation
//

import SwiftUI

struct RecommendationCard: View {
    let recommendation: WorkoutRecommendation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with icon - reserve space for arrow if no icon
            HStack(spacing: 8) {
                if !recommendation.icon.isEmpty {
                    Text(recommendation.icon)
                        .dsFont(.title2)
                } else {
                    // Spacer for arrow when no icon
                    Color.clear.frame(width: 24, height: 1)
                }

                Text(recommendation.title)
                    .dsFont(.headline)
                    .foregroundStyle(.primary)

                Spacer()
            }
            .padding(.top, 4) // Extra spacing from top

            // Reason
            Text(recommendation.reason)
                .dsFont(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            // Action button (if provided)
            if let action = recommendation.action {
                Button {
                    action.handler()
                } label: {
                    Text(action.label)
                        .dsFont(.subheadline, weight: .medium)
                        .foregroundStyle(DS.tint)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(DS.tint.opacity(0.15))
                        .cornerRadius(8)
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
                            Color.blue.opacity(0.05),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .clipShape(ChamferedRectangle(.large))
        .overlay(ChamferedRectangle(.large).stroke(.white.opacity(0.08), lineWidth: 1))
    }
}

