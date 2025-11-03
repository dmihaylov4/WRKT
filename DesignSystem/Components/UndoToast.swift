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
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    onUndo()
                    withAnimation {
                        isShowing = false
                    }
                } label: {
                    Text("Undo")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.Palette.marone)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation {
                        isShowing = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.6))
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(hex: "#1C1C1E"))
                    .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 4)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 80) // Above tab bar
            .transition(.move(edge: .bottom).combined(with: .opacity))
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
