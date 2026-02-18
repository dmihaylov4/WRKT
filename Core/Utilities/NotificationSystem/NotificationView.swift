//
//  NotificationView.swift
//  WRKT
//
//  Unified notification view component
//

import SwiftUI

struct NotificationView: View {
    let notification: ToastNotification
    let onDismiss: () -> Void
    let onAction: () -> Void
    let onTap: () -> Void

    var body: some View {
        Group {
            switch notification.style {
            case .toast:
                toastStyle
            case .banner:
                bannerStyle
            case .inline:
                inlineStyle
            }
        }
        .transition(.asymmetric(
            insertion: notification.position == .top ? .move(edge: .top).combined(with: .opacity) : .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity.combined(with: .scale(scale: 0.9))
        ))
    }

    // MARK: - Toast Style (Floating Card)

    private var toastStyle: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: notification.icon ?? notification.type.icon)
                .font(.title3)
                .foregroundStyle(notification.type.color)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                if let title = notification.title {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }

                Text(notification.message)
                    .font(notification.title != nil ? .caption : .subheadline)
                    .foregroundStyle(notification.title != nil ? .white.opacity(0.8) : .white)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            // Action Button (if present)
            if let action = notification.action {
                Button(action: onAction) {
                    Text(action.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(notification.type.color)
                        .clipShape(Capsule())
                }
            }

            // Close Button
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 20, height: 20)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.black)
                .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(notification.type.color, lineWidth: 2)
        )
        .padding(.horizontal)
        .padding(notification.position == .top ? .top : .bottom, 16)
        .contentShape(Rectangle())
        .onTapGesture {
            if notification.onTap != nil {
                onTap()
            }
        }
    }

    // MARK: - Banner Style (Full Width)

    private var bannerStyle: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: notification.icon ?? notification.type.icon)
                .font(.title2)
                .foregroundStyle(notification.type.color)
                .frame(width: 32)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                if let title = notification.title {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                }

                Text(notification.message)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }

            Spacer()

            // Action Button
            if let action = notification.action {
                Button(action: onAction) {
                    Text(action.label)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(notification.type.color)
                        .clipShape(Capsule())
                }
            }

            // Close Button
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(16)
        .background(.black)
        .overlay(
            Rectangle()
                .fill(notification.type.color)
                .frame(height: 3)
                .frame(maxHeight: .infinity, alignment: notification.position == .top ? .top : .bottom)
        )
        .shadow(color: .black.opacity(0.2), radius: 8, y: notification.position == .top ? 2 : -2)
    }

    // MARK: - Inline Style (Embedded)

    private var inlineStyle: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: notification.icon ?? notification.type.icon)
                .font(.title3)
                .foregroundStyle(notification.type.color)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                if let title = notification.title {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }

                Text(notification.message)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }

            Spacer()

            // Action Button
            if let action = notification.action {
                Button(action: onAction) {
                    Text(action.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(notification.type.color)
                }
            }

            // Close Button
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.black)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(notification.type.color, lineWidth: 1.5)
        )
    }
}

// MARK: - Notification Overlay (for AppShellView)

struct NotificationOverlay: View {
    @State private var manager = AppNotificationManager.shared

    var body: some View {
        ZStack {
            if let notification = manager.currentNotification {
                VStack {
                    if notification.position == .top {
                        NotificationView(
                            notification: notification,
                            onDismiss: {
                                manager.dismiss()
                            },
                            onAction: {
                                manager.performAction()
                            },
                            onTap: {
                                manager.performTap()
                            }
                        )

                        Spacer()
                    } else {
                        Spacer()

                        NotificationView(
                            notification: notification,
                            onDismiss: {
                                manager.dismiss()
                            },
                            onAction: {
                                manager.performAction()
                            },
                            onTap: {
                                manager.performTap()
                            }
                        )
                    }
                }
                .zIndex(1001) // Highest z-index to be above everything
            }
        }
        .allowsHitTesting(manager.isShowing) // Only intercept touches when showing
    }
}

