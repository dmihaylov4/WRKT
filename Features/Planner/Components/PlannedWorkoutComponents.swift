//  PlannedWorkoutComponents.swift
//  WRKT
//
//  Components for planned/scheduled workouts in the calendar
//

import SwiftUI
import SwiftData


// MARK: - Planned Workout Card
struct PlannedWorkoutCard: View {
    @EnvironmentObject var store: WorkoutStoreV2
    @Environment(\.modelContext) private var modelContext
    let planned: PlannedWorkout
    var onEdit: (() -> Void)? = nil
    var hideActions: Bool = false  // Hide action buttons if they're shown elsewhere (e.g., in DayActionCard for today)
    @State private var showDateMismatchAlert = false
    @State private var isExpanded = false
    @State private var showingDeleteConfirmation = false

    // Check if this planned workout has been completed
    private var isCompleted: Bool {
        store.completedWorkouts.contains { $0.plannedWorkoutID == planned.id }
    }

    private var statusColor: Color {
        // Completed workouts always use yellow (brand color)
        if isCompleted {
            return DS.Theme.accent
        }

        switch planned.workoutStatus {
        case .scheduled: return DS.Theme.accent
        case .completed: return DS.Theme.accent
        case .partial: return .yellow
        case .skipped: return .gray
        case .rescheduled: return .orange
        }
    }

    private var statusText: String {
        // If workout is completed (regardless of stored status), show "Completed"
        if isCompleted {
            return "Completed"
        }

        switch planned.workoutStatus {
        case .scheduled: return "Planned"
        case .completed: return "Completed"
        case .partial: return "Partially completed"
        case .skipped: return "Skipped"
        case .rescheduled: return "Rescheduled"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header - Always visible, tappable to expand/collapse
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(planned.splitDayName)
                            .font(.headline)
                            .foregroundStyle(DS.Semantic.textPrimary)

                        HStack(spacing: 4) {
                            Text(statusText)
                                .font(.caption)
                                .foregroundStyle(statusColor)

                            Text("•")
                                .font(.caption2)
                                .foregroundStyle(DS.Semantic.textSecondary)

                            Text("\(planned.exercises.count) exercises")
                                .font(.caption)
                                .foregroundStyle(DS.Semantic.textSecondary)
                        }
                    }

                    Spacer()

                    // Expand/collapse chevron
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DS.Semantic.textSecondary)
                        .padding(.trailing, 4)

                    // Status badge
                    if isCompleted {
                        // Completed: dark badge with yellow text
                        Text(statusText.uppercased())
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(DS.Theme.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.15), in: Capsule())
                            .overlay(Capsule().stroke(DS.Theme.accent.opacity(0.5), lineWidth: 1))
                    } else {
                        // Planned: yellow badge with black text
                        Text(statusText.uppercased())
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(statusColor, in: Capsule())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Rectangle().fill(DS.Semantic.border).frame(height: 1)

                // Exercise preview
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(planned.exercises.prefix(3)) { exercise in
                        HStack {
                            if isCompleted {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(DS.Theme.accent)
                            }

                            Text(exercise.exerciseName)
                                .font(.subheadline)
                                .foregroundStyle(DS.Semantic.textPrimary)

                            Spacer()

                            Text("\(exercise.ghostSets.count) × \(exercise.ghostSets.first?.reps ?? 0)")
                                .font(.caption)
                                .foregroundStyle(DS.Semantic.textSecondary)
                        }
                    }

                    if planned.exercises.count > 3 {
                        HStack {
                            if isCompleted {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(DS.Theme.accent)
                            }

                            Text("+\(planned.exercises.count - 3) more exercises")
                                .font(.caption)
                                .foregroundStyle(DS.Semantic.textSecondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .opacity(isCompleted ? 0.6 : 1.0)
                .transition(.opacity.combined(with: .move(edge: .top)))

                // Action buttons (hidden if actions are shown elsewhere, e.g., in DayActionCard for today)
                if !hideActions && (planned.workoutStatus == .scheduled || isCompleted) {
                    Rectangle().fill(DS.Semantic.border).frame(height: 1)

                    HStack(spacing: 12) {
                        // Edit button (only for scheduled workouts)
                        if !isCompleted, let onEdit = onEdit {
                            Button {
                                onEdit()
                            } label: {
                                HStack {
                                    Image(systemName: "pencil")
                                        .font(.body)
                                    Text("Edit")
                                        .font(.subheadline.weight(.medium))
                                }
                                .foregroundStyle(DS.Semantic.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(DS.Semantic.border, lineWidth: 1))
                            }
                        }

                        // Start/Start Again button
                        Button {
                            // Check if this workout is scheduled for today
                            if !isCompleted && !isScheduledForToday {
                                showDateMismatchAlert = true
                            } else {
                                startPlannedWorkout(planned)
                            }
                        } label: {
                            HStack {
                                if isCompleted {
                                    Image(systemName: "arrow.clockwise.circle.fill")
                                        .font(.body)
                                    Text("Start Again")
                                        .font(.subheadline.weight(.medium))
                                } else {
                                    Image(systemName: "play.circle.fill")
                                        .font(.body)
                                    Text("Start")
                                        .font(.subheadline.weight(.semibold))
                                }
                            }
                            .foregroundStyle(isCompleted ? DS.Semantic.textSecondary : Color.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                isCompleted
                                    ? Color.white.opacity(0.05)
                                    : DS.Theme.accent,
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                            .overlay(
                                isCompleted
                                    ? RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                    : nil
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .background(DS.Theme.cardTop, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isCompleted ? DS.Theme.accent.opacity(0.6) : Color.clear, lineWidth: 2)
        )
        .contextMenu {
            if let onEdit = onEdit {
                Button {
                    onEdit()
                } label: {
                    Label("Edit Workout", systemImage: "pencil")
                }
            }

            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label("Delete Workout", systemImage: "trash")
            }
        }
        .alert("Workout Scheduled for Different Day", isPresented: $showDateMismatchAlert) {
            Button("Start Now (Logs Today)", role: .destructive) {
                startPlannedWorkout(planned)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This workout is scheduled for \(formattedScheduledDate). Starting it will log the workout for today instead.")
        }
        .alert("Delete Workout?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deletePlannedWorkout()
            }
        } message: {
            Text("This will permanently delete this planned workout.")
        }
    }

    private var isScheduledForToday: Bool {
        Calendar.current.isDateInToday(planned.scheduledDate)
    }

    private var formattedScheduledDate: String {
        planned.scheduledDate.formatted(date: .abbreviated, time: .omitted)
    }

    private func startPlannedWorkout(_ planned: PlannedWorkout) {
        store.startPlannedWorkout(planned)
        // Navigate to live workout tab
        NotificationCenter.default.post(name: .openLiveWorkoutTab, object: nil)
    }

    private func deletePlannedWorkout() {
        modelContext.delete(planned)

        do {
            try modelContext.save()
            // Notify calendar to reload planned workouts
            NotificationCenter.default.post(name: .plannedWorkoutsChanged, object: nil)
            // Give SwiftData a moment to process the deletion
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                Haptics.success()
            }
        } catch {
        }
    }
}
