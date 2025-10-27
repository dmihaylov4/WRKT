//
//  NotificationPermissionView.swift
//  WRKT
//
//  Notification permission request during onboarding
//

import SwiftUI
import UserNotifications

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
                .foregroundStyle(Color(hex: "#F4E409"))
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

            // Description
            Text("Get notified when your rest timer completes so you never miss your next set.")
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 40)

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
                .background(
                    LinearGradient(
                        colors: [Color(hex: "#F4E409"), Color(hex: "#FFE869")],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Color(hex: "#F4E409").opacity(0.3), radius: 12, x: 0, y: 6)
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
                colors: [Color(hex: "#0D0D0D"), Color(hex: "#1A1A1A")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
    }

    private func requestPermission() {
        isRequesting = true

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                isRequesting = false

                if let error = error {
                    print("❌ Notification permission error: \(error)")
                } else if granted {
                    print("✅ Notification permissions granted")
                } else {
                    print("⚠️ Notification permissions denied by user")
                }

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
                .foregroundStyle(Color(hex: "#F4E409"))
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

#Preview {
    NotificationPermissionView(onComplete: {})
}
