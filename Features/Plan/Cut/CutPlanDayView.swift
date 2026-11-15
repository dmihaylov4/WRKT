//
//  CutPlanDayView.swift
//  WRKT
//
//  "View day" in the Cut language: the date as a modest hero, the daily summary behind a quiet
//  disclosure, the day's one action as the Plan panel's pill, the planned session, then the
//  workouts and cardio as hairline rows. Takes plain values and closures, so every state renders
//  without the app's services (see CutPlanDayHost for live data).
//

import SwiftUI

struct CutPlanDayActions {
    /// Start, log, plan, start today's plan, edit the plan: the Plan panel's actions.
    var perform: (CutPlanDayPanel.Action) -> Void = { _ in }
    /// A workout or cardio row.
    var open: (CutPlanWorkoutRef) -> Void = { _ in }
    /// Today's completed plan: the workout that completed it.
    var openCompletedPlan: (UUID) -> Void = { _ in }
    /// Start now, start again, delete.
    var planMenu: (CutPlanDayModel.PlanMenuItem) -> Void = { _ in }
}

struct CutPlanDayView: View {
    let model: CutPlanDayModel
    var actions = CutPlanDayActions()
    /// Starts with the summary and the plan's exercises open (captures only; both start closed).
    let startsExpanded: Bool

    @State private var showsSummary = false
    @State private var showsPlanExercises = false

    init(model: CutPlanDayModel, actions: CutPlanDayActions = CutPlanDayActions(), startsExpanded: Bool = false) {
        self.model = model
        self.actions = actions
        self.startsExpanded = startsExpanded
        _showsSummary = State(initialValue: startsExpanded)
        _showsPlanExercises = State(initialValue: startsExpanded)
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if !model.actions.isEmpty {
                    CutPlanDayPills(actions: model.actions, perform: actions.perform)
                        .padding(.top, 24)
                }
                if let completed = model.completedPlan {
                    completedPlan(completed).padding(.top, 28)
                }
                if let plan = model.plan {
                    planBlock(plan).padding(.top, 32)
                }
                if model.showsNoActivity {
                    Text("No activity")
                        .cutFont(.body)
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                        .padding(.top, 32)
                }
                if let workouts = model.workouts {
                    section(workouts).padding(.top, 36)
                }
                if let cardio = model.cardio {
                    section(cardio).padding(.top, 36)
                }
            }
            .padding(.horizontal, DS.Cut.Metrics.gutter)
            .padding(.top, 8)
            .padding(.bottom, DS.Redesign.tabBarClearance(legacy: 80, system: 60))
        }
        .scrollIndicators(.hidden)
        .background(DS.Cut.Colors.background.ignoresSafeArea())
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            CutHeroText(model.title, hero: .xs, minimumScaleFactor: 0.5)
                .foregroundStyle(DS.Cut.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(Text(model.accessibilityTitle))
                .accessibilityAddTraits(.isHeader)
            if let line = model.line {
                Text(line)
                    .cutFont(.secondary)
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .padding(.top, 6)
            }
            if let summary = model.summary {
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { showsSummary.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text("Daily summary")
                        Image(systemName: showsSummary ? "chevron.up" : "chevron.down")
                            .imageScale(.small)
                            .accessibilityHidden(true)
                    }
                    .cutFont(.secondary)
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .frame(minHeight: DS.Cut.Metrics.minTouchTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(Text(showsSummary ? "Shown" : "Hidden"))
                .padding(.top, 2)
                if showsSummary {
                    VStack(spacing: 0) {
                        CutHairline()
                        let rows = dynamicTypeSize.isAccessibilitySize
                            ? [Array(summary.prefix(2)), Array(summary.dropFirst(2))]
                            : [summary]
                        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                            if index > 0 { CutHairline() }
                            CutStatColumns(row).padding(.vertical, 14)
                        }
                        CutHairline()
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    // MARK: Plan

    private func completedPlan(_ completed: CutPlanDayModel.CompletedPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CutSectionTitle("Today's plan")
            CutHairline()
            Button {
                if let id = completed.workoutID {
                    Haptics.light()
                    actions.openCompletedPlan(id)
                }
            } label: {
                CutPlanDayRowLabel(title: "Plan completed", subtitle: completed.subtitle, value: nil,
                                   leading: "checkmark", isHealthMatched: false,
                                   showsChevron: completed.workoutID != nil)
            }
            .buttonStyle(.plain)
            .disabled(completed.workoutID == nil)
            .accessibilityLabel(Text("Plan completed, \(completed.subtitle)"))
        }
    }

    private func planBlock(_ plan: CutPlanDayModel.Plan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CutSectionTitle(plan.sectionTitle)
            CutHairline()
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    Button {
                        guard !plan.exercises.isEmpty else { return }
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { showsPlanExercises.toggle() }
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(plan.name)
                                    .cutFont(.title)
                                    .foregroundStyle(DS.Cut.Colors.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(plan.statusLine)
                                    .cutFont(.secondary)
                                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if !plan.exercises.isEmpty {
                                Image(systemName: showsPlanExercises ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                                    .accessibilityHidden(true)
                            }
                        }
                        .frame(minHeight: 50)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint(Text(plan.exercises.isEmpty ? "" : (showsPlanExercises ? "Hides the exercises" : "Shows the exercises")))
                    if !plan.menu.isEmpty {
                        Menu {
                            ForEach(plan.menu, id: \.self) { item in
                                Button(CutPlanDayLogic.menuLabel(item),
                                       systemImage: item == .delete ? "trash" : (item == .startAgain ? "arrow.clockwise" : "play"),
                                       role: item == .delete ? .destructive : nil) {
                                    actions.planMenu(item)
                                }
                            }
                        } label: {
                            Label("More", systemImage: "ellipsis")
                        }
                        .menuStyle(.button)
                        .buttonStyle(CutIconButtonStyle(diameter: DS.Cut.Metrics.minTouchTarget))
                        .fixedSize()
                        .accessibilityLabel(Text("More for \(plan.name)"))
                    }
                }
                .padding(.vertical, 6)
                if showsPlanExercises {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(plan.exercises) { exercise in
                            CutHairline()
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(exercise.name)
                                    .cutFont(.body)
                                    .foregroundStyle(DS.Cut.Colors.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(exercise.detail)
                                    .cutFont(.secondary, monospacedDigits: true)
                                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                                    .fixedSize()
                            }
                            .padding(.vertical, 12)
                            .accessibilityElement(children: .combine)
                        }
                        if let more = plan.moreLine {
                            CutHairline()
                            Text(more)
                                .cutFont(.secondary)
                                .foregroundStyle(DS.Cut.Colors.textSecondary)
                                .padding(.vertical, 12)
                        }
                    }
                    .transition(.opacity)
                }
                CutHairline()
            }
            if !plan.actions.isEmpty {
                CutPlanDayPills(actions: plan.actions, perform: actions.perform)
                    .padding(.top, 10)
            }
        }
    }

    // MARK: Sections

    private func section(_ section: CutPlanDayModel.Section) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                CutSectionTitle(section.title)
                Text("\(section.count)")
                    .cutFont(.secondary, monospacedDigits: true)
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("\(section.title), \(section.count)"))
            .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                CutHairline()
                ForEach(section.rows) { row in
                    Button {
                        Haptics.light()
                        actions.open(row.target)
                    } label: {
                        CutPlanDayRowLabel(title: row.title, subtitle: row.subtitle, value: row.value,
                                           leading: nil, isHealthMatched: row.isHealthMatched, showsChevron: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(row.accessibilityLabel))
                }
            }
        }
    }
}

// MARK: - Pieces

/// The Plan panel's pills: lime for start, log and plan, outlined for edit; side by side when
/// they fit, stacked at large text sizes. Same labels and styles as the day panel.
struct CutPlanDayPills: View {
    let actions: [CutPlanDayPanel.Action]
    let perform: (CutPlanDayPanel.Action) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { buttons }
            VStack(alignment: .leading, spacing: 10) { buttons }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        ForEach(actions, id: \.self) { action in
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

/// A hairline row: title over one secondary line, an optional value, the Health heart and a chevron.
private struct CutPlanDayRowLabel: View {
    let title: String
    let subtitle: String
    let value: String?
    /// A lime cut tile glyph before the title (the completed plan's check).
    let leading: String?
    let isHealthMatched: Bool
    let showsChevron: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                if let leading {
                    CutTile(systemImage: leading, side: 32)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .cutFont(.title)
                        .foregroundStyle(DS.Cut.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .cutFont(.secondary, monospacedDigits: true)
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let value, dynamicTypeSize.isAccessibilitySize {
                        Text(value)
                            .cutFont(.secondary, monospacedDigits: true)
                            .foregroundStyle(DS.Cut.Colors.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let value, !dynamicTypeSize.isAccessibilitySize {
                    Text(value)
                        .font(DS.Cut.Typography.font(.secondary, monospacedDigits: true).weight(.semibold))
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                        .fixedSize()
                }
                if isHealthMatched {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                        .accessibilityHidden(true)
                }
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 50)
            .padding(.vertical, 10)
            CutHairline()
        }
        .contentShape(Rectangle())
    }
}
