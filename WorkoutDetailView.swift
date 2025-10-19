//
//  WorkoutDetailView.swift
//  WRKT
//
//  Detailed view showing workout exercises and matched HealthKit data
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

    private var hasHealthData: Bool {
        workout.matchedHealthKitUUID != nil
    }

    private var hasHeartRateData: Bool {
        workout.matchedHealthKitHeartRateSamples != nil && !(workout.matchedHealthKitHeartRateSamples?.isEmpty ?? true)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Workout header
                VStack(alignment: .leading, spacing: 8) {
                    Text(workout.date.formatted(date: .long, time: .shortened))
                        .font(.title3.bold())
                        .foregroundStyle(Theme.text)

                    if hasHealthData {
                        HStack {
                            Image(systemName: "heart.circle.fill")
                                .foregroundStyle(.pink)
                            Text("Apple Watch Data")
                                .foregroundStyle(Theme.secondary)
                        }
                        .font(.caption)
                    }
                }
                .padding(.horizontal, 16)

                // HealthKit metrics
                if hasHealthData {
                    HealthKitMetricsSection(workout: workout)
                        .padding(.horizontal, 16)
                }

                // Heart rate graph
                if hasHeartRateData {
                    HeartRateGraph(samples: workout.matchedHealthKitHeartRateSamples!,
                                 avgHR: workout.matchedHealthKitHeartRate ?? 0,
                                 maxHR: workout.matchedHealthKitMaxHeartRate ?? 0,
                                 minHR: workout.matchedHealthKitMinHeartRate ?? 0)
                        .padding(.horizontal, 16)
                }

                // Exercises section
                ExercisesSection(entries: workout.entries)
                    .padding(.horizontal, 16)
            }
            .padding(.vertical, 16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Workout Details")
        .navigationBarTitleDisplayMode(.inline)
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
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
            }
            Text(value)
                .font(.headline)
                .foregroundStyle(Theme.text)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Heart Rate")
                    .font(.headline)
                    .foregroundStyle(Theme.text)

                Spacer()

                // HR zones legend
                HStack(spacing: 12) {
                    HRZoneIndicator(color: .green, label: "\(Int(minHR))")
                    HRZoneIndicator(color: .pink, label: "\(Int(avgHR))")
                    HRZoneIndicator(color: .red, label: "\(Int(maxHR))")
                }
                .font(.caption)
            }

            // Chart
            Chart {
                ForEach(Array(dataPoints.enumerated()), id: \.offset) { index, point in
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

                    AreaMark(
                        x: .value("Time", point.time),
                        y: .value("BPM", point.bpm)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.pink.opacity(0.3), .red.opacity(0.1)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }

                // Average HR line
                RuleMark(y: .value("Avg", avgHR))
                    .foregroundStyle(.pink.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
            }
            .chartYScale(domain: (minHR - 10)...(maxHR + 10))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
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
            .frame(height: 200)

            // Sample count
            Text("\(samples.count) samples")
                .font(.caption2)
                .foregroundStyle(Theme.secondary)
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
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

private struct HRZoneIndicator: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .foregroundStyle(Theme.secondary)
        }
    }
}

// MARK: - Exercises Section

private struct ExercisesSection: View {
    let entries: [WorkoutEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exercises")
                .font(.headline)
                .foregroundStyle(Theme.text)

            ForEach(entries) { entry in
                ExerciseCard(entry: entry)
            }
        }
    }
}

private struct ExerciseCard: View {
    let entry: WorkoutEntry

    private var totalVolume: Double {
        entry.sets.reduce(0) { $0 + (Double($1.reps) * $1.weight) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Exercise name and volume
            HStack {
                Text(entry.exerciseName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)

                Spacer()

                Text("\(Int(totalVolume)) kg")
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
            }

            // Sets
            VStack(spacing: 6) {
                ForEach(Array(entry.sets.enumerated()), id: \.offset) { index, set in
                    HStack {
                        // Set number
                        Text("Set \(index + 1)")
                            .font(.caption)
                            .foregroundStyle(Theme.secondary)
                            .frame(width: 50, alignment: .leading)

                        // Tag
                        Text(set.tag.short)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(set.tag.color, in: Capsule())

                        Spacer()

                        // Reps x Weight
                        Text("\(set.reps) × \(set.weight, specifier: "%.1f") kg")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.text)
                    }
                }
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        WorkoutDetailView(
            workout: CompletedWorkout(
                date: .now,
                entries: [
                    WorkoutEntry(
                        exerciseID: "bench-press",
                        exerciseName: "Barbell Bench Press",
                        muscleGroups: ["Chest"],
                        sets: [
                            SetInput(reps: 10, weight: 60, tag: .warmup),
                            SetInput(reps: 8, weight: 80, tag: .working),
                            SetInput(reps: 6, weight: 90, tag: .working)
                        ]
                    )
                ]
            )
        )
    }
}

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
