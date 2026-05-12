import SwiftUI
import Kingfisher

struct MultiWorkoutCarousel: View {
    let workouts: [CompletedWorkout]
    let mapURLs: [URL]

    var body: some View {
        TabView {
            SessionSummarySlide(workouts: workouts)
                .tag(0)

            ForEach(Array(workouts.enumerated()), id: \.element.id) { index, workout in
                WorkoutSlide(
                    workout: workout,
                    mapURL: mapURL(forWorkoutAt: index)
                )
                .tag(index + 1)
            }
        }
        .frame(height: 340)
        .tabViewStyle(.page(indexDisplayMode: .always))
        .background(DS.Semantic.fillSubtle, in: ChamferedRectangle(.medium))
        .clipShape(ChamferedRectangle(.medium))
        .overlay(ChamferedRectangle(.medium).stroke(DS.Semantic.border, lineWidth: 1))
    }

    private func mapURL(forWorkoutAt workoutIndex: Int) -> URL? {
        guard workouts[workoutIndex].isCardioWorkout else { return nil }
        let cardioIndex = workouts[..<workoutIndex].filter(\.isCardioWorkout).count
        guard cardioIndex < mapURLs.count else { return nil }
        return mapURLs[cardioIndex]
    }
}

private struct SessionSummarySlide: View {
    let workouts: [CompletedWorkout]

    private var totalCalories: Int {
        Int(workouts.compactMap(\.matchedHealthKitCalories).reduce(0, +))
    }

    private var totalDuration: TimeInterval {
        workouts.compactMap { WorkoutPostStatsViews.duration(for: $0) }.reduce(0, +)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SESSION")
                .dsFont(.caption, weight: .bold)
                .foregroundStyle(DS.Semantic.textSecondary)

            HStack(spacing: 24) {
                Label("\(totalCalories) cal", systemImage: "flame.fill")
                Label(WorkoutPostStatsViews.durationText(totalDuration), systemImage: "clock.fill")
            }
            .dsFont(.headline)
            .foregroundStyle(DS.Semantic.textPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(workouts, id: \.id) { workout in
                        Label(
                            "\(workout.workoutName ?? workout.workoutTypeDisplayName) \(WorkoutPostStatsViews.durationText(WorkoutPostStatsViews.duration(for: workout)))",
                            systemImage: workout.workoutIcon
                        )
                        .dsFont(.caption)
                        .foregroundStyle(DS.Semantic.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(DS.Semantic.card, in: Capsule())
                    }
                }
            }
            .simultaneousGesture(DragGesture())

            Spacer()
        }
        .padding(16)
    }
}

private struct WorkoutSlide: View {
    let workout: CompletedWorkout
    let mapURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer()
                Label(workout.workoutName ?? workout.workoutTypeDisplayName, systemImage: workout.workoutIcon)
                    .dsFont(.caption, weight: .bold)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(DS.Semantic.brand, in: Capsule())
            }

            if workout.isCardioWorkout {
                cardioContent
            } else if !workout.entries.isEmpty {
                strengthContent
            } else {
                mixedContent
            }

        }
        .padding(16)
    }

    private var cardioContent: some View {
        VStack(spacing: 12) {
            if let mapURL {
                KFImage(mapURL)
                    .placeholder { Rectangle().fill(DS.Semantic.fillSubtle).overlay(ProgressView()) }
                    .fade(duration: 0.25)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 140)
                    .clipShape(ChamferedRectangle(.small))
            }

            if let distanceMeters = workout.matchedHealthKitDistance, distanceMeters > 0 {
                let durationSec = workout.matchedHealthKitDuration
                let pace = durationSec.map { Double($0) / (distanceMeters / 1000) }
                HStack {
                    stat(icon: "figure.run", value: String(format: "%.2f", distanceMeters / 1000), label: "km")
                    Spacer()
                    if let durationSec {
                        stat(icon: "clock.fill", value: WorkoutPostStatsViews.formatCardioDuration(durationSec), label: "time")
                    }
                    Spacer()
                    if let pace {
                        stat(icon: "speedometer", value: WorkoutPostStatsViews.formatPace(pace), label: "/km")
                    }
                }
            }

            HStack {
                if let calories = workout.matchedHealthKitCalories {
                    stat(icon: "flame.fill", value: String(format: "%.0f", calories), label: "cal")
                }
                Spacer()
                if let avgHR = workout.matchedHealthKitHeartRate {
                    stat(icon: "heart.fill", value: String(format: "%.0f", avgHR), label: "avg bpm")
                }
                Spacer()
                if let maxHR = workout.matchedHealthKitMaxHeartRate {
                    stat(icon: "bolt.heart.fill", value: String(format: "%.0f", maxHR), label: "max bpm")
                }
            }
        }
    }

    private var strengthContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                stat(icon: "dumbbell.fill", value: "\(WorkoutPostStatsViews.exerciseCount(for: workout))", label: "exercises")
                Spacer()
                stat(icon: "list.bullet", value: "\(WorkoutPostStatsViews.totalSets(for: workout))", label: "sets")
                Spacer()
                stat(icon: "scalemass.fill", value: WorkoutPostStatsViews.formatVolume(WorkoutPostStatsViews.totalVolume(for: workout)), label: "kg")
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(workout.entries) { entry in
                        Text("\(entry.exerciseName) · \(entry.sets.count) sets")
                            .dsFont(.caption)
                            .foregroundStyle(DS.Semantic.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var mixedContent: some View {
        HStack {
            if let duration = WorkoutPostStatsViews.duration(for: workout) {
                stat(icon: "clock.fill", value: WorkoutPostStatsViews.durationText(duration), label: "duration")
            }
            Spacer()
            if let calories = workout.matchedHealthKitCalories {
                stat(icon: "flame.fill", value: String(format: "%.0f", calories), label: "cal")
            }
        }
    }

    private func stat(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .dsFont(.caption2)
                .foregroundStyle(DS.Semantic.textSecondary)
            Text(value)
                .dsFont(.caption, weight: .bold)
                .foregroundStyle(DS.Semantic.textPrimary)
            Text(label)
                .dsFont(.caption2)
                .foregroundStyle(DS.Semantic.textSecondary)
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}
