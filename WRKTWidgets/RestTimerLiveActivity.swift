//
//  RestTimerLiveActivity.swift
//  WRKTWidgets
//
//  Live Activity Widget for Rest Timer
//  Displays on lock screen and Dynamic Island
//

import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Brand Colors
private extension Color {
    static let brandAccent = Color(red: 0.8, green: 1.0, blue: 0.0) // #CCFF00
    static let widgetBackground = Color(red: 0.07, green: 0.07, blue: 0.07) // #121212
}

// MARK: - Main Widget

struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerAttributes.self) { context in
            // MARK: - Lock Screen / Banner / Notification View
            RestTimerLockScreenView(context: context)
                .activityBackgroundTint(Color.widgetBackground.opacity(0.95))
                .activitySystemActionForegroundColor(Color.brandAccent)

        } dynamicIsland: { context in
            DynamicIsland {
                // MARK: - Expanded View (when tapped)
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: "dumbbell.fill")
                            .font(.title3)
                            .foregroundStyle(Color.brandAccent)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.attributes.exerciseName)
                                .font(.headline)
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            if context.state.isPaused {
                                Text("Paused")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            } else if context.state.wasAdjusted {
                                Text("Adjusted")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(timeString(context.state.remainingSeconds))
                            .font(.system(.title2, design: .rounded).monospacedDigit().weight(.bold))
                            .foregroundStyle(.white)

                        Text("remaining")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                DynamicIslandExpandedRegion(.center) {
                    if context.state.remainingSeconds > 0 {
                        VStack(spacing: 4) {
                            // Progress bar
                            ProgressView(value: context.state.progress)
                                .tint(Color.brandAccent)
                                .scaleEffect(y: 0.8)
                        }
                        .padding(.horizontal, 8)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.remainingSeconds <= 0 {
                        // Ready state - show action button
                        Button(intent: StartNextSetIntent()) {
                            HStack(spacing: 4) {
                                Image(systemName: "timer")
                                Text("Log Next Set")
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.black)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.brandAccent)
                        .padding(.top, 4)
                    } else {
                        // Timer running - show controls
                        HStack(spacing: 12) {
                            // Subtract 15 seconds
                            Button(intent: AdjustRestTimerIntent(seconds: -15)) {
                                Label("-15s", systemImage: "minus.circle.fill")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .tint(.orange)

                            // Pause/Resume
                            if context.state.isPaused {
                                Button(intent: ResumeRestTimerIntent()) {
                                    Label("Resume", systemImage: "play.circle.fill")
                                        .font(.caption)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                            } else {
                                Button(intent: PauseRestTimerIntent()) {
                                    Label("Pause", systemImage: "pause.circle.fill")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .tint(.blue)
                            }

                            // Add 15 seconds
                            Button(intent: AdjustRestTimerIntent(seconds: 15)) {
                                Label("+15s", systemImage: "plus.circle.fill")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .tint(.orange)

                            // Skip
                            Button(intent: SkipRestTimerIntent()) {
                                Label("Skip", systemImage: "forward.fill")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                        .padding(.top, 4)
                    }
                }

            } compactLeading: {
                // MARK: - Compact Leading (left side when minimized)
                if context.state.remainingSeconds <= 0 {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.brandAccent)
                } else {
                    Image(systemName: "timer")
                        .foregroundStyle(Color.brandAccent)
                }

            } compactTrailing: {
                // MARK: - Compact Trailing (right side when minimized)
                HStack(spacing: 2) {
                    if context.state.remainingSeconds <= 0 {
                        Text("Ready")
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                            .foregroundStyle(Color.brandAccent)
                    } else {
                        if context.state.isPaused {
                            Image(systemName: "pause.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }

                        Text(compactTimeString(context.state.remainingSeconds))
                            .font(.system(.caption, design: .rounded).monospacedDigit().weight(.medium))
                            .foregroundStyle(.white)
                    }
                }

            } minimal: {
                // MARK: - Minimal (when multiple activities exist)
                if context.state.remainingSeconds <= 0 {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.brandAccent)
                } else {
                    Image(systemName: "timer")
                        .foregroundStyle(Color.brandAccent)
                }
            }
            .keylineTint(Color.brandAccent)
        }
    }
}

// MARK: - Lock Screen View

struct RestTimerLockScreenView: View {
    let context: ActivityViewContext<RestTimerAttributes>

    private var isReady: Bool {
        context.state.remainingSeconds <= 0
    }

    var body: some View {
        VStack(spacing: 10) {
            // Header with exercise name
            HStack {
                Image(systemName: "dumbbell.fill")
                    .font(.body)
                    .foregroundStyle(Color.brandAccent)

                Text(context.attributes.exerciseName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                if context.state.isPaused {
                    Image(systemName: "pause.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if isReady {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.brandAccent)
                }
            }

            if isReady {
                // Ready state - show action buttons
                HStack(spacing: 10) {
                    // Log Next Set button - starts timer for next set
                    Button(intent: StartNextSetIntent()) {
                        HStack(spacing: 6) {
                            Image(systemName: "timer")
                                .font(.body)
                            Text("Log Next Set")
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundColor(.black)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.brandAccent)

                    // Open Workout button - opens app
                    Button(intent: OpenAppIntent()) {
                        Image(systemName: "arrow.right.circle")
                            .font(.title3)
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.brandAccent)
                }
            } else {
                // Timer running state
                HStack(spacing: 10) {
                    Image(systemName: "timer")
                        .font(.title2)
                        .foregroundStyle(Color.brandAccent)

                    Text(timeString(context.state.remainingSeconds))
                        .font(.system(.title, design: .rounded).monospacedDigit().weight(.bold))
                        .foregroundStyle(.white)

                    Spacer()
                }

                // Progress Bar
                ProgressView(value: context.state.progress)
                    .tint(Color.brandAccent)
                    .scaleEffect(y: 1.2)

                // Action Buttons
                HStack(spacing: 10) {
                    // Time adjustment
                    Button(intent: AdjustRestTimerIntent(seconds: -15)) {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)

                    Button(intent: AdjustRestTimerIntent(seconds: 15)) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)

                    Spacer()

                    // Skip button
                    Button(intent: SkipRestTimerIntent()) {
                        HStack(spacing: 6) {
                            Text("Skip")
                                .font(.subheadline.weight(.semibold))
                            Image(systemName: "forward.fill")
                                .font(.caption)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
        }
        .padding(14)
    }
}

// MARK: - Helper Functions

/// Format seconds as MM:SS or HH:MM:SS
private func timeString(_ seconds: Int) -> String {
    let absSeconds = abs(seconds)
    let hours = absSeconds / 3600
    let minutes = (absSeconds % 3600) / 60
    let secs = absSeconds % 60

    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    } else {
        return String(format: "%d:%02d", minutes, secs)
    }
}

/// Compact time format for Dynamic Island
private func compactTimeString(_ seconds: Int) -> String {
    let absSeconds = abs(seconds)
    let minutes = absSeconds / 60
    let secs = absSeconds % 60

    if minutes > 0 {
        return String(format: "%d:%02d", minutes, secs)
    } else {
        return String(format: "%ds", secs)
    }
}

// MARK: - Preview

#Preview("Rest Timer Live Activity", as: .content, using: RestTimerAttributes(
    exerciseName: "Bench Press",
    originalDuration: 180,
    exerciseID: "bench-press-001",
    workoutName: "Push Day A",
    startTime: Date()
)) {
    RestTimerLiveActivity()
} contentStates: {
    RestTimerAttributes.ContentState(
        remainingSeconds: 135,
        endDate: Date().addingTimeInterval(135),
        isPaused: false,
        progress: 0.75,
        wasAdjusted: false,
        lastUpdate: Date()
    )

    RestTimerAttributes.ContentState(
        remainingSeconds: 45,
        endDate: Date().addingTimeInterval(45),
        isPaused: true,
        progress: 0.25,
        wasAdjusted: true,
        lastUpdate: Date()
    )

    RestTimerAttributes.ContentState(
        remainingSeconds: 10,
        endDate: Date().addingTimeInterval(10),
        isPaused: false,
        progress: 0.06,
        wasAdjusted: false,
        lastUpdate: Date()
    )
}

#Preview("Dynamic Island Compact", as: .dynamicIsland(.compact), using: RestTimerAttributes(
    exerciseName: "Squats",
    originalDuration: 120,
    exerciseID: "squats-001",
    startTime: Date()
)) {
    RestTimerLiveActivity()
} contentStates: {
    RestTimerAttributes.ContentState(
        remainingSeconds: 85,
        endDate: Date().addingTimeInterval(85),
        isPaused: false,
        progress: 0.7,
        wasAdjusted: false,
        lastUpdate: Date()
    )
}

#Preview("Dynamic Island Expanded", as: .dynamicIsland(.expanded), using: RestTimerAttributes(
    exerciseName: "Deadlifts",
    originalDuration: 240,
    exerciseID: "deadlifts-001",
    startTime: Date()
)) {
    RestTimerLiveActivity()
} contentStates: {
    RestTimerAttributes.ContentState(
        remainingSeconds: 165,
        endDate: Date().addingTimeInterval(165),
        isPaused: false,
        progress: 0.69,
        wasAdjusted: false,
        lastUpdate: Date()
    )
}
