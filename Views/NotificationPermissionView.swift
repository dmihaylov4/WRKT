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
    @State private var authStatus: UNAuthorizationStatus = .notDetermined
    @State private var hasCheckedStatus = false

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
                handleAction()
            } label: {
                HStack {
                    if isRequesting {
                        ProgressView()
                            .tint(.black)
                    } else {
                        Image(systemName: authStatus == .notDetermined ? "bell.fill" : "gear")
                        Text(authStatus == .notDetermined ? "Enable Notifications" : "Open Settings")
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

            // Status message if already determined
            if hasCheckedStatus && authStatus != .notDetermined {
                Text(authStatus == .authorized ? "Already enabled" : "Enable in Settings → Notifications")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 4)
            }

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
        .task {
            await checkAuthorizationStatus()
        }
    }

    private func checkAuthorizationStatus() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        await MainActor.run {
            authStatus = settings.authorizationStatus
            hasCheckedStatus = true
        }
    }

    private func handleAction() {
        if authStatus == .notDetermined {
            requestPermission()
        } else {
            openSettings()
        }
    }

    private func openSettings() {
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL)
        }
        // Still complete onboarding even if they don't change settings
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            onComplete()
        }
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
