//
//  ProfileStatsViews.swift
//  WRKT
//

import SwiftUI
import SwiftData
import Charts   // iOS 16+

// MARK: - Public wrapper (easy to embed in ProfileView)
struct ProfileStatsView: View {
    let weeks: Int

    init(weeks: Int = 12) { self.weeks = weeks }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Training trends")
                .font(.headline)

            ProfileChartsView(weeks: weeks)

            // You can add more cards here later (e.g., Conditioning, Sleep, etc.)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Charts + lists bound to SwiftData summaries
struct ProfileChartsView: View {
    @EnvironmentObject private var repo: ExerciseRepository

    // Windowed SwiftData queries (configured in init)
    @Query private var weekly: [WeeklyTrainingSummary]
    @Query private var exVolumes: [ExerciseVolumeSummary]

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
    }

    var body: some View {
        VStack(spacing: 12) {
            // 1) Weekly volume bar chart + totals
            if weekly.isEmpty {
                ContentUnavailableView("No recent training",
                                       systemImage: "chart.bar.xaxis",
                                       description: Text("Complete some workouts to see trends."))
            } else {
                WeeklyVolumeCard(weekly: weekly)
                TrainingTotalsGrid(weekly: weekly)
            }

            // 2) Top lifts (auto: highest total volume in window)
            TopLiftsCard(items: top)
        }
        .onAppear(perform: recomputeTop)
        .onChange(of: exVolumes, perform: { _ in recomputeTop() })
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

        top = ranked.map { (exID, vol) in
            let name = repo.exercise(byID: exID)?.name ?? exID
            return TopLift(exerciseID: exID, name: name, totalVolume: vol)
        }
    }
}

// MARK: - Cards

private struct WeeklyVolumeCard: View {
    let weekly: [WeeklyTrainingSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Weekly volume", systemImage: "chart.bar.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let last = weekly.last {
                    Text(WeekLabel.format(last.weekStart))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Chart(weekly, id: \.weekStart) { w in
                BarMark(
                    x: .value("Week", w.weekStart, unit: .weekOfYear),
                    y: .value("Volume", w.totalVolume)
                )
                .annotation(position: .top, alignment: .center) {
                    if w.totalVolume > 0 {
                        Text(shortVolume(w.totalVolume))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: max(1, weekly.count / 6))) { value in
                    AxisGridLine()
                    AxisValueLabel(WeekLabel.format((value.as(Date.self)) ?? .now),
                                   centered: true)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let n = value.as(Double.self) {
                            Text(shortVolume(n))
                        }
                    }
                }
            }
            .frame(height: 180)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.quaternary))
        }
    }

    private func shortVolume(_ v: Double) -> String {
        // 12.3k style
        switch v {
        case 0..<1000: return String(Int(v))
        default:
            let k = v / 1000
            return String(format: "%.1fk", k)
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
            Label("Top lifts (by volume)", systemImage: "trophy")
                .font(.subheadline.weight(.semibold))

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
                        HStack {
                            Text(item.name)
                                .font(.subheadline)
                                .lineLimit(1)
                            Spacer()
                            Text(pretty(item.totalVolume))
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.quaternary))
                    }
                }
            }
        }
    }

    private func pretty(_ v: Double) -> String {
        v >= 1000 ? String(format: "%.1fk", v/1000) : String(Int(v))
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
}
