//
//  CompactExerciseBrowse.swift
//  WRKT
//
//  Compact exercise browsing section with quick muscle group access
//

import SwiftUI

struct CompactExerciseBrowse: View {
    let onUpperBody: () -> Void
    let onLowerBody: () -> Void
    let onBrowseAll: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Quick access buttons
            HStack(spacing: 8) {
                MuscleGroupButton(
                    title: "Upper Body",
                    icon: "figure.strengthtraining.traditional",
                    action: onUpperBody
                )

                MuscleGroupButton(
                    title: "Lower Body",
                    icon: "figure.step.training",
                    action: onLowerBody
                )
            }

            // Browse all link
            Button {
                onBrowseAll()
            } label: {
                HStack(spacing: 4) {
                    Text("Browse all exercises")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
