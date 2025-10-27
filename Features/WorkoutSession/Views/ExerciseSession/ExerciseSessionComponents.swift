//
//  ExerciseSessionComponents.swift
//  WRKT
//
//  Small reusable UI components for exercise sessions
//

import SwiftUI

private typealias Theme = ExerciseSessionTheme

// MARK: - Stat Badge

struct StatBadge: View {
    let icon: String
    let value: String
    let label: String
    var accent: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(accent ? Theme.accent : Theme.secondary)

            Text(value)
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(accent ? Theme.accent : Theme.text)

            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Theme.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(accent ? Theme.accent.opacity(0.1) : Theme.surface)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(accent ? Theme.accent.opacity(0.3) : Theme.border, lineWidth: 1))
    }
}

// MARK: - Preset Button

struct PresetButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Theme.accent)
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.text)
            }
            .frame(minWidth: 60, maxWidth: .infinity)
            .frame(height: 60)
            .background(Theme.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
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
                .font(.headline)
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .contentShape(Rectangle())
        }
        .background(Theme.accent)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Preset Chip (Legacy)

struct PresetChip: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                ZStack {
                    Capsule()
                        .fill(Color(hex: "#1A1A1A"))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Theme.accent.opacity(0.15), Theme.accent.opacity(0.05)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
            )
            .overlay(
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [Theme.accent.opacity(0.4), Theme.accent.opacity(0.2)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1
                    )
            )
    }
}
