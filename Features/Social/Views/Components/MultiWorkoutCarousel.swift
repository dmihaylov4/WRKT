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
        VStack(alignment: .leading, spacing: 10) {
            Text("Combined Workout (\(workouts.count) workouts)")
                .dsFont(.subheadline, weight: .bold)
                .foregroundStyle(DS.Semantic.textPrimary)

            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image("streak-icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                    Text("\(totalCalories) cal")
                        .dsFont(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }
                HStack(spacing: 4) {
                    Image("challenge-clock-icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                    Text(WorkoutPostStatsViews.durationText(totalDuration))
                        .dsFont(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(workouts.enumerated()), id: \.element.id) { index, workout in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1)")
                            .dsFont(.caption, weight: .bold)
                            .foregroundStyle(DS.Semantic.brand)
                            .frame(minWidth: 16, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(workout.workoutName ?? workout.workoutTypeDisplayName)
                                    .dsFont(.caption, weight: .medium)
                                    .foregroundStyle(DS.Semantic.textPrimary)
                                Spacer()
                                Text(WorkoutPostStatsViews.durationText(WorkoutPostStatsViews.duration(for: workout)))
                                    .dsFont(.caption)
                                    .foregroundStyle(DS.Semantic.textSecondary)
                            }
                            if workout.isCardioWorkout {
                                if let dist = workout.matchedHealthKitDistance, dist > 0 {
                                    Text(String(format: "%.2f km", dist / 1000))
                                        .dsFont(.caption2)
                                        .foregroundStyle(DS.Semantic.textSecondary)
                                }
                            } else if !workout.entries.isEmpty {
                                let sets = workout.entries.reduce(0) { $0 + $1.sets.count }
                                Text("\(workout.entries.count) exercises · \(sets) sets · \(WorkoutPostStatsViews.formatVolume(WorkoutPostStatsViews.totalVolume(for: workout))) kg")
                                    .dsFont(.caption2)
                                    .foregroundStyle(DS.Semantic.textSecondary)
                            }
                        }
                    }
                }
            }

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
                Text(workout.workoutName ?? workout.workoutTypeDisplayName)
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
                    stat(icon: "streak-icon", value: String(format: "%.0f", calories), label: "cal", assetImage: true)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(workout.entries) { entry in
                    exerciseRow(entry: entry)
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxHeight: .infinity)
    }

    private func exerciseRow(entry: WorkoutEntry) -> some View {
        let totalReps = entry.sets.reduce(0) { $0 + ($1.reps ?? 0) }
        let totalVolume = entry.sets.reduce(0.0) { $0 + Double($1.reps ?? 0) * ($1.weight ?? 0) }

        return VStack(alignment: .leading, spacing: 8) {
            Text(entry.exerciseName)
                .dsFont(.caption, weight: .bold)
                .foregroundStyle(DS.Semantic.textPrimary)

            HStack(spacing: 12) {
                exerciseStat(label: "Sets", value: "\(entry.sets.count)")
                exerciseStat(label: "Reps", value: "\(totalReps)")
                if totalVolume > 0 {
                    exerciseStat(label: "Volume", value: String(format: "%.0f kg", totalVolume))
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(DS.Semantic.fillSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if entry.totalDuration > 0 {
                HStack(spacing: 12) {
                    exerciseStat(label: "Duration", value: entry.formattedTotalDuration)
                    exerciseStat(label: "Work", value: entry.formattedWorkTime)
                    exerciseStat(label: "Rest", value: entry.formattedRestTime)
                    Spacer(minLength: 0)
                }
                .padding(8)
                .background(DS.Semantic.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(spacing: 4) {
                ForEach(Array(entry.sets.enumerated()), id: \.offset) { index, set in
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .dsFont(.caption2, weight: .bold)
                            .foregroundStyle(.black)
                            .frame(width: 20, height: 20)
                            .background(set.tag.color, in: Circle())

                        VStack(alignment: .leading, spacing: 1) {
                            Text(set.displayValue)
                                .dsFont(.caption, weight: .medium)
                                .foregroundStyle(DS.Semantic.textPrimary)
                            if set.workDuration != nil || set.restAfterSeconds != nil {
                                HStack(spacing: 6) {
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

                        Text(set.tag.short)
                            .dsFont(.caption2, weight: .semibold)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(set.tag.color, in: Capsule())
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(DS.Semantic.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(10)
        .background(DS.Semantic.card)
        .clipShape(ChamferedRectangleAlt(.medium))
        .overlay(ChamferedRectangleAlt(.medium).stroke(DS.Semantic.border, lineWidth: 1))
    }

    private func exerciseStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .dsFont(.caption2)
                .foregroundStyle(DS.Semantic.textSecondary)
            Text(value)
                .dsFont(.caption, weight: .semibold)
                .foregroundStyle(DS.Semantic.textPrimary)
        }
    }

    private var mixedContent: some View {
        HStack {
            if let duration = WorkoutPostStatsViews.duration(for: workout) {
                stat(icon: "clock.fill", value: WorkoutPostStatsViews.durationText(duration), label: "duration")
            }
            Spacer()
            if let calories = workout.matchedHealthKitCalories {
                stat(icon: "streak-icon", value: String(format: "%.0f", calories), label: "cal", assetImage: true)
            }
        }
    }

    private func stat(icon: String, value: String, label: String, assetImage: Bool = false) -> some View {
        HStack(spacing: 3) {
            if assetImage {
                Image(icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 11, height: 11)
            } else {
                Image(systemName: icon)
                    .dsFont(.caption2)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }
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
