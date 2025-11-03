//
//  AdaptiveSetRow.swift
//  WRKT
//
//  Adaptive set row that switches UI based on exercise tracking mode
//  - Weighted: Shows reps + weight (strength training)
//  - Timed: Shows duration timer (planks, holds)
//  - Bodyweight: Shows reps only (pull-ups, push-ups)
//

import SwiftUI

// MARK: - Adaptive Set Row

struct AdaptiveSetRow: View {
    let index: Int
    @Binding var set: SetInput
    let unit: WeightUnit
    let exercise: Exercise
    let isActive: Bool
    let isGhost: Bool
    let hasActiveTimer: Bool
    let onDuplicate: () -> Void
    let onActivate: () -> Void
    let onLogSet: () -> Void
    let onTimerStart: () -> Void  // New callback for timed exercises

    var body: some View {
        Group {
            // Determine tracking mode from exercise or fallback to set's tracking mode
            switch determineTrackingMode() {
            case .timed:
                TimedSetRow(
                    index: index,
                    set: $set,
                    exercise: exercise,
                    isActive: isActive,
                    isGhost: isGhost,
                    hasActiveTimer: hasActiveTimer,
                    onActivate: onActivate,
                    onLogSet: onLogSet,
                    onTimerStart: onTimerStart
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))

            case .bodyweight:
                BodyweightSetRow(
                    index: index,
                    set: $set,
                    exercise: exercise,
                    isActive: isActive,
                    isGhost: isGhost,
                    hasActiveTimer: hasActiveTimer,
                    onActivate: onActivate,
                    onLogSet: onLogSet
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))

            case .weighted, .distance:
                // Use the existing SetRowUnified for weighted exercises
                SetRowUnified(
                    index: index,
                    set: $set,
                    unit: unit,
                    exercise: exercise,
                    isActive: isActive,
                    isGhost: isGhost,
                    hasActiveTimer: hasActiveTimer,
                    onDuplicate: onDuplicate,
                    onActivate: onActivate,
                    onLogSet: onLogSet
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: determineTrackingMode())
        .onAppear {
            // Sync set's tracking mode with exercise on appear
            syncTrackingMode()
        }
    }

    // MARK: - Helpers

    /// Determine the tracking mode from exercise definition
    private func determineTrackingMode() -> TrackingMode {
        // First check exercise's tracking mode
        if exercise.isTimedExercise {
            return .timed
        } else if exercise.isBodyweightExercise {
            return .bodyweight
        } else if exercise.isWeightedExercise {
            return .weighted
        }

        // Fallback to set's tracking mode
        return set.trackingMode
    }

    /// Sync set's tracking mode with exercise
    private func syncTrackingMode() {
        let mode = determineTrackingMode()
        if set.trackingMode != mode {
            set.trackingMode = mode

            // Initialize defaults based on mode
            switch mode {
            case .timed:
                if set.durationSeconds == 0, let defaultDuration = exercise.defaultDurationSeconds {
                    set.durationSeconds = defaultDuration
                }
            case .bodyweight:
                set.weight = 0
                if set.reps == 0 {
                    set.reps = 10
                }
            case .weighted:
                // Keep existing values
                break
            case .distance:
                // Future implementation
                break
            }
        }
    }
}
