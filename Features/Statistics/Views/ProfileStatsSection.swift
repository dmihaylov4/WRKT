//
//  ProfileStatsViews.swift
//  WRKT
//

import SwiftUI
import SwiftData
import Charts   // iOS 16+

enum ProfileSectionIconKind: CaseIterable {
    case trainingTrends
    case trainingBalance
    case achievementCup

    var accessibilityLabel: String {
        switch self {
        case .trainingTrends:
            return "Training trends"
        case .trainingBalance:
            return "Training balance"
        case .achievementCup:
            return "Achievement cup"
        }
    }
}

struct ProfileSectionIcon: View {
    let kind: ProfileSectionIconKind
    var color: Color = DS.Theme.accent
    var size: CGFloat = 24

    var body: some View {
        icon
            .frame(width: size, height: size)
            .foregroundStyle(color)
            .accessibilityLabel(kind.accessibilityLabel)
    }

    @ViewBuilder
    private var icon: some View {
        switch kind {
        case .trainingTrends:
            TrainingTrendsIcon()
        case .trainingBalance:
            TrainingBalanceIcon()
        case .achievementCup:
            AchievementCupIcon()
                .offset(y: -2)
        }
    }
}

private struct TrainingTrendsIcon: View {
    var body: some View {
        ZStack {
            HStack(alignment: .bottom, spacing: 3) {
                Capsule()
                    .frame(width: 3, height: 7)
                Capsule()
                    .frame(width: 3, height: 11)
                Capsule()
                    .frame(width: 3, height: 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.leading, 3)
            .padding(.bottom, 3)
            .opacity(0.75)

            Path { path in
                path.move(to: CGPoint(x: 5, y: 16))
                path.addLine(to: CGPoint(x: 10, y: 11))
                path.addLine(to: CGPoint(x: 14, y: 13))
                path.addLine(to: CGPoint(x: 20, y: 6))
            }
            .stroke(style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

            Circle()
                .frame(width: 3.5, height: 3.5)
                .position(x: 20, y: 6)
        }
    }
}

private struct TrainingBalanceIcon: View {
    var body: some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: 4, y: 8))
                path.addLine(to: CGPoint(x: 20, y: 8))
                path.move(to: CGPoint(x: 12, y: 8))
                path.addLine(to: CGPoint(x: 12, y: 16))
            }
            .stroke(style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

            Path { path in
                path.move(to: CGPoint(x: 12, y: 15))
                path.addLine(to: CGPoint(x: 17, y: 21))
                path.addLine(to: CGPoint(x: 7, y: 21))
                path.closeSubpath()
            }
            .fill()

            HStack(spacing: 10) {
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .frame(width: 5, height: 9)
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .frame(width: 7, height: 3)
                }

                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .frame(width: 5, height: 9)
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .frame(width: 7, height: 3)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 9)
        }
    }
}

private struct AchievementCupIcon: View {
    var body: some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: 8, y: 7))
                path.addLine(to: CGPoint(x: 16, y: 7))
                path.addCurve(
                    to: CGPoint(x: 14, y: 16),
                    control1: CGPoint(x: 16, y: 12),
                    control2: CGPoint(x: 15.4, y: 14.8)
                )
                path.addLine(to: CGPoint(x: 10, y: 16))
                path.addCurve(
                    to: CGPoint(x: 8, y: 7),
                    control1: CGPoint(x: 8.6, y: 14.8),
                    control2: CGPoint(x: 8, y: 12)
                )
                path.closeSubpath()
            }
            .fill()

            Path { path in
                path.move(to: CGPoint(x: 8.3, y: 9.2))
                path.addCurve(
                    to: CGPoint(x: 4.5, y: 10.2),
                    control1: CGPoint(x: 6.2, y: 8.2),
                    control2: CGPoint(x: 4.5, y: 8.7)
                )
                path.addCurve(
                    to: CGPoint(x: 9, y: 14),
                    control1: CGPoint(x: 4.5, y: 12.4),
                    control2: CGPoint(x: 6.8, y: 14)
                )

                path.move(to: CGPoint(x: 15.7, y: 9.2))
                path.addCurve(
                    to: CGPoint(x: 19.5, y: 10.2),
                    control1: CGPoint(x: 17.8, y: 8.2),
                    control2: CGPoint(x: 19.5, y: 8.7)
                )
                path.addCurve(
                    to: CGPoint(x: 15, y: 14),
                    control1: CGPoint(x: 19.5, y: 12.4),
                    control2: CGPoint(x: 17.2, y: 14)
                )
            }
            .stroke(style: StrokeStyle(lineWidth: 2.3, lineCap: .round, lineJoin: .round))

            Path { path in
                path.move(to: CGPoint(x: 12, y: 15))
                path.addLine(to: CGPoint(x: 12, y: 19))
                path.move(to: CGPoint(x: 8.5, y: 20))
                path.addLine(to: CGPoint(x: 15.5, y: 20))
                path.move(to: CGPoint(x: 6.5, y: 22))
                path.addLine(to: CGPoint(x: 17.5, y: 22))
            }
            .stroke(style: StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Public wrapper (easy to embed in ProfileView)
struct ProfileStatsView: View {
    @EnvironmentObject private var store: WorkoutStoreV2
    @Environment(\.modelContext) private var modelContext

    let weeks: Int
    @State private var isReindexing = false

    init(weeks: Int = 12) { self.weeks = weeks }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Premium section header
            HStack(alignment: .center, spacing: 12) {
                // Icon with gradient background
                ZStack {
                    LinearGradient(
                        colors: [DS.Theme.accent.opacity(0.3), DS.Theme.accent.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    ProfileSectionIcon(kind: .trainingTrends)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Training Trends")
                        .dsFont(.title3, weight: .bold)
                        .foregroundStyle(.white)

                    Text("Last \(weeks) weeks")
                        .dsFont(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer()

                #if DEBUG
                Button {
                    Task {
                        isReindexing = true
                        if let stats = await getStatsAggregator() {
                            if let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -weeks, to: .now) {
                                await stats.reindex(all: store.completedWorkouts, cutoff: cutoff)
                            }
                        }
                        isReindexing = false
                    }
                } label: {
                    if isReindexing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white.opacity(0.6))
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .dsFont(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .buttonStyle(.plain)
                #endif
            }
            .padding(.bottom, 4)

            ProfileChartsView(weeks: weeks)
        }
        .padding(10)
        .background(
            ChamferedRectangle(.xl)
                .fill(Color.black)
                .overlay(
                    ChamferedRectangle(.xl)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func getStatsAggregator() async -> StatsAggregator? {
        return await MainActor.run {
            store.stats
        }
    }
}

// MARK: - Charts + lists bound to SwiftData summaries
struct ProfileChartsView: View {
    @EnvironmentObject private var repo: ExerciseRepository

    // Windowed SwiftData queries (configured in init)
    @Query private var weekly: [WeeklyTrainingSummary]
    @Query private var exVolumes: [ExerciseVolumeSummary]
    @Query private var movingAvgs: [MovingAverage]
    @Query private var trends: [ExerciseTrend]

    // Derived UI state
    @State private var top: [TopLift] = []
    private let weeks: Int

    init(weeks: Int = 12) {
        self.weeks = weeks

        // compute cutoff OUTSIDE the predicate (important!)
        let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -weeks, to: .now) ?? .distantPast

        _weekly = Query(
            filter: #Predicate<WeeklyTrainingSummary> { $0.weekStart >= cutoff },
            sort: \WeeklyTrainingSummary.weekStart,
            order: .forward
        )

        _exVolumes = Query(
            filter: #Predicate<ExerciseVolumeSummary> { $0.weekStart >= cutoff },
            sort: \ExerciseVolumeSummary.weekStart,
            order: .forward
        )

        _movingAvgs = Query(
            filter: #Predicate<MovingAverage> { $0.weekStart >= cutoff },
            sort: \MovingAverage.weekStart,
            order: .forward
        )
    }

    var body: some View {
        VStack(spacing: 16) {
            // ===== SECTION 1: Volume Chart & Totals =====
            if weekly.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(.white.opacity(0.3))

                    Text("No recent training")
                        .dsFont(.headline)
                        .foregroundStyle(.white.opacity(0.9))

                    Text("Complete some workouts to see trends")
                        .dsFont(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                VolumeWithTrendChart(weekly: weekly, movingAvgs: movingAvgs)

                TrainingTotalsGrid(weekly: weekly)
                    .padding(.top, 4)
            }

            if !weekly.isEmpty && !top.isEmpty {
                Divider()
                    .background(.white.opacity(0.08))
            }

            // ===== SECTION 2: Top Performers =====
            if !top.isEmpty {
                TopLiftsCard(items: top)
            }

            // Note: TrainingBalanceSection is now rendered separately in ProfileView
        }
        .onAppear(perform: recomputeTop)
        .onChange(of: exVolumes, perform: { _ in recomputeTop() })
        .onChange(of: trends, perform: { _ in recomputeTop() })
    }

    private func recomputeTop() {
        

        // Sum volume per exercise in the window and take top 5
        var byExercise: [String: Double] = [:]
        for row in exVolumes {
            byExercise[row.exerciseID, default: 0] += row.volume
        }
        let ranked = byExercise
            .sorted { $0.value > $1.value }
            .prefix(5)

       

        // Build trend lookup
        let trendLookup = Dictionary(uniqueKeysWithValues: trends.map { ($0.exerciseID, $0) })

        top = ranked.map { (exID, vol) in
            let name = repo.exercise(byID: exID)?.name ?? exID
            let trend = trendLookup[exID]
            return TopLift(
                exerciseID: exID,
                name: name,
                totalVolume: vol,
                trendDirection: trend?.trendDirection,
                volumeChange: trend?.volumeChange,
                lowConfidence: trend?.lowConfidence ?? false
            )
        }

       
    }
}

// MARK: - Enhanced Volume Chart with Trend Analysis
private struct VolumeWithTrendChart: View {
    let weekly: [WeeklyTrainingSummary]
    let movingAvgs: [MovingAverage]

    // Determine if we have enough data for full trend analysis
    private var hasMultipleWeeks: Bool { weekly.count > 1 }
    private var showTrendLine: Bool { weekly.count >= 3 }
    private var showStdDevBands: Bool { weekly.count >= 4 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with summary stats
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Label("Weekly Tonnage", systemImage: "chart.line.uptrend.xyaxis")
                            .dsFont(.subheadline, weight: .semibold)
                            .foregroundStyle(.white.opacity(0.9))
                        InfoButton(
                            title: "Weekly Tonnage",
                            message: "Total load lifted across all working sets each week (reps × weight). Useful for spotting big changes in your overall workload. Not a direct measure of strength or muscle growth."
                        )
                    }
                    Text("reps × kg (working sets)")
                        .dsFont(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                if let last = weekly.last, let lastAvg = movingAvgs.last, hasMultipleWeeks {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Week of " + WeekLabel.format(last.weekStart))
                            .dsFont(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                        if abs(lastAvg.percentChange) > 0.1 {
                            HStack(spacing: 2) {
                                Image(systemName: lastAvg.percentChange > 0 ? "arrow.up.right" : "arrow.down.right")
                                    .dsFont(.caption2)
                                Text(String(format: "%.1f%%", abs(lastAvg.percentChange)))
                                    .dsFont(.caption2, monospacedDigits: true)
                            }
                            .foregroundStyle(lastAvg.percentChange > 0 ? DS.Charts.positive : DS.Charts.negative)
                        }
                    }
                }
            }

            // Chart with bars, trend line, and reference line
            Chart {
                // Personal average reference line (only show if multiple weeks)
                // Use last (most recent) to get the most up-to-date personal average
                if hasMultipleWeeks, let latestAvg = movingAvgs.last {
                    RuleMark(y: .value("Average", latestAvg.personalAvg))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("Personal avg")
                                .dsFont(.caption2)
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(.white.opacity(0.1), in: Capsule())
                        }
                }

                // Standard deviation band (only show with 4+ weeks)
                if showStdDevBands {
                    ForEach(movingAvgs, id: \.weekStart) { ma in
                        RectangleMark(
                            x: .value("Week", ma.weekStart, unit: .weekOfYear),
                            yStart: .value("Lower", max(0, ma.fourWeekAvg - ma.stdDev)),
                            yEnd: .value("Upper", ma.fourWeekAvg + ma.stdDev),
                            width: 5
                        )
                        .foregroundStyle(DS.Charts.legs.opacity(0.05))
                    }
                }

                // Weekly volume bars (color-coded by performance)
                ForEach(weekly, id: \.weekStart) { w in
                    let ma = movingAvgs.first(where: { $0.weekStart == w.weekStart })
                    BarMark(
                        x: .value("Week", w.weekStart, unit: .weekOfYear),
                        y: .value("Volume", w.totalVolume),
                        width: hasMultipleWeeks ? .automatic : .fixed(40)
                    )
                    .foregroundStyle(hasMultipleWeeks ? barColor(for: w.totalVolume, movingAvg: ma) : DS.Charts.legs)
                    .opacity(0.85)
                }

                // 4-week moving average trend line (only show with 3+ weeks)
                if showTrendLine {
                    ForEach(movingAvgs, id: \.weekStart) { ma in
                        LineMark(
                            x: .value("Week", ma.weekStart, unit: .weekOfYear),
                            y: .value("Trend", ma.fourWeekAvg)
                        )
                        .foregroundStyle(DS.Charts.legs)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .symbol(.circle)
                        .symbolSize(40)
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: hasMultipleWeeks ? max(1, weekly.count / 6) : 1)) { value in
                    AxisGridLine()
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(hasMultipleWeeks ? WeekLabel.format(date) : "Week of " + WeekLabel.format(date))
                                .dsFont(.caption2)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let n = value.as(Double.self) {
                            Text(shortVolume(n))
                                .dsFont(.caption2)
                        }
                    }
                }
            }
            .frame(height: hasMultipleWeeks ? 200 : 160)
            .padding(.leading, 8)
            .padding(.trailing, 8)
            .padding(.vertical, 12)
            .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))

            // Legend (only show if we have trend analysis)
            if hasMultipleWeeks {
                HStack(spacing: 16) {
                    LegendItem(color: DS.Charts.positive, label: "Above avg")
                    if showTrendLine {
                        LegendItem(color: DS.Charts.legs, label: "4-week trend", isLine: true)
                    }
                    LegendItem(color: .white.opacity(0.5), label: "Personal avg", isDashed: true)
                }
                .dsFont(.caption2)
                .padding(.top, 4)
            } else {
                // Explanation for single week
                Text("Complete more workouts across different weeks to see trends")
                    .dsFont(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.top, 4)
            }
        }
    }

    private func barColor(for volume: Double, movingAvg: MovingAverage?) -> Color {
        guard let ma = movingAvg else { return .gray }
        if ma.isAboveAverage {
            return DS.Charts.positive
        } else {
            return DS.Charts.pull.opacity(0.7)
        }
    }

    private func shortVolume(_ v: Double) -> String {
        switch v {
        case 0..<1000: return String(Int(v))
        default: return String(format: "%.1fk", v / 1000)
        }
    }
}

// MARK: - Chart Legend Item
private struct LegendItem: View {
    let color: Color
    let label: String
    var isLine: Bool = false
    var isDashed: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if isLine {
                Rectangle()
                    .fill(color)
                    .frame(width: 16, height: 2)
            } else if isDashed {
                Rectangle()
                    .fill(color)
                    .frame(width: 16, height: 1)
                    .overlay(
                        Rectangle()
                            .stroke(color, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    )
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 10, height: 10)
            }
            Text(label)
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}

private struct TrainingTotalsGrid: View {
    let weekly: [WeeklyTrainingSummary]

    private var totals: (volume: Double, sessions: Int, sets: Int, reps: Int, minutes: Int) {
        weekly.reduce(into: (0, 0, 0, 0, 0)) { acc, w in
            acc.volume  += w.totalVolume
            acc.sessions += w.sessions
            acc.sets    += w.totalSets
            acc.reps    += w.totalReps
            acc.minutes += w.minutes
        }
    }

    var body: some View {
        let t = totals
        Grid(horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                StatPill(title: "Sessions", value: "\(t.sessions)")
                StatPill(title: "Sets",     value: "\(t.sets)")
                StatPill(title: "Reps",     value: "\(t.reps)")
            }
            GridRow {
                let hasBodyweightEst = weekly.contains { $0.containsBodyweightEstimates }
                VStack(spacing: 2) {
                    StatPill(title: "Volume", value: prettyVolume(t.volume))
                    if hasBodyweightEst {
                        DataQualityBadge(quality: .bodyweightEst)
                    }
                }
                StatPill(title: "Minutes",  value: "\(t.minutes)")
                Spacer().gridCellUnsizedAxes([.horizontal, .vertical])
            }
        }
    }

    private func prettyVolume(_ v: Double) -> String {
        if v >= 1000 { return String(format: "%.1fk", v/1000) }
        return String(Int(v))
    }
}

private struct TopLiftsCard: View {
    let items: [TopLift]
    @EnvironmentObject var repo: ExerciseRepository
    @State private var selectedExercise: SelectedExerciseInfo?

    // Helper struct to hold exercise info
    struct SelectedExerciseInfo: Identifiable {
        let id = UUID()
        let exerciseID: String
        let exerciseName: String
        let trackingMode: TrackingMode
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label("Top lifts (by volume)", systemImage: "trophy")
                    .dsFont(.subheadline, weight: .semibold)
                    .foregroundStyle(.white.opacity(0.9))
                InfoButton(
                    title: "Top Lifts",
                    message: "Your top 5 exercises ranked by total training volume in the selected period. Arrows indicate trend direction (improving/declining) based on recent 4-week comparison. Percentage shows volume change. Tap to view detailed statistics."
                )
            }

            if items.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .dsFont(.title3)
                        .foregroundStyle(.white.opacity(0.4))

                    Text("No data yet")
                        .dsFont(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))

                    Spacer()
                }
                .padding(16)
                .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
            } else {
                VStack(spacing: 8) {
                    ForEach(items) { item in
                        Button {
                            // Lookup exercise info NOW (while repo is available)
                            // and store all needed data to avoid race conditions
                            AppLogger.debug("Tapping top lift: \(item.name) (ID: \(item.exerciseID))", category: AppLogger.statistics)

                            if let exercise = repo.exercise(byID: item.exerciseID) {
                                AppLogger.debug("Found exercise in repo: \(exercise.name), trackingMode: \(exercise.trackingMode)", category: AppLogger.statistics)
                                selectedExercise = SelectedExerciseInfo(
                                    exerciseID: exercise.id,
                                    exerciseName: exercise.name,
                                    trackingMode: TrackingMode(rawValue: exercise.trackingMode) ?? .weighted
                                )
                            } else {
                                AppLogger.warning("Exercise not found in repo, using fallback data for: \(item.name)", category: AppLogger.statistics)
                                selectedExercise = SelectedExerciseInfo(
                                    exerciseID: item.exerciseID,
                                    exerciseName: item.name,
                                    trackingMode: .weighted  // Assume weighted for top lifts
                                )
                            }

                            AppLogger.debug("Created SelectedExerciseInfo: \(selectedExercise?.exerciseName ?? "nil")", category: AppLogger.statistics)
                        } label: {
                            HStack(spacing: 8) {
                                // Trend indicator
                                if let direction = item.trendDirection {
                                    if item.lowConfidence {
                                        Image(systemName: "questionmark")
                                            .dsFont(.caption)
                                            .foregroundStyle(DS.Semantic.textSecondary)
                                            .frame(width: 20)
                                    } else {
                                        trendIcon(for: direction)
                                            .dsFont(.caption)
                                            .frame(width: 20)
                                    }
                                }

                                // Exercise name
                                Text(item.name)
                                    .dsFont(.subheadline)
                                    .foregroundStyle(.white.opacity(0.9))
                                    .lineLimit(1)

                                Spacer()

                                // Volume with optional change percentage
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(pretty(item.totalVolume))
                                        .dsFont(.footnote, monospacedDigits: true)
                                        .foregroundStyle(.white.opacity(0.95))

                                    if item.lowConfidence {
                                        Text("low data")
                                            .dsFont(.caption2)
                                            .foregroundStyle(DS.Semantic.textSecondary)
                                    } else if let change = item.volumeChange, abs(change) >= 5 {
                                        Text(String(format: "%+.0f%%", change))
                                            .dsFont(.caption2, monospacedDigits: true)
                                            .foregroundStyle(change > 0 ? DS.Charts.positive : DS.Charts.negative)
                                    }
                                }

                                // Chevron indicator
                                Image(systemName: "chevron.right")
                                    .dsFont(.caption2)
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                            .padding(10)
                            .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .sheet(item: $selectedExercise) { exerciseInfo in
            NavigationStack {
                ExerciseStatisticsView(
                    exerciseID: exerciseInfo.exerciseID,
                    exerciseName: exerciseInfo.exerciseName,
                    trackingMode: exerciseInfo.trackingMode
                )
                .withDependencies()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private func trendIcon(for direction: String) -> some View {
        Group {
            switch direction {
            case "improving":
                Image(systemName: "arrow.up.right")
                    .foregroundStyle(DS.Charts.positive)
            case "declining":
                Image(systemName: "arrow.down.right")
                    .foregroundStyle(DS.Charts.negative)
            default:
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func pretty(_ v: Double) -> String {
        v >= 1000 ? String(format: "%.1fk", v/1000) : String(Int(v))
    }
}

// MARK: - Info Button Component

private struct InfoButton: View {
    let title: String
    let message: String
    @State private var showingAlert = false

    var body: some View {
        Button {
            showingAlert = true
        } label: {
            Image(systemName: "info.circle")
                .dsFont(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
        .buttonStyle(.plain)
        .alert(title, isPresented: $showingAlert) {
            Button("Got it", role: .cancel) {}
        } message: {
            Text(message)
        }
    }
}

// MARK: - Small pieces

private struct StatPill: View {
    let title: String
    let value: String
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .dsFont(.headline, monospacedDigits: true)
                .foregroundStyle(.white.opacity(0.95))
            Text(title)
                .dsFont(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1))
    }
}

private enum WeekLabel {
    static let df: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US")
        df.setLocalizedDateFormatFromTemplate("MMM d")
        return df
    }()
    static func format(_ date: Date) -> String { df.string(from: date) }
}

// MARK: - Local lightweight model used by UI
struct TopLift: Identifiable, Hashable {
    var id: String { exerciseID }
    let exerciseID: String
    let name: String
    let totalVolume: Double
    let trendDirection: String?      // "improving", "stable", "declining"
    let volumeChange: Double?        // % change
    let lowConfidence: Bool          // fewer samples than ideal
}
