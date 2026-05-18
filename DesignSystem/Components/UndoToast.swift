//
//  UndoToast.swift
//  WRKT
//
//  Toast notification with undo functionality for destructive actions
//

import SwiftUI
import Combine
/// Toast notification that appears at the bottom of the screen with an undo button
struct UndoToast: View {
    let message: String
    let onUndo: () -> Void
    @Binding var isShowing: Bool

    var body: some View {
        if isShowing {
            HStack(spacing: 14) {
                Text(message)
                    .dsFont(.subheadline, weight: .medium)
                    .foregroundStyle(DS.Semantic.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(DS.Semantic.border)
                    .frame(width: 1, height: 18)

                Button {
                    onUndo()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isShowing = false
                    }
                } label: {
                    Text("Undo")
                        .dsFont(.subheadline, weight: .bold)
                        .foregroundStyle(DS.Theme.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                ChamferedRectangle(.large)
                    .fill(
                        DS.Theme.cardTop
                    )
                    .overlay(
                        ChamferedRectangle(.large)
                            .stroke(DS.Semantic.border, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 8)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 90) // tab bar (49) + gap (41)
            .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.95)))
        }
    }
}

/// Manager to coordinate undo toasts across the app
@MainActor
class UndoToastManager: ObservableObject {
    static let shared = UndoToastManager()

    @Published var isShowing = false
    @Published var message = ""

    private var undoAction: (() -> Void)?
    private var hideTask: Task<Void, Never>?

    private init() {}

    /// Show a toast with an undo action that auto-dismisses after 5 seconds
    func show(message: String, undoAction: @escaping () -> Void) {
        self.message = message
        self.undoAction = undoAction

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isShowing = true
        }

        // Cancel any existing hide task
        hideTask?.cancel()

        // Auto-hide after 5 seconds
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            if !Task.isCancelled {
                withAnimation {
                    isShowing = false
                }
            }
        }
    }

    /// Perform the undo action
    func undo() {
        undoAction?()
        undoAction = nil
        isShowing = false
        hideTask?.cancel()
    }

    /// Dismiss the toast without performing undo
    func dismiss() {
        isShowing = false
        undoAction = nil
        hideTask?.cancel()
    }
}

/// Global undo toast overlay that should be added at the app root level
struct UndoToastOverlay: View {
    @StateObject private var manager = UndoToastManager.shared

    var body: some View {
        VStack {
            Spacer()
            UndoToast(
                message: manager.message,
                onUndo: { manager.undo() },
                isShowing: $manager.isShowing
            )
        }
        .allowsHitTesting(manager.isShowing)
        .zIndex(1000) // Ensure it appears above other content
    }
}
