//
//  RestTimerView.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 20.10.25.
//

import SwiftUI

// MARK: - Theme (using DS tokens)
private enum Theme {
    static let bg        = DS.Semantic.surface
    static let surface   = DS.Theme.cardTop
    static let surface2  = Color(red: 0.10, green: 0.10, blue: 0.10)
    static let border    = DS.Semantic.border
    static let text      = Color.white
    static let secondary = Color.white.opacity(0.65)
    static let accent    = DS.Theme.accent
    static let success   = DS.Status.success
    static let danger    = DS.Status.error
}

// MARK: - Compact Timer Display for LiveWorkoutGrabTab

/// Compact inline timer display for grab tab
struct RestTimerCompact: View {
    @ObservedObject var manager = RestTimerManager.shared
    @ObservedObject private var ticker = RestTimerManager.shared.ticker

    private var timeString: String {
        let minutes = ticker.remainingSeconds.safeInt / 60
        let seconds = ticker.remainingSeconds.safeInt % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        Group {
            if manager.isRunning {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 6, height: 6)
                        .opacity(0.9)

                    Text(timeString)
                        .dsFont(.subheadline, weight: .semibold, monospacedDigits: true)
                        .foregroundStyle(Theme.accent.opacity(0.95))
                        .contentTransition(.numericText())
                }
            } else if manager.isCompleted {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .dsFont(.caption, weight: .semibold)
                        .foregroundStyle(Theme.accent)

                    Text("Ready")
                        .dsFont(.caption, weight: .semibold)
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }
}
