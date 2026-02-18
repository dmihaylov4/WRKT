//  DayDetailView.swift
//  WRKT
//
//  Detailed view of a specific day's activities including workouts and runs
//

import SwiftUI
import SwiftData

// MARK: - Day Detail
struct DayDetail: View {
    @EnvironmentObject var store: WorkoutStoreV2
    @EnvironmentObject var repo: ExerciseRepository
    @Environment(\.modelContext) private var context
    let date: Date
    @Binding var selectedAction: DayActionCard.DayAction?

    // State to track planned workout (refreshed when notification fires)
    @State private var plannedWorkout: PlannedWorkout? = nil

    private var workouts: [CompletedWorkout] { store.workouts(on: date) }
    private var allRuns: [Run] { store.runs(on: date) }

    // Get matched HealthKit UUIDs from app workouts (to avoid showing duplicates)
    private var matchedHealthKitUUIDs: Set<UUID> {
        Set(workouts.compactMap { $0.matchedHealthKitUUID })
    }

    // Separate HealthKit strength workouts from cardio
    // Exclude strength workouts that are already matched to app workouts or were discarded
    private var healthKitStrengthWorkouts: [Run] {
        allRuns.filter { run in
            // Must be a strength workout
            guard run.countsAsStrengthDay else { return false }
            // Must have a HealthKit UUID
            guard let uuid = run.healthKitUUID else { return false }
            // Must NOT be matched to an app workout
            guard !matchedHealthKitUUIDs.contains(uuid) else { return false }
            // Must NOT be in the ignored list (from discarded workouts)
            guard !store.ignoredHealthKitUUIDs.contains(uuid) else { return false }
            return true
        }
    }
    private var cardioRuns: [Run] {
        allRuns.filter { !$0.countsAsStrengthDay }
    }

    // Fetch planned workout for this day
    private func loadPlannedWorkout() {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let predicate = #Predicate<PlannedWorkout> { $0.scheduledDate == startOfDay }
        plannedWorkout = try? context.fetch(FetchDescriptor(predicate: predicate)).first
    }

    // Aggregates (workouts only)
    private var workoutCount: Int { workouts.count }
    private var exerciseCount: Int {
        workouts.reduce(0) { $0 + $1.entries.count }
    }
    private var setCount: Int {
        workouts.reduce(0) { sum, w in sum + w.entries.reduce(0) { $0 + $1.sets.count } }
    }
    private var repCount: Int {
        workouts.reduce(0) { sum, w in
            sum + w.entries.reduce(0) { $0 + $1.sets.reduce(0) { $0 + max(0, $1.reps) } }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Daily Summary — workouts only
            DailySummaryCard(date: date, workoutCount: workoutCount, exerciseCount: exerciseCount, setCount: setCount, repCount: repCount)

            // Day Action Card - context-aware actions
            // Only show if: (1) no planned workout, (2) it's today, or (3) it's a past date
            // For future dates with planned workouts, we show PlannedWorkoutCard instead
            let shouldShowDayActionCard = plannedWorkout == nil ||
                                         Calendar.current.isDateInToday(date) ||
                                         date.dayContext == .past

            if shouldShowDayActionCard {
                DayActionCard(
                    date: date,
                    plannedWorkout: plannedWorkout,
                    hasCompletedWorkouts: !workouts.isEmpty,
                    selectedAction: $selectedAction
                )
            }

            // Planned workout section (if exists and not completed)
            // For today, this is integrated into DayActionCard, so only show for non-today dates
            if let planned = plannedWorkout,
               planned.workoutStatus != .completed,
               !Calendar.current.isDateInToday(date) {
                PlannedWorkoutCard(
                    planned: planned,
                    onEdit: {
                        selectedAction = .editPlannedWorkout(planned)
                    }
                )
            }

            if workouts.isEmpty && allRuns.isEmpty && plannedWorkout == nil {
                ContentUnavailableView("No activity", systemImage: "calendar")
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .background(DS.Theme.cardTop, in: ChamferedRectangle(.large))
                    .overlay(ChamferedRectangle(.large).stroke(DS.Semantic.border, lineWidth: 1))
            } else {
                // Unified Strength Workouts Section
                if !workouts.isEmpty || !healthKitStrengthWorkouts.isEmpty {
                    let totalStrengthWorkouts = workouts.count + healthKitStrengthWorkouts.count
                    VStack(spacing: 0) {
                        SectionHeader(title: "Workouts", count: totalStrengthWorkouts)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        Rectangle().fill(DS.Semantic.border).frame(height: 1)

                        // App workouts
                        ForEach(workouts, id: \.id) { w in
                            WorkoutRow(workout: w)
                            if w.id != workouts.last?.id || !healthKitStrengthWorkouts.isEmpty {
                                Rectangle().fill(DS.Semantic.border.opacity(0.6)).frame(height: 1)
                            }
                        }

                        // HealthKit strength workouts
                        ForEach(healthKitStrengthWorkouts) { workout in
                            HealthKitWorkoutRow(workout: workout)
                            if workout.id != healthKitStrengthWorkouts.last?.id {
                                Rectangle().fill(DS.Semantic.border.opacity(0.6)).frame(height: 1)
                            }
                        }
                    }
                    .background(DS.Theme.cardTop, in: ChamferedRectangle(.large))
                    .overlay(ChamferedRectangle(.large).stroke(DS.Semantic.border, lineWidth: 1))
                }

                // Cardio Runs (kept minimal)
                if !cardioRuns.isEmpty {
                    VStack(spacing: 0) {
                        SectionHeader(title: "Cardio", count: cardioRuns.count)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        Rectangle().fill(DS.Semantic.border).frame(height: 1)

                        ForEach(cardioRuns) { r in
                            HStack {
                                Text(timeOnly(r.date))
                                    .foregroundStyle(DS.Semantic.textPrimary)
                                Spacer()
                                Text(String(format: "%.2f km", max(0, r.distanceKm)))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(DS.Semantic.textPrimary)
                                Text("•")
                                    .foregroundStyle(DS.Semantic.textSecondary)
                                Text(hms(max(0, r.durationSec)))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(DS.Semantic.textPrimary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)

                            if r.id != cardioRuns.last?.id {
                                Rectangle().fill(DS.Semantic.border.opacity(0.6)).frame(height: 1)
                            }
                        }
                    }
                    .background(DS.Theme.cardTop, in: ChamferedRectangle(.large))
                    .overlay(ChamferedRectangle(.large).stroke(DS.Semantic.border, lineWidth: 1))
                }
            }
        }
        .onAppear {
            loadPlannedWorkout()
        }
        .onChange(of: date) { _, _ in
            loadPlannedWorkout()
        }
        .onReceive(NotificationCenter.default.publisher(for: .plannedWorkoutsChanged)) { _ in
            loadPlannedWorkout()
        }
    }
}

// MARK: - Daily Summary Card
struct DailySummaryCard: View {
    let date: Date
    let workoutCount: Int
    let exerciseCount: Int
    let setCount: Int
    let repCount: Int

    @State private var isExpanded = false

    struct Tile: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let value: String
    }

    private var tiles: [Tile] {
        [
            .init(title: "Workouts",  value: "\(workoutCount)"),
            .init(title: "Exercises", value: "\(exerciseCount)"),
            .init(title: "Sets",      value: "\(setCount)"),
            .init(title: "Reps",      value: "\(repCount)")
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Date header - no container, just text
            Button {
                if workoutCount > 0 {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                }
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text(date.formatted(.dateTime.weekday(.wide).day().month()))
                        .font(.headline).foregroundStyle(DS.Semantic.textPrimary)
                    Spacer()
                    if workoutCount > 0 {
                        Text("Daily summary")
                            .font(.caption).foregroundStyle(DS.Semantic.textSecondary)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }
                }
            }
            .buttonStyle(.plain)

            // Expandable summary grid with its own container
            if isExpanded {
                SummaryGrid(tiles: tiles)
                    .frame(height: 108)
                    .background(DS.Theme.cardTop, in: ChamferedRectangle(.medium))
                    .overlay(ChamferedRectangle(.medium).stroke(DS.Semantic.border, lineWidth: 1))
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
    }
}

// MARK: - Summary Grid
private struct SummaryGrid: View {
    let tiles: [DailySummaryCard.Tile] // expects 4

    var body: some View {
        ZStack {
            VStack(spacing: 0) { Spacer(); HLine(); Spacer() }
            HStack(spacing: 0) { Spacer(); VLine(); Spacer() }

            VStack(spacing: 0) {
                HStack(spacing: 0) { cell(tiles[safe: 0]); VLine(); cell(tiles[safe: 1]) }
                HLine()
                HStack(spacing: 0) { cell(tiles[safe: 2]); VLine(); cell(tiles[safe: 3]) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .background(Color.clear)
    }

    private func cell(_ t: DailySummaryCard.Tile?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t?.title ?? "—")
                .font(.caption2).foregroundStyle(DS.Semantic.textSecondary)
            Text(t?.value ?? "—")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DS.Semantic.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.clear)
    }

    private struct VLine: View { var body: some View { Rectangle().fill(DS.Semantic.border).frame(width: 1) } }
    private struct HLine: View { var body: some View { Rectangle().fill(DS.Semantic.border).frame(height: 1) } }
}

// MARK: - Section Header
struct SectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack {
            Text(title).font(.headline).foregroundStyle(DS.Semantic.textPrimary)
            Spacer()
            Text("\(count)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(DS.Theme.accent, in: Capsule())
        }
        .padding(.top, 2)
        .padding(.bottom, 2)
    }
}

// MARK: - Workout Row
struct WorkoutRow: View {
    @EnvironmentObject var store: WorkoutStoreV2
    let workout: CompletedWorkout
    @State private var selectedExercise: Exercise?
    @EnvironmentObject var repo: ExerciseRepository

    private var hasHealthData: Bool {
        workout.matchedHealthKitUUID != nil
    }

    // Display custom name if set, otherwise muscle group classification
    private var workoutTitle: String {
        // Use custom name if set, otherwise auto-classify
        if let customName = workout.workoutName, !customName.isEmpty {
            return customName
        }
        return MuscleGroupClassifier.classify(workout)
    }

    // Show only the workout completion time with "Ended:" prefix
    private var workoutTime: String {
        "Ended: " + workout.date.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        NavigationLink {
            WorkoutDetailView(workout: workout)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(workoutTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.Semantic.textPrimary)

                    Text(workoutTime)
                        .font(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }

                Spacer()

                // Show Apple Health badge if matched
                if hasHealthData {
                    Image(systemName: "heart.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.pink)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .opacity(0.6)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - HealthKit Workout Row

struct HealthKitWorkoutRow: View {
    let workout: Run

    // Use classifier to generate consistent workout title
    private var workoutTitle: String {
        MuscleGroupClassifier.classifyHealthKitStrength(workout)
    }

    // Show "Ended: HH:MM" format for consistency with app workouts
    private var workoutTime: String {
        "Ended: " + workout.date.formatted(date: .omitted, time: .shortened)
    }

    // Determine if this is a strength workout or cardio
    private var isStrengthWorkout: Bool {
        workout.countsAsStrengthDay
    }

    var body: some View {
        NavigationLink {
            // Route to appropriate detail view based on workout type
            if isStrengthWorkout {
                HealthKitStrengthDetailView(run: workout)
            } else {
                CardioDetailView(run: workout)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(workoutTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.Semantic.textPrimary)

                    Text(workoutTime)
                        .font(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }

                Spacer()

                // Show Apple Health badge to indicate source
                Image(systemName: "heart.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.pink)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .opacity(0.6)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
