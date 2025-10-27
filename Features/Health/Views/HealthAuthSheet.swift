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
    var onDismiss: (() -> Void)? = nil

    @State private var isAuthorizing = false
    @State private var error: Error?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon - clean and professional with border
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 80, weight: .semibold))
                .foregroundStyle(Color.pink)
                .padding(32)
                .background(
                    Circle()
                        .stroke(Color.pink.opacity(0.3), lineWidth: 2)
                )
                .padding(.bottom, 40)

            // Title
            Text("Connect Apple Health")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            // Description
            Text("Sync cardio workouts and MVPA minutes automatically")
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 40)

            // Features list
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(icon: "figure.run", title: "Auto-sync workouts", description: "Running, cycling, and other cardio activities")
                FeatureRow(icon: "flame.fill", title: "MVPA tracking", description: "Apple Exercise Time for weekly goals")
                FeatureRow(icon: "map.fill", title: "Route visualization", description: "Interactive maps with heart rate overlay")
                FeatureRow(icon: "chart.line.uptrend.xyaxis", title: "Progress analytics", description: "Track trends and personal records")
            }
            .padding(.horizontal, 40)
            .padding(.top, 16)

            Spacer()

            // Error message
            if let error {
                Text("Error: \(error.localizedDescription)")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 24)
            }

            // Action button
            Button {
                authorize()
            } label: {
                HStack {
                    if isAuthorizing {
                        ProgressView()
                            .tint(.black)
                    } else {
                        Image(systemName: "heart.fill")
                        Text("Connect Health")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .foregroundStyle(.black)
                .background(
                    LinearGradient(
                        colors: [Color.pink, Color.pink.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Color.pink.opacity(0.3), radius: 12, x: 0, y: 6)
            }
            .disabled(isAuthorizing)
            .padding(.horizontal, 24)

            Button("Not Now") {
                if let onDismiss {
                    onDismiss()
                } else {
                    dismiss()
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white.opacity(0.6))
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Color(hex: "#0D0D0D"), Color(hex: "#1A1A1A")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
    }

    private func authorize() {
        isAuthorizing = true
        error = nil

        Task {
            do {
                print("🔐 Requesting HealthKit authorization...")
                try await healthKit.requestAuthorization()
                print("✅ Authorization granted, connection state: \(healthKit.connectionState)")

                // Do a FULL sync on first authorization to populate all workout types
                print("🔄 Starting full initial sync...")
                await healthKit.forceFullResync()
                print("✅ Full sync complete")

                await healthKit.syncExerciseTimeIncremental()
                healthKit.setupBackgroundObservers()

                await MainActor.run {
                    if let onDismiss {
                        onDismiss()
                    } else {
                        dismiss()
                    }
                }
            } catch {
                print("❌ Authorization failed: \(error)")
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
                    .foregroundStyle(.white.opacity(0.9))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}
