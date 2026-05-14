import SwiftUI
import Kingfisher

struct MultiWorkoutCarousel: View {
    let workouts: [CompletedWorkout]
    let mapURLs: [URL]

    @State private var selectedTab: Int = 0

    private var tabCount: Int { workouts.count + 1 }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                WorkoutPostHeroSummaryCard(
                    summary: .make(for: workouts),
                    context: .carousel
                )
                .padding(16)
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
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(DS.Semantic.fillSubtle, in: ChamferedRectangle(.medium))
            .clipShape(ChamferedRectangle(.medium))
            .overlay(ChamferedRectangle(.medium).stroke(DS.Semantic.border, lineWidth: 1))

            if tabCount > 1 {
                HStack(spacing: 5) {
                    ForEach(0..<tabCount, id: \.self) { index in
                        Capsule()
                            .fill(index == selectedTab ? DS.tint : Color.secondary.opacity(0.3))
                            .frame(width: index == selectedTab ? 24 : 8, height: 3)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedTab)
                    }
                }
                .padding(.bottom, 10)
            }
        }
    }

    private func mapURL(forWorkoutAt workoutIndex: Int) -> URL? {
        guard workouts[workoutIndex].isCardioWorkout else { return nil }
        let cardioIndex = workouts[..<workoutIndex].filter(\.isCardioWorkout).count
        guard cardioIndex < mapURLs.count else { return nil }
        return mapURLs[cardioIndex]
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
        let summary = WorkoutPostSummaryPresentation.make(for: [workout])

        return VStack(alignment: .leading, spacing: 12) {
            ForEach(summary.breakdownRows.prefix(4)) { row in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title)
                            .dsFont(.caption, weight: .bold)
                            .foregroundStyle(DS.Semantic.textPrimary)
                            .lineLimit(1)
                        Text(row.detail)
                            .dsFont(.caption2)
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }

                    Spacer(minLength: 8)

                    Text(row.value)
                        .dsFont(.caption, weight: .bold)
                        .foregroundStyle(DS.Semantic.textPrimary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(DS.Semantic.fillSubtle, in: RoundedRectangle(cornerRadius: 8))
            }

            if summary.breakdownRows.count > 4 {
                Text("+ \(summary.breakdownRows.count - 4) more exercises")
                    .dsFont(.caption2, weight: .semibold)
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .padding(.top, 2)
            }

            Spacer(minLength: 0)
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
