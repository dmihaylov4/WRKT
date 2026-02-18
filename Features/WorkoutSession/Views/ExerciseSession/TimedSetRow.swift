//
//  TimedSetRow.swift
//  WRKT
//
//  Set row component for timed exercises (planks, holds, etc.)
//

import SwiftUI

private typealias Theme = ExerciseSessionTheme

// MARK: - Timed Set Row

struct TimedSetRow: View {
    let index: Int
    @Binding var set: SetInput
    let exercise: Exercise
    let isActive: Bool
    let isGhost: Bool
    let hasActiveTimer: Bool
    let onActivate: () -> Void
    let onLogSet: () -> Void
    let onTimerStart: () -> Void  // New callback when timer starts

    @ObservedObject private var timerManager = RestTimerManager.shared
    @State private var isEditingDuration = false
    @State private var isRunningExercise = false
    @State private var elapsedSeconds: Int = 0
    @State private var exerciseTimer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            // Header: Set number, status, and type
            HStack(spacing: 12) {
                // Set number with status indicator
                HStack(spacing: 6) {
                    if set.isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    } else if isActive {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 8, height: 8)
                    } else {
                        Circle()
                            .strokeBorder(Theme.secondary.opacity(0.3), lineWidth: 1.5)
                            .frame(width: 8, height: 8)
                    }

                    Text("Set \(index)")
                        .font(.subheadline.weight(isActive ? .bold : .semibold))
                        .foregroundStyle(
                            set.isCompleted && hasActiveTimer ? Theme.text.opacity(0.7) :
                            set.isCompleted ? Theme.secondary :
                            Theme.text
                        )
                }

                // Rest timer (if active for this set)
                if hasActiveTimer && timerManager.isRunning {
                    Button {
                        timerManager.stopTimer()
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "timer")
                                .font(.caption.weight(.medium))
                            Text(formatTime(timerManager.remainingSeconds))
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text("•")
                                .font(.caption2)
                            Text("Cancel")
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                        }
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.accent.opacity(0.15))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Theme.accent.opacity(0.3), lineWidth: 1))
                        .lineLimit(1)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                // Set type badge
                TagDotCycler(tag: $set.tag)
                    .disabled(set.isCompleted || isGhost)
                    .opacity(set.isCompleted ? 0.5 : 1.0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 6)

            Divider()
                .background(Theme.border)
                .padding(.horizontal, 16)

            // Duration controls
            VStack(spacing: 12) {
                // Large timer display
                Text(formatDuration(isRunningExercise ? elapsedSeconds : set.durationSeconds))
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(set.isCompleted ? Theme.secondary : Theme.text)
                    .frame(maxWidth: .infinity)

                Text("DURATION")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondary)

                // Quick adjustment buttons (only when not running)
                if !isRunningExercise && !set.isCompleted && !isGhost {
                    HStack(spacing: 12) {
                        QuickTimeButton(label: "-15s", disabled: set.durationSeconds < 15) {
                            set.durationSeconds = max(0, set.durationSeconds - 15)
                            set.isAutoGeneratedPlaceholder = false
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }

                        QuickTimeButton(label: "-5s", disabled: set.durationSeconds < 5) {
                            set.durationSeconds = max(0, set.durationSeconds - 5)
                            set.isAutoGeneratedPlaceholder = false
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }

                        QuickTimeButton(label: "+5s", disabled: false) {
                            set.durationSeconds += 5
                            set.isAutoGeneratedPlaceholder = false
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }

                        QuickTimeButton(label: "+15s", disabled: false) {
                            set.durationSeconds += 15
                            set.isAutoGeneratedPlaceholder = false
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    }
                }

                // Start/Stop timer button
                if isActive && !set.isCompleted && !isGhost {
                    Button(action: toggleExerciseTimer) {
                        HStack(spacing: 8) {
                            Image(systemName: isRunningExercise ? "stop.circle.fill" : "play.circle.fill")
                            Text(isRunningExercise ? "Stop Timer" : "Start Timer")
                                .fontWeight(.semibold)
                        }
                        .font(.subheadline)
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(isRunningExercise ? Color.red : Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Active set: Show "Log This Set" button
            if isActive && !set.isCompleted && !isGhost && !isRunningExercise {
                Divider()
                    .background(Theme.border)
                    .padding(.horizontal, 16)

                Button(action: {
                    // If timer is running, stop it and save the elapsed time
                    if isRunningExercise {
                        stopExerciseTimer()
                    }
                    onLogSet()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Log This Set")
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(borderColor, lineWidth: isActive ? 2 : 1)
        )
        .opacity(rowOpacity)
        .animation(.easeInOut(duration: 0.2), value: isActive)
        .animation(.easeInOut(duration: 0.2), value: set.isCompleted)
        .animation(.easeInOut(duration: 0.2), value: hasActiveTimer)
        .animation(.easeInOut(duration: 0.2), value: isRunningExercise)
        .onTapGesture {
            if !set.isCompleted {
                set.isAutoGeneratedPlaceholder = false
                onActivate()
            }
        }
        .onAppear {
            seedFromDefaultIfNeeded()
        }
        .onDisappear {
            stopExerciseTimer()
        }
    }

    // MARK: - Timer Management

    private func toggleExerciseTimer() {
        if isRunningExercise {
            stopExerciseTimer()
        } else {
            startExerciseTimer()
        }
    }

    private func startExerciseTimer() {
        isRunningExercise = true
        elapsedSeconds = set.durationSeconds

        // Call the callback to ensure exercise is added to workout
        onTimerStart()

        exerciseTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            elapsedSeconds += 1
            set.durationSeconds = elapsedSeconds
        }

        Haptics.light()
    }

    private func stopExerciseTimer() {
        isRunningExercise = false
        exerciseTimer?.invalidate()
        exerciseTimer = nil
        set.durationSeconds = elapsedSeconds

        Haptics.soft()
    }

    // MARK: - Styling

    private var backgroundColor: Color {
        if set.isCompleted && hasActiveTimer {
            return Theme.accent.opacity(0.08)
        } else if set.isCompleted {
            return Theme.accent.opacity(0.04)
        } else if isActive {
            return Theme.surface2
        } else {
            return Theme.surface
        }
    }

    private var borderColor: Color {
        if isRunningExercise {
            return Color.red.opacity(0.6)
        } else if set.isCompleted && hasActiveTimer {
            return Theme.accent.opacity(0.5)
        } else if set.isCompleted {
            return Theme.accent.opacity(0.2)
        } else if isActive {
            return Theme.accent
        } else {
            return Theme.border
        }
    }

    private var rowOpacity: Double {
        if set.isCompleted && hasActiveTimer {
            return 0.85
        } else if set.isCompleted {
            return 0.65
        } else {
            return 1.0
        }
    }

    // MARK: - Helpers

    private func seedFromDefaultIfNeeded() {
        if set.durationSeconds == 0, let defaultDuration = exercise.defaultDurationSeconds {
            set.durationSeconds = defaultDuration
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Quick Time Button

private struct QuickTimeButton: View {
    let label: String
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(disabled ? Theme.secondary.opacity(0.4) : Theme.text)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(disabled ? Theme.surface : Theme.accent.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(disabled ? Theme.border : Theme.accent.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}
