//
//  ExerciseStatisticsView.swift
//  WRKT
//
//  Comprehensive exercise statistics view with charts, PRs, and history
//

import SwiftUI
import Charts
import OSLog

struct ExerciseStatisticsView: View {
    let exerciseID: String
    let exerciseName: String
    let trackingMode: TrackingMode

    @EnvironmentObject var store: WorkoutStoreV2
    @Environment(\.dismiss) private var dismiss
    @State private var stats: ExerciseStatistics?
    @State private var showAllHistory = false

    var body: some View {
        ZStack {
            DS.Semantic.surface.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    if let stats = stats {
                        if stats.hasSufficientData {
                            VStack(alignment: .leading, spacing: 20) {
                                // Header with last performed
                                HeaderSection(stats: stats)
                                    .padding(.horizontal, 16)
                                    .padding(.top, 8)

                                // PR Cards
                                if stats.hasPRs {
                                    PRCardsSection(stats: stats)
                                        .padding(.horizontal, 16)
                                }

                                // Progress Charts
                                if !stats.progressData.volumeProgression.isEmpty {
                                    ProgressChartsSection(stats: stats)
                                        .padding(.horizontal, 16)
                                }

                                // Statistics Grid
                                StatisticsGridSection(stats: stats)
                                    .padding(.horizontal, 16)

                                // Recent History
                                if !stats.history.recentWorkouts.isEmpty {
                                    RecentHistorySection(
                                        workouts: stats.history.recentWorkouts,
                                        exerciseName: exerciseName
                                    )
                                    .padding(.horizontal, 16)
                                }

                                // All-Time History (Expandable)
                                if stats.history.allWorkouts.count > 4 {
                                    AllTimeHistorySection(
                                        workouts: stats.history.allWorkouts,
                                        exerciseName: exerciseName,
                                        showAll: $showAllHistory
                                    )
                                    .padding(.horizontal, 16)
                                }
                            }
                            .padding(.vertical, 16)
                        } else {
                            // Not enough data
                            VStack {
                                Spacer()
                                InsufficientDataView(exerciseName: exerciseName)
                                    .padding(16)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 400)
                        }
                    } else {
                        // Loading state
                        VStack {
                            Spacer()
                            ProgressView("Loading statistics...")
                                .tint(DS.Theme.accent)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 400)
                    }
                }
            }
        }
        .navigationTitle("Statistics: \(exerciseName)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadStatistics()
        }
        .onAppear {
            AppLogger.debug("ExerciseStatisticsView appeared for: \(exerciseName)", category: AppLogger.statistics)
        }
    }

    private func loadStatistics() async {
        AppLogger.debug("Loading statistics for \(exerciseName) (ID: \(exerciseID))", category: AppLogger.statistics)

        let aggregator = ExerciseStatsAggregator()
        let workouts = await MainActor.run { store.completedWorkouts }

        AppLogger.debug("Found \(workouts.count) total workouts", category: AppLogger.statistics)

        // Compute statistics on background thread
        let computed = await Task.detached {
            aggregator.computeStatistics(
                exerciseID: exerciseID,
                exerciseName: exerciseName,
                trackingMode: trackingMode,
                from: workouts
            )
        }.value

        await MainActor.run {
            stats = computed
            AppLogger.debug("Statistics computed: \(computed.frequencyStats.totalTimesPerformed) sessions", category: AppLogger.statistics)
        }
    }
}

// MARK: - Header Section

private struct HeaderSection: View {
    let stats: ExerciseStatistics

    private var lastPerformedText: String {
        guard let lastDate = stats.frequencyStats.lastPerformed else {
            return "Never performed"
        }

        if let days = stats.frequencyStats.daysSinceLastPerformed {
            if days == 0 {
                return "Last performed: Today"
            } else if days == 1 {
                return "Last performed: Yesterday"
            } else if days < 7 {
                return "Last performed: \(days) days ago"
            } else {
                let weeks = days / 7
                return "Last performed: \(weeks) week\(weeks == 1 ? "" : "s") ago"
            }
        }

        return "Last performed: \(lastDate.formatted(date: .abbreviated, time: .omitted))"
    }

    private var trendColor: Color {
        switch stats.progressData.trendDirection {
        case .improving: return DS.Charts.positive
        case .declining: return DS.Charts.negative
        case .stable: return DS.Semantic.textSecondary
        case .insufficient: return DS.Semantic.textSecondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(lastPerformedText)
                        .font(.subheadline)
                        .foregroundStyle(DS.Semantic.textSecondary)

                    HStack(spacing: 8) {
                        Image(systemName: stats.progressData.trendDirection.iconName)
                            .font(.caption)
                            .foregroundStyle(trendColor)

                        Text(stats.progressData.trendDirection.displayText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(trendColor)

                        if let change = stats.progressData.volumeChangePercent, abs(change) > 1 {
                            Text(String(format: "%+.1f%%", change))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(change > 0 ? DS.Charts.positive : DS.Charts.negative)
                        }
                    }
                }

                Spacer()

                // Tracking mode badge
                Text(stats.trackingMode.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DS.Semantic.surface)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(DS.Theme.accent, in: Capsule())
            }
        }
        .padding(14)
        .background(DS.Theme.cardTop, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DS.Semantic.border, lineWidth: 1))
    }
}

// MARK: - PR Cards Section

private struct PRCardsSection: View {
    let stats: ExerciseStatistics

    private var displayedPRs: [PRDisplay] {
        var prs: [PRDisplay] = []

        switch stats.trackingMode {
        case .weighted:
            if let e1rm = stats.personalRecords.bestE1RM {
                prs.append(PRDisplay(
                    title: "Best E1RM",
                    value: e1rm.displayText,
                    date: e1rm.date,
                    icon: "chart.line.uptrend.xyaxis",
                    color: DS.Theme.accent
                ))
            }
            if let weight = stats.personalRecords.heaviestWeight {
                prs.append(PRDisplay(
                    title: "Heaviest Weight",
                    value: weight.displayText,
                    date: weight.date,
                    icon: "scalemass.fill",
                    color: DS.Theme.accent
                ))
            }
            if let reps = stats.personalRecords.mostReps {
                prs.append(PRDisplay(
                    title: "Most Reps",
                    value: reps.displayText,
                    date: reps.date,
                    icon: "arrow.clockwise",
                    color: DS.Theme.accent
                ))
            }
            if let volume = stats.personalRecords.bestVolume {
                prs.append(PRDisplay(
                    title: "Best Volume",
                    value: volume.displayText,
                    date: volume.date,
                    icon: "chart.bar.fill",
                    color: DS.Theme.accent
                ))
            }

        case .timed:
            if let hold = stats.personalRecords.longestHold {
                prs.append(PRDisplay(
                    title: "Longest Hold",
                    value: hold.displayText,
                    date: hold.date,
                    icon: "timer",
                    color: DS.Theme.accent
                ))
            }

        case .bodyweight:
            // Show unweighted PRs
            if let reps = stats.personalRecords.mostRepsBodyweight {
                prs.append(PRDisplay(
                    title: "Most Reps (BW)",
                    value: reps.displayText,
                    date: reps.date,
                    icon: "arrow.clockwise",
                    color: DS.Theme.accent
                ))
            }

            // Also show weighted PRs if they exist (e.g., weighted pull-ups)
            if let e1rm = stats.personalRecords.bestE1RM {
                prs.append(PRDisplay(
                    title: "Best E1RM (Weighted)",
                    value: e1rm.displayText,
                    date: e1rm.date,
                    icon: "chart.line.uptrend.xyaxis",
                    color: DS.Charts.push
                ))
            }
            if let weight = stats.personalRecords.heaviestWeight {
                prs.append(PRDisplay(
                    title: "Heaviest Weight",
                    value: weight.displayText,
                    date: weight.date,
                    icon: "scalemass.fill",
                    color: DS.Charts.push
                ))
            }
            if let reps = stats.personalRecords.mostReps {
                prs.append(PRDisplay(
                    title: "Most Reps (Weighted)",
                    value: reps.displayText,
                    date: reps.date,
                    icon: "arrow.clockwise",
                    color: DS.Charts.push
                ))
            }

        case .distance:
            break
        }

        return prs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "trophy.fill")
                    .font(.subheadline)
                    .foregroundStyle(DS.Theme.accent)
                Text("Personal Records")
                    .font(.headline)
                    .foregroundStyle(DS.Semantic.textPrimary)
            }

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(displayedPRs) { pr in
                    PRCard(pr: pr)
                }
            }
        }
    }
}

private struct PRDisplay: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let date: Date
    let icon: String
    let color: Color
}

private struct PRCard: View {
    let pr: PRDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: pr.icon)
                    .font(.caption)
                    .foregroundStyle(pr.color)

                Text(pr.title)
                    .font(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }

            Text(pr.value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DS.Semantic.textPrimary)
                .lineLimit(3)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)

            Text(pr.date, style: .date)
                .font(.caption2)
                .foregroundStyle(DS.Semantic.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            LinearGradient(
                colors: [pr.color.opacity(0.1), pr.color.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(pr.color.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Progress Charts Section

private struct ProgressChartsSection: View {
    let stats: ExerciseStatistics
    @State private var selectedChart: ChartType = .volume

    enum ChartType: String, CaseIterable {
        case volume = "Volume"
        case weight = "Weight"
        case e1rm = "E1RM"

        var icon: String {
            switch self {
            case .volume: return "chart.bar.fill"
            case .weight: return "scalemass.fill"
            case .e1rm: return "chart.line.uptrend.xyaxis"
            }
        }

        /// Get the display label based on tracking mode
        func label(for trackingMode: TrackingMode) -> String {
            switch self {
            case .volume:
                switch trackingMode {
                case .weighted: return "Volume"
                case .bodyweight: return "Reps"
                case .timed: return "Duration"
                case .distance: return "Distance"
                }
            case .weight:
                switch trackingMode {
                case .weighted: return "Weight"
                case .bodyweight: return "Reps/Set"
                case .timed: return "Time/Set"
                case .distance: return "Dist/Set"
                }
            case .e1rm:
                return "E1RM"
            }
        }
    }

    private var availableCharts: [ChartType] {
        var charts: [ChartType] = []
        if !stats.progressData.volumeProgression.isEmpty { charts.append(.volume) }
        if !stats.progressData.weightProgression.isEmpty { charts.append(.weight) }
        if !stats.progressData.e1rmProgression.isEmpty && stats.trackingMode == .weighted {
            charts.append(.e1rm)
        }
        return charts
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Progress Over Time")
                .font(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)

            // Chart selector - horizontal segmented style
            if availableCharts.count > 1 {
                HStack(spacing: 0) {
                    ForEach(availableCharts, id: \.self) { chartType in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedChart = chartType
                            }
                        } label: {
                            Text(chartType.label(for: stats.trackingMode).uppercased())
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(selectedChart == chartType ? DS.Semantic.surface : DS.Semantic.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    selectedChart == chartType ? DS.Theme.accent : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(DS.Theme.cardTop, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(DS.Semantic.border, lineWidth: 1))
            }

            // Chart
            Group {
                switch selectedChart {
                case .volume:
                    VolumeChart(data: stats.progressData.volumeProgression, trackingMode: stats.trackingMode)
                case .weight:
                    WeightChart(data: stats.progressData.weightProgression, trackingMode: stats.trackingMode)
                case .e1rm:
                    E1RMChart(data: stats.progressData.e1rmProgression)
                }
            }
            .frame(height: 220)
            .padding(12)
            .background(DS.Theme.cardTop, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DS.Semantic.border, lineWidth: 1))
        }
    }
}

private struct VolumeChart: View {
    let data: [ProgressPoint]
    let trackingMode: TrackingMode

    private var yAxisLabel: String {
        switch trackingMode {
        case .weighted: return "Volume"
        case .bodyweight: return "Reps"
        case .timed: return "Duration"
        case .distance: return "Distance"
        }
    }

    var body: some View {
        Chart {
            ForEach(data) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value(yAxisLabel, point.value)
                )
                .foregroundStyle(DS.Charts.legs)
                .lineStyle(StrokeStyle(lineWidth: 2.5))

                AreaMark(
                    x: .value("Date", point.date),
                    yStart: .value("Min", 0),
                    yEnd: .value(yAxisLabel, point.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [DS.Charts.legs.opacity(0.3), DS.Charts.legs.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month().day())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let volume = value.as(Double.self) {
                        Text(formatVolume(volume))
                    }
                }
            }
        }
    }

    private func formatVolume(_ v: Double) -> String {
        switch trackingMode {
        case .weighted:
            // Volume in kg (reps × weight)
            if v >= 1000 { return String(format: "%.1fk kg", v / 1000) }
            return String(format: "%.0f kg", v)
        case .bodyweight:
            // Total reps
            return String(format: "%.0f reps", v)
        case .timed:
            // Duration in seconds, format as minutes if large
            if v >= 60 {
                let minutes = v / 60
                return String(format: "%.1f min", minutes)
            }
            return String(format: "%.0f sec", v)
        case .distance:
            // Distance in meters, format as km if large
            if v >= 1000 {
                return String(format: "%.2f km", v / 1000)
            }
            return String(format: "%.0f m", v)
        }
    }
}

private struct WeightChart: View {
    let data: [ProgressPoint]
    let trackingMode: TrackingMode

    private var yAxisUnit: String {
        switch trackingMode {
        case .weighted: return "kg"
        case .bodyweight: return "reps"
        case .timed: return "sec"
        case .distance: return "m"
        }
    }

    private var yAxisLabel: String {
        switch trackingMode {
        case .weighted: return "Weight"
        case .bodyweight: return "Reps"
        case .timed: return "Duration"
        case .distance: return "Distance"
        }
    }

    var body: some View {
        Chart {
            ForEach(data) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value(yAxisLabel, point.value)
                )
                .foregroundStyle(DS.Charts.push)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
                .symbol(.circle)
                .symbolSize(50)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month().day())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let val = value.as(Double.self) {
                        Text(String(format: "%.1f %@", val, yAxisUnit))
                    }
                }
            }
        }
    }
}

private struct E1RMChart: View {
    let data: [ProgressPoint]

    var body: some View {
        Chart {
            ForEach(data) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("E1RM", point.value)
                )
                .foregroundStyle(DS.Theme.accent)
                .lineStyle(StrokeStyle(lineWidth: 2.5))

                AreaMark(
                    x: .value("Date", point.date),
                    yStart: .value("Min", 0),
                    yEnd: .value("E1RM", point.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [DS.Theme.accent.opacity(0.3), DS.Theme.accent.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month().day())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let e1rm = value.as(Double.self) {
                        Text(String(format: "%.1f kg", e1rm))
                    }
                }
            }
        }
    }
}

// MARK: - Statistics Grid Section

private struct StatisticsGridSection: View {
    let stats: ExerciseStatistics

    private var statItems: [StatItem] {
        var items: [StatItem] = []

        // Always show frequency stats
        items.append(StatItem(
            title: "Times Performed",
            value: "\(stats.frequencyStats.totalTimesPerformed)",
            icon: "calendar"
        ))

        // Volume stats (for weighted exercises)
        if stats.trackingMode == .weighted && stats.volumeStats.totalVolume > 0 {
            items.append(StatItem(
                title: "Total Volume",
                value: formatVolume(stats.volumeStats.totalVolume),
                icon: "chart.bar.fill"
            ))
        }

        // Sets and reps
        items.append(StatItem(
            title: "Total Sets",
            value: "\(stats.volumeStats.totalSets)",
            icon: "list.bullet"
        ))

        if stats.volumeStats.totalReps > 0 {
            items.append(StatItem(
                title: "Total Reps",
                value: "\(stats.volumeStats.totalReps)",
                icon: "arrow.clockwise"
            ))
        }

        // Average rest time
        if let avgRest = stats.timeStats.averageRestBetweenSets {
            items.append(StatItem(
                title: "Avg Rest",
                value: formatDuration(avgRest),
                icon: "timer"
            ))
        }

        // Frequency
        if stats.frequencyStats.averagePerWeek > 0 {
            items.append(StatItem(
                title: "Per Week",
                value: String(format: "%.1f×", stats.frequencyStats.averagePerWeek),
                icon: "repeat"
            ))
        }

        // Streak
        if stats.frequencyStats.longestStreak > 0 {
            items.append(StatItem(
                title: "Longest Streak",
                value: "\(stats.frequencyStats.longestStreak) wk",
                icon: "flame.fill"
            ))
        }

        // Time under tension (for timed exercises)
        if stats.trackingMode == .timed && stats.timeStats.totalTimeUnderTension > 0 {
            items.append(StatItem(
                title: "Total TUT",
                value: formatDuration(stats.timeStats.totalTimeUnderTension),
                icon: "clock.fill"
            ))
        }

        return items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Statistics")
                .font(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(statItems) { item in
                    StatCard(item: item)
                }
            }
        }
    }

    private func formatVolume(_ v: Double) -> String {
        if v >= 1000 { return String(format: "%.1fk kg", v / 1000) }
        return String(format: "%.0f kg", v)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let secs = Int(seconds)
        let minutes = secs / 60
        let remainingSecs = secs % 60

        if minutes > 0 {
            return "\(minutes)m \(remainingSecs)s"
        } else {
            return "\(secs)s"
        }
    }
}

private struct StatItem: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let icon: String
}

private struct StatCard: View {
    let item: StatItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: item.icon)
                    .font(.caption2)
                    .foregroundStyle(DS.Theme.accent.opacity(0.7))

                Text(item.title)
                    .font(.caption2)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }

            Text(item.value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(DS.Semantic.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(DS.Theme.cardTop, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(DS.Semantic.border, lineWidth: 1))
    }
}

// MARK: - Recent History Section

private struct RecentHistorySection: View {
    let workouts: [ExerciseWorkoutEntry]
    let exerciseName: String
    @State private var selectedWorkout: ExerciseWorkoutEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent History")
                .font(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)

            VStack(spacing: 10) {
                ForEach(workouts) { workout in
                    Button {
                        selectedWorkout = workout
                    } label: {
                        WorkoutHistoryCard(workout: workout, exerciseName: exerciseName)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(item: $selectedWorkout) { workout in
            ExerciseLogDetailSheet(workout: workout, exerciseName: exerciseName)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - All-Time History Section

private struct AllTimeHistorySection: View {
    let workouts: [ExerciseWorkoutEntry]
    let exerciseName: String
    @Binding var showAll: Bool
    @State private var selectedWorkout: ExerciseWorkoutEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showAll.toggle()
                }
            } label: {
                HStack {
                    Text("All-Time History")
                        .font(.headline)
                        .foregroundStyle(DS.Semantic.textPrimary)

                    Spacer()

                    Text("\(workouts.count) workouts")
                        .font(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)

                    Image(systemName: showAll ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DS.Semantic.textSecondary)
                }
            }
            .buttonStyle(.plain)

            if showAll {
                VStack(spacing: 10) {
                    ForEach(workouts) { workout in
                        Button {
                            selectedWorkout = workout
                        } label: {
                            WorkoutHistoryCard(workout: workout, exerciseName: exerciseName, isCompact: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
        .sheet(item: $selectedWorkout) { workout in
            ExerciseLogDetailSheet(workout: workout, exerciseName: exerciseName)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Workout History Card

private struct WorkoutHistoryCard: View {
    let workout: ExerciseWorkoutEntry
    let exerciseName: String
    var isCompact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.date, style: .date)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DS.Semantic.textPrimary)

                    Text(workout.date, style: .time)
                        .font(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }

                Spacer()

                if workout.isPR, let prType = workout.prType {
                    HStack(spacing: 4) {
                        Image(systemName: "trophy.fill")
                            .font(.caption2)
                        Text(prType)
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(DS.Theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DS.Theme.accent.opacity(0.15), in: Capsule())
                }
            }

            if !isCompact {
                // Show set details
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(workout.sets.prefix(5)) { set in
                        HStack(spacing: 8) {
                            Text("Set \(set.setNumber)")
                                .font(.caption2)
                                .foregroundStyle(DS.Semantic.textSecondary)
                                .frame(width: 45, alignment: .leading)

                            Text(set.displayValue)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(DS.Semantic.textPrimary)

                            if set.isPR {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .foregroundStyle(DS.Theme.accent)
                            }

                            Spacer()

                            if let rest = set.restAfter {
                                Text("Rest: \(Int(rest))s")
                                    .font(.caption2)
                                    .foregroundStyle(DS.Semantic.textSecondary)
                            }
                        }
                    }

                    if workout.sets.count > 5 {
                        Text("+\(workout.sets.count - 5) more sets")
                            .font(.caption2)
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }
                }
            } else {
                // Compact view - just summary
                HStack {
                    Text("\(workout.sets.count) sets")
                        .font(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)

                    if workout.totalVolume > 0 {
                        Text("•")
                            .foregroundStyle(DS.Semantic.textSecondary)
                        Text(String(format: "%.0f kg", workout.totalVolume))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }
                }
            }
        }
        .padding(12)
        .background(
            workout.isPR
                ? LinearGradient(
                    colors: [DS.Theme.accent.opacity(0.08), DS.Theme.accent.opacity(0.03)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                : LinearGradient(colors: [DS.Theme.cardTop, DS.Theme.cardTop], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(workout.isPR ? DS.Theme.accent.opacity(0.4) : DS.Semantic.border, lineWidth: workout.isPR ? 2 : 1)
        )
        .shadow(color: workout.isPR ? DS.Theme.accent.opacity(0.15) : .clear, radius: workout.isPR ? 8 : 0, x: 0, y: 2)
    }
}

// MARK: - Insufficient Data View

private struct InsufficientDataView: View {
    let exerciseName: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(DS.Semantic.textSecondary.opacity(0.5))

            Text("Not enough data yet")
                .font(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)

            Text("Perform \(exerciseName) in at least 2 workouts to see statistics")
                .font(.subheadline)
                .foregroundStyle(DS.Semantic.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(DS.Theme.cardTop, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(DS.Semantic.border, lineWidth: 1))
    }
}

// MARK: - Exercise Log Detail Sheet

private struct ExerciseLogDetailSheet: View {
    let workout: ExerciseWorkoutEntry
    let exerciseName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Date and time header
                    VStack(alignment: .leading, spacing: 4) {
                        Text(workout.date, style: .date)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(DS.Semantic.textPrimary)

                        Text(workout.date, style: .time)
                            .font(.subheadline)
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    // Summary stats
                    HStack(spacing: 12) {
                        SummaryStatPill(value: "\(workout.sets.count)", label: "Sets")

                        let totalReps = workout.sets.reduce(0) { $0 + $1.reps }
                        if totalReps > 0 {
                            SummaryStatPill(value: "\(totalReps)", label: "Reps")
                        }

                        if workout.totalVolume > 0 {
                            SummaryStatPill(value: String(format: "%.0f kg", workout.totalVolume), label: "Volume")
                        }

                        if let avgRest = workout.averageRest, avgRest > 0 {
                            SummaryStatPill(value: formatRestTime(avgRest), label: "Avg Rest")
                        }
                    }
                    .padding(.horizontal, 16)

                    // PR badge if applicable
                    if workout.isPR, let prType = workout.prType {
                        HStack(spacing: 6) {
                            Image(systemName: "trophy.fill")
                                .font(.caption)
                            Text("PR: \(prType)")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(DS.Theme.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(DS.Theme.accent.opacity(0.15), in: Capsule())
                        .padding(.horizontal, 16)
                    }

                    // Sets detail
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Sets")
                            .font(.headline)
                            .foregroundStyle(DS.Semantic.textPrimary)
                            .padding(.horizontal, 16)

                        VStack(spacing: 8) {
                            ForEach(workout.sets) { set in
                                SetDetailRow(set: set)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 16)
            }
            .background(DS.Semantic.surface.ignoresSafeArea())
            .navigationTitle(exerciseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(DS.Theme.accent)
                }
            }
        }
    }

    private func formatRestTime(_ seconds: TimeInterval) -> String {
        let secs = Int(seconds)
        let minutes = secs / 60
        let remainingSecs = secs % 60

        if minutes > 0 {
            return "\(minutes)m \(remainingSecs)s"
        } else {
            return "\(secs)s"
        }
    }
}

private struct SummaryStatPill: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(DS.Semantic.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(DS.Semantic.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(DS.Theme.cardTop, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct SetDetailRow: View {
    let set: SetPerformance

    var body: some View {
        HStack(spacing: 12) {
            // Set number badge
            Text("\(set.setNumber)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(DS.Semantic.surface)
                .frame(width: 24, height: 24)
                .background(set.tag.color, in: Circle())

            // Set details
            VStack(alignment: .leading, spacing: 2) {
                Text(set.displayValue)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DS.Semantic.textPrimary)

                if let rest = set.restAfter, rest > 0 {
                    Text("Rest: \(formatRestDuration(rest))")
                        .font(.caption2)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }
            }

            Spacer()

            // PR star if applicable
            if set.isPR {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(DS.Theme.accent)
            }

            // Tag
            Text(set.tag.short)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(DS.Semantic.surface)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(set.tag.color, in: Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(DS.Theme.cardTop, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(set.isPR ? DS.Theme.accent.opacity(0.4) : DS.Semantic.border, lineWidth: set.isPR ? 2 : 1)
        )
    }

    private func formatRestDuration(_ seconds: TimeInterval) -> String {
        let secs = Int(seconds)
        let minutes = secs / 60
        let remainingSecs = secs % 60

        if minutes > 0 {
            return "\(minutes)m \(remainingSecs)s"
        } else {
            return "\(secs)s"
        }
    }
}
