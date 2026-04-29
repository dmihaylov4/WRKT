//
//  HealthAuthSheet.swift
//  WRKT
//
//  Sheet for requesting HealthKit authorization
//

import SwiftUI
import OSLog

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
                .font(DS.Typography.custom(size: 32, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

      

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
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .dsFont(.title2)
                        .foregroundStyle(.red)

                    Text(error.localizedDescription)
                        .dsFont(.subheadline)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.red.opacity(0.2))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.red.opacity(0.5), lineWidth: 1)
                )
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
                .dsFont(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .foregroundStyle(.black)
                .background(Color.pink)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            .dsFont(.subheadline, weight: .medium)
            .foregroundStyle(.white.opacity(0.6))
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [DS.Theme.cardBottom, DS.Theme.cardTop],
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
                AppLogger.info("Requesting HealthKit authorization...", category: AppLogger.health)
                try await healthKit.requestAuthorization()
                AppLogger.success("Authorization granted, connection state: \(healthKit.connectionState)", category: AppLogger.health)

                // Do a FULL sync on first authorization to populate all workout types
                AppLogger.info("Starting full initial sync...", category: AppLogger.health)
                await healthKit.forceFullResync()
                AppLogger.success("Full sync complete", category: AppLogger.health)

                AppLogger.success("Historical cardio enrichment complete", category: AppLogger.health)

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
                AppLogger.error("Authorization failed: \(error)", category: AppLogger.health)
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
                .dsFont(.title3)
                .foregroundStyle(.pink)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .dsFont(.subheadline, weight: .semibold)
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                Text(description)
                    .dsFont(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
