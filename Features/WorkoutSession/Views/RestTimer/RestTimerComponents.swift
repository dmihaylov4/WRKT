//
//  RestTimerComponents.swift
//  WRKT
//
//  Rest timer settings and editor views
//

import SwiftUI

private typealias Theme = ExerciseSessionTheme

// MARK: - Compact Rest Timer Badge (Inline)

struct RestTimerCompactBadge: View {
    let exerciseID: String
    @ObservedObject private var manager = RestTimerManager.shared

    private var isActive: Bool {
        manager.isTimerFor(exerciseID: exerciseID) && manager.isRunning
    }

    private var timeRemaining: String {
        let remaining = manager.remainingSeconds.safeInt
        let minutes = remaining / 60
        let seconds = remaining % 60
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        } else {
            return "\(seconds)s"
        }
    }

    var body: some View {
        if isActive {
            HStack(spacing: 4) {
                Image(systemName: "timer")
                    .font(.caption2)
                Text(timeRemaining)
                    .font(.caption.monospacedDigit().weight(.semibold))
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.accent.opacity(0.12))
            .clipShape(ChamferedRectangle(.small))
            .transition(.scale.combined(with: .opacity))
        }
    }
}

// MARK: - Rest Timer Settings Card

struct RestTimerSettingsCard: View {
    let exercise: Exercise
    @ObservedObject private var prefs = RestTimerPreferences.shared

    private var currentDuration: TimeInterval {
        // Force view update by reading lastUpdate
        _ = prefs.lastUpdate
        return prefs.restDuration(for: exercise)
    }

    private var hasCustomTimer: Bool {
        prefs.hasOverride(for: exercise.id)
    }

    private var durationSource: String {
        if hasCustomTimer {
            return "Custom"
        } else if exercise.mechanic?.lowercased() == "compound" {
            return "Compound Default"
        } else {
            return "Isolation Default"
        }
    }

    private var timeString: String {
        let minutes = Int(currentDuration) / 60
        let seconds = Int(currentDuration) % 60
        if seconds == 0 {
            return "\(minutes):00"
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "hourglass")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Text("Rest Timer")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
            }

            // Current timer display
            NavigationLink {
                CustomTimerEditorView(exercise: exercise)
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(timeString)
                            .font(.title2.monospacedDigit().weight(.bold))
                            .foregroundStyle(Theme.text)

                        HStack(spacing: 4) {
                            if hasCustomTimer {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.accent)
                            }
                            Text(durationSource)
                                .font(.caption)
                                .foregroundStyle(Theme.secondary)
                        }
                    }

                    Spacer()

                    // Edit indicator
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.secondary)
                }
                .padding(12)
                .background(Theme.surface)
                .overlay(ChamferedRectangle(.medium).stroke(Theme.border, lineWidth: 1))
                .clipShape(ChamferedRectangle(.medium))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Custom Timer Editor View

struct CustomTimerEditorView: View {
    let exercise: Exercise
    @ObservedObject private var prefs = RestTimerPreferences.shared
    @Environment(\.dismiss) private var dismiss

    @State private var minutes: Int = 0
    @State private var seconds: Int = 0

    private var hasCustomTimer: Bool {
        prefs.hasOverride(for: exercise.id)
    }

    var body: some View {
        VStack(spacing: 24) {
            // Timer preview
            VStack(spacing: 8) {
                Text("Rest Timer")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondary)
                    .textCase(.uppercase)

                Text(String(format: "%d:%02d", minutes, seconds))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.accent)
            }
            .padding(.top, 32)

            // Pickers
            VStack(spacing: 16) {
                HStack {
                    Text("Minutes")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Picker("Minutes", selection: $minutes) {
                        ForEach(0..<11) { m in
                            Text("\(m)").tag(m)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 100, height: 120)
                }

                HStack {
                    Text("Seconds")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Picker("Seconds", selection: $seconds) {
                        ForEach(Array(stride(from: 0, to: 60, by: 15)), id: \.self) { s in
                            Text("\(s)").tag(s)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 100, height: 120)
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            // Reset button (if custom timer exists)
            if hasCustomTimer {
                Button {
                    prefs.removeOverride(for: exercise.id)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset to Default")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Theme.surface)
                    .clipShape(ChamferedRectangle(.medium))
                    .overlay(
                        ChamferedRectangle(.medium)
                            .stroke(Theme.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .navigationTitle("Custom Rest Timer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let totalSeconds = minutes * 60 + seconds
                    prefs.setRestDuration(totalSeconds, for: exercise.id)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    dismiss()
                }
                .fontWeight(.semibold)
                .disabled(minutes == 0 && seconds == 0)
            }
        }
        .onAppear {
            // Initialize with current duration
            let currentDuration = (prefs.restDuration(for: exercise)).safeInt
            minutes = currentDuration / 60
            seconds = currentDuration % 60
        }
    }
}
