//
//  ProfileStatsViews.swift
//  WRKT
//

import SwiftUI
import SwiftData
import Charts   // iOS 16+

// MARK: - Public wrapper (easy to embed in ProfileView)
struct ProfileStatsView: View {
    @EnvironmentObject private var store: WorkoutStore
    @Environment(\.modelContext) private var modelContext

    let weeks: Int
    @State private var isReindexing = false

    init(weeks: Int = 12) { self.weeks = weeks }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Training trends")
                    .font(.headline)

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
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                #endif
            }

            ProfileChartsView(weeks: weeks)

            // You can add more cards here later (e.g., Conditioning, Sleep, etc.)
        }
        .padding(.vertical, 6)
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
         

            // ===== SECTION 1: Training Trends =====
            if weekly.isEmpty {
                ContentUnavailableView("No recent training",
                                       systemImage: "chart.bar.xaxis",
                                       description: Text("Complete some workouts to see trends."))
            } else {
                VolumeWithTrendChart(weekly: weekly, movingAvgs: movingAvgs)

                TrainingTotalsGrid(weekly: weekly)
                    .padding(.top, 4)
            }

            // ===== SECTION 2: Top Performers =====
            TopLiftsCard(items: top)
                .padding(.top, 12)

            // ===== SECTION 3: Training Balance =====
            TrainingBalanceSection(weeks: weeks)
                .padding(.top, 12)
        }
        .onAppear(perform: recomputeTop)
        .onChange(of: exVolumes, perform: { _ in recomputeTop() })
        .onChange(of: trends, perform: { _ in recomputeTop() })
    }

    private func recomputeTop() {
        print("🏋️ recomputeTop: Processing \(exVolumes.count) exercise volumes, \(trends.count) trends")

        // Sum volume per exercise in the window and take top 5
        var byExercise: [String: Double] = [:]
        for row in exVolumes {
            byExercise[row.exerciseID, default: 0] += row.volume
        }
        let ranked = byExercise
            .sorted { $0.value > $1.value }
            .prefix(5)

        print("🏋️ Found \(byExercise.count) unique exercises, top 5: \(ranked.map { $0.key }.joined(separator: ", "))")

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
                volumeChange: trend?.volumeChange
            )
        }

        print("🏋️ Built \(top.count) top lifts")
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
                        Label("Weekly volume", systemImage: "chart.line.uptrend.xyaxis")
                            .font(.subheadline.weight(.semibold))
                        InfoButton(
                            title: "Weekly Volume",
                            message: "This chart shows your total training volume (reps × weight) per week. The blue line is your 4-week moving average. Bars are colored green when above your personal average and orange when below. The shaded area represents ±1 standard deviation from your trend."
                        )
                    }
                    Text("Total volume (reps × kg)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let last = weekly.last, let lastAvg = movingAvgs.last, hasMultipleWeeks {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Week of " + WeekLabel.format(last.weekStart))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if abs(lastAvg.percentChange) > 0.1 {
                            HStack(spacing: 2) {
                                Image(systemName: lastAvg.percentChange > 0 ? "arrow.up.right" : "arrow.down.right")
                                    .font(.caption2)
                                Text(String(format: "%.1f%%", abs(lastAvg.percentChange)))
                                    .font(.caption2.monospacedDigit())
                            }
                            .foregroundStyle(lastAvg.percentChange > 0 ? .green : .red)
                        }
                    }
                }
            }

            // Chart with bars, trend line, and reference line
            Chart {
                // Personal average reference line (only show if multiple weeks)
                if hasMultipleWeeks, let firstAvg = movingAvgs.first {
                    RuleMark(y: .value("Average", firstAvg.personalAvg))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("Personal avg")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(.ultraThinMaterial, in: Capsule())
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
                        .foregroundStyle(.blue.opacity(0.05))
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
                    .foregroundStyle(hasMultipleWeeks ? barColor(for: w.totalVolume, movingAvg: ma) : Color.blue)
                    .opacity(0.85)
                }

                // 4-week moving average trend line (only show with 3+ weeks)
                if showTrendLine {
                    ForEach(movingAvgs, id: \.weekStart) { ma in
                        LineMark(
                            x: .value("Week", ma.weekStart, unit: .weekOfYear),
                            y: .value("Trend", ma.fourWeekAvg)
                        )
                        .foregroundStyle(.blue)
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
                                .font(.caption2)
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
                                .font(.caption2)
                        }
                    }
                }
            }
            .frame(height: hasMultipleWeeks ? 200 : 160)
            .padding(.leading, 8)
            .padding(.trailing, 8)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.quaternary))

            // Legend (only show if we have trend analysis)
            if hasMultipleWeeks {
                HStack(spacing: 16) {
                    LegendItem(color: .green.opacity(0.7), label: "Above avg")
                    if showTrendLine {
                        LegendItem(color: .blue, label: "4-week trend", isLine: true)
                    }
                    LegendItem(color: .secondary.opacity(0.5), label: "Personal avg", isDashed: true)
                }
                .font(.caption2)
                .padding(.top, 4)
            } else {
                // Explanation for single week
                Text("Complete more workouts across different weeks to see trends")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    private func barColor(for volume: Double, movingAvg: MovingAverage?) -> Color {
        guard let ma = movingAvg else { return .gray }
        if ma.isAboveAverage {
            return .green.opacity(0.7)
        } else {
            return .orange.opacity(0.7)
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
                .foregroundStyle(.secondary)
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
                StatPill(title: "Volume",   value: prettyVolume(t.volume))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label("Top lifts (by volume)", systemImage: "trophy")
                    .font(.subheadline.weight(.semibold))
                InfoButton(
                    title: "Top Lifts",
                    message: "Your top 5 exercises ranked by total training volume in the selected period. Arrows indicate trend direction (improving/declining) based on recent 4-week comparison. Percentage shows volume change."
                )
            }

            if items.isEmpty {
                Text("No data yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.quaternary))
            } else {
                VStack(spacing: 8) {
                    ForEach(items) { item in
                        HStack(spacing: 8) {
                            // Trend indicator
                            if let direction = item.trendDirection {
                                trendIcon(for: direction)
                                    .font(.caption)
                                    .frame(width: 20)
                            }

                            // Exercise name
                            Text(item.name)
                                .font(.subheadline)
                                .lineLimit(1)

                            Spacer()

                            // Volume with optional change percentage
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(pretty(item.totalVolume))
                                    .font(.footnote.monospacedDigit())
                                    .foregroundStyle(.primary)

                                if let change = item.volumeChange, abs(change) >= 5 {
                                    Text(String(format: "%+.0f%%", change))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(change > 0 ? .green : .red)
                                }
                            }
                        }
                        .padding(10)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.quaternary))
                    }
                }
            }
        }
    }

    private func trendIcon(for direction: String) -> some View {
        Group {
            switch direction {
            case "improving":
                Image(systemName: "arrow.up.right")
                    .foregroundStyle(.green)
            case "declining":
                Image(systemName: "arrow.down.right")
                    .foregroundStyle(.red)
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
                .font(.caption)
                .foregroundStyle(.secondary)
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
            Text(value).font(.headline.monospacedDigit())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.quaternary))
    }
}

private enum WeekLabel {
    static let df: DateFormatter = {
        let df = DateFormatter()
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
}
