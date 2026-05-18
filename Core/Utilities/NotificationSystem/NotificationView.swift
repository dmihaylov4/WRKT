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
        HStack(spacing: 14) {
            // Content
            VStack(alignment: .leading, spacing: 2) {
                if let title = notification.title {
                    Text(title)
                        .dsFont(.subheadline, weight: .semibold)
                        .foregroundStyle(.white)
                }

                Text(notification.message)
                    .font(notification.title != nil ? .caption : .subheadline)
                    .foregroundStyle(notification.title != nil ? .white.opacity(0.8) : .white)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Action (if present)
            if let _ = notification.action {
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 1, height: 18)

                Button(action: onAction) {
                    Text(notification.action!.label)
                        .dsFont(.subheadline, weight: .bold)
                        .foregroundStyle(notification.type.color)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            ChamferedRectangle(.large)
                .fill(.black)
                .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
        )
        .overlay(
            ChamferedRectangle(.large)
                .stroke(notification.type.color.opacity(0.5), lineWidth: 1)
        )
        .padding(.horizontal)
        .padding(notification.position == .top ? .top : .bottom, 16)
        .contentShape(Rectangle())
        .onTapGesture {
            if notification.onTap != nil {
                onTap()
            } else {
                onDismiss()
            }
        }
    }

    // MARK: - Banner Style (Full Width)

    private var bannerStyle: some View {
        HStack(spacing: 14) {
            // Content
            VStack(alignment: .leading, spacing: 4) {
                if let title = notification.title {
                    Text(title)
                        .dsFont(.headline)
                        .foregroundStyle(.white)
                }

                Text(notification.message)
                    .dsFont(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Action Button
            if let action = notification.action {
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 1, height: 18)

                Button(action: onAction) {
                    Text(action.label)
                        .dsFont(.subheadline, weight: .bold)
                        .foregroundStyle(notification.type.color)
                }
                .buttonStyle(.plain)
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
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
    }

    // MARK: - Inline Style (Embedded)

    private var inlineStyle: some View {
        HStack(spacing: 14) {
            // Content
            VStack(alignment: .leading, spacing: 2) {
                if let title = notification.title {
                    Text(title)
                        .dsFont(.subheadline, weight: .semibold)
                        .foregroundStyle(.white)
                }

                Text(notification.message)
                    .dsFont(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Action Button
            if let action = notification.action {
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 1, height: 18)

                Button(action: onAction) {
                    Text(action.label)
                        .dsFont(.caption, weight: .semibold)
                        .foregroundStyle(notification.type.color)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            ChamferedRectangle(.large)
                .fill(.black)
        )
        .overlay(
            ChamferedRectangle(.large)
                .stroke(notification.type.color.opacity(0.5), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
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

