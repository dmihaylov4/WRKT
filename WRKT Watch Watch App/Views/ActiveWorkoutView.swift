//
//  ActiveWorkoutView.swift
//  WRKT Watch
//
//  Active workout view shown when HKWorkoutSession is running
//  Matches Apple Watch workout UI style
//

import SwiftUI
import WatchKit
import Combine

struct ActiveWorkoutView: View {
    var isLuminanceReduced: Bool = false

    @StateObject private var connectivity = WatchConnectivityManager.shared

    // Store reference to the observable singleton
    let healthManager = WatchHealthKitManager.shared

    @State private var displaySeconds: Int = 0
    @State private var lastHapticSecond: Int? = nil
    private let tickTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // Brand colors
    private let accentGreen = Color(hex: "#CCFF00")

    private var timerInfo: WatchRestTimerInfo? {
        connectivity.workoutState.restTimer
    }

    private var isRestTimerActive: Bool {
        guard let timer = timerInfo, timer.isActive else { return false }
        return timer.endDate.timeIntervalSinceNow > 0
    }

    private var currentExerciseName: String? {
        connectivity.workoutState.activeExercise?.name
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLuminanceReduced {
                // Always-On Display: simplified dimmed view
                alwaysOnView
            } else {
                VStack(spacing: 0) {
                    // Top: Exercise name
                    exerciseNameHeader
                        .padding(.top, 4)

                    Spacer()

                    // Center: Main display (elapsed time or rest timer)
                    if isRestTimerActive, let timerData = timerInfo {
                        restTimerDisplay(timer: timerData)
                    } else {
                        elapsedTimeDisplay
                    }

                    Spacer()

                    // Bottom: Stats (calories, heart rate)
                    statsRow
                        .padding(.bottom, 8)
                }
                .padding(.horizontal, 8)
            }
        }
        .onReceive(tickTimer) { _ in
            guard let timer = timerInfo, timer.isActive else {
                displaySeconds = 0
                lastHapticSecond = nil
                return
            }
            let remaining = max(0, Int(timer.endDate.timeIntervalSinceNow))
            displaySeconds = remaining

            if remaining != lastHapticSecond {
                if remaining == 10 || remaining == 5 {
                    WKInterfaceDevice.current().play(.notification)
                    lastHapticSecond = remaining
                } else if remaining == 0 {
                    WKInterfaceDevice.current().play(.success)
                    lastHapticSecond = remaining
                }
            }
        }
    }

    // MARK: - Always-On Display

    private var alwaysOnView: some View {
        VStack(spacing: 8) {
            Spacer()

            // Elapsed time — main metric
            Text(formatElapsedTime(healthManager.elapsedTime))
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundColor(accentGreen.opacity(0.6))
                .monospacedDigit()

            // Rest timer if active
            if isRestTimerActive {
                HStack(spacing: 6) {
                    Text("REST")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.3))
                        .tracking(1)
                    Text(timeString(seconds: displaySeconds))
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(accentGreen.opacity(0.4))
                        .monospacedDigit()
                }
            }

            Spacer()

            // Heart rate at bottom
            if healthManager.heartRate > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.red.opacity(0.4))
                    Text("\(Int(healthManager.heartRate))")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Exercise Name Header

    private var exerciseNameHeader: some View {
        Text(currentExerciseName ?? "Strength Training")
            .font(.system(.caption, design: .rounded))
            .fontWeight(.medium)
            .foregroundColor(.white.opacity(0.8))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    // MARK: - Elapsed Time Display

    private var elapsedTimeDisplay: some View {
        VStack(spacing: 4) {
            Text(formatElapsedTime(healthManager.elapsedTime))
                .font(.system(size: 54, weight: .bold, design: .rounded))
                .foregroundColor(accentGreen)
                .monospacedDigit()

            Text("DURATION")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
                .tracking(1)
        }
    }

    // MARK: - Rest Timer Display

    private func restTimerDisplay(timer: WatchRestTimerInfo) -> some View {
        VStack(spacing: 4) {
            Text(timeString(seconds: displaySeconds))
                .font(.system(size: 54, weight: .bold, design: .rounded))
                .foregroundColor(accentGreen)
                .monospacedDigit()

            Text("REST")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
                .tracking(1)

            // Skip button
            Button {
                WKInterfaceDevice.current().play(.click)
                connectivity.send(type: .skipRestTimer)
            } label: {
                Text("Skip")
                    .font(.system(.caption2, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(accentGreen)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 0) {
            // Calories
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Int(healthManager.activeCalories))")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                HStack(spacing: 2) {
                    Text("ACTIVE")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    Text("KCAL")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Heart rate
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    if healthManager.heartRate > 0 {
                        Text("\(Int(healthManager.heartRate))")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                    } else {
                        Text("--")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    Image(systemName: "heart.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.red)
                }
                Text("BPM")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    // MARK: - Helpers

    private func timeString(seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func formatElapsedTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let mins = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        } else {
            return String(format: "%d:%02d", mins, secs)
        }
    }

}

#Preview {
    ActiveWorkoutView()
}
