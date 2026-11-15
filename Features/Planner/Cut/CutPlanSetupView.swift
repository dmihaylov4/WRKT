//
//  CutPlanSetupView.swift
//  WRKT
//
//  The new program flow: a round back or close button, a segmented progress bar and "n of N",
//  a big condensed question, choices as full-width tiles, and one button at the bottom.
//

import SwiftUI

struct CutPlanSetupActions {
    var back: () -> Void = {}
    var next: () -> Void = {}
    // Split
    var chooseTemplate: (String) -> Void = { _ in }
    var chooseBuildOwn: () -> Void = {}
    var deleteSaved: (String) -> Void = { _ in }
    // Days
    var toggleDay: (Int) -> Void = { _ in }
    var setWeeks: (Int) -> Void = { _ in }
    // Review
    var openDay: (String) -> Void = { _ in }
    var changeStart: () -> Void = {}
    var start: () -> Void = {}
    // Customise one day
    var editExercise: (Int) -> Void = { _ in }
    var removeExercise: (Int) -> Void = { _ in }
    var addExercise: () -> Void = {}
    // Custom path
    var setName: (String) -> Void = { _ in }
    var setPartCount: (Int) -> Void = { _ in }
    var setPartName: (Int, String) -> Void = { _, _ in }
    var quickFill: () -> Void = {}
    var openPart: (String) -> Void = { _ in }
}

enum CutPlanSetupContent: Equatable {
    case split(CutPlanSplitModel)
    case customName(CutPlanCustomNameModel)
    case customExercises(CutPlanCustomExercisesModel)
    case days(CutPlanDaysModel)
    case customize(CutPlanCustomizeModel)
    case review(CutPlanReviewModel)
}

struct CutPlanSetupView: View {
    let content: CutPlanSetupContent
    let step: Int
    let total: Int
    /// The first screen closes the flow; later screens go back.
    let isFirst: Bool
    var actions = CutPlanSetupActions()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    screen
                    // At accessibility sizes the button scrolls with the screen instead of covering it.
                    if dynamicTypeSize.isAccessibilitySize { bottomBar.padding(.top, 24) }
                }
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
            if !dynamicTypeSize.isAccessibilitySize { bottomBar }
        }
        .foregroundStyle(DS.Cut.Colors.textPrimary)
        .background(DS.Cut.Colors.background.ignoresSafeArea())
    }

    // MARK: Header

    private var topBar: some View {
        CutPlannerTopBar(leading: isFirst ? .close : .back, action: actions.back) {
            HStack(spacing: 5) {
                ForEach(0..<total, id: \.self) { index in
                    Capsule()
                        .fill(index < step ? DS.Cut.Colors.lime : DS.Cut.Colors.segmentTrack)
                        .frame(height: 6)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
            Text("\(step) of \(total)")
                .font(DS.Typography.custom(size: 16, weight: .semibold, relativeTo: .subheadline, monospacedDigits: true))
                .foregroundStyle(DS.Cut.Colors.textSecondary)
                .lineLimit(1)
                .fixedSize()
                .accessibilityLabel(Text("Step \(step) of \(total)"))
        }
    }

    private func title(_ text: String, line: String? = nil, lineColor: Color = DS.Cut.Colors.textSecondary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CutPlannerTitle(text)
            if let line { CutPlannerLine(line, color: lineColor, size: 17) }
        }
        .padding(.horizontal, DS.Cut.Metrics.gutter)
        .padding(.top, 26)
    }

    @ViewBuilder private var screen: some View {
        switch content {
        case .split(let model): split(model)
        case .customName(let model): customName(model)
        case .customExercises(let model): customExercises(model)
        case .days(let model): days(model)
        case .customize(let model): customize(model)
        case .review(let model): review(model)
        }
    }

    // MARK: Split

    private func split(_ model: CutPlanSplitModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            title("How do you want to train?")
            VStack(spacing: 10) {
                ForEach(model.templates) { option in
                    CutPlanSetupTile(option: option) { actions.chooseTemplate(option.id) }
                }
                CutPlanSetupTile(option: model.buildOwn, outlined: true, action: actions.chooseBuildOwn)
            }
            .padding(.horizontal, DS.Cut.Metrics.panelInset)
            .padding(.top, 22)
            if !model.saved.isEmpty {
                CutPanelHeader("Your splits").padding(.top, 26)
                VStack(spacing: 10) {
                    ForEach(model.saved) { option in
                        CutPlanSetupTile(option: option) { actions.chooseTemplate(option.id) }
                            .contextMenu {
                                Button("Delete split", systemImage: "trash", role: .destructive) { actions.deleteSaved(option.id) }
                            }
                            .accessibilityAction(named: Text("Delete split")) { actions.deleteSaved(option.id) }
                    }
                }
                .padding(.horizontal, DS.Cut.Metrics.panelInset)
                .padding(.top, 10)
            }
        }
    }

    // MARK: Days

    private func days(_ model: CutPlanDaysModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            title("Which days?", line: "Tap the days you train. The rest are rest days.")
            let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: dynamicTypeSize.isAccessibilitySize ? 3 : 7)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(model.tiles) { tile in
                    Button { actions.toggleDay(tile.id) } label: {
                        Text(tile.short)
                            .font(DS.Typography.custom(size: 17, weight: tile.isTraining ? .bold : .semibold, relativeTo: .body))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(tile.isTraining ? DS.Cut.Colors.ink : DS.Cut.Colors.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 72)
                            .background(Rectangle().fill(tile.isTraining ? DS.Cut.Colors.lime : DS.Cut.Colors.panel))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(tile.spoken))
                    .accessibilityAddTraits(tile.isTraining ? .isSelected : [])
                }
            }
            .padding(.horizontal, DS.Cut.Metrics.panelInset)
            .padding(.top, 24)
            Text(model.countLine)
                .font(DS.Typography.custom(size: 18, weight: .semibold, relativeTo: .body))
                .foregroundStyle(model.countIsWarning ? DS.Cut.Colors.destructive : DS.Cut.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, DS.Cut.Metrics.gutter)
                .padding(.top, 20)
            CutPlannerLabel("Run it for")
                .padding(.horizontal, DS.Cut.Metrics.gutter)
                .padding(.top, 30)
            CutPlannerSegmented(items: model.weekOptions, selected: model.selectedWeeks, title: { "\($0) weeks" },
                                select: actions.setWeeks, fill: DS.Cut.Colors.panel)
                .padding(.horizontal, 20)
                .padding(.top, 10)
        }
    }

    // MARK: Customise one day

    private func customize(_ model: CutPlanCustomizeModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            title(model.title, line: "Tap an exercise to change it.")
            if !model.rows.isEmpty {
                CutPanel {
                    ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { CutHairline() }
                        HStack(spacing: 12) {
                            Button { actions.editExercise(row.id) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    CutPlannerRowTitle(row.name)
                                    CutPlannerLine(row.line)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .combine)
                            .accessibilityHint(Text("Changes sets, reps and weight"))
                            Button { actions.removeExercise(row.id) } label: {
                                Image(systemName: "minus")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(DS.Cut.Colors.destructive)
                                    .frame(width: DS.Cut.Metrics.minTouchTarget, height: DS.Cut.Metrics.minTouchTarget)
                                    .background(Circle().fill(DS.Cut.Colors.panelControl))
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Remove \(row.name)"))
                        }
                        .padding(.horizontal, DS.Cut.Metrics.panelRowPadding)
                        .padding(.vertical, 12)
                    }
                }
                .padding(.top, 22)
            }
            Button("Add exercise", systemImage: "plus", action: actions.addExercise)
                .buttonStyle(CutPillButtonStyle(.outline))
                .padding(.horizontal, DS.Cut.Metrics.gutter)
                .padding(.top, 16)
        }
    }

    // MARK: Review

    private func review(_ model: CutPlanReviewModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            title(model.title, line: model.line, lineColor: DS.Cut.Colors.lime)
            CutPanel {
                ForEach(Array(model.days.enumerated()), id: \.element.id) { index, day in
                    if index > 0 { CutHairline() }
                    Button { actions.openDay(day.dayID) } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                CutPlannerRowTitle(day.title)
                                CutPlannerLine(day.line)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(DS.Cut.Colors.textSecondary)
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, DS.Cut.Metrics.panelRowPadding)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint(Text("Changes its exercises"))
                }
            }
            .padding(.top, 22)
            CutPlannerLine("Tap a day to change its exercises.")
                .padding(.horizontal, DS.Cut.Metrics.gutter)
                .padding(.top, 12)
        }
    }

    // MARK: Custom path

    private func customName(_ model: CutPlanCustomNameModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            title("Name your split")
            CutPlannerField(prompt: "My split", text: Binding(get: { model.name }, set: actions.setName), fill: DS.Cut.Colors.panel)
                .accessibilityLabel(Text("Split name"))
                .padding(.horizontal, DS.Cut.Metrics.panelInset)
                .padding(.top, 22)
            CutPlannerLabel("Parts")
                .padding(.horizontal, DS.Cut.Metrics.gutter)
                .padding(.top, 26)
            CutPlannerSegmented(items: CutPlanSetupLogic.partOptions, selected: model.partCount > 0 ? model.partCount : nil,
                                title: { "\($0) parts" }, select: actions.setPartCount, fill: DS.Cut.Colors.panel)
                .padding(.horizontal, 20)
                .padding(.top, 10)
            if !model.partNames.isEmpty {
                VStack(spacing: 10) {
                    ForEach(Array(model.partNames.enumerated()), id: \.offset) { index, name in
                        CutPlannerField(prompt: "Part \(index + 1)", text: Binding(get: { name }, set: { actions.setPartName(index, $0) }),
                                        fill: DS.Cut.Colors.panel)
                            .accessibilityLabel(Text("Part \(index + 1) name"))
                    }
                }
                .padding(.horizontal, DS.Cut.Metrics.panelInset)
                .padding(.top, 16)
            }
            if let hint = model.hint {
                CutPlannerLine(hint, color: DS.Cut.Colors.destructive)
                    .padding(.horizontal, DS.Cut.Metrics.gutter)
                    .padding(.top, 12)
            }
            if model.showsQuickFill {
                Button("Use Push, Pull, Legs", action: actions.quickFill)
                    .buttonStyle(CutPillButtonStyle(.outline))
                    .padding(.horizontal, DS.Cut.Metrics.gutter)
                    .padding(.top, 16)
            }
        }
    }

    private func customExercises(_ model: CutPlanCustomExercisesModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            title("Add exercises", line: "Pick \(PlannerConstants.ExerciseLimits.minPerPart) to \(PlannerConstants.ExerciseLimits.maxPerPart) for each part.")
            CutPanel {
                ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { CutHairline() }
                    Button { actions.openPart(row.name) } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                CutPlannerRowTitle(row.name)
                                CutPlannerLine(row.line)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: row.isComplete ? "checkmark" : "chevron.right")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(row.isComplete ? DS.Cut.Colors.lime : DS.Cut.Colors.textSecondary)
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, DS.Cut.Metrics.panelRowPadding)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(Text(row.isComplete ? "Ready" : "Needs exercises"))
                }
            }
            .padding(.top, 22)
        }
    }

    // MARK: Bottom

    @ViewBuilder private var bottomBar: some View {
        VStack(spacing: 10) {
            switch content {
            case .split(let model): nextButton(enabled: model.canProceed)
            case .customName(let model): nextButton(enabled: model.canProceed)
            case .customExercises(let model): nextButton(enabled: model.canProceed)
            case .days(let model): nextButton(enabled: model.canProceed)
            case .customize:
                Button("Done", action: actions.next).buttonStyle(CutPillButtonStyle(.white, size: .regular, fillsWidth: true))
            case .review(let model):
                Button(action: actions.changeStart) {
                    VStack(spacing: 2) {
                        (Text(model.startLine) + Text(" Change").foregroundStyle(DS.Cut.Colors.lime).fontWeight(.bold))
                        if let replace = model.replaceLine { Text(replace) }
                    }
                    .font(DS.Typography.custom(size: 16, weight: .medium, relativeTo: .subheadline))
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text([model.startLine, model.replaceLine].compactMap { $0 }.joined(separator: " ")))
                .accessibilityHint(Text("Changes the start date"))
                Button(model.buttonTitle, action: actions.start)
                    .buttonStyle(CutPillButtonStyle(.lime, size: .regular, fillsWidth: true))
                    .disabled(!model.canStart)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(DS.Cut.Colors.background.ignoresSafeArea())
    }

    private func nextButton(enabled: Bool) -> some View {
        Button("Next", action: actions.next)
            .buttonStyle(CutPillButtonStyle(.white, size: .regular, fillsWidth: true))
            .disabled(!enabled)
    }
}

/// A full-width choice tile: lime with a check when chosen, a raised panel otherwise.
private struct CutPlanSetupTile: View {
    let option: CutPlanSplitModel.Option
    var outlined = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(DS.Typography.custom(size: 20, weight: .bold, relativeTo: .title3))
                    Text(option.line)
                        .font(DS.Typography.custom(size: 16, weight: option.isSelected ? .semibold : .medium, relativeTo: .subheadline))
                        .foregroundStyle(option.isSelected ? DS.Cut.Colors.ink : DS.Cut.Colors.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                if option.isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 20, weight: .bold))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(option.isSelected ? DS.Cut.Colors.ink : DS.Cut.Colors.textPrimary)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Rectangle().fill(option.isSelected ? DS.Cut.Colors.lime : (outlined ? Color.clear : DS.Cut.Colors.panel)))
            .overlay { if outlined && !option.isSelected { Rectangle().strokeBorder(DS.Cut.Colors.hairlineStrong, lineWidth: 1.5) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(option.isSelected ? .isSelected : [])
    }
}

/// The start date, as the legacy review's date picker offered it.
struct CutPlanStartDateView: View {
    @Binding var date: Date
    var done: () -> Void = {}
    var close: () -> Void = {}

    var body: some View {
        CutSheet("Start date", close: close) {
            DatePicker("Start date", selection: $date, in: Calendar.current.startOfDay(for: .now)..., displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(DS.Cut.Colors.lime)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        } footer: {
            Button("Done", action: done)
                .buttonStyle(CutPillButtonStyle(.lime, size: .regular, fillsWidth: true))
                .padding(.horizontal, DS.Cut.Metrics.gutter)
                .padding(.top, 8)
                .padding(.bottom, 12)
        }
    }
}
