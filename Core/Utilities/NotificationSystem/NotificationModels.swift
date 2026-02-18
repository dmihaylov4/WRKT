//
//  NotificationModels.swift
//  WRKT
//
//  Unified notification system models
//

import Foundation
import SwiftUI

/// Toast notification type determines appearance and behavior
enum ToastNotificationType {
    case success
    case error
    case info
    case warning
    case undo

    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .undo: return "arrow.uturn.backward.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .success: return DS.Status.success
        case .error: return DS.Status.error
        case .info: return .blue
        case .warning: return DS.Status.warning
        case .undo: return DS.Theme.accent
        }
    }

    var haptic: HapticType {
        switch self {
        case .success: return .success
        case .error: return .error
        case .info: return .light
        case .warning: return .warning
        case .undo: return .light
        }
    }
}

/// Position where notification appears
enum NotificationPosition {
    case top
    case bottom

    var alignment: Alignment {
        switch self {
        case .top: return .top
        case .bottom: return .bottom
        }
    }
}

/// Style of notification presentation
enum NotificationStyle {
    case toast      // Small floating notification
    case banner     // Full-width banner
    case inline     // Embedded in view
}

/// Unified toast notification model
struct ToastNotification: Identifiable, Equatable {
    let id = UUID()
    let type: ToastNotificationType
    let title: String?
    let message: String
    let icon: String?
    let duration: TimeInterval
    let position: NotificationPosition
    let style: NotificationStyle
    let action: NotificationAction?
    let onTap: (() -> Void)?

    init(
        type: ToastNotificationType,
        title: String? = nil,
        message: String,
        icon: String? = nil,
        duration: TimeInterval = 3.0,
        position: NotificationPosition = .top,
        style: NotificationStyle = .toast,
        action: NotificationAction? = nil,
        onTap: (() -> Void)? = nil
    ) {
        self.type = type
        self.title = title
        self.message = message
        self.icon = icon ?? type.icon
        self.duration = duration
        self.position = position
        self.style = style
        self.action = action
        self.onTap = onTap
    }

    static func == (lhs: ToastNotification, rhs: ToastNotification) -> Bool {
        lhs.id == rhs.id
    }
}

/// Action that can be attached to a notification
struct NotificationAction: Equatable {
    let label: String
    let handler: () -> Void

    static func == (lhs: NotificationAction, rhs: NotificationAction) -> Bool {
        lhs.label == rhs.label
    }
}

// MARK: - Convenience Initializers

extension ToastNotification {
    /// Success notification (green checkmark)
    static func success(
        _ message: String,
        title: String? = nil,
        duration: TimeInterval = 3.0,
        position: NotificationPosition = .top
    ) -> ToastNotification {
        ToastNotification(
            type: .success,
            title: title,
            message: message,
            duration: duration,
            position: position
        )
    }

    /// Error notification (red X)
    static func error(
        _ message: String,
        title: String? = "Error",
        duration: TimeInterval = 4.0,
        position: NotificationPosition = .top
    ) -> ToastNotification {
        ToastNotification(
            type: .error,
            title: title,
            message: message,
            duration: duration,
            position: position
        )
    }

    /// Info notification (blue info circle)
    static func info(
        _ message: String,
        title: String? = nil,
        duration: TimeInterval = 3.0,
        position: NotificationPosition = .top
    ) -> ToastNotification {
        ToastNotification(
            type: .info,
            title: title,
            message: message,
            duration: duration,
            position: position
        )
    }

    /// Warning notification (yellow triangle)
    static func warning(
        _ message: String,
        title: String? = "Warning",
        duration: TimeInterval = 4.0,
        position: NotificationPosition = .top
    ) -> ToastNotification {
        ToastNotification(
            type: .warning,
            title: title,
            message: message,
            duration: duration,
            position: position
        )
    }

    /// Undo notification with action button
    static func undo(
        _ message: String,
        duration: TimeInterval = 5.0,
        position: NotificationPosition = .bottom,
        action: @escaping () -> Void
    ) -> ToastNotification {
        ToastNotification(
            type: .undo,
            message: message,
            duration: duration,
            position: position,
            action: NotificationAction(label: "Undo", handler: action)
        )
    }

    /// Workout started notification
    static func workoutStarted(exerciseName: String) -> ToastNotification {
        ToastNotification(
            type: .success,
            message: "Workout started! Added \(exerciseName)",
            icon: "dumbbell.fill",
            duration: 3.0,
            position: .top
        )
    }

    /// Rest timer completed notification
    static func restComplete(exerciseName: String, onTap: @escaping () -> Void) -> ToastNotification {
        ToastNotification(
            type: .info,
            title: "Rest Complete!",
            message: "Ready for \(exerciseName)",
            icon: "timer",
            duration: 4.0,
            position: .top,
            action: NotificationAction(label: "Go", handler: onTap)
        )
    }

    /// Workout deleted with undo
    static func workoutDeleted(count: Int = 1, onUndo: @escaping () -> Void) -> ToastNotification {
        let message = count > 1 ? "Workouts deleted" : "Workout deleted"
        return ToastNotification.undo(message, action: onUndo)
    }

    /// Workout discarded with undo
    static func workoutDiscarded(onUndo: @escaping () -> Void) -> ToastNotification {
        ToastNotification.undo("Workout discarded", action: onUndo)
    }

    /// Post deleted with undo
    static func postDeleted(onUndo: @escaping () -> Void) -> ToastNotification {
        ToastNotification.undo("Post deleted", action: onUndo)
    }
}

// MARK: - HapticType Extension

enum HapticType {
    case success
    case error
    case warning
    case light

    func play() {
        switch self {
        case .success: Haptics.success()
        case .error: Haptics.error()
        case .warning: Haptics.warning()
        case .light: Haptics.light()
        }
    }
}
