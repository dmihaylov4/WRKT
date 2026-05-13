//  DayActionCard.swift
//  WRKT
//
//  Context-aware action card for calendar day selection
//

import SwiftUI
import SwiftData

struct DayActionCard: View {
    let date: Date
    let plannedWorkout: PlannedWorkout?
    let hasCompletedWorkouts: Bool

    @Binding var selectedAction: DayAction?
    @State private var isExpanded = false

    enum DayAction: Identifiable, Equatable {
        case startWorkout(Date)
        case startPlannedWorkout(PlannedWorkout)
        case planWorkout(Date)
        case editPlannedWorkout(PlannedWorkout)
        case logWorkout(Date)
        case viewCompletedWorkout(UUID)

        var id: String {
            switch self {
            case .startWorkout: return "start"
            case .startPlannedWorkout: return "start-planned"
            case .planWorkout: return "plan"
            case .editPlannedWorkout: return "edit"
            case .logWorkout: return "log"
            case .viewCompletedWorkout(let id): return "view-completed-\(id)"
            }
        }

        static func == (lhs: DayAction, rhs: DayAction) -> Bool {
            switch (lhs, rhs) {
            case (.startWorkout(let lDate), .startWorkout(let rDate)):
                return lDate == rDate
            case (.startPlannedWorkout(let lWorkout), .startPlannedWorkout(let rWorkout)):
                return lWorkout.id == rWorkout.id
            case (.planWorkout(let lDate), .planWorkout(let rDate)):
                return lDate == rDate
            case (.editPlannedWorkout(let lWorkout), .editPlannedWorkout(let rWorkout)):
                return lWorkout.id == rWorkout.id
            case (.logWorkout(let lDate), .logWorkout(let rDate)):
                return lDate == rDate
            case (.viewCompletedWorkout(let lID), .viewCompletedWorkout(let rID)):
                return lID == rID
            default:
                return false
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Context-aware primary action
            switch date.dayContext {
            case .past:
                pastDayAction
            case .today:
                todayAction
            case .future:
                futureDayAction
            }
        }
        .background(DS.Theme.cardTop, in: ChamferedRectangle(.large))
        .overlay(ChamferedRectangle(.large).stroke(DS.Semantic.border, lineWidth: 1))
    }

    // MARK: - Past Day Action

    private var pastDayAction: some View {
        Button {
            selectedAction = .logWorkout(date)
            Haptics.light()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .dsFont(.title2)
                    .foregroundStyle(DS.Theme.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Log Workout")
                        .dsFont(.headline)
                        .foregroundStyle(DS.Semantic.textPrimary)

                    Text("Add a retrospective workout for this day")
                        .dsFont(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .dsFont(.caption, weight: .semibold)
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .opacity(0.6)
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Today Action

    private var todayAction: some View {
        Group {
            if let planned = plannedWorkout {
                if planned.workoutStatus == .completed || planned.workoutStatus == .partial {
                    // Planned workout already done - show completion state
                    completedPlanCard(planned)
                } else {
                    // Has planned workout for today - show expandable plan card
                    pendingPlanCard(planned)
                }
            } else {
                // No planned workout - show quick start
                Button {
                    selectedAction = .startWorkout(date)
                    Haptics.medium()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .dsFont(.title2)
                            .foregroundStyle(.black)
                            .frame(width: 40, height: 40)
                            .background(DS.Theme.accent, in: Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Start Workout")
                                .dsFont(.headline)
                                .foregroundStyle(DS.Semantic.textPrimary)

                            Text("Begin training now")
                                .dsFont(.caption)
                                .foregroundStyle(DS.Semantic.textSecondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .dsFont(.caption, weight: .semibold)
                            .foregroundStyle(DS.Semantic.textSecondary)
                            .opacity(0.6)
                    }
                    .padding(16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Today Plan Sub-views

    private func completedPlanCard(_ planned: PlannedWorkout) -> some View {
        Button {
            if let workoutID = planned.completedWorkoutID {
                selectedAction = .viewCompletedWorkout(workoutID)
                Haptics.light()
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(DS.Semantic.brand.opacity(0.15))
                        .frame(width: 40, height: 40)

                    Image(systemName: "checkmark")
                        .dsFont(.subheadline, weight: .bold)
                        .foregroundStyle(DS.Semantic.brand)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Plan Completed")
                        .dsFont(.headline)
                        .foregroundStyle(DS.Semantic.textPrimary)

                    Text("\(planned.exercises.count) exercises • \(planned.splitDayName)")
                        .dsFont(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .dsFont(.caption, weight: .semibold)
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .opacity(0.6)
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func pendingPlanCard(_ planned: PlannedWorkout) -> some View {
        VStack(spacing: 0) {
            // Plan summary (tappable to expand/collapse)
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "calendar.badge.checkmark")
                        .dsFont(.title2)
                        .foregroundStyle(DS.Theme.accent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Today's Plan")
                            .dsFont(.headline)
                            .foregroundStyle(DS.Semantic.textPrimary)

                        Text("\(planned.exercises.count) exercises • \(planned.splitDayName)")
                            .dsFont(.caption)
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .dsFont(.caption, weight: .semibold)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Rectangle().fill(DS.Semantic.border).frame(height: 1)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(planned.exercises.prefix(3)) { exercise in
                        HStack {
                            Text(exercise.exerciseName)
                                .dsFont(.subheadline)
                                .foregroundStyle(DS.Semantic.textPrimary)

                            Spacer()

                            Text("\(exercise.ghostSets.count) × \(exercise.ghostSets.first?.reps ?? 0)")
                                .dsFont(.caption)
                                .foregroundStyle(DS.Semantic.textSecondary)
                        }
                    }

                    if planned.exercises.count > 3 {
                        Text("+\(planned.exercises.count - 3) more exercises")
                            .dsFont(.caption)
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Rectangle().fill(DS.Semantic.border).frame(height: 1)

            HStack(spacing: 12) {
                Button {
                    selectedAction = .editPlannedWorkout(planned)
                    Haptics.light()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil")
                            .dsFont(.subheadline)
                        Text("Edit")
                            .dsFont(.subheadline, weight: .medium)
                    }
                    .foregroundStyle(DS.Semantic.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(DS.Semantic.border, lineWidth: 1))
                }

                Button {
                    selectedAction = .startPlannedWorkout(planned)
                    Haptics.medium()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.circle.fill")
                            .dsFont(.subheadline)
                        Text("Start")
                            .dsFont(.subheadline, weight: .semibold)
                    }
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(DS.Theme.accent, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Future Day Action

    private var futureDayAction: some View {
        Group {
            if let planned = plannedWorkout {
                // Edit existing plan
                Button {
                    selectedAction = .editPlannedWorkout(planned)
                    Haptics.light()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar.badge.checkmark")
                            .dsFont(.title2)
                            .foregroundStyle(DS.Theme.accent)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Edit Planned Workout")
                                .dsFont(.headline)
                                .foregroundStyle(DS.Semantic.textPrimary)

                            Text("\(planned.exercises.count) exercises planned")
                                .dsFont(.caption)
                                .foregroundStyle(DS.Semantic.textSecondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .dsFont(.caption, weight: .semibold)
                            .foregroundStyle(DS.Semantic.textSecondary)
                            .opacity(0.6)
                    }
                    .padding(16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                // Create new plan
                Button {
                    selectedAction = .planWorkout(date)
                    Haptics.light()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar.badge.plus")
                            .dsFont(.title2)
                            .foregroundStyle(DS.Theme.accent)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Plan Workout")
                                .dsFont(.headline)
                                .foregroundStyle(DS.Semantic.textPrimary)

                            Text("Schedule exercises for this day")
                                .dsFont(.caption)
                                .foregroundStyle(DS.Semantic.textSecondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .dsFont(.caption, weight: .semibold)
                            .foregroundStyle(DS.Semantic.textSecondary)
                            .opacity(0.6)
                    }
                    .padding(16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Preview

#Preview("Today") {
    VStack(spacing: 20) {
        DayActionCard(
            date: Date(),
            plannedWorkout: nil,
            hasCompletedWorkouts: false,
            selectedAction: .constant(nil)
        )
        .padding()
    }
    .background(DS.Semantic.surface)
}

#Preview("Future with Plan") {
    VStack(spacing: 20) {
        let futureDate = Calendar.current.date(byAdding: .day, value: 3, to: Date())!
        DayActionCard(
            date: futureDate,
            plannedWorkout: nil,
            hasCompletedWorkouts: false,
            selectedAction: .constant(nil)
        )
        .padding()
    }
    .background(DS.Semantic.surface)
}

#Preview("Past Day") {
    VStack(spacing: 20) {
        let pastDate = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        DayActionCard(
            date: pastDate,
            plannedWorkout: nil,
            hasCompletedWorkouts: false,
            selectedAction: .constant(nil)
        )
        .padding()
    }
    .background(DS.Semantic.surface)
}
