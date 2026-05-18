//
//  WorkoutDetailComponents.swift
//  WRKT
//
//  Timing UI components for workout detail view
//

import SwiftUI


// MARK: - Exercise Timing Card

struct ExerciseTimingCard: View {
    let entry: WorkoutEntry

    var body: some View {
        HStack(spacing: 16) {
            TimingStat(label: "Duration", value: entry.formattedTotalDuration)
            TimingStat(label: "Work Time", value: entry.formattedWorkTime)
            TimingStat(label: "Rest Time", value: entry.formattedRestTime)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(DS.Theme.cardTop, in: ChamferedRectangle(.large))
    }
}

private struct TimingStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .dsFont(.caption2)
                .foregroundStyle(DS.Semantic.textSecondary)
            Text(value)
                .dsFont(.caption, weight: .semibold)
                .foregroundStyle(DS.Semantic.textPrimary)
        }
    }
}

// MARK: - Set Timing Row

struct SetTimingRow: View {
    let set: SetInput
    let setNumber: Int

    var body: some View {
        HStack(spacing: 12) {
            // Set number badge
            Text("\(setNumber)")
                .dsFont(.caption, weight: .bold, monospacedDigits: true)
                .foregroundStyle(.black)
                .frame(width: 24, height: 24)
                .background(set.tag.color, in: Circle())

            // Set details
            VStack(alignment: .leading, spacing: 2) {
                Text(set.displayValue)
                    .dsFont(.subheadline, weight: .medium)
                    .foregroundStyle(DS.Semantic.textPrimary)

                if set.workDuration != nil || set.restAfterSeconds != nil {
                    HStack(spacing: 8) {
                        if set.formattedWorkDuration != "—" {
                            Text("Work: \(set.formattedWorkDuration)")
                                .dsFont(.caption2)
                                .foregroundStyle(DS.Semantic.textSecondary)
                        }
                        if set.formattedRestDuration != "—" {
                            Text("Rest: \(set.formattedRestDuration)")
                                .dsFont(.caption2)
                                .foregroundStyle(DS.Semantic.textSecondary)
                        }
                    }
                }
            }

            Spacer()

            // Tag
            Text(set.tag.short)
                .dsFont(.caption2, weight: .semibold)
                .foregroundStyle(.black)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(set.tag.color)
                .clipShape(ChamferedRectangleAlt(.micro))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(DS.Theme.cardTop, in: ChamferedRectangle(.large))
    }
}

// MARK: - Workout Duration Summary

struct WorkoutDurationSummary: View {
    let workout: CompletedWorkout

    private var totalWorkTime: TimeInterval {
        workout.entries.reduce(0) { $0 + $1.totalWorkTime }
    }

    private var totalRestTime: TimeInterval {
        workout.entries.reduce(0) { $0 + $1.totalRestTime }
    }

    private var workoutDuration: TimeInterval {
        // Use actual timing data if available
        if totalWorkTime > 0 {
            return totalWorkTime + totalRestTime
        }
        // Fallback to HealthKit duration if available
        if let healthKitDuration = workout.matchedHealthKitDuration {
            return TimeInterval(healthKitDuration)
        }
        // Fallback to estimated duration from set timestamps
        if let estimatedDuration = workout.estimatedDuration {
            return estimatedDuration
        }
        // No timing data available
        return 0
    }

    var body: some View {
        HStack(spacing: 12) {
            if totalWorkTime > 0 {
                DurationPill(
                    icon: "timer",
                    label: "Total",
                    value: formatDuration(Int(workoutDuration))
                )

                DurationPill(
                    icon: "bolt.fill",
                    label: "Active",
                    value: formatDuration(Int(totalWorkTime)),
                    accentColor: .orange
                )

                DurationPill(
                    icon: "moon.fill",
                    label: "Rest",
                    value: formatDuration(Int(totalRestTime)),
                    accentColor: .blue
                )
            }
        }
    }
}

private struct DurationPill: View {
    let icon: String
    let label: String
    let value: String
    var accentColor: Color = DS.Theme.accent

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .dsFont(.caption)
                .foregroundStyle(accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .dsFont(.subheadline, weight: .semibold)
                    .foregroundStyle(DS.Semantic.textPrimary)
                Text(label)
                    .dsFont(.caption2)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(DS.Theme.cardTop, in: ChamferedRectangle(.large))
        .overlay(ChamferedRectangle(.large).stroke(DS.Semantic.border, lineWidth: 1))
    }
}

// MARK: - Enhanced Exercises Section

struct ExercisesSectionWithTiming: View {
    let entries: [WorkoutEntry]
    let workout: CompletedWorkout  // Pass the workout to check if it's current
    @EnvironmentObject var repo: ExerciseRepository
    @EnvironmentObject var store: WorkoutStoreV2
    @State private var selectedExercise: Exercise?

    // Check if this workout is editable (only true for the current active workout)
    // Historical/completed workouts viewed from calendar should never be editable
    private var isEditable: Bool {
        // Only allow editing if:
        // 1. There's an active workout
        // 2. The workout we're viewing was just completed (same date & time)
        guard let currentWorkout = store.currentWorkout else { return false }

        // Check if this completed workout matches the current active one
        // by comparing timestamps (within 1 minute) and exercise IDs
        let timeDiff = abs(workout.date.timeIntervalSince(currentWorkout.startedAt))
        if timeDiff > 60 { return false }  // More than 1 minute apart = different workouts

        // Also verify exercise IDs match
        let currentExerciseIDs = Set(currentWorkout.entries.map { $0.exerciseID })
        let workoutExerciseIDs = Set(entries.map { $0.exerciseID })
        return currentExerciseIDs == workoutExerciseIDs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exercises")
                .dsFont(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)

            ForEach(entries) { entry in
                // Make the whole card clickable only if:
                // 1. Exercise exists in repo
                // 2. This workout is editable (current active workout, not historical)
                if let exercise = repo.exercises.first(where: { $0.id == entry.exerciseID }),
                   isEditable {
                    Button {
                        selectedExercise = exercise
                    } label: {
                        ExerciseCardContent(entry: entry, isClickable: true)
                    }
                    .buttonStyle(.plain)
                } else {
                    ExerciseCardContent(entry: entry, isClickable: false)
                }
            }
        }
        .sheet(item: $selectedExercise) { exercise in
            NavigationStack {
                ExerciseSessionView(
                    exercise: exercise,
                    initialEntryID: store.existingEntry(for: exercise.id)?.id
                )
            }
        }
    }
}

// MARK: - Exercise Card Content

private struct ExerciseCardContent: View {
    let entry: WorkoutEntry
    let isClickable: Bool
    @State private var showingStats = false
    @EnvironmentObject var repo: ExerciseRepository

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Exercise name with stats button and chevron
            HStack {
                Text(entry.exerciseName)
                    .dsFont(.subheadline, weight: .semibold)
                    .foregroundStyle(DS.Semantic.textPrimary)

                Spacer()

                // Stats button - prominent display for critical information
                Button {
                    showingStats = true
                } label: {
                    Text("Stats")
                        .dsFont(.subheadline, weight: .semibold)
                        .foregroundStyle(DS.Theme.cardTop)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(DS.Theme.accent)
                        .clipShape(ChamferedRectangleAlt(.micro))
                }
                .buttonStyle(.plain)

                if isClickable {
                    Image(systemName: "chevron.right")
                        .dsFont(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)
                        .padding(.leading, 4)
                }
            }
            .sheet(isPresented: $showingStats) {
                NavigationStack {
                    // Use ExerciseStatsWrapper to properly look up tracking mode
                    ExerciseStatsWrapper(
                        exerciseID: entry.exerciseID,
                        exerciseName: entry.exerciseName
                    )
                    .withDependencies()
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }

            // Exercise stats (clean, no icons)
            ExerciseStatsRow(entry: entry)

            // Timing card (only show if data available)
            if entry.totalDuration > 0 {
                ExerciseTimingCard(entry: entry)
            }

            // Sets with timing
            VStack(spacing: 8) {
                ForEach(Array(entry.sets.enumerated()), id: \.offset) { index, set in
                    SetTimingRow(set: set, setNumber: index + 1)
                }
            }
        }
        .padding(14)
        .background(DS.Theme.cardTop, in: ChamferedRectangle(.large))
        .overlay(ChamferedRectangle(.large).stroke(DS.Semantic.border, lineWidth: 1))
        .contentShape(Rectangle())
    }
}

// MARK: - Exercise Stats Row

struct ExerciseStatsRow: View {
    let entry: WorkoutEntry

    private var totalSets: Int {
        entry.sets.count
    }

    private var totalReps: Int {
        entry.sets.reduce(0) { $0 + $1.reps }
    }

    private var totalVolume: Double {
        entry.sets.reduce(0) { $0 + (Double($1.reps) * $1.weight) }
    }

    var body: some View {
        HStack(spacing: 16) {
            StatItem(label: "Sets", value: "\(totalSets)")
            StatItem(label: "Reps", value: "\(totalReps)")
            if totalVolume > 0 {
                StatItem(label: "Volume", value: String(format: "%.0f kg", totalVolume))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(DS.Theme.cardTop, in: ChamferedRectangle(.large))
    }
}

private struct StatItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .dsFont(.caption2)
                .foregroundStyle(DS.Semantic.textSecondary)
            Text(value)
                .dsFont(.caption, weight: .semibold)
                .foregroundStyle(DS.Semantic.textPrimary)
        }
    }
}

// MARK: - Exercise Stats Wrapper

/// Wrapper view that looks up exercise definition and determines tracking mode
private struct ExerciseStatsWrapper: View {
    let exerciseID: String
    let exerciseName: String

    @EnvironmentObject var repo: ExerciseRepository
    @State private var trackingMode: TrackingMode = .weighted
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading...")
            } else {
                ExerciseStatisticsView(
                    exerciseID: exerciseID,
                    exerciseName: exerciseName,
                    trackingMode: trackingMode
                )
            }
        }
        .task {
            await loadTrackingMode()
        }
    }

    private func loadTrackingMode() async {
        // Try to look up exercise from repository
        if let exercise = repo.exercise(byID: exerciseID) {
            trackingMode = TrackingMode(rawValue: exercise.trackingMode) ?? .weighted
        } else {
            // Try async cache lookup as fallback
            let allExercises = await repo.getAllExercises()
            if let exercise = allExercises.first(where: { $0.id == exerciseID }) {
                trackingMode = TrackingMode(rawValue: exercise.trackingMode) ?? .weighted
            } else {
                // Last resort: default to weighted
                trackingMode = .weighted
            }
        }
        isLoading = false
    }
}

