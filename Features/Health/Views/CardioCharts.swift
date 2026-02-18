//
//  CardioCharts.swift
//  WRKT
//
//  Shared chart components for cardio data display (used by CardioDetailView & PostDetailView)
//

import SwiftUI
import Charts

// MARK: - Splits Chart

struct SplitsChart: View {
    let splits: [KilometerSplit]

    private var avgPace: Int {
        guard !splits.isEmpty else { return 0 }
        return splits.map(\.paceSecPerKm).reduce(0, +) / splits.count
    }

    private var minPace: Int { splits.map(\.paceSecPerKm).min() ?? 0 }
    private var maxPace: Int { splits.map(\.paceSecPerKm).max() ?? 0 }

    @State private var selectedSplit: KilometerSplit?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Kilometer Splits")
                .font(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)

            if splits.isEmpty {
                Text("No split data available")
                    .font(.subheadline)
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                Chart {
                    ForEach(splits) { split in
                        BarMark(
                            x: .value("KM", "KM \(split.number)"),
                            y: .value("Pace", split.paceSecPerKm)
                        )
                        .foregroundStyle(splitColor(for: split.paceSecPerKm))
                        .cornerRadius(4)
                    }

                    // Average pace line
                    RuleMark(y: .value("Avg", avgPace))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                        .foregroundStyle(DS.Semantic.textSecondary.opacity(0.6))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("Avg \(paceString(avgPace))")
                                .font(.caption2)
                                .foregroundStyle(DS.Semantic.textSecondary)
                        }
                }
                .chartYScale(domain: (minPace - 15)...(maxPace + 15))
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let intValue = value.as(Int.self) {
                                Text(paceString(intValue))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel()
                            .font(.caption2)
                    }
                }
                .frame(height: 200)
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture { location in
                                if let plotFrame = proxy.plotFrame {
                                    let relX = location.x - geo[plotFrame].origin.x
                                    if let category: String = proxy.value(atX: relX),
                                       let split = splits.first(where: { "KM \($0.number)" == category }) {
                                        selectedSplit = (selectedSplit?.id == split.id) ? nil : split
                                    }
                                }
                            }
                    }
                }

                // Selected split detail
                if let split = selectedSplit {
                    HStack(spacing: 16) {
                        Label("KM \(split.number)", systemImage: "mappin.circle.fill")
                            .font(.caption.bold())
                            .foregroundStyle(DS.Semantic.brand)

                        Text(paceString(split.paceSecPerKm) + " /km")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(DS.Semantic.textPrimary)

                        if split.distanceKm < 1.0 {
                            Text(String(format: "%.2f km", split.distanceKm))
                                .font(.caption)
                                .foregroundStyle(DS.Semantic.textSecondary)
                        }

                        Spacer()

                        Text(formatDuration(split.durationSec))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }
                    .padding(10)
                    .background(DS.Semantic.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(16)
        .background(DS.Semantic.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.Semantic.border, lineWidth: 1))
    }

    private func splitColor(for pace: Int) -> Color {
        guard maxPace > minPace else { return DS.Semantic.brand }
        let range = Double(maxPace - minPace)
        let normalized = Double(pace - minPace) / range // 0 = fastest, 1 = slowest
        if normalized < 0.33 {
            return .green
        } else if normalized < 0.66 {
            return DS.Semantic.brand
        } else {
            return .orange
        }
    }

    private func paceString(_ spk: Int) -> String {
        let m = spk / 60
        let s = spk % 60
        return String(format: "%d:%02d", m, s)
    }

    private func formatDuration(_ sec: Int) -> String {
        let m = sec / 60
        let s = sec % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - HR Zone Chart

struct HRZoneChart: View {
    let zones: [HRZoneSummary]
    let samples: [HeartRateSample]?

    private var totalMinutes: Double {
        zones.reduce(0) { $0 + $1.minutes }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Stacked zone bar
            if !zones.isEmpty && totalMinutes > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Time in Zones")
                        .font(.headline)
                        .foregroundStyle(DS.Semantic.textPrimary)

                    // Horizontal stacked bar
                    GeometryReader { geo in
                        HStack(spacing: 1) {
                            ForEach(zones.filter { $0.minutes > 0 }.sorted { $0.zone < $1.zone }) { zone in
                                let fraction = zone.minutes / totalMinutes
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(hex: zone.colorHex))
                                    .frame(width: max(geo.size.width * fraction, 4))
                            }
                        }
                    }
                    .frame(height: 14)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                    // Zone rows
                    ForEach(zones.sorted { $0.zone < $1.zone }) { zone in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(hex: zone.colorHex))
                                .frame(width: 10, height: 10)

                            Text("Z\(zone.zone)")
                                .font(.caption.bold())
                                .foregroundStyle(DS.Semantic.textPrimary)
                                .frame(width: 24, alignment: .leading)

                            Text(zone.name)
                                .font(.caption)
                                .foregroundStyle(DS.Semantic.textSecondary)

                            Spacer()

                            if totalMinutes > 0 {
                                Text(String(format: "%.0f%%", (zone.minutes / totalMinutes) * 100))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(DS.Semantic.textSecondary)
                                    .frame(width: 36, alignment: .trailing)
                            }

                            Text(String(format: "%.0fm", zone.minutes))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(DS.Semantic.textPrimary)
                                .frame(width: 32, alignment: .trailing)

                            Text(zone.rangeDisplay)
                                .font(.caption2)
                                .foregroundStyle(DS.Semantic.textSecondary)
                                .frame(width: 75, alignment: .trailing)
                        }
                    }
                }
            } else {
                Text("No heart rate zone data")
                    .font(.subheadline)
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            }

            // HR over time line chart (if samples available)
            if let samples = samples, samples.count > 2 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Heart Rate Over Time")
                        .font(.subheadline.bold())
                        .foregroundStyle(DS.Semantic.textPrimary)

                    Chart {
                        ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                            LineMark(
                                x: .value("Time", sample.timestamp),
                                y: .value("BPM", sample.bpm)
                            )
                            .foregroundStyle(DS.Semantic.brand)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                            .interpolationMethod(.catmullRom)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let intValue = value.as(Int.self) {
                                    Text("\(intValue)")
                                        .font(.caption2)
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.hour().minute())
                                .font(.caption2)
                        }
                    }
                    .frame(height: 150)
                }
            }
        }
        .padding(16)
        .background(DS.Semantic.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.Semantic.border, lineWidth: 1))
    }
}

// MARK: - Running Dynamics Grid

struct RunningDynamicsGrid: View {
    let avgPower: Double?
    let avgCadence: Double?
    let avgStrideLength: Double?
    let avgGroundContactTime: Double?
    let avgVerticalOscillation: Double?

    private var hasAnyData: Bool {
        [avgPower, avgCadence, avgStrideLength, avgGroundContactTime, avgVerticalOscillation]
            .contains { $0 != nil }
    }

    var body: some View {
        if hasAnyData {
            VStack(alignment: .leading, spacing: 10) {
                Text("Running Dynamics")
                    .font(.headline)
                    .foregroundStyle(DS.Semantic.textPrimary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    if let power = avgPower {
                        dynamicCard(
                            icon: "bolt.fill",
                            title: "Power",
                            value: String(format: "%.0f W", power)
                        )
                    }

                    if let cadence = avgCadence {
                        dynamicCard(
                            icon: "metronome.fill",
                            title: "Cadence",
                            value: String(format: "%.0f spm", cadence)
                        )
                    }

                    if let stride = avgStrideLength {
                        dynamicCard(
                            icon: "ruler.fill",
                            title: "Stride",
                            value: String(format: "%.2f m", stride)
                        )
                    }

                    if let gct = avgGroundContactTime {
                        dynamicCard(
                            icon: "arrow.down.to.line",
                            title: "Ground Contact",
                            value: String(format: "%.0f ms", gct)
                        )
                    }

                    if let vo = avgVerticalOscillation {
                        dynamicCard(
                            icon: "arrow.up.arrow.down",
                            title: "Vert. Oscillation",
                            value: String(format: "%.1f cm", vo)
                        )
                    }
                }
            }
            .padding(16)
            .background(DS.Semantic.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.Semantic.border, lineWidth: 1))
        }
    }

    private func dynamicCard(icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(DS.Semantic.brand)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }
            Text(value)
                .font(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(DS.Semantic.fillSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
