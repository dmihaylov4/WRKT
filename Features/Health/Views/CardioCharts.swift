//
//  CardioCharts.swift
//  WRKT
//
//  Shared chart components for cardio data display (used by CardioDetailView & PostDetailView)
//

import SwiftUI
import Charts
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Splits Chart

struct SplitsChart: View {
    let splits: [KilometerSplit]
    var showCard: Bool = true

    private var avgPace: Int {
        guard !splits.isEmpty else { return 0 }
        return splits.map(\.paceSecPerKm).reduce(0, +) / splits.count
    }

    private var minPace: Int { splits.map(\.paceSecPerKm).min() ?? 0 }
    private var maxPace: Int { splits.map(\.paceSecPerKm).max() ?? 0 }

    @State private var selectedSplit: KilometerSplit?

    private var displayedSplit: KilometerSplit? {
        selectedSplit ?? splits.last
    }

    var body: some View {
        if showCard {
            content
                .padding(16)
                .background(DS.Semantic.card)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.Semantic.border, lineWidth: 1))
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            if splits.isEmpty {
                Text("No split data available")
                    .dsFont(.subheadline)
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                // Always-visible info row — shows selected split or last split as default
                if let split = displayedSplit {
                    HStack(spacing: 8) {
                        Text("KM \(split.number)")
                            .dsFont(.subheadline, weight: .bold, monospacedDigits: true)
                            .foregroundStyle(DS.Semantic.brand)

                        Text("·")
                            .dsFont(.subheadline)
                            .foregroundStyle(Color.white.opacity(0.35))

                        Text(paceString(split.paceSecPerKm) + " /km")
                            .dsFont(.subheadline, weight: .bold, monospacedDigits: true)
                            .foregroundStyle(Color.white)

                        Spacer()

                        Text(formatDuration(split.durationSec))
                            .dsFont(.subheadline, monospacedDigits: true)
                            .foregroundStyle(Color.white.opacity(0.7))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Chart {
                    ForEach(splits) { split in
                        BarMark(
                            x: .value("KM", "\(split.number)"),
                            y: .value("Pace", split.paceSecPerKm)
                        )
                        .foregroundStyle(barColor(for: split))
                        .cornerRadius(3)
                        .annotation(position: .overlay, alignment: .bottom) {
                            let isSelected = displayedSplit?.id == split.id
                            Text("\(split.number)")
                                .font(.system(size: 10, weight: isSelected ? .bold : .regular))
                                .foregroundStyle(isSelected ? Color.black : DS.Semantic.textSecondary)
                                .padding(.bottom, 4)
                        }
                    }

                    RuleMark(y: .value("Avg", avgPace))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(DS.Semantic.textSecondary.opacity(0.5))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("avg  \(paceString(avgPace))")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(DS.Semantic.textSecondary)
                        }
                }
                .chartYScale(domain: (minPace - 10)...(maxPace + 20))
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine()
                            .foregroundStyle(DS.Semantic.border.opacity(0.4))
                        AxisValueLabel {
                            if let intValue = value.as(Int.self) {
                                Text(paceString(intValue))
                                    .font(.system(size: 10))
                                    .foregroundStyle(DS.Semantic.textSecondary)
                            }
                        }
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: 140)
                // DragGesture(minimumDistance: 0) fires immediately on touch-up
                // without the ~350ms disambiguation delay that onTapGesture incurs
                // inside a TabView(.page) carousel.
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            // simultaneousGesture lets the tap fire alongside the
                            // TabView(.page) swipe recognizer instead of competing with it.
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                                    .onEnded { value in
                                        let moved = max(abs(value.translation.width), abs(value.translation.height))
                                        guard moved < 8 else { return }
                                        guard let plotFrame = proxy.plotFrame else { return }
                                        let relX = value.startLocation.x - geo[plotFrame].origin.x
                                        let plotWidth = geo[plotFrame].width
                                        guard plotWidth > 0, relX >= 0, relX <= plotWidth else { return }
                                        let barIndex = Int(relX / (plotWidth / CGFloat(splits.count)))
                                        let clampedIndex = max(0, min(splits.count - 1, barIndex))
                                        selectedSplit = splits[clampedIndex]
                                        #if canImport(UIKit)
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        #endif
                                    }
                            )
                    }
                }
            }
        }
    }

    private func barColor(for split: KilometerSplit) -> Color {
        guard let displayed = displayedSplit else {
            return split.paceSecPerKm <= avgPace
                ? DS.Semantic.brand
                : DS.Semantic.textSecondary.opacity(0.4)
        }
        return split.id == displayed.id
            ? DS.Semantic.brand
            : DS.Semantic.textSecondary.opacity(0.25)
    }

    private func paceString(_ spk: Int) -> String {
        String(format: "%d:%02d", spk / 60, spk % 60)
    }

    private func formatDuration(_ sec: Int) -> String {
        String(format: "%d:%02d", sec / 60, sec % 60)
    }
}

// MARK: - HR Zone Chart

struct HRZoneChart: View {
    let zones: [HRZoneSummary]
    let samples: [HeartRateSample]?
    var showZonesSection: Bool = true
    var showTimeSeriesSection: Bool = true
    var showCard: Bool = true

    private var totalMinutes: Double {
        zones.reduce(0) { $0 + $1.minutes }
    }

    var body: some View {
        if showCard {
            contentView
                .padding(16)
                .background(DS.Semantic.card)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.Semantic.border, lineWidth: 1))
        } else {
            contentView
        }
    }

    private var contentView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showZonesSection {
                if !zones.isEmpty && totalMinutes > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("Time in Zones")
                                .dsFont(.headline)
                                .foregroundStyle(DS.Semantic.textPrimary)
                            Text(HRZoneCalculator.shared.methodDisplayName)
                                .dsFont(.caption2)
                                .foregroundStyle(DS.Semantic.textSecondary)
                            let method = HRZoneCalculator.shared.config?.method
                            if method == .ageBased || method == .defaultMax {
                                DataQualityBadge(quality: .ageBased)
                            }
                            if zones.first?.isEstimated == true {
                                DataQualityBadge(quality: .estimated)
                            }
                        }

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

                        ForEach(zones.sorted { $0.zone < $1.zone }) { zone in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(hex: zone.colorHex))
                                    .frame(width: 10, height: 10)

                                Text("Z\(zone.zone)")
                                    .dsFont(.caption, weight: .bold)
                                    .foregroundStyle(DS.Semantic.textPrimary)
                                    .frame(width: 24, alignment: .leading)

                                Text(zone.name)
                                    .dsFont(.caption)
                                    .foregroundStyle(DS.Semantic.textSecondary)

                                Spacer()

                                if totalMinutes > 0 {
                                    Text(String(format: "%.0f%%", (zone.minutes / totalMinutes) * 100))
                                        .dsFont(.caption, monospacedDigits: true)
                                        .foregroundStyle(DS.Semantic.textSecondary)
                                        .frame(width: 36, alignment: .trailing)
                                }

                                Text(String(format: "%.0fm", zone.minutes))
                                    .dsFont(.caption, monospacedDigits: true)
                                    .foregroundStyle(DS.Semantic.textPrimary)
                                    .frame(width: 32, alignment: .trailing)

                                Text(zone.rangeDisplay)
                                    .dsFont(.caption2)
                                    .foregroundStyle(DS.Semantic.textSecondary)
                                    .frame(width: 75, alignment: .trailing)
                            }
                        }
                    }
                } else {
                    Text("No heart rate zone data")
                        .dsFont(.subheadline)
                        .foregroundStyle(DS.Semantic.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                }
            }

            if showTimeSeriesSection, let samples = samples, samples.count > 2 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Heart Rate Over Time")
                        .dsFont(.subheadline, weight: .bold)
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
                                        .dsFont(.caption2)
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let date = value.as(Date.self) {
                                    Text(date, format: .dateTime.hour().minute())
                                        .dsFont(.caption2)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
                }
            }
        }
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
                    .dsFont(.headline)
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
            .clipShape(ChamferedRectangleAlt(.large))
            .overlay(ChamferedRectangleAlt(.large).stroke(DS.Semantic.border, lineWidth: 1))
        }
    }

    private func dynamicCard(icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .dsFont(.caption)
                    .foregroundStyle(DS.Semantic.brand)
                Text(title)
                    .dsFont(.caption)
                    .foregroundStyle(DS.Semantic.textSecondary)
            }
            Text(value)
                .dsFont(.headline)
                .foregroundStyle(DS.Semantic.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(DS.Semantic.fillSubtle)
        .clipShape(ChamferedRectangleAlt(.medium))
    }
}
