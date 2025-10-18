//
//  HealthAuthSheet.swift
//  WRKT
//
//  Sheet for requesting HealthKit authorization
//

import SwiftUI

struct HealthAuthSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var healthKit: HealthKitManager

    @State private var isAuthorizing = false
    @State private var error: Error?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "heart.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.pink, .white.opacity(0.1))
                        .symbolRenderingMode(.palette)

                    Text("Connect Apple Health")
                        .font(.title2.bold())

                    Text("Sync cardio workouts and MVPA minutes automatically")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)

                // Features list
                VStack(alignment: .leading, spacing: 16) {
                    FeatureRow(icon: "figure.run", title: "Auto-sync workouts", description: "Running, cycling, and other cardio activities")
                    FeatureRow(icon: "flame.fill", title: "MVPA tracking", description: "Apple Exercise Time for weekly goals")
                    FeatureRow(icon: "map.fill", title: "Route visualization", description: "Interactive maps with heart rate overlay")
                    FeatureRow(icon: "chart.line.uptrend.xyaxis", title: "Progress analytics", description: "Track trends and personal records")
                }
                .padding(.horizontal)

                Spacer()

                // Error message
                if let error {
                    Text("Error: \(error.localizedDescription)")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                // Action button
                Button {
                    authorize()
                } label: {
                    HStack {
                        if isAuthorizing {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "heart.fill")
                            Text("Connect Health")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.pink)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isAuthorizing)
                .padding(.horizontal)

                Button("Not Now") {
                    dismiss()
                }
                .foregroundStyle(.secondary)
                .padding(.bottom, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func authorize() {
        isAuthorizing = true
        error = nil

        Task {
            do {
                try await healthKit.requestAuthorization()
                await healthKit.syncWorkoutsIncremental()
                await healthKit.syncExerciseTimeIncremental()
                healthKit.setupBackgroundObservers()
                dismiss()
            } catch {
                self.error = error
                isAuthorizing = false
            }
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.pink)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
