//
//  NotificationPermissionView.swift
//  WRKT
//
//  Notification permission request during onboarding
//

import SwiftUI
import UserNotifications
import OSLog

struct NotificationPermissionView: View {
    @Environment(\.dismiss) private var dismiss
    var onComplete: () -> Void

    @State private var isRequesting = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon - clean and professional with border
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 80, weight: .semibold))
                .foregroundStyle(DS.Theme.accent)
                .padding(32)
                .background(
                    Circle()
                        .stroke(Color(hex: "#F4E409").opacity(0.3), lineWidth: 2)
                )
                .padding(.bottom, 40)

            // Title
            Text("Stay on Track")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

          

            // Features list
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(icon: "timer", title: "Rest timer alerts", description: "Know when it's time for your next set")
                FeatureRow(icon: "flame.fill", title: "Streak reminders", description: "Keep your workout streak alive")
                FeatureRow(icon: "trophy.fill", title: "Achievement unlocks", description: "Celebrate your progress")
            }
            .padding(.horizontal, 40)
            .padding(.top, 16)

            Spacer()

            // Action button
            Button {
                requestPermission()
            } label: {
                HStack {
                    if isRequesting {
                        ProgressView()
                            .tint(.black)
                    } else {
                        Image(systemName: "bell.fill")
                        Text("Enable Notifications")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .foregroundStyle(.black)
                .background(DS.Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .disabled(isRequesting)
            .padding(.horizontal, 24)

            Button("Not Now") {
                onComplete()
            }
            .font(.subheadline.weight(.medium))
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

    private func requestPermission() {
        isRequesting = true

        Task {
            await NotificationManager.shared.requestAuthorization()

            await MainActor.run {
                isRequesting = false
                // Complete onboarding regardless of permission result
                onComplete()
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
                .foregroundStyle(DS.Theme.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    NotificationPermissionView(onComplete: {})
}
