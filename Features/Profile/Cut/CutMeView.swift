//
//  CutMeView.swift
//  WRKT
//
//  The Me tab in the Cut language: the level as the header title with Settings beside it, the
//  V mark filled to the level's XP with the streak under it, the weekly goal as hairline rows,
//  then plan adherence, training trends, training balance and the collection. Takes plain
//  values and closures, so every state renders without SwiftData (see CutMeHost for live data).
//

import SwiftUI

/// What the rows and links do. Every closure calls an existing flow.
struct CutMeActions {
    var openSettings: () -> Void = {}
    var openWeeklyGoal: () -> Void = {}
    var setUpGoal: () -> Void = {}
    var customizeGoal: () -> Void = {}
    var resetGoal: () -> Void = {}
    var activateFreeze: () -> Void = {}
    var shareWeek: () -> Void = {}
    var openTrends: () -> Void = {}
    var openBalance: () -> Void = {}
    var openRecords: () -> Void = {}
    var openMilestones: () -> Void = {}
    var openBarbell: () -> Void = {}
}

struct CutMeView: View {
    let model: CutMeModel
    var actions = CutMeActions()

    @State private var confirmsFreeze = false

    var body: some View {
        VStack(spacing: 0) {
            CutTabHeader(model.title) {
                Button(action: actions.openSettings) {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            .padding(.horizontal, DS.Cut.Metrics.gutter)
            .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    heroSection
                        .padding(.top, 16)
                    goalSection
                        .padding(.top, 24)
                    if !model.streakStats.isEmpty {
                        CutStatColumns(model.streakStats)
                            .padding(.top, 20)
                    }
                    if let adherence = model.adherence {
                        adherenceSection(adherence)
                            .padding(.top, 40)
                    }
                    trendsSection
                        .padding(.top, 40)
                    if let balance = model.balance {
                        balanceSection(balance)
                            .padding(.top, 40)
                    }
                    collectionSection
                        .padding(.top, 40)
                }
                .padding(.horizontal, DS.Cut.Metrics.gutter)
                .padding(.bottom, DS.Redesign.tabBarClearance(legacy: 80, system: 60))
            }
            .scrollIndicators(.hidden)
        }
        .background(DS.Cut.Colors.background.ignoresSafeArea())
        .alert("Freeze your streak?", isPresented: $confirmsFreeze) {
            Button("Cancel", role: .cancel) {}
            Button("Activate", action: actions.activateFreeze)
        } message: {
            Text(model.freeze?.alertMessage ?? "")
        }
    }

    // MARK: Level

    @ViewBuilder
    private var heroSection: some View {
        if let hero = model.hero {
            HStack(alignment: .center, spacing: 22) {
                VMarkProgress(left: hero.fraction, right: hero.fraction, accessibilityLabel: hero.accessibilityLabel)
                    .frame(width: 112)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(hero.xp)
                            .cutNumeral(.large)
                            .foregroundStyle(DS.Cut.Colors.textPrimary)
                        Text(hero.xpTotal)
                            .cutFont(.secondary)
                            .foregroundStyle(DS.Cut.Colors.textSecondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .accessibilityHidden(true)
                    Text(hero.line)
                        .font(DS.Cut.Typography.font(.secondary).weight(.semibold))
                        .foregroundStyle(hero.lineIsActive ? DS.Cut.Colors.lime : DS.Cut.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if let line = model.emptyLine {
            HStack(alignment: .center, spacing: 22) {
                VMarkProgress(left: 0, right: 0, tone: .line, accessibilityLabel: "No level yet")
                    .frame(width: 112)
                Text(line)
                    .cutFont(.body)
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Weekly goal

    private var goalSection: some View {
        CutHairlineList {
            switch model.goal {
            case .setUp:
                Button(action: actions.setUpGoal) {
                    CutHairlineRow("Set weekly goals", subtitle: "Active minutes and strength days", showsChevron: true)
                }
                .buttonStyle(.plain)
            case .progress(let rows):
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        Button(action: actions.openWeeklyGoal) {
                            valueRow(row.title, value: row.value, isMet: row.isMet)
                        }
                        .buttonStyle(.plain)
                    }
                }
                // The legacy card's long-press actions.
                .contextMenu {
                    Button("Customize goal", systemImage: "slider.horizontal.3", action: actions.customizeGoal)
                    Button("Reset weekly goal", systemImage: "arrow.counterclockwise", role: .destructive, action: actions.resetGoal)
                }
            }
            if let freeze = model.freeze {
                Button {
                    confirmsFreeze = true
                } label: {
                    CutHairlineRow("Streak freeze", value: freeze.value, valueTone: .lime,
                                   subtitle: freeze.line, showsChevron: freeze.canActivate)
                }
                .buttonStyle(.plain)
                .disabled(!freeze.canActivate)
            }
            if model.canShareWeek {
                Button(action: actions.shareWeek) {
                    iconRow("Share this week", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// A goal row: title on the left, the count as a condensed numeral on the right.
    private func valueRow(_ title: String, value: String, isMet: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text(title)
                    .cutFont(.title)
                    .foregroundStyle(DS.Cut.Colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(value)
                    .font(DS.Cut.Typography.condensed(size: 28, relativeTo: .title2, monospacedDigits: true))
                    .foregroundStyle(isMet ? DS.Cut.Colors.lime : DS.Cut.Colors.textPrimary)
                    .lineLimit(1)
                    .fixedSize()
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 50)
            .padding(.vertical, 10)
            CutHairline()
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func iconRow(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text(title)
                    .cutFont(.title)
                    .foregroundStyle(DS.Cut.Colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 50)
            .padding(.vertical, 10)
            CutHairline()
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Plan adherence

    private func adherenceSection(_ adherence: CutMeModel.Adherence) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CutSectionTitle("Plan adherence")
            Text(adherence.hero)
                .cutNumeral(.large)
                .foregroundStyle(DS.Cut.Colors.textPrimary)
                .padding(.top, 8)
            Text(adherence.line)
                .cutFont(.secondary)
                .foregroundStyle(DS.Cut.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
            if let segments = adherence.segments {
                CutSegmentProgress(total: segments.total, filled: segments.filled,
                                   accessibilityLabel: Text("Planned sessions this week"))
                    .padding(.top, 14)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Training trends

    private var trendsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch model.trends {
            case .empty(let line):
                CutSectionTitle("Training trends")
                Text(line)
                    .cutFont(.secondary)
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            case .data(let value, let unit, let line, let bars):
                sectionHeader("Training trends", action: actions.openTrends)
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Text(value)
                        .font(DS.Cut.Typography.condensed(size: DS.Cut.Typography.Hero.l.size, monospacedDigits: true))
                        .tracking(DS.Cut.Typography.Hero.l.tracking)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(DS.Cut.Colors.textPrimary)
                    Text(unit)
                        .cutHero(.xs)
                        .foregroundStyle(DS.Cut.Colors.textPrimary)
                        .fixedSize()
                }
                .accessibilityElement(children: .combine)
                .padding(.top, 6)
                Text(line)
                    .cutFont(.secondary)
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                CutMeWeekChart(bars: bars)
                    .padding(.top, 20)
            }
        }
    }

    // MARK: Training balance

    private func balanceSection(_ balance: CutMeModel.Balance) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Training balance", action: actions.openBalance)
            if let push = balance.push, let pull = balance.pull {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(push)
                        .cutNumeral(.large)
                        .foregroundStyle(DS.Cut.Colors.textPrimary)
                    Text("push")
                        .cutFont(.secondary)
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                    Spacer(minLength: 12)
                    Text("pull")
                        .cutFont(.secondary)
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                    Text(pull)
                        .cutNumeral(.large)
                        .foregroundStyle(DS.Cut.Colors.textPrimary)
                }
                .lineLimit(1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Push \(push), pull \(pull)"))
                .padding(.top, 6)
                CutSplitBar(fraction: balance.pushFraction ?? 0)
                    .padding(.top, 8)
            }
            if !balance.rows.isEmpty {
                CutHairlineList {
                    ForEach(balance.rows) { row in
                        CutHairlineRow(row.title, value: row.value)
                    }
                }
                .padding(.top, 18)
            }
        }
    }

    // MARK: Collection

    private var collectionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            CutSectionTitle("Collection")
                .padding(.bottom, 4)
            CutHairlineList {
                CutBigRow("PR collection", action: actions.openRecords) { count(model.prCount) }
                CutBigRow("Milestones", action: actions.openMilestones) { count(model.milestoneCount) }
                CutBigRow("Your barbell", action: actions.openBarbell) {
                    CutTile(systemImage: "arrow.right", side: 56)
                }
            }
        }
    }

    @ViewBuilder
    private func count(_ value: String?) -> some View {
        if let value {
            Text(value)
                .cutHero(.s)
                .foregroundStyle(DS.Cut.Colors.textPrimary)
                .fixedSize()
        }
    }

    // MARK: Pieces

    /// A section title with a lime Details link on the right.
    private func sectionHeader(_ title: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            CutSectionTitle(title)
            Button(action: action) {
                Text("Details")
                    .cutFont(.title)
                    .foregroundStyle(DS.Cut.Colors.lime)
                    .frame(minHeight: DS.Cut.Metrics.minTouchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(title) details"))
            .fixedSize()
        }
        .frame(minHeight: DS.Cut.Metrics.minTouchTarget)
    }
}

/// Twelve weekly bars, oldest first. The hero week is lime and cut at the corner; the rest grey.
private struct CutMeWeekChart: View {
    let bars: [CutMeModel.WeekBar]

    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 96

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(bars) { bar in
                VStack {
                    Spacer(minLength: 0)
                    if bar.fraction > 0 {
                        CutCornerShape(corner: .topTrailing, cut: .points(bar.isHighlighted ? 10 : 0))
                            .fill(bar.isHighlighted ? DS.Cut.Colors.lime : DS.Cut.Colors.controlFill)
                            .frame(height: max(6, height * bar.fraction))
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: height)
        .overlay(alignment: .bottom) { CutHairline() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Weekly tonnage, last 12 weeks"))
    }
}
