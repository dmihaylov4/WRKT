//
//  ExerciseView.swift
//  WRKT Watch
//
//  Redesigned for proper layout without overlap
//

import SwiftUI

struct ExerciseView: View {
    let exercise: WatchExerciseInfo
    let index: Int

    @StateObject private var connectivity = WatchConnectivityManager.shared
    @State private var showCompletionAnimation = false

    private var nextSet: (index: Int, set: WatchSetInfo)? {
        exercise.nextIncompleteSet
    }

    private var currentSetNumber: Int {
        (nextSet?.index ?? exercise.sets.count - 1) + 1
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top padding
            Spacer()
                .frame(height: 8)

            // Header - Fixed height
            VStack(spacing: 3) {
                Text("EXERCISE \(index + 1)")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundColor(.gray)
                    .textCase(.uppercase)

                Text(exercise.name)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)

            Spacer()
                .frame(height: 12)

            // Set display - Fixed height
            VStack(spacing: 6) {
                Text("SET \(currentSetNumber)/\(exercise.totalSets)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: "#FFB86F"))

                // Large set details
                if let (_, set) = nextSet {
                    Text(set.displayText)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                } else if let lastSet = exercise.sets.last {
                    Text(lastSet.displayText)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                }

                // Progress dots
                HStack(spacing: 3) {
                    ForEach(0..<exercise.totalSets, id: \.self) { i in
                        Circle()
                            .fill(i < exercise.completedSets ? Color(hex: "#FFB86F") : Color.white.opacity(0.2))
                            .frame(width: 5, height: 5)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)

            // Large flexible spacer to push buttons down
            Spacer()
                .frame(minHeight: 60)

            // Buttons - Fixed at bottom
            VStack(spacing: 10) {
                if let (setIndex, _) = nextSet {
                    Button {
                        completeSet(at: setIndex)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                            Text("Complete")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: "#FFB86F"))

                    Button {
                        startSet(at: setIndex)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                            Text("Start Timer")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white.opacity(0.2))

                } else if exercise.sets.allSatisfy({ $0.isCompleted }) {
                    Button {
                        addAndStartNewSet()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 16))
                            Text("Add Set")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: "#FFB86F"))

                    Text("All sets complete!")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .ignoresSafeArea()
        .overlay {
            if showCompletionAnimation {
                completionCheckmark
            }
        }
    }

    private var completionCheckmark: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(Color(hex: "#FFB86F"))
                    .scaleEffect(showCompletionAnimation ? 1.0 : 0.5)
                    .opacity(showCompletionAnimation ? 1.0 : 0.0)

                Text("Exercise Complete!")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .opacity(showCompletionAnimation ? 1.0 : 0.0)
            }
        }
        .transition(.opacity)
    }

    // MARK: - Actions

    private func startSet(at index: Int) {
        WKInterfaceDevice.current().play(.start)
        connectivity.startSet(
            exerciseID: exercise.id,
            entryID: exercise.entryID,
            setIndex: index
        )
    }

    private func completeSet(at index: Int) {
        WKInterfaceDevice.current().play(.success)

        connectivity.completeSet(
            exerciseID: exercise.id,
            entryID: exercise.entryID,
            setIndex: index
        )

        // Show animation if all sets completed
        if exercise.completedSets + 1 == exercise.totalSets {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                showCompletionAnimation = true
            }

            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                withAnimation {
                    showCompletionAnimation = false
                }
            }
        }
    }

    private func addAndStartNewSet() {
        WKInterfaceDevice.current().play(.start)
        connectivity.addAndStartSet(
            exerciseID: exercise.id,
            entryID: exercise.entryID
        )
    }
}
