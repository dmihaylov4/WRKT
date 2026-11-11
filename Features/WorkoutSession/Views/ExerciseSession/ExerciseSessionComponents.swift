//
//  ExerciseSessionComponents.swift
//  WRKT
//
//  Small reusable UI components for exercise sessions
//

import SwiftUI

private typealias Theme = ExerciseSessionTheme

// MARK: - Superset Toggle Button

struct SupersetToggleButton: View {
    let isActive: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            VStack(spacing: 4) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .dsFont(.title3, weight: .medium)
                    .foregroundStyle(isActive ? .black : Theme.accent)
                Text(isActive ? "In Superset" : "Superset")
                    .dsFont(.caption2, weight: .semibold)
                    .foregroundStyle(isActive ? .black : Theme.text)
            }
            .frame(minWidth: 60, maxWidth: .infinity)
            .frame(height: 60)
            .background(isActive ? Theme.accent : Theme.surface2)
            .clipShape(DS.RoleShape(.control, legacy: ChamferedRectangle(.medium)))
            .overlay(
                DS.RoleShape(.control, legacy: ChamferedRectangle(.medium))
                    .stroke(isActive ? Theme.accent : Theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Primary CTA Button

struct PrimaryCTA: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.light()
            action()
        }) {
            Text(title)
                .dsFont(.headline)
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .contentShape(Rectangle())
        }
        .background(Theme.accent)
        .clipShape(DS.RoleShape(.control, legacy: ChamferedRectangle(.large)))
    }
}
