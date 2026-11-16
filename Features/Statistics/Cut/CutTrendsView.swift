//
//  CutTrendsView.swift
//  WRKT
//
//  Trends: the back button and title on one row, this week's tonnage with one lime line, twelve
//  weekly bars with the dashed average and a two-part caption, three stat columns for the week,
//  and the top lifts as a raised panel whose rows open each exercise's statistics.
//  Plain values and closures only.
//

import SwiftUI

struct CutTrendsActions {
    var back: () -> Void = {}
    var openLift: (String) -> Void = { _ in }
}

struct CutTrendsView: View {
    let model: CutTrendsModel
    var actions = CutTrendsActions()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                CutStatsTopBar(title: model.title, back: actions.back)
                if let hero = model.hero {
                    heroBlock(hero)
                        .padding(.horizontal, DS.Cut.Metrics.gutter)
                        .padding(.top, 22)
                    CutStatsWeekChart(bars: model.bars, averageFraction: model.averageFraction,
                                      accessibilityLabel: model.chartAccessibilityLabel)
                        .padding(.horizontal, DS.Cut.Metrics.gutter)
                        .padding(.top, 22)
                    CutStatsCaption(leading: model.captionLeading, trailing: model.captionTrailing)
                        .padding(.horizontal, DS.Cut.Metrics.gutter)
                        .padding(.top, 8)
                    CutStatsColumns(columns: model.stats)
                        .padding(.horizontal, DS.Cut.Metrics.gutter)
                        .padding(.top, 22)
                } else if let empty = model.emptyLine {
                    CutStatsEmptyLine(text: empty)
                        .padding(.horizontal, DS.Cut.Metrics.gutter)
                        .padding(.top, 22)
                }
                if !model.lifts.isEmpty {
                    CutPanelHeader(model.liftsTitle)
                        .padding(.top, 26)
                    CutPanel {
                        ForEach(Array(model.lifts.enumerated()), id: \.element.id) { index, lift in
                            if index > 0 { CutHairline() }
                            Button { actions.openLift(lift.id) } label: {
                                CutStatsValueRow(title: lift.name, value: lift.value, showsChevron: true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text(lift.accessibilityLabel))
                            .accessibilityHint(Text("Opens its statistics."))
                            .accessibilityAddTraits(.isButton)
                        }
                    }
                    .padding(.top, 10)
                }
            }
            .padding(.bottom, DS.Redesign.tabBarClearance(legacy: 96, system: 76))
        }
        .foregroundStyle(DS.Cut.Colors.textPrimary)
        .background(DS.Cut.Colors.background.ignoresSafeArea())
    }

    private func heroBlock(_ hero: CutTrendsModel.Hero) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(hero.label)
                .font(DS.Typography.custom(size: 17, weight: .semibold, relativeTo: .body))
                .foregroundStyle(DS.Cut.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(hero.value)
                    .font(DS.Cut.Typography.condensed(size: 60, relativeTo: .largeTitle, monospacedDigits: true))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(hero.unit)
                    .font(DS.Typography.custom(size: 20, weight: .semibold, relativeTo: .title3))
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .fixedSize()
            }
            Text(hero.change)
                .font(DS.Typography.custom(size: 17, weight: .bold, relativeTo: .body))
                .foregroundStyle(hero.changeIsUp ? DS.Cut.Colors.lime : DS.Cut.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(hero.accessibilityLabel))
    }
}

// MARK: - Pieces shared by the statistics screens

/// The back button with the screen title on the same row.
struct CutStatsTopBar: View {
    let title: String
    let back: () -> Void

    var body: some View {
        CutPlannerTopBar(leading: .back, action: back) {
            Text(title)
                .font(DS.Cut.Typography.condensed(size: 34, relativeTo: .largeTitle))
                .textCase(.uppercase)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

/// Twelve weekly bars on a baseline, the current week in lime, with an optional dashed average.
struct CutStatsWeekChart: View {
    let bars: [CutTrendsModel.Bar]
    let averageFraction: Double?
    let accessibilityLabel: String

    private let height: CGFloat = 150

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(bars) { bar in
                Rectangle()
                    .fill(bar.isCurrent ? DS.Cut.Colors.lime : DS.Cut.SheetLevel.stacked.control)
                    .frame(height: bar.fraction > 0 ? max(2, height * bar.fraction) : 0)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: height, alignment: .bottom)
        .overlay(alignment: .bottom) {
            if let averageFraction {
                Line()
                    .stroke(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .frame(height: 2)
                    .offset(y: -height * averageFraction + 1)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.3)).frame(height: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityAddTraits(.isImage)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }
}

/// The two-part line under a chart; the parts stack when they do not fit side by side.
struct CutStatsCaption: View {
    let leading: String
    let trailing: String?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                text(leading)
                Spacer(minLength: 8)
                if let trailing { text(trailing) }
            }
            VStack(alignment: .leading, spacing: 2) {
                text(leading, wraps: true)
                if let trailing { text(trailing, wraps: true) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityHidden(true)
    }

    private func text(_ value: String, wraps: Bool = false) -> some View {
        Text(value)
            .font(DS.Typography.custom(size: 15, weight: .medium, relativeTo: .subheadline))
            .foregroundStyle(DS.Cut.Colors.textSecondary)
            .lineLimit(wraps ? nil : 1)
            .fixedSize(horizontal: false, vertical: wraps)
    }
}

/// Stat columns at the mock's 30 pt: value over a plain label, 1 pt hairlines between columns.
/// They stack at accessibility sizes so no value or label is cut.
struct CutStatsColumns: View {
    let columns: [CutStatColumn]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                    if index > 0 { CutHairline() }
                    cell(column).padding(.vertical, 8)
                }
            }
        } else {
            HStack(spacing: 0) {
                ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                    if index > 0 {
                        Rectangle().fill(DS.Cut.Colors.hairline).frame(width: DS.Cut.Metrics.hairline)
                    }
                    cell(column)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, index > 0 ? 14 : 0)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func cell(_ column: CutStatColumn) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(column.value)
                .font(DS.Cut.Typography.condensed(size: 30, relativeTo: .title, monospacedDigits: true))
                .foregroundStyle(DS.Cut.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(column.label)
                .font(DS.Typography.custom(size: 16, weight: .medium, relativeTo: .subheadline))
                .foregroundStyle(DS.Cut.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One row inside a raised panel: a bold title, an optional value (lime or plain) and chevron.
/// At accessibility sizes the value moves under the title.
struct CutStatsValueRow: View {
    let title: String
    var value: String?
    var line: String?
    var valueIsLime = false
    var showsChevron = false
    var minHeight: CGFloat = 56
    var horizontalPadding: CGFloat = DS.Cut.Metrics.panelRowPadding

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 12) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    titleText
                    if let line { lineText(line) }
                    if let value { valueText(value) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    titleText
                    if let line { lineText(line) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let value { valueText(value).fixedSize() }
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 10)
        .frame(minHeight: minHeight)
        .contentShape(Rectangle())
    }

    private var titleText: some View {
        Text(title)
            .font(DS.Typography.custom(size: 18, weight: .bold, relativeTo: .body))
            .foregroundStyle(DS.Cut.Colors.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func lineText(_ text: String) -> some View {
        Text(text)
            .font(DS.Typography.custom(size: 16, weight: .medium, relativeTo: .subheadline))
            .foregroundStyle(DS.Cut.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func valueText(_ text: String) -> some View {
        Text(text)
            .font(DS.Typography.custom(size: valueIsLime ? 16 : 18, weight: valueIsLime ? .bold : .medium, relativeTo: .body))
            .foregroundStyle(valueIsLime ? DS.Cut.Colors.lime : DS.Cut.Colors.textSecondary)
    }
}

/// The plain line shown in place of a section with nothing to show.
struct CutStatsEmptyLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(DS.Typography.custom(size: 17, weight: .medium, relativeTo: .body))
            .foregroundStyle(DS.Cut.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
