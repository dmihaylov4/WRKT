import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Brand Colors

private extension Color {
    static let brandAccent = Color(red: 0.8, green: 1.0, blue: 0.0) // #CCFF00
    static let widgetBackground = Color(red: 0.03, green: 0.03, blue: 0.03) // #080808
    static let widgetSurface = Color(red: 0.10, green: 0.10, blue: 0.10)
}

// MARK: - Main Widget

struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerAttributes.self) { context in
            RestTimerLockScreenView(context: context)
                .activityBackgroundTint(Color.widgetBackground)
                .activitySystemActionForegroundColor(Color.brandAccent)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        Image("LaunchLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(context.attributes.exerciseName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            if context.state.isPaused {
                                Text("Paused")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isPaused {
                        Text(timeString(context.state.remainingSeconds))
                            .font(.system(.title2, design: .rounded).monospacedDigit().weight(.bold))
                            .foregroundStyle(Color.brandAccent)
                    } else {
                        Text(timerInterval: Date.now...context.state.endDate, countsDown: true)
                            .font(.system(.title2, design: .rounded).monospacedDigit().weight(.bold))
                            .foregroundStyle(Color.brandAccent)
                            .multilineTextAlignment(.trailing)
                    }
                }

                DynamicIslandExpandedRegion(.center) {
                    if context.state.isPaused {
                        ProgressView(value: context.state.progress)
                            .tint(Color.brandAccent.opacity(0.5))
                    } else {
                        ProgressView(
                            timerInterval: context.attributes.startTime...context.state.endDate,
                            countsDown: false
                        )
                        .tint(Color.brandAccent)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.endDate <= Date() && !context.state.isPaused {
                        Button(intent: StartNextSetIntent()) {
                            Label("Log Next Set", systemImage: "checkmark.circle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.black)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.brandAccent)
                        .padding(.top, 4)
                    } else {
                        HStack(spacing: 10) {
                            Button(intent: AdjustRestTimerIntent(seconds: -15)) {
                                Text("-15s")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .tint(.white.opacity(0.4))

                            Button(intent: AdjustRestTimerIntent(seconds: 15)) {
                                Text("+15s")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .tint(.white.opacity(0.4))

                            Spacer()

                            Button(intent: SkipRestTimerIntent()) {
                                Label("Skip", systemImage: "forward.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.black)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.brandAccent)
                        }
                        .padding(.top, 4)
                    }
                }

            } compactLeading: {
                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)

            } compactTrailing: {
                if context.state.isPaused {
                    Text(timeString(context.state.remainingSeconds))
                        .font(.system(.caption, design: .rounded).monospacedDigit().weight(.medium))
                        .foregroundStyle(.white.opacity(0.6))
                } else if context.state.endDate <= Date() {
                    Text("Ready")
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(Color.brandAccent)
                } else {
                    Text(timerInterval: Date.now...context.state.endDate, countsDown: true)
                        .font(.system(.caption, design: .rounded).monospacedDigit().weight(.medium))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.trailing)
                }

            } minimal: {
                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
            }
            .keylineTint(Color.brandAccent)
        }
    }
}

// MARK: - Lock Screen View

struct RestTimerLockScreenView: View {
    let context: ActivityViewContext<RestTimerAttributes>

    private var isReady: Bool {
        context.state.endDate <= Date() && !context.state.isPaused
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)

                Text(context.attributes.exerciseName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                if context.state.isPaused {
                    Text("Paused")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }

            if isReady {
                // Ready state
                Button(intent: StartNextSetIntent()) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Log Next Set")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundColor(.black)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.brandAccent)

            } else {
                // Timer
                if context.state.isPaused {
                    Text(timeString(context.state.remainingSeconds))
                        .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.brandAccent.opacity(0.6))
                } else {
                    Text(timerInterval: Date.now...context.state.endDate, countsDown: true)
                        .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.brandAccent)
                        .contentTransition(.numericText(countsDown: true))
                }

                // Progress bar
                if context.state.isPaused {
                    ProgressView(value: context.state.progress)
                        .tint(Color.brandAccent.opacity(0.4))
                } else {
                    ProgressView(
                        timerInterval: context.attributes.startTime...context.state.endDate,
                        countsDown: false,
                        label: { EmptyView() },
                        currentValueLabel: { EmptyView() }
                    )
                    .tint(Color.brandAccent)
                }

                // Controls
                HStack(spacing: 8) {
                    Button(intent: AdjustRestTimerIntent(seconds: -15)) {
                        Image(systemName: "minus")
                            .font(.system(size: 15, weight: .bold))
                            .frame(width: 40, height: 36)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white.opacity(0.3))

                    Button(intent: AdjustRestTimerIntent(seconds: 15)) {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .bold))
                            .frame(width: 40, height: 36)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white.opacity(0.3))

                    Spacer()

                    Button(intent: SkipRestTimerIntent()) {
                        HStack(spacing: 6) {
                            Text("Skip")
                                .fontWeight(.semibold)
                            Image(systemName: "forward.fill")
                                .font(.caption)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .foregroundColor(.black)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.brandAccent)
                }
            }
        }
        .padding(16)
    }
}

// MARK: - Helper

private func timeString(_ seconds: Int) -> String {
    let s = max(0, seconds)
    let m = s / 60
    let sec = s % 60
    return String(format: "%d:%02d", m, sec)
}

// MARK: - Previews

#Preview("Lock Screen", as: .content, using: RestTimerAttributes(
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
