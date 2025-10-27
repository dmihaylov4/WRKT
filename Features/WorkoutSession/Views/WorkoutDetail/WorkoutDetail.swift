//
//  WorkoutDetail.swift
//  WRKT
//
//  Enhanced workout detail view with HealthKit integration and heart rate graphs
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
    static let accent    = Color(hex: "#F4E409")
}

struct WorkoutDetailView: View {
    let workout: CompletedWorkout
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: WorkoutStoreV2

    private var hasHealthData: Bool {
        workout.matchedHealthKitUUID != nil
    }

    private var hasHeartRateData: Bool {
        workout.matchedHealthKitHeartRateSamples != nil && !(workout.matchedHealthKitHeartRateSamples?.isEmpty ?? true)
    }

    private var totalVolume: Double {
        workout.entries.reduce(0) { total, entry in
            total + entry.sets.reduce(0) { $0 + (Double($1.reps) * $1.weight) }
        }
    }

    private var totalSets: Int {
        workout.entries.reduce(0) { $0 + $1.sets.count }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // MARK: - Header Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(workout.date.formatted(date: .long, time: .omitted))
                                .font(.title2.bold())
                                .foregroundStyle(Theme.text)

                            Text(workout.date.formatted(date: .omitted, time: .shortened))
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondary)
                        }

                        Spacer()

                        if hasHealthData {
                            VStack(spacing: 4) {
                                Image(systemName: "heart.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.pink)
                                Text("Apple Watch")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.secondary)
                            }
                        }
                    }

                    // Quick stats
                    HStack(spacing: 16) {
                        StatPill(icon: "dumbbell.fill", value: "\(workout.entries.count)", label: "Exercises")
                        StatPill(icon: "figure.strengthtraining.traditional", value: "\(totalSets)", label: "Sets")
                        StatPill(icon: "scalemass.fill", value: String(format: "%.0f kg", totalVolume), label: "Volume")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // MARK: - HealthKit Metrics
                if hasHealthData {
                    HealthKitMetricsSection(workout: workout)
                        .padding(.horizontal, 16)
                }

                // MARK: - Heart Rate Graph
                if hasHeartRateData {
                    HeartRateGraph(
                        samples: workout.matchedHealthKitHeartRateSamples!,
                        avgHR: workout.matchedHealthKitHeartRate ?? 0,
                        maxHR: workout.matchedHealthKitMaxHeartRate ?? 0,
                        minHR: workout.matchedHealthKitMinHeartRate ?? 0
                    )
                    .padding(.horizontal, 16)
                }

                // MARK: - Exercises Section
                ExercisesSection(entries: workout.entries)
                    .padding(.horizontal, 16)
            }
            .padding(.vertical, 16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Workout Details")
        .navigationBarTitleDisplayMode(.inline)
        // Listen for tab changes
        .onReceive(NotificationCenter.default.publisher(for: .tabDidChange)) { _ in
            dismiss()
        }
        // Listen for calendar tab reselection
        .onReceive(NotificationCenter.default.publisher(for: .calendarTabReselected)) { _ in
            print("📅 WorkoutDetailView received calendar reselection - dismissing")
            dismiss()
        }
        // Listen for cardio tab reselection
        .onReceive(NotificationCenter.default.publisher(for: .cardioTabReselected)) { _ in
            print("🏃 WorkoutDetailView received cardio reselection - dismissing")
            dismiss()
        }
    }
}

// MARK: - Stat Pill

private struct StatPill: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

// MARK: - HealthKit Metrics

private struct HealthKitMetricsSection: View {
    let workout: CompletedWorkout

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Apple Watch Metrics")
                .font(.headline)
                .foregroundStyle(Theme.text)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                if let duration = workout.matchedHealthKitDuration {
                    MetricTile(icon: "timer", title: "Duration", value: formatDuration(duration))
                }

                if let calories = workout.matchedHealthKitCalories {
                    MetricTile(icon: "flame.fill", title: "Calories", value: "\(Int(calories)) cal", iconColor: .orange)
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
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border, lineWidth: 1))
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
    var iconColor: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
            }
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                        .font(.headline)
                        .foregroundStyle(Theme.text)

                    Text("\(samples.count) samples")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondary)
                }

                Spacer()

                // HR stats in compact format
                HStack(spacing: 16) {
                    HRStat(icon: "arrow.down", value: Int(minHR), color: .green)
                    HRStat(icon: "heart.fill", value: Int(avgHR), color: .pink)
                    HRStat(icon: "arrow.up", value: Int(maxHR), color: .red)
                }
                .font(.caption)
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
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.pink)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.6), in: Capsule())
                    }
            }
            .chartYScale(domain: (minHR - 10)...(maxHR + 10))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { value in
                    if let seconds = value.as(Double.self) {
                        AxisValueLabel {
                            Text(formatTimeAxis(seconds))
                                .font(.caption2)
                                .foregroundStyle(Theme.secondary)
                        }
                        AxisGridLine().foregroundStyle(Theme.border)
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisValueLabel {
                        Text("\(value.as(Int.self) ?? 0)")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondary)
                    }
                    AxisGridLine().foregroundStyle(Theme.border)
                }
            }
            .frame(height: 220)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border, lineWidth: 1))
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
                .font(.caption2)
                .foregroundStyle(color)
            Text("\(value)")
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Exercises Section

private struct ExercisesSection: View {
    let entries: [WorkoutEntry]
    @EnvironmentObject var repo: ExerciseRepository
    @EnvironmentObject var store: WorkoutStoreV2
    @State private var selectedExercise: Exercise?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exercises")
                .font(.headline)
                .foregroundStyle(Theme.text)

            ForEach(entries) { entry in
                if let exercise = repo.exercises.first(where: { $0.id == entry.exerciseID }) {
                    Button {
                        selectedExercise = exercise
                    } label: {
                        ExerciseCard(entry: entry)
                    }
                    .buttonStyle(.plain)
                } else {
                    ExerciseCard(entry: entry)
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

private struct ExerciseCard: View {
    let entry: WorkoutEntry

    private var totalVolume: Double {
        entry.sets.reduce(0) { $0 + (Double($1.reps) * $1.weight) }
    }

    private var maxWeight: Double {
        entry.sets.map { $0.weight }.max() ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Exercise header
            HStack(alignment: .top) {
                Text(entry.exerciseName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(totalVolume)) kg")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    Text("volume")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondary)
                }
            }

            Divider()
                .background(Theme.border)

            // Sets
            VStack(spacing: 8) {
                ForEach(Array(entry.sets.enumerated()), id: \.offset) { index, set in
                    HStack(spacing: 12) {
                        // Set number badge
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(.black)
                            .frame(width: 24, height: 24)
                            .background(Theme.accent, in: Circle())

                        // Tag
                        Text(set.tag.short)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(set.tag.color, in: Capsule())

                        Spacer()

                        // Reps
                        HStack(spacing: 4) {
                            Text("\(set.reps)")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Theme.text)
                            Text("reps")
                                .font(.caption2)
                                .foregroundStyle(Theme.secondary)
                        }

                        // Weight
                        HStack(spacing: 4) {
                            Text("\(set.weight, specifier: "%.1f")")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(set.weight == maxWeight ? Theme.accent : Theme.text)
                            Text("kg")
                                .font(.caption2)
                                .foregroundStyle(Theme.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

// MARK: - Color Extension

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:(a, r, g, b) = (255, 244, 228, 9)
        }
        self.init(.sRGB,
                  red: Double(r) / 255,
                  green: Double(g) / 255,
                  blue: Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}
