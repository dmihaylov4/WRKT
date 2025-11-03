//
//  Haptics.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 09.10.25.
//

import SwiftUI

// MARK: - Feedback helpers
 enum Haptics {
    static func light()   { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func soft()    { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func medium()  { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func rigid()   { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
    static func heavy()   { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }

    // Notification feedback
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func error()   { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

// MARK: - Press feedback styles
 struct PressCardStyle: ButtonStyle {
    var corner: CGFloat = 20
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(.white.opacity(configuration.isPressed ? 0.06 : 0))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: configuration.isPressed)
    }
}

 struct PressTileStyle: ButtonStyle {
    var corner: CGFloat = 14
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(.white.opacity(configuration.isPressed ? 0.08 : 0))
            )
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.9), value: configuration.isPressed)
    }
}
