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
                        .dsFont(.subheadline)
                        .foregroundStyle(DS.Semantic.textSecondary)

                    HStack(spacing: 8) {
                        Image(systemName: stats.progressData.trendDirection.iconName)
                            .dsFont(.caption)
                            .foregroundStyle(trendColor)

                        Text(stats.progressData.trendDirection.displayText)
                            .dsFont(.caption, weight: .medium)
                            .foregroundStyle(trendColor)

                        if let change = stats.progressData.volumeChangePercent, abs(change) > 1 {
                            Text(String(format: "%+.1f%%", change))
                                .dsFont(.caption, monospacedDigits: true)
                                .foregroundStyle(change > 0 ? DS.Charts.positive : DS.Charts.negative)
                        }
                    }
                }

                Spacer()

                // Tracking mode badge
                Text(stats.trackingMode.label)
                    .dsFont(.caption2, weight: .semibold)
                    .foregroundStyle(DS.Semantic.surface)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(DS.Theme.accent)
                    .clipShape(ChamferedRectangleAlt(.micro))
            }
        }
        .padding(14)
        .background(DS.Theme.cardTop, in: ChamferedRectangle(.large))
        .overlay(ChamferedRectangle(.large).stroke(DS.Semantic.border, lineWidth: 1))
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
                    .dsFont(.subheadline)
                    .foregroundStyle(DS.Theme.accent)
                Text("Personal Records")
                    .dsFont(.headline)
                    .foregroundStyle(DS.Semantic.textPrimary)
            }

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(Array(displayedPRs.enumerated()), id: \.element.id) { index, pr in
                    PRCard(pr: pr, useAlt: (index % 2 + index / 2) % 2 == 0)
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

// Applies the correct chamfer shape based on grid position.
// Even checkerboard positions (col+row even) use Alt (TL+BR cuts),
// odd positions use Std (TR+BL cuts), so all inner cuts converge at grid center.
private struct PRCardShape: ViewModifier {
    let useAlt: Bool
    let strokeColor: Color

    func body(content: Content) -> some View {
        if useAlt {
            content
                .clipShape(ChamferedRectangleAlt(.large))
                .overlay(ChamferedRectangleAlt(.large).stroke(strokeColor, lineWidth: 1))
        } else {
            content
                .clipShape(ChamferedRectangle(.large))
                .overlay(ChamferedRectangle(.large).stroke(strokeColor, lineWidth: 1))
        }
    }
}

private struct PRCard: View {
    let pr: PRDisplay
    var useAlt: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: pr.icon)
                    .dsFont(.caption)
                    .foregroundStyle(pr.color)

                Text(pr.title)
                    .dsFont(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }

            Text(pr.value)
                .dsFont(.subheadline, weight: .semibold)
                .foregroundStyle(DS.Semantic.textPrimary)
                .lineLimit(3)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)

            Text(pr.date, style: .date)
                .dsFont(.caption2)
                .foregroundStyle(DS.Semantic.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            LinearGradient(
                colors: [pr.color.opacity(0.1), pr.color.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .modifier(PRCardShape(useAlt: useAlt, strokeColor: pr.color.opacity(0.3)))
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
                .dsFont(.headline)
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
                                .dsFont(.caption, weight: .semibold)
                                .foregroundStyle(selectedChart == chartType ? DS.Semantic.surface : DS.Semantic.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    selectedChart == chartType ? DS.Theme.accent : Color.clear,
                                    in: ChamferedRectangle(.large)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(DS.Theme.cardTop, in: ChamferedRectangle(.large))
                .overlay(ChamferedRectangle(.large).stroke(DS.Semantic.border, lineWidth: 1))
            }

            // Chart
            Group {
                switch selectedChart {
                case .volume:
                    VolumeChart(data: stats.progressData.volumeProgression, trackingMode: stats.trackingMode)
                case .weight:
                    WeightChart(data: stats.progressData.weightProgression, trackingMode: stats.trackingMode)
                case .e1rm:
                    E1RMChart(data: stats.progressData.e1rmProgression, plateauState: stats.progressData.plateauState)
                }
            }
            .frame(height: 220)
            .padding(12)
            .background(DS.Theme.cardTop, in: ChamferedRectangle(.large))
            .overlay(ChamferedRectangle(.large).stroke(DS.Semantic.border, lineWidth: 1))
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
    var plateauState: PlateauState = .none

    // Linear regression on last 6-8 points; returns (slope kg/day, intercept) relative to data.first
    private func linearRegression(_ points: [ProgressPoint]) -> (slope: Double, intercept: Double)? {
        guard points.count >= 2, let origin = points.first else { return nil }
        let n = Double(points.count)
        let xs = points.map { $0.date.timeIntervalSince(origin.date) / 86400.0 }
        let ys = points.map { $0.value }
        let sumX = xs.reduce(0, +), sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).map(*).reduce(0, +)
        let sumX2 = xs.map { $0 * $0 }.reduce(0, +)
        let denom = n * sumX2 - sumX * sumX
        guard abs(denom) > 0 else { return nil }
        let slope = (n * sumXY - sumX * sumY) / denom
        let intercept = (sumY - slope * sumX) / n
        return (slope, intercept)
    }

    private var projectionPoints: [ProgressPoint] {
        guard !plateauState.isPlateaued, let last = data.last, let first = data.first else { return [] }
        let window = Array(data.suffix(8))
        guard let reg = linearRegression(window), reg.slope > 0.005 else { return [] }
        let lastX = last.date.timeIntervalSince(first.date) / 86400.0
        let projectedDate = Calendar.current.date(byAdding: .day, value: 28, to: last.date) ?? last.date
        let projectedY = reg.slope * (lastX + 28) + reg.intercept
        return [
            ProgressPoint(date: last.date, value: last.value),
            ProgressPoint(date: projectedDate, value: max(projectedY, 0))
        ]
    }

    var body: some View {
        let projection = projectionPoints
        let projectedLabel: String? = {
            guard let end = projection.last else { return nil }
            let kg = String(format: "%.1f kg", end.value)
            let date = end.date.formatted(.dateTime.month(.abbreviated).day())
            return "~\(kg) by \(date)"
        }()

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

            if projection.count == 2 {
                ForEach(projection) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("E1RM", point.value)
                    )
                    .foregroundStyle(DS.Semantic.textSecondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                }
                if let end = projection.last, let label = projectedLabel {
                    PointMark(
                        x: .value("Date", end.date),
                        y: .value("E1RM", end.value)
                    )
                    .foregroundStyle(DS.Semantic.textSecondary.opacity(0.5))
                    .annotation(position: .top, alignment: .trailing) {
                        Text(label)
                            .dsFont(.caption2)
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }
                }
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
        items.append(StatItem(title: "Times Performed", value: "\(stats.frequencyStats.totalTimesPerformed)"))

        // Volume stats (for weighted exercises)
        if stats.trackingMode == .weighted && stats.volumeStats.totalVolume > 0 {
            items.append(StatItem(title: "Total Volume", value: formatVolume(stats.volumeStats.totalVolume)))
        }

        // Sets and reps
        items.append(StatItem(title: "Total Sets", value: "\(stats.volumeStats.totalSets)"))

        if stats.volumeStats.totalReps > 0 {
            items.append(StatItem(title: "Total Reps", value: "\(stats.volumeStats.totalReps)"))
        }

        // Average rest time
        if let avgRest = stats.timeStats.averageRestBetweenSets {
            items.append(StatItem(title: "Avg Rest", value: formatDuration(avgRest)))
        }

        // Frequency
        if stats.frequencyStats.averagePerWeek > 0 {
            items.append(StatItem(title: "Per Week", value: String(format: "%.1f×", stats.frequencyStats.averagePerWeek)))
        }

        // Streak
        if stats.frequencyStats.longestStreak > 0 {
            items.append(StatItem(title: "Longest Streak", value: "\(stats.frequencyStats.longestStreak) wk"))
        }

        // Time under tension (for timed exercises)
        if stats.trackingMode == .timed && stats.timeStats.totalTimeUnderTension > 0 {
            items.append(StatItem(title: "Total TUT", value: formatDuration(stats.timeStats.totalTimeUnderTension)))
        }

        return items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Statistics")
                .dsFont(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)

            VStack(spacing: 0) {
                ForEach(Array(statItems.enumerated()), id: \.element.id) { index, item in
                    HStack {
                        Text(item.title)
                            .dsFont(.subheadline)
                            .foregroundStyle(DS.Semantic.textSecondary)
                        Spacer()
                        Text(item.value)
                            .dsFont(.subheadline, weight: .semibold, monospacedDigits: true)
                            .foregroundStyle(DS.Semantic.textPrimary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)

                    if index < statItems.count - 1 {
                        Rectangle()
                            .fill(DS.Semantic.border)
                            .frame(height: 1)
                            .padding(.horizontal, 14)
                    }
                }
            }
            .background(DS.Theme.cardTop, in: ChamferedRectangle(.large))
            .overlay(ChamferedRectangle(.large).stroke(DS.Semantic.border, lineWidth: 1))
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
}

// MARK: - Recent History Section

private struct RecentHistorySection: View {
    let workouts: [ExerciseWorkoutEntry]
    let exerciseName: String
    @State private var selectedWorkout: ExerciseWorkoutEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent History")
                .dsFont(.headline)
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
                        .dsFont(.headline)
                        .foregroundStyle(DS.Semantic.textPrimary)

                    Spacer()

                    Text("\(workouts.count) workouts")
                        .dsFont(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)

                    Image(systemName: showAll ? "chevron.up" : "chevron.down")
                        .dsFont(.caption, weight: .semibold)
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
                        .dsFont(.subheadline, weight: .medium)
                        .foregroundStyle(DS.Semantic.textPrimary)

                    Text(workout.date, style: .time)
                        .dsFont(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }

                Spacer()

                if workout.isPR, let prType = workout.prType {
                    HStack(spacing: 4) {
                        Image(systemName: "trophy.fill")
                            .dsFont(.caption2)
                        Text(prType)
                            .dsFont(.caption2, weight: .semibold)
                    }
                    .foregroundStyle(DS.Theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DS.Theme.accent.opacity(0.15))
                    .clipShape(ChamferedRectangleAlt(.micro))
                }
            }

            if !isCompact {
                // Show set details
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(workout.sets.prefix(5)) { set in
                        HStack(spacing: 8) {
                            Text("Set \(set.setNumber)")
                                .dsFont(.caption2)
                                .foregroundStyle(DS.Semantic.textSecondary)
                                .frame(width: 45, alignment: .leading)

                            Text(set.displayValue)
                                .dsFont(.caption, monospacedDigits: true)
                                .foregroundStyle(DS.Semantic.textPrimary)

                            if set.isPR {
                                Image(systemName: "star.fill")
                                    .dsFont(.caption2)
                                    .foregroundStyle(DS.Theme.accent)
                            }

                            Spacer()

                            if let rest = set.restAfter {
                                Text("Rest: \(Int(rest))s")
                                    .dsFont(.caption2)
                                    .foregroundStyle(DS.Semantic.textSecondary)
                            }
                        }
                    }

                    if workout.sets.count > 5 {
                        Text("+\(workout.sets.count - 5) more sets")
                            .dsFont(.caption2)
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }
                }
            } else {
                // Compact view - just summary
                HStack {
                    Text("\(workout.sets.count) sets")
                        .dsFont(.caption)
                        .foregroundStyle(DS.Semantic.textSecondary)

                    if workout.totalVolume > 0 {
                        Text("•")
                            .foregroundStyle(DS.Semantic.textSecondary)
                        Text(String(format: "%.0f kg", workout.totalVolume))
                            .dsFont(.caption, monospacedDigits: true)
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
                : LinearGradient(colors: [DS.Theme.cardTop, DS.Theme.cardTop], startPoint: .top, endPoint: .bottom)
        )
        .clipShape(ChamferedRectangle(.large))
        .overlay(
            ChamferedRectangle(.large)
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
                .dsFont(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)

            Text("Perform \(exerciseName) in at least 2 workouts to see statistics")
                .dsFont(.subheadline)
                .foregroundStyle(DS.Semantic.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(DS.Theme.cardTop, in: ChamferedRectangle(.large))
        .overlay(ChamferedRectangle(.large).stroke(DS.Semantic.border, lineWidth: 1))
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
                            .dsFont(.title2, weight: .bold)
                            .foregroundStyle(DS.Semantic.textPrimary)

                        Text(workout.date, style: .time)
                            .dsFont(.subheadline)
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
                                .dsFont(.caption)
                            Text("PR: \(prType)")
                                .dsFont(.caption, weight: .semibold)
                        }
                        .foregroundStyle(DS.Theme.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(DS.Theme.accent.opacity(0.15))
                        .clipShape(ChamferedRectangleAlt(.micro))
                        .padding(.horizontal, 16)
                    }

                    // Sets detail
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Sets")
                            .dsFont(.headline)
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

private struct SetDetailRow: View {
    let set: SetPerformance

    var body: some View {
        HStack(spacing: 12) {
            // Set number badge
            Text("\(set.setNumber)")
                .dsFont(.caption, weight: .bold, monospacedDigits: true)
                .foregroundStyle(DS.Semantic.surface)
                .frame(width: 24, height: 24)
                .background(set.tag.color, in: Circle())

            // Set details
            VStack(alignment: .leading, spacing: 2) {
                Text(set.displayValue)
                    .dsFont(.subheadline, weight: .medium)
                    .foregroundStyle(DS.Semantic.textPrimary)

                if let rest = set.restAfter, rest > 0 {
                    Text("Rest: \(formatRestDuration(rest))")
                        .dsFont(.caption2)
                        .foregroundStyle(DS.Semantic.textSecondary)
                }
            }

            Spacer()

            // PR star if applicable
            if set.isPR {
                Image(systemName: "star.fill")
                    .dsFont(.caption)
                    .foregroundStyle(DS.Theme.accent)
            }

            // Tag
            Text(set.tag.short)
                .dsFont(.caption2, weight: .semibold)
                .foregroundStyle(DS.Semantic.surface)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(set.tag.color)
                .clipShape(ChamferedRectangleAlt(.micro))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(DS.Theme.cardTop, in: ChamferedRectangle(.large))
        .overlay(
            ChamferedRectangle(.large)
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
