//
//  WorkoutToast.swift
//  WRKT
//
//  Toast notification for workout feedback
//

import SwiftUI
import Combine
/// Simple toast notification that appears at the bottom of the screen
struct WorkoutToast: View {
    let message: String
    let icon: String
    @Binding var isShowing: Bool

    var body: some View {
        if isShowing {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(DS.Theme.accent)
                    .frame(width: 32, height: 32)
                    .background(DS.Theme.accent.opacity(0.15), in: Circle())

                // Message
                Text(message)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DS.Semantic.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Close button
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isShowing = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.Semantic.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DS.Theme.cardTop)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(DS.Semantic.border, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 8)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 90) // Above tab bar
            .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.95)))
        }
    }
}

/// Manager to coordinate workout toasts across the app
@MainActor
class WorkoutToastManager: ObservableObject {
    static let shared = WorkoutToastManager()

    @Published var isShowing = false
    @Published var message = ""
    @Published var icon = "checkmark.circle.fill"

    private var hideTask: Task<Void, Never>?

    private init() {}

    /// Show a toast that auto-dismisses after 3 seconds
    func show(message: String, icon: String = "checkmark.circle.fill") {
        self.message = message
        self.icon = icon

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isShowing = true
        }

        // Play haptic feedback
        Haptics.success()

        // Cancel any existing hide task
        hideTask?.cancel()

        // Auto-hide after 3 seconds
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            if !Task.isCancelled {
                withAnimation {
                    isShowing = false
                }
            }
        }
    }

    /// Dismiss the toast immediately
    func dismiss() {
        isShowing = false
        hideTask?.cancel()
    }
}

/// Global workout toast overlay that should be added at the app root level
struct WorkoutToastOverlay: View {
    @StateObject private var manager = WorkoutToastManager.shared

    var body: some View {
        VStack {
            Spacer()
            WorkoutToast(
                message: manager.message,
                icon: manager.icon,
                isShowing: $manager.isShowing
            )
        }
        .allowsHitTesting(manager.isShowing)
        .zIndex(999) // Below undo toast (1000) but above other content
    }
}
