//
//  CutExerciseStatsView.swift
//  WRKT
//
//  One exercise's statistics: the exercise name as the title, a lime cut-corner field with up to
//  three records, a segment over one line chart with a two-part caption, and the sessions list
//  (a record session says "Record"); a session opens its log as a Browser sheet. Pushed, it has
//  the back button on the title row; presented, it is a Browser sheet with Close; embedded (the
//  exercise details Stats tab), it shows the content only. Plain values and closures only.
//

import SwiftUI

struct CutExerciseStatsActions {
    var back: () -> Void = {}
    var close: () -> Void = {}
    var openSession: (UUID) -> Void = { _ in }
}

enum CutExerciseStatsChrome: Equatable {
    case pushed, presented, embedded
}

struct CutExerciseStatsView: View {
    let title: String
    /// nil while the statistics are computed.
    let model: CutExerciseStatsModel?
    let chrome: CutExerciseStatsChrome
    var actions = CutExerciseStatsActions()

    @State private var selected: CutExerciseStatsModel.Metric?

    init(title: String, model: CutExerciseStatsModel?, chrome: CutExerciseStatsChrome,
         actions: CutExerciseStatsActions = .init(), metric: CutExerciseStatsModel.Metric? = nil) {
        self.title = title
        self.model = model
        self.chrome = chrome
        self.actions = actions
        _selected = State(initialValue: metric)
    }

    var body: some View {
        switch chrome {
        case .presented:
            CutSheet(title, kind: .browser, close: actions.close) {
                content.padding(.bottom, 24)
            }
        case .embedded:
            ScrollView {
                content.padding(.bottom, 24)
            }
            .foregroundStyle(DS.Cut.Colors.textPrimary)
        case .pushed:
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    CutStatsTopBar(title: title, back: actions.back)
                    content.padding(.top, 20)
                }
                .padding(.bottom, DS.Redesign.tabBarClearance(legacy: 96, system: 76))
            }
            .foregroundStyle(DS.Cut.Colors.textPrimary)
            .background(DS.Cut.Colors.background.ignoresSafeArea())
        }
    }

    @ViewBuilder
    private var content: some View {
        if let model {
            VStack(alignment: .leading, spacing: 0) {
                if let empty = model.emptyLine {
                    CutStatsEmptyLine(text: empty)
                        .padding(.horizontal, DS.Cut.Metrics.gutter)
                }
                if !model.records.isEmpty {
                    CutExerciseRecordsField(records: model.records)
                        .padding(.horizontal, DS.Cut.Metrics.panelInset)
                }
                chart(model)
                if !model.sessions.isEmpty {
                    CutPanelHeader(model.sessionsTitle)
                        .padding(.top, 24)
                    CutExerciseSessionList(sessions: model.sessions, onPanel: chrome == .pushed, open: actions.openSession)
                        .padding(.top, 10)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ProgressView()
                .tint(DS.Cut.Colors.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 240)
                .accessibilityLabel(Text("Loading statistics"))
        }
    }

    @ViewBuilder
    private func chart(_ model: CutExerciseStatsModel) -> some View {
        if let series = model.series(for: selected) {
            if model.series.count > 1 {
                CutExerciseSegment(series: model.series, selected: series.metric, onSheet: chrome != .pushed) { metric in
                    selected = metric
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
            }
            CutStatsLineChart(points: series.points, accessibilityLabel: series.accessibilityLabel)
                .padding(.horizontal, DS.Cut.Metrics.gutter)
                .padding(.top, 16)
            CutStatsCaption(leading: series.captionLeading, trailing: series.captionTrailing)
                .padding(.horizontal, DS.Cut.Metrics.gutter)
                .padding(.top, 8)
        } else if let note = model.chartNote {
            CutStatsEmptyLine(text: note)
                .padding(.horizontal, DS.Cut.Metrics.gutter)
                .padding(.top, 22)
        }
    }
}

// MARK: - Records

/// The lime field: one column per record, ink hairlines between; stacked at accessibility sizes.
private struct CutExerciseRecordsField: View {
    let records: [CutExerciseStatsModel.Record]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        CutField(tone: .lime, corner: .bottomTrailing, cut: 26,
                 padding: EdgeInsets(top: 16, leading: 20, bottom: 22, trailing: 20)) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                        if index > 0 { CutHairline().padding(.vertical, 10) }
                        column(record)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                        if index > 0 {
                            Rectangle().fill(DS.Cut.Colors.inkHairline).frame(width: DS.Cut.Metrics.hairline)
                        }
                        column(record)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, index > 0 ? 14 : 0)
                            .padding(.trailing, 6)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func column(_ record: CutExerciseStatsModel.Record) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(record.label)
                .font(DS.Typography.custom(size: 16, weight: .bold, relativeTo: .subheadline))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(0.8)
            Text(record.value)
                .font(DS.Cut.Typography.condensed(size: 34, relativeTo: .title, monospacedDigits: true))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(record.line)
                .font(DS.Typography.custom(size: 15, weight: .semibold, relativeTo: .subheadline))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
        }
        .foregroundStyle(DS.Cut.Colors.ink)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(record.accessibilityLabel))
    }
}

// MARK: - Segment and chart

private struct CutExerciseSegment: View {
    let series: [CutExerciseStatsModel.Series]
    let selected: CutExerciseStatsModel.Metric
    let onSheet: Bool
    let select: (CutExerciseStatsModel.Metric) -> Void
    @Environment(\.cutSheetLevel) private var level

    var body: some View {
        CutPlannerSegmented(
            items: series.map(\.metric),
            selected: selected,
            title: { metric in series.first { $0.metric == metric }?.title ?? "" },
            select: { metric in
                guard metric != selected else { return }
                Haptics.light()
                select(metric)
            },
            fill: onSheet ? level.inset : DS.Cut.SheetLevel.base.surface
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Chart"))
    }
}

/// One lime line over a baseline with a dot on the latest session. Points are normalised 0...1.
struct CutStatsLineChart: View {
    let points: [CutExerciseStatsModel.Point]
    let accessibilityLabel: String

    private let height: CGFloat = 150
    private let inset: CGFloat = 8

    var body: some View {
        Canvas { context, size in
            guard points.count >= 2 else { return }
            let rect = CGRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset * 2 - 6)
            func location(_ point: CutExerciseStatsModel.Point) -> CGPoint {
                CGPoint(x: rect.minX + rect.width * point.x, y: rect.maxY - rect.height * point.y)
            }
            var path = Path()
            path.move(to: location(points[0]))
            for point in points.dropFirst() { path.addLine(to: location(point)) }
            context.stroke(path, with: .color(DS.Cut.Colors.lime),
                           style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
            if let last = points.last {
                let end = location(last)
                context.fill(Path(ellipseIn: CGRect(x: end.x - 6, y: end.y - 6, width: 12, height: 12)),
                             with: .color(DS.Cut.Colors.lime))
            }
        }
        .frame(height: height)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.3)).frame(height: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityAddTraits(.isImage)
    }
}

// MARK: - Sessions

/// The sessions as rows: a raised panel on the black page, hairline rows on a sheet.
private struct CutExerciseSessionList: View {
    let sessions: [CutExerciseStatsModel.Session]
    let onPanel: Bool
    let open: (UUID) -> Void

    var body: some View {
        if onPanel {
            CutPanel { rows }
        } else {
            VStack(spacing: 0) {
                CutHairline()
                rows
                CutHairline()
            }
            .padding(.horizontal, DS.Cut.Metrics.gutter)
        }
    }

    private var rows: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                if index > 0 { CutHairline() }
                Button { open(session.id) } label: {
                    CutStatsValueRow(title: session.title, value: session.isRecord ? "Record" : nil, line: session.line,
                                     valueIsLime: true, minHeight: 60,
                                     horizontalPadding: onPanel ? DS.Cut.Metrics.panelRowPadding : 0)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(session.accessibilityLabel))
                .accessibilityHint(Text("Opens this session's sets."))
                .accessibilityAddTraits(.isButton)
            }
        }
    }
}

// MARK: - Session log

/// A session's log in the sheet family: the records it holds, its totals and every set.
struct CutSessionLogView: View {
    let model: CutSessionLogModel
    let close: () -> Void

    var body: some View {
        CutSheet(model.title, subtitle: model.subtitle, kind: .browser, close: close) {
            VStack(alignment: .leading, spacing: 20) {
                if let record = model.recordLine {
                    Text(record)
                        .font(DS.Typography.custom(size: 17, weight: .bold, relativeTo: .body))
                        .foregroundStyle(DS.Cut.Colors.lime)
                        .fixedSize(horizontal: false, vertical: true)
                }
                CutStatsColumns(columns: model.stats)
                if !model.sets.isEmpty {
                    CutSheetInset {
                        ForEach(Array(model.sets.enumerated()), id: \.element.id) { index, row in
                            if index > 0 { CutHairline() }
                            CutSheetInsetRow(row.label, value: row.value)
                        }
                    }
                }
            }
            .padding(.horizontal, DS.Cut.Metrics.gutter)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }
}
