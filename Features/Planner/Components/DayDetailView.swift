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
    @Environment(\.modelContext) private var context
    let date: Date

    private var workouts: [CompletedWorkout] { store.workouts(on: date) }
    private var allRuns: [Run] { store.runs(on: date) }

    // Get matched HealthKit UUIDs from app workouts (to avoid showing duplicates)
    private var matchedHealthKitUUIDs: Set<UUID> {
        Set(workouts.compactMap { $0.matchedHealthKitUUID })
    }

    // Separate HealthKit strength workouts from cardio
    // Exclude strength workouts that are already matched to app workouts
    private var healthKitStrengthWorkouts: [Run] {
        allRuns.filter { run in
            // Must be a strength workout
            guard run.countsAsStrengthDay else { return false }
            // Must have a HealthKit UUID
            guard let uuid = run.healthKitUUID else { return false }
            // Must NOT be matched to an app workout
            return !matchedHealthKitUUIDs.contains(uuid)
        }
    }
    private var cardioRuns: [Run] {
        allRuns.filter { !$0.countsAsStrengthDay }
    }

    // Fetch planned workout for this day
    private var plannedWorkout: PlannedWorkout? {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let predicate = #Predicate<PlannedWorkout> { $0.scheduledDate == startOfDay }
        return try? context.fetch(FetchDescriptor(predicate: predicate)).first
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

            // Planned workout section (if exists and not completed)
            if let planned = plannedWorkout, planned.workoutStatus != .completed {
                PlannedWorkoutCard(planned: planned)
            }

            if workouts.isEmpty && allRuns.isEmpty && plannedWorkout == nil {
                ContentUnavailableView("No activity", systemImage: "calendar")
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .background(DS.Theme.cardTop, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DS.Semantic.border, lineWidth: 1))
            } else {
                // Workouts list — EACH ROW = start time (compact, zero clutter)
                if !workouts.isEmpty {
                    VStack(spacing: 0) {
                        SectionHeader(title: "Workouts", count: workouts.count)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        Rectangle().fill(DS.Semantic.border).frame(height: 1)

                        ForEach(workouts, id: \.id) { w in
                            WorkoutRow(workout: w)
                            if w.id != workouts.last?.id {
                                Rectangle().fill(DS.Semantic.border.opacity(0.6)).frame(height: 1)
                            }
                        }
                    }
                    .background(DS.Theme.cardTop, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DS.Semantic.border, lineWidth: 1))
                }

                // HealthKit Strength Workouts (Apple Watch strength training)
                if !healthKitStrengthWorkouts.isEmpty {
                    VStack(spacing: 0) {
                        SectionHeader(title: "Apple Watch Workouts", count: healthKitStrengthWorkouts.count)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        Rectangle().fill(DS.Semantic.border).frame(height: 1)

                        ForEach(healthKitStrengthWorkouts) { workout in
                            HealthKitWorkoutRow(workout: workout)
                            if workout.id != healthKitStrengthWorkouts.last?.id {
                                Rectangle().fill(DS.Semantic.border.opacity(0.6)).frame(height: 1)
                            }
                        }
                    }
                    .background(DS.Theme.cardTop, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DS.Semantic.border, lineWidth: 1))
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
                    .background(DS.Theme.cardTop, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DS.Semantic.border, lineWidth: 1))
                }
            }
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
            HStack(alignment: .firstTextBaseline) {
                Text(date.formatted(.dateTime.weekday(.wide).day().month()))
                    .font(.headline).foregroundStyle(DS.Semantic.textPrimary)
                Spacer()
                if workoutCount > 0 {
                    Text("Daily summary")
                        .font(.caption).foregroundStyle(DS.Semantic.textSecondary)
                }
            }

            SummaryGrid(tiles: tiles)
                .frame(height: 108)
        }
        .padding(12)
        .background(DS.Theme.cardTop, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DS.Semantic.border, lineWidth: 1))
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

    // Determine workout type from matched HealthKit data
    private var workoutType: String {
        // Try to find the matched run to get the workout type
        if let hkUUID = workout.matchedHealthKitUUID,
           let matchedRun = store.runs.first(where: { $0.healthKitUUID == hkUUID }),
           let type = matchedRun.workoutType {
            return type
        }
        // Default to "Strength Workout" for app-logged workouts
        return "Strength Workout"
    }

    // Calculate start time based on duration
    private var startTime: Date {
        if let duration = workout.matchedHealthKitDuration {
            return workout.date.addingTimeInterval(-TimeInterval(duration))
        }
        // Estimate 1 hour workout if no duration data
        return workout.date.addingTimeInterval(-3600)
    }

    private var timeRange: String {
        let start = startTime.formatted(date: .omitted, time: .shortened)
        let end = workout.date.formatted(date: .omitted, time: .shortened)
        return "\(start) - \(end)"
    }

    var body: some View {
        NavigationLink {
            WorkoutDetailView(workout: workout)
        } label: {
            VStack(spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(workoutType)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DS.Semantic.textPrimary)

                        Text(timeRange)
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

                // Show matched HealthKit data
                if hasHealthData {
                    HStack(spacing: 12) {
                        if let duration = workout.matchedHealthKitDuration, duration > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "timer")
                                    .font(.caption2)
                                    .foregroundStyle(DS.Semantic.textSecondary)
                                Text(hms(duration))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(DS.Semantic.textSecondary)
                            }
                        }

                        if let calories = workout.matchedHealthKitCalories, calories > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "flame.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                Text("\(Int(calories)) cal")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(DS.Semantic.textSecondary)
                            }
                        }

                        if let hr = workout.matchedHealthKitHeartRate, hr > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "heart.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.pink)
                                Text("\(Int(hr)) bpm")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(DS.Semantic.textSecondary)
                            }
                        }

                        Spacer()
                    }
                    .padding(.top, 2)
                }
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

    private var workoutIcon: String {
        let activityType = CardioActivityType(from: workout.workoutType)
        return activityType.icon
    }

    private var workoutTypeName: String {
        workout.workoutType ?? "Workout"
    }

    private var startTime: Date {
        // Calculate start time based on duration
        if workout.durationSec > 0 {
            return workout.date.addingTimeInterval(-TimeInterval(workout.durationSec))
        }
        return workout.date.addingTimeInterval(-3600) // Default 1 hour
    }

    private var timeRange: String {
        let start = startTime.formatted(date: .omitted, time: .shortened)
        let end = workout.date.formatted(date: .omitted, time: .shortened)
        return "\(start) - \(end)"
    }

    var body: some View {
        NavigationLink {
            CardioDetailView(run: workout)
        } label: {
            VStack(spacing: 6) {
                HStack(alignment: .center, spacing: 12) {
                    // Workout type icon
                    Image(systemName: workoutIcon)
                        .font(.title3)
                        .foregroundStyle(DS.Theme.accent)
                        .frame(width: 40, height: 40)
                        .background(DS.Theme.accent.opacity(0.15), in: Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(workoutTypeName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DS.Semantic.textPrimary)

                        Text(timeRange)
                            .font(.caption)
                            .foregroundStyle(DS.Semantic.textSecondary)

                        // Show custom workout name if available
                        if let workoutName = workout.workoutName {
                            Text(workoutName)
                                .font(.caption2)
                                .foregroundStyle(DS.Theme.accent)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(DS.Semantic.textSecondary)
                        .opacity(0.6)
                }

                // Show HealthKit data if available
                if workout.durationSec > 0 || workout.calories != nil || workout.avgHeartRate != nil {
                    HStack(spacing: 12) {
                        if workout.durationSec > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "timer")
                                    .font(.caption2)
                                    .foregroundStyle(DS.Semantic.textSecondary)
                                Text(hms(workout.durationSec))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(DS.Semantic.textSecondary)
                            }
                        }

                        if let calories = workout.calories, calories > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "flame.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                Text("\(Int(calories)) cal")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(DS.Semantic.textSecondary)
                            }
                        }

                        if let hr = workout.avgHeartRate, hr > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "heart.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.pink)
                                Text("\(Int(hr)) bpm")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(DS.Semantic.textSecondary)
                            }
                        }

                        Spacer()
                    }
                    .padding(.top, 2)
                }

                // Apple Watch badge
                HStack {
                    Image(systemName: "applewatch")
                        .font(.caption2)
                        .foregroundStyle(DS.Semantic.textSecondary)
                    Text("Apple Watch")
                        .font(.caption2)
                        .foregroundStyle(DS.Semantic.textSecondary)
                    Spacer()
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
