//
//  CutCardioDetailView.swift
//  WRKT
//
//  One cardio workout in the Cut language: the name and distance as heroes, one stat row, the
//  route map full width, splits as slanted bars with the fastest in lime, heart rate as stat
//  columns, a bar strip and zone bars, then performance as a hairline grid. Takes plain values
//  and closures; the host supplies the live route map.
//

import SwiftUI

struct CutCardioDetailActions {
    var fetchRoute: () -> Void = {}
    var refreshDetails: () -> Void = {}
}

struct CutCardioDetailView<RouteMap: View>: View {
    let model: CutCardioDetailModel
    /// A route, splits or heart rate fetch is running.
    var isRefreshing = false
    var actions = CutCardioDetailActions()
    @ViewBuilder var routeMap: () -> RouteMap

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, DS.Cut.Metrics.gutter)
                route
                    .padding(.top, 28)
                if !model.splits.isEmpty || model.canLoadSplits {
                    splits
                        .padding(.horizontal, DS.Cut.Metrics.gutter)
                        .padding(.top, 32)
                }
                if model.heartRate != nil || model.canLoadDetails {
                    heartRate
                        .padding(.horizontal, DS.Cut.Metrics.gutter)
                        .padding(.top, 32)
                }
                if !model.performance.isEmpty {
                    performance
                        .padding(.horizontal, DS.Cut.Metrics.gutter)
                        .padding(.top, 32)
                }
                if let notes = model.notes {
                    VStack(alignment: .leading, spacing: 10) {
                        CutSectionTitle("Notes")
                        CutHairline()
                        Text(notes)
                            .cutFont(.body)
                            .foregroundStyle(DS.Cut.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, DS.Cut.Metrics.gutter)
                    .padding(.top, 32)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(DS.Cut.Colors.background.ignoresSafeArea())
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            CutHeroText(CutHeroText.balancedLines(model.title), hero: .xs, minimumScaleFactor: 0.5)
                .foregroundStyle(DS.Cut.Colors.textPrimary)
            Text(model.dateLine)
                .cutFont(.secondary)
                .foregroundStyle(DS.Cut.Colors.textSecondary)
                .padding(.top, 6)
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text(model.hero.value)
                    .font(DS.Cut.Typography.condensed(size: DS.Cut.Typography.Hero.l.size, monospacedDigits: true))
                    .tracking(DS.Cut.Typography.Hero.l.tracking)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if let unit = model.hero.unit {
                    Text(unit).cutHero(.xs).fixedSize()
                }
            }
            .foregroundStyle(DS.Cut.Colors.textPrimary)
            .accessibilityElement(children: .combine)
            .padding(.top, 14)
            if !model.stats.isEmpty {
                CutStatColumns(model.stats)
                    .padding(.top, 10)
            }
        }
    }

    // MARK: Route

    @ViewBuilder
    private var route: some View {
        switch model.route {
        case .none:
            EmptyView()
        case .map:
            VStack(alignment: .leading, spacing: 12) {
                routeMap()
                    .frame(height: 260)
                    .frame(maxWidth: .infinity)
                    .clipped()
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        ForEach([Color.blue.opacity(0.9), DS.Cut.Colors.lime, Color.red], id: \.self) { color in
                            SlantedSegmentShape().fill(color).frame(width: 18, height: 8)
                        }
                    }
                    .accessibilityHidden(true)
                    Text("Heart rate, low to high")
                        .cutFont(.secondary)
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                }
                .padding(.horizontal, DS.Cut.Metrics.gutter)
            }
        case .canFetch:
            Button(action: actions.fetchRoute) {
                Label(isRefreshing ? "Getting route" : "Get route map", systemImage: "map")
            }
            .buttonStyle(CutSecondaryButtonStyle(fillsWidth: true))
            .disabled(isRefreshing)
            .padding(.horizontal, DS.Cut.Metrics.gutter)
        }
    }

    // MARK: Splits

    private var splits: some View {
        VStack(alignment: .leading, spacing: 10) {
            CutSectionTitle("Splits per km")
            CutHairline()
            if model.splits.isEmpty {
                loadButton("Load splits")
            } else {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                    ForEach(model.splits) { split in
                        GridRow {
                            Text(split.label)
                                .font(DS.Cut.Typography.condensed(size: 22, relativeTo: .title3, monospacedDigits: true))
                                .foregroundStyle(split.isFastest ? DS.Cut.Colors.lime : DS.Cut.Colors.textPrimary)
                                .fixedSize()
                                .accessibilityLabel(Text("Kilometre \(split.label), \(split.pace) per kilometre\(split.isFastest ? ", fastest" : "")"))
                            CutCardioBar(fraction: split.fraction, fill: split.isFastest ? DS.Cut.Colors.lime : DS.Cut.Colors.segmentTrack)
                            Text(split.pace)
                                .font(DS.Cut.Typography.condensed(size: 22, relativeTo: .title3, monospacedDigits: true))
                                .foregroundStyle(split.isFastest ? DS.Cut.Colors.lime : DS.Cut.Colors.textPrimary)
                                .fixedSize()
                                .gridColumnAlignment(.trailing)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    // MARK: Heart rate

    private var heartRate: some View {
        VStack(alignment: .leading, spacing: 10) {
            CutSectionTitle("Heart rate")
            if let heart = model.heartRate, heart.isEstimated {
                Text("Zones are estimated from your average heart rate.")
                    .cutFont(.secondary)
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            CutHairline()
            if let heart = model.heartRate {
                if !heart.stats.isEmpty {
                    CutStatColumns(heart.stats)
                        .padding(.top, 4)
                }
                if !heart.bars.isEmpty {
                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(Array(heart.bars.enumerated()), id: \.offset) { _, value in
                            Rectangle()
                                .fill(DS.Cut.Colors.lime.opacity(0.25 + 0.75 * value))
                                .frame(height: 72 * value)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 72, alignment: .bottom)
                    .padding(.top, 18)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Heart rate over the workout"))
                }
                if !heart.zones.isEmpty {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                        ForEach(heart.zones) { zone in
                            GridRow {
                                Text(zone.label)
                                    .cutFont(.title)
                                    .foregroundStyle(DS.Cut.Colors.textPrimary)
                                    .fixedSize()
                                    .accessibilityLabel(Text("\(zone.label), \(zone.time)"))
                                CutCardioBar(fraction: zone.fraction,
                                             fill: DS.Cut.Colors.lime.opacity(0.35 + 0.13 * Double(zone.id)))
                                Text(zone.time)
                                    .font(DS.Cut.Typography.condensed(size: 22, relativeTo: .title3, monospacedDigits: true))
                                    .foregroundStyle(DS.Cut.Colors.textPrimary)
                                    .fixedSize()
                                    .gridColumnAlignment(.trailing)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .padding(.top, 18)
                }
            }
            if model.canLoadDetails {
                loadButton("Load details")
                    .padding(.top, 8)
            }
        }
    }

    // MARK: Performance

    private var performance: some View {
        VStack(alignment: .leading, spacing: 0) {
            CutSectionTitle("Performance")
                .padding(.bottom, 10)
            CutHairline()
            ForEach(Array(model.performance.enumerated()), id: \.offset) { _, row in
                CutStatColumns(row.count == 1 ? row + [CutStatColumn(value: "", label: "")] : row)
                    .padding(.vertical, 14)
                CutHairline()
            }
        }
    }

    private func loadButton(_ title: String) -> some View {
        Button(action: actions.refreshDetails) {
            if isRefreshing {
                HStack(spacing: 10) {
                    ProgressView().tint(DS.Cut.Colors.textPrimary)
                    Text("Loading")
                }
            } else {
                Text(title)
            }
        }
        .buttonStyle(CutSecondaryButtonStyle(fillsWidth: true))
        .disabled(isRefreshing)
        .padding(.top, 4)
    }
}

extension CutCardioDetailView where RouteMap == EmptyView {
    init(model: CutCardioDetailModel, isRefreshing: Bool = false, actions: CutCardioDetailActions = CutCardioDetailActions()) {
        self.init(model: model, isRefreshing: isRefreshing, actions: actions) { EmptyView() }
    }
}

/// A slanted bar on the empty track: `fraction` of the width in `fill`.
private struct CutCardioBar: View {
    let fraction: Double
    let fill: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                SlantedSegmentShape().fill(DS.Cut.Colors.controlFill.opacity(0.5))
                SlantedSegmentShape().fill(fill)
                    .frame(width: max(10, proxy.size.width * DS.Cut.clampedFraction(fraction)))
            }
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }
}
