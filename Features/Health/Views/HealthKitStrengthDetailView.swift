//
//  HealthKitStrengthDetailView.swift
//  WRKT
//
//  Detail view for HealthKit-synced strength workouts (Apple Watch, etc.)
//  Shows available metrics without exercise-level breakdown
//

import SwiftUI
import Charts

private enum Theme {
    static let bg        = Color.black
    static let surface   = Color(red: 0.07, green: 0.07, blue: 0.07)
    static let surface2  = Color(red: 0.10, green: 0.10, blue: 0.10)
    static let border    = Color.white.opacity(0.10)
    static let text      = Color.white
    static let secondary = Color.white.opacity(0.65)
    static let accent    = DS.Theme.accent
}

struct HealthKitStrengthDetailView: View {
    let run: Run
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: WorkoutStoreV2
    @EnvironmentObject var repo: ExerciseRepository

    @State private var showingEditor = false
    @State private var showDeleteConfirmation = false

    // Check if this workout has already been converted to a detailed workout
    private var existingWorkout: CompletedWorkout? {
        guard let healthKitUUID = run.healthKitUUID else { return nil }
        return store.completedWorkouts.first { $0.matchedHealthKitUUID == healthKitUUID }
    }

    private var workoutTitle: String {
        // If this has been converted to a CompletedWorkout, use its custom name
        if let workout = existingWorkout {
            if let customName = workout.workoutName, !customName.isEmpty {
                return customName
            }
            // Auto-classify from exercises
            return MuscleGroupClassifier.classify(workout)
        }

        // Otherwise use HealthKit data
        if let name = run.workoutName, !name.isEmpty {
            return name
        }
        return run.workoutType ?? "Strength Workout"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Card
                HeaderCard(run: run, workoutTitle: workoutTitle)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                // Key Metrics
                MetricsGrid(run: run)
                    .padding(.horizontal, 16)

                // Source Info or Add Exercises
                if existingWorkout == nil {
                    AddExercisesCard(onTap: {
                        showingEditor = true
                    })
                    .padding(.horizontal, 16)
                } else {
                    SourceInfoCard()
                        .padding(.horizontal, 16)
                }

                // Notes (if any)
                if let notes = run.notes, !notes.isEmpty {
                    NotesCard(notes: notes)
                        .padding(.horizontal, 16)
                }

                Spacer(minLength: 20)
            }
            .padding(.vertical, 16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Workout Details")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Theme.accent)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    if existingWorkout != nil {
                        Button {
                            showingEditor = true
                        } label: {
                            Label("Edit Workout", systemImage: "pencil")
                        }
                    } else {
                        Button {
                            showingEditor = true
                        } label: {
                            Label("Add Exercise Details", systemImage: "plus")
                        }
                    }

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Workout", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            if let workout = existingWorkout {
                // Edit existing workout
                CompletedWorkoutEditor(workout: workout, isNewWorkout: false)
                    .environmentObject(store)
                    .environmentObject(repo)
            } else {
                // Create new workout from HealthKit data
                CompletedWorkoutEditor(workout: createWorkoutFromRun(), isNewWorkout: true)
                    .environmentObject(store)
                    .environmentObject(repo)
            }
        }
        .confirmationDialog("Delete Workout", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Workout", role: .destructive) {
                if let workout = existingWorkout {
                    // Delete the CompletedWorkout (which has exercise details)
                    store.deleteWorkout(workout)
                } else {
                    // Delete just the HealthKit Run record
                    store.removeRun(withId: run.id)
                }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this workout? You can undo this action.")
        }
        // Listen for tab changes
        .onReceive(NotificationCenter.default.publisher(for: .tabDidChange)) { _ in
            dismiss()
        }
        .onReceive(NotificationCenter.default.publisher(for: .calendarTabReselected)) { _ in
            dismiss()
        }
    }

    // Convert Run to CompletedWorkout with HealthKit data
    private func createWorkoutFromRun() -> CompletedWorkout {
        let startTime = run.date.addingTimeInterval(-TimeInterval(run.durationSec))
        var workout = CompletedWorkout(
            date: run.date,
            startedAt: startTime,
            entries: [],
            plannedWorkoutID: nil
        )

        // Attach HealthKit data
        workout.matchedHealthKitUUID = run.healthKitUUID
        workout.matchedHealthKitCalories = run.calories
        workout.matchedHealthKitHeartRate = run.avgHeartRate
        workout.matchedHealthKitDuration = run.durationSec

        return workout
    }
}

// MARK: - Header Card

private struct HeaderCard: View {
    let run: Run
    let workoutTitle: String

    var body: some View {
        VStack(spacing: 16) {
            // Workout Name & Type
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "dumbbell.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.accent)

                    Text(workoutTitle)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.text)
                }

                HStack(spacing: 6) {
                    Image(systemName: "applewatch")
                        .font(.caption)
                    Text("Apple Watch")
                        .font(.caption.weight(.medium))
                    Text("•")
                    Text(run.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                }
                .foregroundStyle(Theme.secondary)
            }

            Divider()
                .background(Theme.border)
                .padding(.vertical, 4)

            // Duration - Hero Display
            VStack(spacing: 6) {
                Text(formatTime(run.durationSec))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accent)
                Text("DURATION")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondary)
                    .tracking(1.5)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Theme.surface, Theme.surface2],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }

    private func formatTime(_ sec: Int) -> String {
        let h = sec / 3600
        let m = (sec % 3600) / 60
        let s = sec % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }
}

// MARK: - Metrics Grid

private struct MetricsGrid: View {
    let run: Run

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workout Summary")
                .font(.headline)
                .foregroundStyle(Theme.text)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                // Calories
                if let calories = run.calories, calories > 0 {
                    MetricCard(
                        icon: "flame.fill",
                        title: "Calories",
                        value: "\(Int(calories))",
                        unit: "kcal",
                        color: .orange
                    )
                }

                // Heart Rate
                if let avgHR = run.avgHeartRate, avgHR > 0 {
                    MetricCard(
                        icon: "heart.fill",
                        title: "Avg Heart Rate",
                        value: "\(Int(avgHR))",
                        unit: "bpm",
                        color: .pink
                    )
                }

                // Start Time
                MetricCard(
                    icon: "clock.fill",
                    title: "Started",
                    value: run.date.formatted(date: .omitted, time: .shortened),
                    unit: nil,
                    color: .blue
                )

                // Workout Type
                if let workoutType = run.workoutType {
                    MetricCard(
                        icon: "figure.strengthtraining.traditional",
                        title: "Type",
                        value: workoutType,
                        unit: nil,
                        color: Theme.accent
                    )
                }
            }
        }
    }
}

private struct MetricCard: View {
    let icon: String
    let title: String
    let value: String
    let unit: String?
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if let unit = unit {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            LinearGradient(
                colors: [color.opacity(0.12), color.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Add Exercises Card

private struct AddExercisesCard: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.accent)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Add Exercise Details")
                            .font(.headline)
                            .foregroundStyle(Theme.text)

                        Text("Tap to add exercises, sets, and weights to this workout")
                            .font(.caption)
                            .foregroundStyle(Theme.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.secondary)
                        .opacity(0.6)
                }

                Divider()
                    .background(Theme.border)

                HStack(spacing: 4) {
                    Image(systemName: "applewatch")
                        .font(.caption2)
                        .foregroundStyle(.pink)

                    Text("HealthKit data will be preserved")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondary)
                }
            }
            .padding(14)
            .background(
                LinearGradient(
                    colors: [Theme.accent.opacity(0.15), Theme.accent.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.accent.opacity(0.4), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Source Info Card

private struct SourceInfoCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)

                Text("Exercise Details Added")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
            }

            Text("This Apple Watch workout now includes detailed exercise and set information.")
                .font(.caption)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 4) {
                Image(systemName: "applewatch")
                    .font(.caption2)
                    .foregroundStyle(.pink)

                Text("HealthKit data preserved")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondary)
            }
            .padding(.top, 4)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

// MARK: - Notes Card

private struct NotesCard: View {
    let notes: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "note.text")
                    .font(.subheadline)
                    .foregroundStyle(Theme.accent)

                Text("Notes")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
            }

            Text(notes)
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}
