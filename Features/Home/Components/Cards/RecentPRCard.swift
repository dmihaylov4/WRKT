//
//  RecentPRCard.swift
//  WRKT
//
//  Shows recent personal record achievement
//

import SwiftUI

struct RecentPRCard: View {
    let pr: PRSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Text("Recent PR")
                .font(.headline)
                .foregroundStyle(.primary)

            // PR details
            HStack(spacing: 12) {
                // Trophy icon
                Image(systemName: "medal.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.orange)

                // Exercise info
                VStack(alignment: .leading, spacing: 4) {
                    Text(pr.exerciseName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    HStack(spacing: 4) {
                        Text("\(pr.weight.safeInt) kg")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.orange)

                        Text("×")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("\(pr.reps) reps")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                }

                Spacer()

                // Date
                VStack(alignment: .trailing, spacing: 2) {
                    Text(pr.relativeDateString)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            // Motivational message
            Text("Keep pushing for new records!")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            DS.card
                .overlay(
                    // Subtle gradient overlay for PR celebration
                    LinearGradient(
                        colors: [
                            .orange.opacity(0.05),
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

// MARK: - Preview

#Preview("Today") {
    VStack {
        RecentPRCard(
            pr: PRSummary(
                exerciseName: "Bench Press",
                weight: 225,
                reps: 5,
                date: Date()
            )
        )
        Spacer()
    }
    .padding()
    .background(Color.black)
}

#Preview("Yesterday") {
    VStack {
        RecentPRCard(
            pr: PRSummary(
                exerciseName: "Squat",
                weight: 315,
                reps: 3,
                date: Date().addingTimeInterval(-86400)
            )
        )
        Spacer()
    }
    .padding()
    .background(Color.black)
}

#Preview("3 Days Ago") {
    VStack {
        RecentPRCard(
            pr: PRSummary(
                exerciseName: "Deadlift",
                weight: 405,
                reps: 1,
                date: Date().addingTimeInterval(-259200)
            )
        )
        Spacer()
    }
    .padding()
    .background(Color.black)
}
