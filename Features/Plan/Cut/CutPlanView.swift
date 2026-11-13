//
//  CutPlanView.swift
//  WRKT
//
//  The Plan tab in the Cut language: one-row header, the month as condensed numerals with
//  restrained marks, and a panel about the selected day only. Takes plain values and closures,
//  so every state can be rendered without the app's services (see CutPlanHost for live data).
//

import SwiftUI

/// What the Plan tab's controls do. Every closure calls an existing flow.
struct CutPlanActions {
    var previousMonth: () -> Void = {}
    var nextMonth: () -> Void = {}
    var goToToday: () -> Void = {}
    var selectDay: (Date) -> Void = { _ in }
    var editPlan: () -> Void = {}
    var openWeek: () -> Void = {}
    var perform: (CutPlanDayPanel.Action) -> Void = { _ in }
    var refresh: () async -> Void = {}
    /// Frames for the first-run tutorial, in global coordinates.
    var reportFrame: (CutPlanTutorialTarget, CGRect) -> Void = { _, _ in }
}

struct CutPlanView<Accessory: View>: View {
    let model: CutPlanModel
    var actions = CutPlanActions()
    /// Shown between the header and the calendar (the Health sync progress while it runs).
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                accessory()
                CutPlanCalendar(month: model.month, actions: actions)
                    .padding(.top, 6)
                    .captureFrame { actions.reportFrame(.calendar, $0) }
                CutPlanDayPanelView(panel: model.panel, perform: actions.perform)
                    .padding(.top, 16)
                    .captureFrame { actions.reportFrame(.day, $0) }
            }
            .padding(.horizontal, DS.Cut.Metrics.gutter)
            .padding(.top, 8)
            .padding(.bottom, DS.Redesign.tabBarClearance(legacy: 80, system: 60))
        }
        .scrollIndicators(.hidden)
        .refreshable { await actions.refresh() }
        .background(DS.Cut.Colors.background.ignoresSafeArea())
    }

    private var header: some View {
        CutTabHeader("Plan") {
            if model.showsGoToToday {
                Button("Go to today", systemImage: "calendar", action: actions.goToToday)
            }
            Button("Weekly goal", systemImage: "flame") {
                Haptics.light()
                actions.openWeek()
            }
            .captureFrame { actions.reportFrame(.week, $0) }
            Button("Edit plan", systemImage: "pencil") {
                Haptics.light()
                actions.editPlan()
            }
            .captureFrame { actions.reportFrame(.editPlan, $0) }
        }
    }
}

extension CutPlanView where Accessory == EmptyView {
    init(model: CutPlanModel, actions: CutPlanActions = CutPlanActions()) {
        self.init(model: model, actions: actions) { EmptyView() }
    }
}

// MARK: - Calendar

private struct CutPlanCalendar: View {
    let month: CutPlanMonth
    let actions: CutPlanActions

    var body: some View {
        VStack(spacing: 0) {
            monthRow
            weekdayRow
                .padding(.top, 8)
            VStack(spacing: 2) {
                ForEach(Array(month.weeks.enumerated()), id: \.offset) { _, week in
                    HStack(spacing: 0) {
                        ForEach(week) { cell in
                            CutPlanDayCellView(cell: cell) { actions.selectDay(cell.date) }
                        }
                    }
                }
            }
            .padding(.top, 4)
            // Large text sizes would overflow the 44 pt day circle; the panel keeps scaling.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .simultaneousGesture(
                DragGesture(minimumDistance: 20).onEnded { value in
                    switch CutPlanLogic.swipeStep(translation: value.translation) {
                    case 1: actions.nextMonth()
                    case -1: actions.previousMonth()
                    default: break
                    }
                }
            )
        }
    }

    private var monthRow: some View {
        HStack(spacing: 0) {
            chevron("chevron.left", label: "Previous month", action: actions.previousMonth)
            Text(month.title)
                .font(DS.Cut.Typography.condensed(size: 26, weight: .extraBold, relativeTo: .title2))
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(DS.Cut.Colors.textPrimary)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            chevron("chevron.right", label: "Next month", action: actions.nextMonth)
        }
    }

    /// Bare chevron at the calendar's edge: no platter, low opacity, 44 pt target.
    private func chevron(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(DS.Cut.Colors.textPrimary.opacity(0.4))
                .frame(width: DS.Cut.Metrics.minTouchTarget, height: DS.Cut.Metrics.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(month.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(DS.Cut.Typography.font(.secondary).weight(.bold))
                    .foregroundStyle(DS.Cut.Colors.textSecondary.opacity(0.7))
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct CutPlanDayCellView: View {
    let cell: CutPlanDayCell
    let select: () -> Void

    private var numberColor: Color {
        if cell.isSelected { return DS.Cut.Colors.ink }
        if !cell.inMonth { return DS.Cut.Colors.textPrimary.opacity(0.25) }
        if cell.isToday { return DS.Cut.Colors.lime }
        return DS.Cut.Colors.textPrimary
    }

    var body: some View {
        Button(action: select) {
            VStack(spacing: 4) {
                Text("\(cell.day)")
                    .font(DS.Cut.Typography.condensed(size: 22, weight: .bold, relativeTo: .title3, monospacedDigits: true))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(numberColor)
                HStack(spacing: 3) {
                    ForEach(Array(cell.marks.enumerated()), id: \.offset) { _, mark in
                        CutPlanMarkView(mark: mark, onLime: cell.isSelected)
                    }
                }
                .frame(height: 6)
                .opacity(cell.inMonth || cell.isSelected ? 1 : 0.35)
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .background {
                if cell.isSelected {
                    Circle()
                        .fill(DS.Cut.Colors.lime)
                        .frame(width: 44, height: 44)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(cell.accessibilityLabel))
        .accessibilityAddTraits(cell.isSelected ? .isSelected : [])
    }
}

/// A 6 pt square with its bottom trailing half cut away, or an outlined square for a plan.
private struct CutPlanMarkView: View {
    let mark: CutPlanMark
    let onLime: Bool

    private static let shape = CutCornerShape(corner: .bottomTrailing, cut: .fraction(0.5))

    var body: some View {
        Group {
            switch mark {
            case .strength:
                Self.shape.fill(onLime ? DS.Cut.Colors.ink : DS.Cut.Colors.lime)
            case .cardio:
                Self.shape.fill(onLime ? DS.Cut.Colors.ink.opacity(0.55) : DS.Cut.Colors.textPrimary)
            case .planned:
                Rectangle().strokeBorder(onLime ? DS.Cut.Colors.ink : DS.Cut.Colors.lime, lineWidth: 1.5)
            }
        }
        .frame(width: 6, height: 6)
        .accessibilityHidden(true)
    }
}

// MARK: - Day panel

private struct CutPlanDayPanelView: View {
    let panel: CutPlanDayPanel
    let perform: (CutPlanDayPanel.Action) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CutHairline()
            VStack(alignment: .leading, spacing: 0) {
                Text(panel.title)
                    .cutHero(.action, minimumScaleFactor: 0.5)
                    .foregroundStyle(panel.isToday ? DS.Cut.Colors.lime : DS.Cut.Colors.textPrimary)
                Text(panel.headline)
                    .font(DS.Typography.custom(size: 24, weight: .bold, relativeTo: .title2))
                    .foregroundStyle(DS.Cut.Colors.textPrimary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                if let line = panel.line {
                    Text(line)
                        .cutFont(.body)
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
            }
            .padding(.top, 16)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            if !panel.actions.isEmpty {
                // Side by side when they fit; stacked at large Dynamic Type sizes.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { buttons }
                    VStack(alignment: .leading, spacing: 10) { buttons }
                }
                .padding(.top, 18)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var buttons: some View {
        ForEach(panel.actions, id: \.self) { action in
            let title = CutPlanLogic.label(for: action)
            if CutPlanLogic.isPrimary(action) {
                Button(title) {
                    Haptics.medium()
                    perform(action)
                }
                .buttonStyle(CutPrimaryButtonStyle(fillsWidth: false))
            } else {
                Button(title) {
                    Haptics.light()
                    perform(action)
                }
                .buttonStyle(CutSecondaryButtonStyle(fillsWidth: false))
            }
        }
    }
}
