//
//  NotificationManager.swift
//  WRKT
//
//  Unified in-app notification manager for toasts, banners, and alerts
//

import Foundation
import SwiftUI
import Combine

@MainActor
@Observable
final class AppNotificationManager {
    static let shared = AppNotificationManager()

    // Current notification being displayed
    private(set) var currentNotification: ToastNotification?

    // Queue of pending notifications
    private var queue: [ToastNotification] = []

    // Timer for auto-dismiss
    private var dismissTimer: Timer?

    // Is a notification currently showing
    var isShowing: Bool {
        currentNotification != nil
    }

    private init() {}

    // MARK: - Public API

    /// Show a notification (adds to queue if one is already showing)
    func show(_ notification: ToastNotification) {
        // Play haptic feedback
        notification.type.haptic.play()

        if currentNotification == nil {
            // Show immediately
            displayNotification(notification)
        } else {
            // Add to queue
            queue.append(notification)
        }
    }

    /// Convenience method for success notifications
    func showSuccess(_ message: String, title: String? = nil) {
        show(.success(message, title: title))
    }

    /// Convenience method for error notifications
    func showError(_ message: String, title: String? = "Error") {
        show(.error(message, title: title))
    }

    /// Convenience method for info notifications
    func showInfo(_ message: String, title: String? = nil) {
        show(.info(message, title: title))
    }

    /// Convenience method for warning notifications
    func showWarning(_ message: String, title: String? = "Warning") {
        show(.warning(message, title: title))
    }

    /// Convenience method for undo notifications
    func showUndo(_ message: String, action: @escaping () -> Void) {
        show(.undo(message, action: action))
    }

    /// Dismiss the current notification
    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentNotification = nil
        }

        // Show next notification in queue after a brief delay
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
            await showNextInQueue()
        }
    }

    /// Perform the notification action (if any) and dismiss
    func performAction() {
        guard let action = currentNotification?.action else {
            dismiss()
            return
        }

        action.handler()
        dismiss()
    }

    /// Perform the notification tap handler (if any) and dismiss
    func performTap() {
        guard let tapHandler = currentNotification?.onTap else {
            dismiss()
            return
        }

        tapHandler()
        dismiss()
    }

    // MARK: - Private Methods

    private func displayNotification(_ notification: ToastNotification) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentNotification = notification
        }

        // Set up auto-dismiss timer
        dismissTimer = Timer.scheduledTimer(
            withTimeInterval: notification.duration,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.dismiss()
            }
        }
    }

    private func showNextInQueue() {
        guard !queue.isEmpty else { return }

        let nextNotification = queue.removeFirst()
        displayNotification(nextNotification)
    }
}

// MARK: - Convenience Extensions

extension AppNotificationManager {
    /// Show workout started notification
    func showWorkoutStarted(exerciseName: String) {
        show(.workoutStarted(exerciseName: exerciseName))
    }

    /// Show rest timer completed notification
    func showRestComplete(exerciseName: String, onTap: @escaping () -> Void) {
        show(.restComplete(exerciseName: exerciseName, onTap: onTap))
    }

    /// Show workout deleted with undo
    func showWorkoutDeleted(count: Int = 1, onUndo: @escaping () -> Void) {
        show(.workoutDeleted(count: count, onUndo: onUndo))
    }

    /// Show workout discarded with undo
    func showWorkoutDiscarded(onUndo: @escaping () -> Void) {
        show(.workoutDiscarded(onUndo: onUndo))
    }

    /// Show post deleted with undo
    func showPostDeleted(onUndo: @escaping () -> Void) {
        show(.postDeleted(onUndo: onUndo))
    }

    /// Show sets completed notification
    func showSetsCompleted(count: Int) {
        show(ToastNotification(
            type: .success,
            message: "\(count) sets completed! Tap + to add more",
            icon: "checkmark.circle.fill"
        ))
    }
}
