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
            let now = Date.now
            let countdown = context.state.countdownInterval(at: now)
            return DynamicIsland {
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
                    } else if let countdown {
                        Text(timerInterval: countdown, countsDown: true)
                            .font(.system(.title2, design: .rounded).monospacedDigit().weight(.bold))
                            .foregroundStyle(Color.brandAccent)
                            .multilineTextAlignment(.trailing)
                    } else {
                        Text("Ready")
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .foregroundStyle(Color.brandAccent)
                    }
                }

                DynamicIslandExpandedRegion(.center) {
                    if context.state.isPaused {
                        ProgressView(value: context.state.progress)
                            .tint(Color.brandAccent.opacity(0.5))
                    } else if let countdown {
                        ProgressView(
                            timerInterval: min(context.attributes.startTime, countdown.lowerBound)...countdown.upperBound,
                            countsDown: false
                        )
                        .tint(Color.brandAccent)
                    } else {
                        ProgressView(value: 1)
                            .tint(Color.brandAccent)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    if let message = context.state.errorMessage {
                        Text(message).font(.caption2).foregroundStyle(.white).lineLimit(2)
                    }
                    if countdown == nil && !context.state.isPaused {
                        Button(intent: StartNextSetIntent(timerID: context.attributes.timerID)) {
                            Label("Log Next Set", systemImage: "checkmark.circle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.black)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.brandAccent)
                        .padding(.top, 4)
                    } else {
                        HStack(spacing: 10) {
                            Button(intent: StartNextSetIntent(timerID: context.attributes.timerID)) {
                                Label("Log Set", systemImage: "checkmark")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .tint(Color.brandAccent)

                            Button(intent: AdjustRestTimerIntent(timerID: context.attributes.timerID, seconds: -15)) {
                                Text("-15s")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .tint(.white.opacity(0.4))

                            Button(intent: AdjustRestTimerIntent(timerID: context.attributes.timerID, seconds: 15)) {
                                Text("+15s")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .tint(.white.opacity(0.4))

                            Spacer()

                            Button(intent: SkipRestTimerIntent(timerID: context.attributes.timerID)) {
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
                } else if countdown == nil {
                    Text("Ready")
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(Color.brandAccent)
                } else if let countdown {
                    Text(timerInterval: countdown, countsDown: true)
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

    var body: some View {
        let now = Date.now
        let countdown = context.state.countdownInterval(at: now)
        let isReady = countdown == nil && !context.state.isPaused
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 8) {
                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .layoutPriority(1)

                Text(context.attributes.exerciseName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if context.state.isPaused {
                    Text("Paused")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)

            if isReady {
                Button(intent: StartNextSetIntent(timerID: context.attributes.timerID)) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Log Next Set")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundColor(.black)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.brandAccent)

            } else {
                // Timer
                if context.state.isPaused {
                    Text(timeString(context.state.remainingSeconds))
                        .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.brandAccent.opacity(0.6))
                } else if let countdown {
                    Text(timerInterval: countdown, countsDown: true)
                        .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.brandAccent)
                        .contentTransition(.numericText(countsDown: true))
                }

                // Progress bar
                if context.state.isPaused {
                    ProgressView(value: context.state.progress)
                        .tint(Color.brandAccent.opacity(0.4))
                } else if let countdown {
                    ProgressView(
                        timerInterval: min(context.attributes.startTime, countdown.lowerBound)...countdown.upperBound,
                        countsDown: false,
                        label: { EmptyView() },
                        currentValueLabel: { EmptyView() }
                    )
                    .tint(Color.brandAccent)
                }

                // Controls
                HStack(spacing: 8) {
                    Button(intent: StartNextSetIntent(timerID: context.attributes.timerID)) {
                        Label("Log Set", systemImage: "checkmark")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.brandAccent)

                    Button(intent: AdjustRestTimerIntent(timerID: context.attributes.timerID, seconds: -15)) {
                        Image(systemName: "minus")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 30, height: 28)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white.opacity(0.3))

                    Button(intent: AdjustRestTimerIntent(timerID: context.attributes.timerID, seconds: 15)) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 30, height: 28)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white.opacity(0.3))

                    Spacer()

                    Button(intent: SkipRestTimerIntent(timerID: context.attributes.timerID)) {
                        HStack(spacing: 6) {
                            Text("Skip")
                                .fontWeight(.semibold)
                                .lineLimit(1)
                            Image(systemName: "forward.fill")
                                .font(.caption2)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .foregroundColor(.black)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.brandAccent)
                }
            }
            if let message = context.state.errorMessage {
                Text(message).font(.caption2).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
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
