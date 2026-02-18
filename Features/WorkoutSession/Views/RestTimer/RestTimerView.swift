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

// MARK: - Rest Timer Banner

/// Compact banner that shows rest timer state - only for matching exercise
struct RestTimerBanner: View {
    let exerciseID: String
    @ObservedObject var manager = RestTimerManager.shared

    var body: some View {
        Group {
            // Only show banner if timer is for this specific exercise
            if manager.isTimerFor(exerciseID: exerciseID) {
                switch manager.state {
                case .idle:
                    EmptyView()

                case .running(_, _, let exerciseName, let originalDuration, _):
                    RunningTimerBanner(
                        exerciseName: exerciseName,
                        remainingSeconds: manager.remainingSeconds,
                        originalDuration: originalDuration,
                        hasBeenAdjusted: manager.hasBeenAdjusted,
                        isCustomTimer: manager.isUsingCustomTimer,
                        onSkip: { manager.skipTimer() },
                        onStop: { manager.stopTimer() },
                        onAdjust: { seconds in manager.adjustTime(by: seconds) },
                        onSaveAsDefault: { manager.saveAsDefaultForCurrentExercise() }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))

                case .paused(let remaining, _, let exerciseName, _, _):
                    PausedTimerBanner(
                        exerciseName: exerciseName,
                        remainingSeconds: remaining,
                        onResume: { manager.resumeTimer() },
                        onStop: { manager.stopTimer() }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))

                case .completed(_, let exerciseName):
                    CompletedTimerBanner(
                        exerciseName: exerciseName,
                        onDismiss: { manager.dismissCompleted() }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: manager.state)
    }
}

// MARK: - Running Timer Banner

private struct RunningTimerBanner: View {
    let exerciseName: String
    let remainingSeconds: TimeInterval
    let originalDuration: TimeInterval
    let hasBeenAdjusted: Bool
    let isCustomTimer: Bool
    let onSkip: () -> Void
    let onStop: () -> Void
    let onAdjust: (TimeInterval) -> Void
    let onSaveAsDefault: () -> Void

    private var timeString: String {
        let minutes = Int(remainingSeconds) / 60
        let seconds = Int(remainingSeconds) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var progressFraction: Double {
        // Calculate progress - originalDuration is always updated when timer is adjusted
        guard originalDuration > 0 else { return 0 }
        let elapsed = originalDuration - remainingSeconds
        return min(1.0, max(0.0, elapsed / originalDuration))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                // Timer display - prominent
                HStack(spacing: 8) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .symbolEffect(.pulse, options: .repeating)

                    Text(timeString)
                        .font(.title2.monospacedDigit().weight(.bold))
                        .foregroundStyle(Theme.accent)
                        .contentTransition(.numericText())
                }

                Spacer()

                // Adjustment buttons - compact
                HStack(spacing: 8) {
                    QuickAdjustButton(icon: "minus", isNegative: true) {
                        onAdjust(-30)
                    }

                    QuickAdjustButton(icon: "plus", isNegative: false) {
                        onAdjust(30)
                    }
                }

                // Save as default button - only show if adjusted
                if hasBeenAdjusted {
                    Button(action: {
                        onSaveAsDefault()
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Save")
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Theme.accent.opacity(0.15), in: ChamferedRectangle(.small))
                        .overlay(ChamferedRectangle(.small).stroke(Theme.accent.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }

                // Skip button
                Button(action: onSkip) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                        .frame(width: 32, height: 32)
                        .background(Theme.surface2, in: Circle())
                        .overlay(Circle().stroke(Theme.border, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.surface)
            .overlay(
                Rectangle()
                    .fill(Theme.border)
                    .frame(height: 0.5),
                alignment: .bottom
            )

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Theme.border.opacity(0.3))

                    Rectangle()
                        .fill(Theme.accent)
                        .frame(width: geo.size.width * progressFraction)
                        .animation(.linear(duration: 0.1), value: progressFraction)
                }
            }
            .frame(height: 2)
        }
    }
}

// Quick adjust button component
private struct QuickAdjustButton: View {
    let icon: String
    let isNegative: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.text)
                .frame(width: 32, height: 32)
                .background(Theme.surface2, in: Circle())
                .overlay(Circle().stroke(Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Paused Timer Banner

private struct PausedTimerBanner: View {
    let exerciseName: String
    let remainingSeconds: TimeInterval
    let onResume: () -> Void
    let onStop: () -> Void

    private var timeString: String {
        let minutes = Int(remainingSeconds) / 60
        let seconds = Int(remainingSeconds) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(Theme.secondary.opacity(0.2))
                    .frame(width: 32, height: 32)

                Image(systemName: "pause.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
            }

            // Timer info
            VStack(alignment: .leading, spacing: 2) {
                Text("Rest Timer Paused")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.secondary)
                    .textCase(.uppercase)

                Text(timeString)
                    .font(.title3.monospacedDigit().weight(.bold))
                    .foregroundStyle(Theme.text)
            }

            Spacer()

            // Resume button
            Button(action: onResume) {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                        .font(.caption2)
                    Text("Resume")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Theme.accent.opacity(0.15), in: ChamferedRectangle(.small))
                .overlay(ChamferedRectangle(.small).stroke(Theme.accent.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)

            // Stop button
            Button(action: onStop) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 28, height: 28)
                    .background(Theme.surface2, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.surface)
    }
}

// MARK: - Completed Timer Banner

private struct CompletedTimerBanner: View {
    let exerciseName: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Icon with success animation
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .symbolEffect(.bounce, options: .nonRepeating)

            // Message
            VStack(alignment: .leading, spacing: 2) {
                Text("Rest Complete")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.text)

                Text("Ready for your next set")
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
            }

            Spacer()

            // Dismiss button
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 28, height: 28)
                    .background(Theme.surface2, in: Circle())
                    .overlay(Circle().stroke(Theme.border, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Theme.accent.opacity(0.08)
        )
        .overlay(
            Rectangle()
                .fill(Theme.accent.opacity(0.3))
                .frame(height: 2),
            alignment: .bottom
        )
    }
}

// MARK: - Adjust Button

private struct AdjustButton: View {
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.15), in: Circle())
                .overlay(Circle().stroke(tint.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Compact Timer Display for LiveWorkoutGrabTab

/// Compact inline timer display for grab tab
struct RestTimerCompact: View {
    @ObservedObject var manager = RestTimerManager.shared

    private var timeString: String {
        let minutes = manager.remainingSeconds.safeInt / 60
        let seconds = manager.remainingSeconds.safeInt % 60
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
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Theme.accent.opacity(0.95))
                        .contentTransition(.numericText())
                }
            } else if manager.isCompleted {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)

                    Text("Ready")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Running Timer") {
    VStack(spacing: 0) {
        RunningTimerBanner(
            exerciseName: "Bench Press",
            remainingSeconds: 125,
            originalDuration: 180,
            hasBeenAdjusted: true,
            isCustomTimer: false,
            onSkip: {},
            onStop: {},
            onAdjust: { _ in },
            onSaveAsDefault: {}
        )
        Spacer()
    }
    .background(Color.black)
}

#Preview("Completed Timer") {
    VStack(spacing: 0) {
        CompletedTimerBanner(
            exerciseName: "Bench Press",
            onDismiss: {}
        )
        Spacer()
    }
    .background(Color.black)
}

// MARK: - Global In-App Toast for Completion

/// Shows a prominent toast banner when rest timer completes (while app is active)
struct RestTimerCompletionToast: View {
    @ObservedObject var manager = RestTimerManager.shared
    @State private var showToast = false
    @State private var currentExerciseName: String?
    @State private var currentExerciseID: String?

    /// Called when user taps the toast to navigate to the exercise
    var onTap: ((String) -> Void)?

    var body: some View {
        VStack {
            if showToast, let exerciseName = currentExerciseName {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .symbolEffect(.bounce, options: .nonRepeating)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rest Complete!")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Theme.text)

                        Text("Ready for \(exerciseName)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondary)
                    }

                    Spacer()

                    Button(action: { withAnimation(.spring(response: 0.3)) { showToast = false } }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Theme.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    ChamferedRectangle(.large)
                        .fill(Theme.surface)
                        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                )
                .overlay(
                    ChamferedRectangle(.large)
                        .stroke(Theme.accent.opacity(0.3), lineWidth: 2)
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .contentShape(Rectangle())
                .onTapGesture {
                    // Navigate to exercise session when toast is tapped
                    if let exerciseID = currentExerciseID {
                        onTap?(exerciseID)
                        withAnimation(.spring(response: 0.3)) {
                            showToast = false
                        }
                    }
                }
            }

            Spacer()
        }
        .onChange(of: manager.state) { _, newState in
            if case .completed(let exerciseID, let exerciseName) = newState {
                // Timer just completed, show toast
                currentExerciseName = exerciseName
                currentExerciseID = exerciseID
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    showToast = true
                }

                // Auto-dismiss after 4 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    withAnimation(.spring(response: 0.3)) {
                        showToast = false
                    }
                }
            }
        }
    }
}

// MARK: - Helper Extension
// Color(hex:) is now available from DS.swift, no need to redefine
