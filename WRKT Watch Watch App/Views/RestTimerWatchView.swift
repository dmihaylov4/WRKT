//
//  RestTimerWatchView.swift
//  WRKT Watch
//
//  Prominent rest timer view for Apple Watch
//  Takes over the full screen during rest periods
//

import SwiftUI
import Combine

struct RestTimerWatchView: View {
    let timerInfo: WatchRestTimerInfo
    let onSkip: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void

    @State private var displaySeconds: Int = 0

    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private var remainingSeconds: Int {
        // If paused, just show the remaining seconds from timerInfo
        if !timerInfo.isActive {
            return timerInfo.remainingSeconds
        }
        // If active, calculate from end date
        return max(0, Int(timerInfo.endDate.timeIntervalSince(Date())))
    }

    private var progress: Double {
        guard timerInfo.totalSeconds > 0 else { return 0 }
        return 1.0 - (Double(remainingSeconds) / Double(timerInfo.totalSeconds))
    }

    private var progressColor: Color {
        // Use app yellow for all progress states
        return Color(hex: "#FFB86F")
    }

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color.black,
                    progressColor.opacity(0.2)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Timer display
                timerDisplay

                Spacer()

                // Exercise name if available
                if let exerciseName = timerInfo.exerciseName {
                    Text(exerciseName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }

                // Control buttons
                controlButtons
                    .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Circular progress
            GeometryReader { geometry in
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        progressColor.opacity(0.3),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: geometry.size.width * 0.85, height: geometry.size.width * 0.85)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    .animation(.linear(duration: 0.1), value: progress)
            }
        }
        .onReceive(timer) { _ in
            // Only update if timer is active
            if timerInfo.isActive {
                displaySeconds = remainingSeconds

                // Haptic feedback at specific intervals
                if remainingSeconds == 10 || remainingSeconds == 5 || remainingSeconds == 3 {
                    WKInterfaceDevice.current().play(.notification)
                } else if remainingSeconds == 0 {
                    WKInterfaceDevice.current().play(.success)
                }
            }
        }
        .onAppear {
            displaySeconds = remainingSeconds
        }
        .onChange(of: timerInfo.isActive) { isActive in
            // Update display when pause state changes
            displaySeconds = remainingSeconds
        }
        .onChange(of: timerInfo.remainingSeconds) { newValue in
            // Update display when remaining seconds change (from iPhone updates)
            displaySeconds = remainingSeconds
        }
    }

    // MARK: - Components

    private var timerDisplay: some View {
        VStack(spacing: 4) {
            Text("REST")
                .font(.caption2)
                .foregroundColor(.secondary)
                .fontWeight(.semibold)
                .tracking(2)

            Text(formatTime(displaySeconds))
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundColor(progressColor)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.default, value: displaySeconds)
        }
    }

    private var controlButtons: some View {
        VStack(spacing: 8) {
            // Skip button (prominent)
            Button {
                WKInterfaceDevice.current().play(.click)
                onSkip()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "forward.fill")
                        .font(.callout)
                    Text("Skip Rest")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(progressColor)
            .controlSize(.large)

            // Pause/Resume button (secondary)
            if timerInfo.isActive {
                Button {
                    WKInterfaceDevice.current().play(.click)
                    onPause()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "pause.fill")
                            .font(.caption)
                        Text("Pause")
                            .font(.caption)
                    }
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
            } else {
                Button {
                    WKInterfaceDevice.current().play(.click)
                    onResume()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.caption)
                        Text("Resume")
                            .font(.caption)
                    }
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

#Preview {
    RestTimerWatchView(
        timerInfo: WatchRestTimerInfo(
            isActive: true,
            remainingSeconds: 90,
            totalSeconds: 120,
            endDate: Date().addingTimeInterval(90),
            exerciseName: "Bench Press"
        ),
        onSkip: {},
        onPause: {},
        onResume: {}
    )
}
