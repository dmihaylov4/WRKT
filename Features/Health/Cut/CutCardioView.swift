//
//  CutCardioView.swift
//  WRKT
//
//  The Cardio tab in the Cut language: a one-row header with the sync menu, underline tabs for
//  the activity type, then the selected week: distance as the hero, stat columns, a seven-day
//  bar chart, streak and best pace, and the week's sessions as hairline rows. Takes plain values
//  and closures, so every state renders without HealthKit (see CutCardioHost for live data).
//

import SwiftUI

/// What the header, tabs and rows do. Every closure calls an existing flow.
struct CutCardioActions {
    var selectType: (CardioType) -> Void = { _ in }
    var olderWeek: () -> Void = {}
    var newerWeek: () -> Void = {}
    var syncNew: () -> Void = {}
    var fullResync: () -> Void = {}
    var connectHealth: () -> Void = {}
    var refresh: () async -> Void = {}
    var openRun: (UUID) -> Void = { _ in }
}

struct CutCardioView: View {
    let model: CutCardioTabModel
    var actions = CutCardioActions()

    @State private var confirmsResync = false

    var body: some View {
        VStack(spacing: 0) {
            CutTabHeader("Cardio") {
                Menu {
                    if model.canSync {
                        Button("Sync new workouts", systemImage: "arrow.triangle.2.circlepath", action: actions.syncNew)
                            .disabled(model.isSyncing)
                        Button("Force full re-sync", systemImage: "arrow.clockwise") { confirmsResync = true }
                            .disabled(model.isSyncing)
                    }
                    Button("Apple Health access", systemImage: "heart", action: actions.connectHealth)
                } label: {
                    Label("Sync and Health", systemImage: "ellipsis")
                }
                .menuStyle(.button)
            }
            .padding(.horizontal, DS.Cut.Metrics.gutter)
            .padding(.top, 8)

            CutUnderlineTabs(CardioType.allCases, selection: model.type, title: \.displayName, select: actions.selectType)
                .padding(.top, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let sync = model.sync {
                        syncRow(sync)
                    }
                    if model.showsConnectRow {
                        connectRow
                    }
                    content
                }
                .padding(.bottom, DS.Redesign.tabBarClearance(legacy: 80, system: 60))
            }
            .scrollIndicators(.hidden)
            .refreshable { await actions.refresh() }
        }
        .background(DS.Cut.Colors.background.ignoresSafeArea())
        .alert("Re-import everything?", isPresented: $confirmsResync) {
            Button("Cancel", role: .cancel) {}
            Button("Re-sync", action: actions.fullResync)
        } message: {
            Text("Every workout is read again from Apple Health.")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.content {
        case .loading:
            CutCardioSkeleton()
        case .empty(let message):
            VStack(alignment: .leading, spacing: 0) {
                CutHeroText(CutHeroText.balancedLines(message.title), hero: .s)
                    .foregroundStyle(DS.Cut.Colors.textPrimary)
                Text(message.line)
                    .cutFont(.body)
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                if message.showsConnect {
                    Button("Connect Health", action: actions.connectHealth)
                        .buttonStyle(CutPrimaryButtonStyle(fillsWidth: false))
                        .padding(.top, 22)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Cut.Metrics.gutter)
            .padding(.top, 40)
        case .week(let week):
            CutCardioWeekView(week: week, actions: actions)
        }
    }

    private func syncRow(_ sync: CutCardioSync) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ProgressView().tint(DS.Cut.Colors.textSecondary)
                Text(sync.title)
                    .cutFont(.secondary)
                    .foregroundStyle(DS.Cut.Colors.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let percent = sync.percent {
                    Text(percent)
                        .font(DS.Cut.Typography.font(.secondary, monospacedDigits: true).weight(.semibold))
                        .foregroundStyle(DS.Cut.Colors.lime)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, DS.Cut.Metrics.gutter)
            CutHairline()
        }
        .accessibilityElement(children: .combine)
    }

    private var connectRow: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text("Apple Health is not connected")
                    .cutFont(.secondary)
                    .foregroundStyle(DS.Cut.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Connect", action: actions.connectHealth)
                    .buttonStyle(CutSecondaryButtonStyle(size: .compact, fillsWidth: false))
            }
            .padding(.vertical, 12)
            .padding(.horizontal, DS.Cut.Metrics.gutter)
            CutHairline()
        }
    }
}

// MARK: - Week

private struct CutCardioWeekView: View {
    let week: CutCardioWeek
    let actions: CutCardioActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            navigator
                .padding(.top, 16)
            hero
                .padding(.top, 6)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 20).onEnded(swipe))
            CutStatColumns(week.stats)
                .padding(.top, 10)
            CutCardioBarChart(bars: week.bars)
                .padding(.top, 28)
            VStack(spacing: 0) {
                CutHairline()
                CutStatColumns(week.summary)
                    .padding(.vertical, 16)
                CutHairline()
            }
            .padding(.top, 28)

            CutSectionTitle(week.sectionTitle)
                .padding(.top, 28)
                .padding(.bottom, 10)
            if week.rows.isEmpty {
                CutHairlineList {
                    Text(week.emptyLine)
                        .cutFont(.secondary)
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 18)
                }
            } else {
                CutHairlineList {
                    ForEach(week.rows) { row in
                        Button { actions.openRun(row.id) } label: { CutCardioRunRowView(row: row) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, DS.Cut.Metrics.gutter)
    }

    private var navigator: some View {
        HStack(spacing: 10) {
            Text(week.label)
                .cutFont(.secondary)
                .foregroundStyle(DS.Cut.Colors.textSecondary)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            HStack(spacing: 0) {
                chevron("chevron.left", label: "Previous week", enabled: week.canGoOlder, action: actions.olderWeek)
                chevron("chevron.right", label: "Next week", enabled: week.canGoNewer, action: actions.newerWeek)
            }
        }
    }

    /// Bare chevron as on Plan's month row: no platter, low opacity, 44 pt target; dimmer when disabled.
    private func chevron(_ systemImage: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(DS.Cut.Colors.textPrimary.opacity(enabled ? 0.4 : 0.15))
                .frame(width: DS.Cut.Metrics.minTouchTarget, height: DS.Cut.Metrics.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(Text(label))
    }

    private var hero: some View {
        HStack(alignment: .lastTextBaseline, spacing: 10) {
            Text(week.hero.value)
                .font(DS.Cut.Typography.condensed(size: DS.Cut.Typography.Hero.xl.size, monospacedDigits: true))
                .tracking(DS.Cut.Typography.Hero.xl.tracking)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(DS.Cut.Colors.textPrimary)
            if let unit = week.hero.unit {
                Text(unit).cutHero(.xs)
                    .foregroundStyle(DS.Cut.Colors.textPrimary)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func swipe(_ value: DragGesture.Value) {
        let horizontal = value.translation.width
        guard abs(horizontal) > 40, abs(horizontal) > abs(value.translation.height) else { return }
        if horizontal < 0, week.canGoOlder {
            actions.olderWeek()
        } else if horizontal > 0, week.canGoNewer {
            actions.newerWeek()
        }
    }
}

/// Seven flat bars, Monday first. Today is lime and cut at the corner; the rest are grey.
private struct CutCardioBarChart: View {
    let bars: [CutCardioDayBar]

    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 96

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(bars) { bar in
                    VStack {
                        Spacer(minLength: 0)
                        if bar.fraction > 0 {
                            CutCornerShape(corner: .topTrailing, cut: .points(bar.isToday ? 12 : 0))
                                .fill(bar.isToday ? DS.Cut.Colors.lime : DS.Cut.Colors.controlFill)
                                .frame(height: max(6, height * bar.fraction))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: height)
            .overlay(alignment: .bottom) { CutHairline() }
            HStack(spacing: 10) {
                ForEach(bars) { bar in
                    Text(bar.letter)
                        .font(DS.Cut.Typography.font(.secondary).weight(bar.isToday ? .bold : .medium))
                        .foregroundStyle(bar.isToday ? DS.Cut.Colors.lime : DS.Cut.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Daily totals this week"))
    }
}

struct CutCardioRunRowView: View {
    let row: CutCardioRunRow

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .cutFont(.title)
                        .foregroundStyle(DS.Cut.Colors.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(row.line)
                        .cutFont(.secondary)
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(row.value)
                    .font(DS.Cut.Typography.condensed(size: 28, relativeTo: .title2, monospacedDigits: true))
                    .foregroundStyle(DS.Cut.Colors.textPrimary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.vertical, 12)
            .frame(minHeight: 64)
            CutHairline()
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Quiet placeholder while the workout store loads.
private struct CutCardioSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Capsule().frame(width: 110, height: 16)
            Capsule().frame(width: 200, height: 72)
            HStack(spacing: 24) {
                ForEach(0..<3, id: \.self) { _ in Capsule().frame(width: 70, height: 30) }
            }
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array([30, 0, 55, 0, 40, 0, 70].enumerated()), id: \.offset) { _, value in
                    Rectangle().frame(height: CGFloat(max(value, 4))).frame(maxWidth: .infinity)
                }
            }
            .frame(height: 96, alignment: .bottom)
        }
        .foregroundStyle(DS.Cut.Colors.controlFill)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Cut.Metrics.gutter)
        .padding(.top, 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Loading cardio"))
    }
}
