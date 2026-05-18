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
    @Binding var isShowing: Bool

    var body: some View {
        if isShowing {
            Text(message)
                .dsFont(.subheadline, weight: .medium)
                .foregroundStyle(DS.Semantic.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    ChamferedRectangle(.large)
                        .fill(DS.Theme.cardTop)
                        .overlay(
                            ChamferedRectangle(.large)
                                .stroke(DS.Semantic.border, lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 8)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 90)
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

    private var hideTask: Task<Void, Never>?

    private init() {}

    /// Show a toast that auto-dismisses after 3 seconds
    func show(message: String) {
        self.message = message

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
                isShowing: $manager.isShowing
            )
        }
        .allowsHitTesting(manager.isShowing)
        .zIndex(999) // Below undo toast (1000) but above other content
    }
}
