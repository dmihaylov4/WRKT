//
//  WorkoutDetail.swift
//  WRKT
//
//  Enhanced workout detail view with HealthKit integration and heart rate graphs
//

import SwiftUI
import Charts


struct WorkoutDetailView: View {
    let workout: CompletedWorkout
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: WorkoutStoreV2
    @EnvironmentObject var repo: ExerciseRepository
    @State private var showDeleteConfirmation = false
    @State private var showingEditor = false

    private var hasHealthData: Bool {
        workout.matchedHealthKitUUID != nil
    }

    private var hasHeartRateData: Bool {
        workout.matchedHealthKitHeartRateSamples != nil && !(workout.matchedHealthKitHeartRateSamples?.isEmpty ?? true)
    }

    private var workoutStats: WorkoutStats {
        var weightedVolume: Double = 0
        var timeUnderTension: Int = 0
        var totalReps: Int = 0
        var sets: Int = 0

        for entry in workout.entries {
            sets += entry.sets.count
            for set in entry.sets {
                switch set.trackingMode {
                case .weighted:
                    weightedVolume += Double(set.reps) * set.weight
                case .timed:
                    timeUnderTension += set.durationSeconds
                case .bodyweight:
                    totalReps += set.reps
                case .distance:
                    break // Future implementation
                }
            }
        }

        return WorkoutStats(
            weightedVolume: weightedVolume,
            timeUnderTension: timeUnderTension,
            totalReps: totalReps,
            totalSets: sets
        )
    }

    private var totalVolume: Double {
        workoutStats.weightedVolume
    }

    private var totalSets: Int {
        workoutStats.totalSets
    }

    private var startTime: String {
        // Use actual workout start time if available (most accurate)
        if let actualStartTime = workout.startedAt {
            return actualStartTime.formatted(date: .omitted, time: .shortened)
        }
        // Try HealthKit duration
        if let duration = workout.matchedHealthKitDuration {
            return workout.date.addingTimeInterval(-TimeInterval(duration)).formatted(date: .omitted, time: .shortened)
        }
        // Use estimated duration from set timing data
        if let duration = workout.estimatedDuration {
            return workout.date.addingTimeInterval(-duration).formatted(date: .omitted, time: .shortened)
        }
        // If no timing data, just show end time without a start time
        return "—"
    }

    private var endTime: String {
        workout.date.formatted(date: .omitted, time: .shortened)
    }

    private var workoutTitle: String {
        // Use custom name if set, otherwise auto-classify
        if let customName = workout.workoutName, !customName.isEmpty {
            return customName
        }
        return MuscleGroupClassifier.classify(workout)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // MARK: - Clean Header Section
                VStack(alignment: .leading, spacing: 16) {
                    // Title and date
                    VStack(alignment: .leading, spacing: 4) {
                        Text(workoutTitle)
                            .dsFont(.title2, weight: .bold)
                            .foregroundStyle(DS.Semantic.textPrimary)

                        Text(workout.date.formatted(date: .long, time: .omitted))
                            .dsFont(.subheadline)
                            .foregroundStyle(DS.Semantic.textSecondary)

                        // Only show time range if we have start time, otherwise just show end time
                        if startTime != "—" {
                            let timeRange = startTime + " : " + endTime
                            Text(timeRange)
                                .dsFont(.subheadline)
                                .foregroundStyle(DS.Semantic.textSecondary)
                        } else {
                            Text("Ended: " + endTime)
                                .dsFont(.subheadline)
                                .foregroundStyle(DS.Semantic.textSecondary)
                        }

                        // Show indicator when workout is enhanced with HealthKit data
                        if hasHealthData {
                            HStack(spacing: 4) {
                                Image(systemName: "applewatch")
                                    .dsFont(.caption2)
                                Text("Enhanced with Apple Watch data")
                                    .dsFont(.caption2)
                            }
                            .foregroundStyle(DS.Theme.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(DS.Theme.accent.opacity(0.15))
                            .clipShape(ChamferedRectangleAlt(.micro))
                            .padding(.top, 4)
                        }
                    }

                    // Key metrics - clean layout without icons
                    VStack(alignment: .leading, spacing: 10) {
                        // Show HealthKit duration if available, otherwise use estimated duration
                        if let duration = workout.matchedHealthKitDuration {
                            StatRow(label: "Duration", value: formatDuration(duration))
                        } else if let duration = workout.estimatedDuration {
                            StatRow(label: "Duration", value: formatDuration(Int(duration)))
                        }

                        if let calories = workout.matchedHealthKitCalories {
                            StatRow(label: "Calories Burned", value: "\(calories.safeInt) cal")
                        }

                        if workout.entries.reduce(0, { $0 + $1.totalRestTime }) > 0 {
                            let avgRest = workout.entries.reduce(0.0, { $0 + $1.totalRestTime }) / Double(max(1, totalSets - workout.entries.count))
                            if avgRest > 0 {
                                StatRow(label: "Average Rest Time", value: formatDuration(Int(avgRest)))
                            }
                        }
                    }
                    .padding(12)
                    .background(DS.Theme.cardTop, in: ChamferedRectangle(.large))
                    .overlay(ChamferedRectangle(.large).stroke(DS.Semantic.border, lineWidth: 1))

                    // Summary stats
                    HStack(spacing: 12) {
                        StatPill(value: "\(workout.entries.count)", label: "Exercises")
                        StatPill(value: "\(totalSets)", label: "Sets")

                        if workoutStats.hasTotalReps {
                            StatPill(value: "\(workoutStats.totalReps)", label: "Reps")
                        }

                        if workoutStats.hasWeightedVolume {
                            StatPill(value: String(format: "%.0f kg", workoutStats.weightedVolume), label: "Volume")
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // MARK: - Heart Rate Graph
                if let heartRateSamples = workout.matchedHealthKitHeartRateSamples, !heartRateSamples.isEmpty {
                    HeartRateGraph(
                        samples: heartRateSamples,
                        avgHR: workout.matchedHealthKitHeartRate ?? 0,
                        maxHR: workout.matchedHealthKitMaxHeartRate ?? 0,
                        minHR: workout.matchedHealthKitMinHeartRate ?? 0
                    )
                    .padding(.horizontal, 16)
                }

                // MARK: - HR Zone Distribution
                if let samples = workout.matchedHealthKitHeartRateSamples, samples.count > 5 {
                    HRZoneDistributionSection(samples: samples)
                        .padding(.horizontal, 16)
                }

                // MARK: - Exercises Section (ENHANCED)
                ExercisesSectionWithTiming(entries: workout.entries, workout: workout)
                    .padding(.horizontal, 16)
            }
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(DS.Semantic.surface.ignoresSafeArea())
        .navigationTitle("Workout Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showingEditor = true
                    } label: {
                        Label("Edit Workout", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Workout", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(DS.Theme.accent)
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            CompletedWorkoutEditor(workout: workout, isNewWorkout: false)
                .environmentObject(store)
                .environmentObject(repo)
        }
        .confirmationDialog("Delete Workout", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Workout", role: .destructive) {
                store.deleteWorkout(workout)
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
        // Listen for calendar tab reselection
        .onReceive(NotificationCenter.default.publisher(for: .calendarTabReselected)) { _ in

            dismiss()
        }
        // Listen for cardio tab reselection
        .onReceive(NotificationCenter.default.publisher(for: .cardioTabReselected)) { _ in

            dismiss()
        }
    }
}

// MARK: - HR Zone Distribution Section

private struct HRZoneDistributionSection: View {
    let samples: [HeartRateSample]

    private var zoneSummaries: [HRZoneSummary] {
        let calculator = HRZoneCalculator.shared
        let boundaries = calculator.zoneBoundaries()
        var zoneDurations: [Int: TimeInterval] = [:]

        for i in 0..<samples.count - 1 {
            let zone = calculator.zone(for: samples[i].bpm)
            let interval = samples[i + 1].timestamp.timeIntervalSince(samples[i].timestamp)
            let clamped = min(interval, 60)
            zoneDurations[zone, default: 0] += clamped
        }

        return boundaries.compactMap { boundary -> HRZoneSummary? in
            let duration = zoneDurations[boundary.zone] ?? 0
            guard duration > 0 else { return nil }
            return HRZoneSummary(
                zone: boundary.zone,
                name: boundary.name,
                minutes: duration / 60.0,
                rangeDisplay: boundary.rangeString,
                colorHex: boundary.color.toHex()
            )
        }
        .sorted { $0.zone < $1.zone }
    }

    var body: some View {
        if !zoneSummaries.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Heart Rate Zones")
                    .dsFont(.headline)
                    .foregroundStyle(DS.Semantic.textPrimary)

                HRZoneChart(zones: zoneSummaries, samples: samples)
            }
            .padding(14)
            .background(DS.Theme.cardTop, in: ChamferedRectangle(.large))
            .overlay(ChamferedRectangle(.large).stroke(DS.Semantic.border, lineWidth: 1))
        }
    }
}

// MARK: - Workout Stats Model

struct WorkoutStats {
    let weightedVolume: Double
    let timeUnderTension: Int
    let totalReps: Int
    let totalSets: Int

    var hasWeightedVolume: Bool { weightedVolume > 0 }
    var hasTimeUnderTension: Bool { timeUnderTension > 0 }
    var hasTotalReps: Bool { totalReps > 0 }

    var formattedDuration: String {
        let hours = timeUnderTension / 3600
        let minutes = (timeUnderTension % 3600) / 60
        let seconds = timeUnderTension % 60

        if hours > 0 {
            return String(format: "%dh %dm %ds", hours, minutes, seconds)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }
}

// MARK: - Stat Pill

private struct StatPill: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .dsFont(.title3, weight: .semibold)
                .foregroundStyle(DS.Semantic.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .dsFont(.caption)
                .foregroundStyle(DS.Semantic.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(DS.Theme.cardTop, in: ChamferedRectangle(.large))
    }
}

// MARK: - Stat Row (Clean, no icons)

private struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .dsFont(.subheadline)
                .foregroundStyle(DS.Semantic.textSecondary)
            Spacer()
            Text(value)
                .dsFont(.subheadline, weight: .medium)
                .foregroundStyle(DS.Semantic.textPrimary)
        }
    }
}

// MARK: - HealthKit Metrics

private struct HealthKitMetricsSection: View {
    let workout: CompletedWorkout

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Apple Watch Metrics")
                .dsFont(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                if let duration = workout.matchedHealthKitDuration {
                    MetricTile(icon: "timer", title: "Duration", value: formatDuration(duration))
                }

                if let calories = workout.matchedHealthKitCalories {
                    MetricTile(icon: "flame.fill", title: "Calories", value: "\(calories.safeInt) cal", iconColor: .orange)
                }

                if let avgHR = workout.matchedHealthKitHeartRate {
                    MetricTile(icon: "heart.fill", title: "Avg HR", value: "\(Int(avgHR)) bpm", iconColor: .pink)
                }

                if let maxHR = workout.matchedHealthKitMaxHeartRate {
                    MetricTile(icon: "arrow.up.heart.fill", title: "Max HR", value: "\(Int(maxHR)) bpm", iconColor: .red)
                }

                if let minHR = workout.matchedHealthKitMinHeartRate {
                    MetricTile(icon: "arrow.down.heart.fill", title: "Min HR", value: "\(Int(minHR)) bpm", iconColor: .green)
                }
            }
        }
        .padding(14)
        .background(DS.Theme.cardTop, in: ChamferedRectangle(.large))
        .overlay(ChamferedRectangle(.large).stroke(DS.Semantic.border, lineWidth: 1))
    }

    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

private struct MetricTile: View {
    let icon: String
    let title: String
    let value: String
    var iconColor: Color = DS.Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .dsFont(.caption)
                    .foregroundStyle(iconColor.opacity(0.7))
                Text(title)
                    .dsFont(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }
            Text(value)
                .dsFont(.body, weight: .semibold)
                .foregroundStyle(DS.Semantic.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(DS.Theme.cardTop, in: ChamferedRectangle(.large))
    }
}

// MARK: - Heart Rate Graph

private struct HeartRateGraph: View {
    let samples: [HeartRateSample]
    let avgHR: Double
    let maxHR: Double
    let minHR: Double

    // Calculate relative time from workout start
    private var dataPoints: [(time: TimeInterval, bpm: Double)] {
        guard let firstSample = samples.first else { return [] }
        let startTime = firstSample.timestamp

        return samples.map { sample in
            let elapsed = sample.timestamp.timeIntervalSince(startTime)
            return (elapsed, sample.bpm)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Heart Rate")
                        .dsFont(.headline)
                        .foregroundStyle(DS.Semantic.textPrimary)

                    Text("\(samples.count) samples")
                        .dsFont(.caption2)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }

                Spacer()

                // HR stats in compact format
                HStack(spacing: 16) {
                    HRStat(icon: "arrow.down", value: Int(minHR), color: .green)
                    HRStat(icon: "heart.fill", value: Int(avgHR), color: .pink)
                    HRStat(icon: "arrow.up", value: Int(maxHR), color: .red)
                }
                .dsFont(.caption)
            }

            // Chart
            Chart {
                ForEach(Array(dataPoints.enumerated()), id: \.offset) { index, point in
                    // Area fill - use yStart to prevent extending below chart
                    AreaMark(
                        x: .value("Time", point.time),
                        yStart: .value("Min", minHR - 10),
                        yEnd: .value("BPM", point.bpm)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.pink.opacity(0.4), .red.opacity(0.1)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    // Line
                    LineMark(
                        x: .value("Time", point.time),
                        y: .value("BPM", point.bpm)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.pink, .red],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }

                // Average HR line
                RuleMark(y: .value("Avg", avgHR))
                    .foregroundStyle(.pink.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("AVG")
                            .dsFont(.caption2, weight: .medium)
                            .foregroundStyle(.pink)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.6))
                            .clipShape(ChamferedRectangleAlt(.micro))
                    }
            }
            .chartYScale(domain: (minHR - 10)...(maxHR + 10))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { value in
                    if let seconds = value.as(Double.self) {
                        AxisValueLabel {
                            Text(formatTimeAxis(seconds))
                                .dsFont(.caption2)
                                .foregroundStyle(DS.Semantic.textSecondary)
                        }
                        AxisGridLine().foregroundStyle(DS.Semantic.border)
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisValueLabel {
                        Text("\(value.as(Int.self) ?? 0)")
                            .dsFont(.caption2)
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }
                    AxisGridLine().foregroundStyle(DS.Semantic.border)
                }
            }
            .frame(height: 220)
        }
        .padding(14)
        .background(DS.Theme.cardTop, in: ChamferedRectangle(.large))
        .overlay(ChamferedRectangle(.large).stroke(DS.Semantic.border, lineWidth: 1))
    }

    private func formatTimeAxis(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "\(secs)s"
        }
    }
}

private struct HRStat: View {
    let icon: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .dsFont(.caption2)
                .foregroundStyle(color)
            Text("\(value)")
                .dsFont(.caption, weight: .medium, monospacedDigits: true)
                .foregroundStyle(DS.Semantic.textPrimary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15))
        .clipShape(ChamferedRectangleAlt(.micro))
    }
}

private extension Color {
    func toHex() -> String {
        let uiColor = UIColor(self)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }
}

