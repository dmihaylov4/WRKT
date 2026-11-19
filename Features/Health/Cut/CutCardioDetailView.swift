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
    var inSheet = false
    var close: () -> Void = {}
    var tools: AnyView? = nil
    @ViewBuilder var routeMap: () -> RouteMap

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if inSheet {
            CutSheet(model.title, kind: .browser, close: close) { detailContent }
        } else {
            ScrollView { detailContent }
                .scrollIndicators(.hidden)
                .background(DS.Cut.Colors.background.ignoresSafeArea())
        }
    }

    private var detailContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, DS.Cut.Metrics.gutter)
            route
                .padding(.top, 28)
            if !model.splits.isEmpty || model.canLoadSplits || model.splitPlaceholderCount > 0 {
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
    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            if inSheet {
                if let tools { tools.frame(maxWidth: .infinity, alignment: .trailing) }
            } else {
                CutHeroText(CutHeroText.balancedLines(model.title), hero: .xs, minimumScaleFactor: 0.5)
                    .foregroundStyle(DS.Cut.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
            }
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
                statColumns(model.stats)
                    .padding(.top, 10)
            }
        }
    }

    @ViewBuilder
    private func statColumns(_ columns: [CutStatColumn]) -> some View {
        if inSheet && dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                    if !column.label.isEmpty {
                        Text(column.label).cutFont(.secondary).foregroundStyle(DS.Cut.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(column.value + (column.unit.map { " " + $0 } ?? ""))
                            .cutFont(.title).fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(column.isHighlighted ? DS.Cut.Colors.lime : DS.Cut.Colors.textPrimary)
                        CutHairline()
                    }
                }
            }
        } else {
            CutStatColumns(columns)
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
                Group {
                    switch model.availability {
                    case .ready:
                        routeMap()
                    case .loading:
                        CutCardioPendingFill()
                    case .unavailable:
                        CutCardioPendingFill(line: "Route unavailable")
                    }
                }
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
            if model.splits.isEmpty && model.splitPlaceholderCount > 0 {
                VStack(spacing: 12) {
                    ForEach(0..<model.splitPlaceholderCount, id: \.self) { _ in
                        CutCardioBar(fraction: 0, fill: .clear).frame(height: 26)
                    }
                }
                .padding(.top, 6)
                .accessibilityHidden(true)
            } else if model.splits.isEmpty {
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
                    statColumns(heart.stats)
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
                statColumns(row.count == 1 ? row + [CutStatColumn(value: "", label: "")] : row)
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

/// The place of a route map that is not here: empty while it is read, after a short wait a
/// small spinner, or one line when it could not be read.
struct CutCardioPendingFill: View {
    var line: String? = nil
    @State private var showsSpinner = false

    var body: some View {
        ZStack {
            DS.Cut.Colors.controlFill.opacity(0.3)
            if let line {
                Text(line)
                    .cutFont(.secondary)
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
            } else if showsSpinner {
                ProgressView().tint(DS.Cut.Colors.textSecondary)
            }
        }
        .task {
            guard line == nil else { return }
            try? await Task.sleep(for: .milliseconds(300))
            showsSpinner = true
        }
    }
}

/// A slanted bar on the empty track: `fraction` of the width in `fill`.
struct CutCardioBar: View {
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
