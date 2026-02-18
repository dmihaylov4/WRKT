//
//  SimpleTimerView.swift
//  WRKT Watch
//
//  Minimal, fast rest timer control for Apple Watch
//  Focus: reliability and performance over features
//

import SwiftUI
import WatchKit
import Combine

struct SimpleTimerView: View {
    @StateObject private var connectivity = WatchConnectivityManager.shared
    @State private var displaySeconds: Int = 0
    @State private var lastHapticSecond: Int? = nil
    private let tickTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // Brand colors
    private let accentGreen = Color(hex: "#CCFF00")

    private var timerInfo: WatchRestTimerInfo? {
        connectivity.workoutState.restTimer
    }

    private var isTimerActive: Bool {
        guard let timer = timerInfo, timer.isActive else { return false }
        return timer.endDate.timeIntervalSinceNow > 0
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isTimerActive, let timerData = timerInfo {
                timerDisplay(timer: timerData)
            } else {
                startButton
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

    // MARK: - Timer Display

    private func timerDisplay(timer: WatchRestTimerInfo) -> some View {
        VStack(spacing: 16) {
            // Large countdown - use local countdown for smooth updates
            Text(timeString(seconds: displaySeconds))
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .foregroundColor(accentGreen)
                .monospacedDigit()

            // Exercise name (if available)
            if let name = timer.exerciseName, !name.isEmpty {
                Text(name)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }

            // Control buttons
            HStack(spacing: 12) {
                // Skip button
                Button {
                    WKInterfaceDevice.current().play(.click)
                    connectivity.send(type: .skipRestTimer)
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title3)
                        .foregroundColor(.black)
                        .frame(width: 44, height: 44)
                        .background(accentGreen)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                // Pause/Resume button
                Button {
                    WKInterfaceDevice.current().play(.click)
                    if timer.isActive {
                        connectivity.send(type: .pauseRestTimer)
                    } else {
                        connectivity.send(type: .resumeRestTimer)
                    }
                } label: {
                    Image(systemName: timer.isActive ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .foregroundColor(.black)
                        .frame(width: 44, height: 44)
                        .background(accentGreen)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Start Button

    private var startButton: some View {
        VStack(spacing: 12) {
            Button {
                WKInterfaceDevice.current().play(.start)
                // Request default timer start (90 seconds)
                connectivity.send(type: .startRestTimer, payload: ["durationSeconds": 90])
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "timer")
                        .font(.system(size: 40))
                        .foregroundColor(accentGreen)

                    Text("Start Rest")
                        .font(.caption)
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)

            Text("No active timer")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.4))
        }
    }

    // MARK: - Helpers

    private func timeString(seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

}
