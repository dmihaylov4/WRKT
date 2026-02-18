//
//  WatchWorkoutView.swift
//  WRKT Watch
//
//  Main workout view for Apple Watch
//  Optimized for performance and battery efficiency
//

import SwiftUI
import WatchConnectivity

struct WatchWorkoutView: View {
    @StateObject private var connectivity = WatchConnectivityManager.shared
    @State private var selectedIndex: Int = 0
    @State private var isRefreshing = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            // Rest timer takes over the entire screen when active
            if let restTimer = connectivity.workoutState.restTimer, restTimer.remainingSeconds > 0 {
                RestTimerWatchView(
                    timerInfo: restTimer,
                    onSkip: { connectivity.send(type: .skipRestTimer) },
                    onPause: { connectivity.send(type: .pauseRestTimer) },
                    onResume: { connectivity.send(type: .resumeRestTimer) }
                )
                .transition(.opacity.combined(with: .scale(scale: 1.1)))
            } else if connectivity.workoutState.hasActiveWorkout {
                workoutContent
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                emptyState
                    .transition(.opacity)
            }

            // Connection error banner
            if let error = connectivity.connectionError {
                errorBanner(message: error)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: connectivity.workoutState.hasActiveWorkout)
        .animation(.easeInOut(duration: 0.3), value: connectivity.workoutState.restTimer?.remainingSeconds)
        .animation(.easeInOut(duration: 0.2), value: connectivity.connectionError)
        .onAppear {
            requestStateIfNeeded()
            syncSelectedIndex()
        }
        .onChange(of: connectivity.workoutState.activeExerciseIndex) { newIndex in
            if let newIndex = newIndex, newIndex != selectedIndex {
                withAnimation {
                    selectedIndex = newIndex
                }
            }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                requestStateIfNeeded()
            }
        }
    }

    // MARK: - Content

    private var workoutContent: some View {
        TabView(selection: $selectedIndex) {
            ForEach(Array(connectivity.workoutState.exercises.enumerated()), id: \.element.id) { index, exercise in
                ExerciseView(exercise: exercise, index: index)
                    .tag(index)
            }
        }
        .tabViewStyle(.verticalPage)
        .ignoresSafeArea()
        .onChange(of: selectedIndex) { newIndex in
            connectivity.navigate(to: newIndex)
        }
    }

    private var emptyState: some View {
        VStack {
            Spacer()

            // Single centered button
            Button {
                openPhoneApp()
            } label: {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "#FFB86F"))
                            .frame(width: 80, height: 80)

                        Image(systemName: "bolt.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.white)
                    }

                    Text("Open on iPhone")
                        .font(.caption)
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorBanner(message: String) -> some View {
        VStack {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                Text(message)
                    .font(.caption2)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color(hex: "#FFB86F").opacity(0.9))
            )
            .padding(.top, 4)

            Spacer()
        }
    }

    // MARK: - Helpers

    private func syncSelectedIndex() {
        if let activeIndex = connectivity.workoutState.activeExerciseIndex {
            selectedIndex = activeIndex
        }
    }

    private func requestStateIfNeeded() {
        // Always request on appear to ensure we have latest state
        connectivity.requestState()
    }

    private func refreshState() {
        isRefreshing = true
        connectivity.requestState()

        // Reset refreshing state after delay
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            isRefreshing = false
        }
    }

    private func openPhoneApp() {
        // Send a message to wake up and open the iPhone app
        // Using requestState will activate the app on iPhone
        connectivity.requestState()

        // Also try to trigger app launch through WatchConnectivity
        if WCSession.isSupported() && WCSession.default.isReachable {
            WCSession.default.sendMessage(
                ["action": "openApp"],
                replyHandler: nil,
                errorHandler: { error in
                }
            )
        }
    }
}
