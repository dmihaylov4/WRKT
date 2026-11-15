//
//  CutWeeklyGoalSetupView.swift
//  WRKT
//
//  Weekly goal setup in the Cut language, one family with the Settings pages: a modest title
//  with one line under it, then age, the activity target, strength days and the week start as
//  hairline sections. Steppers are grey minus and plus pills beside a plain value; the activity
//  target keeps its slider, tinted lime; the week start is a choice row. Save goal is the one
//  lime pill, at the end. Plain values, bindings and closures (see CutWeeklyGoalSetupHost).
//

import SwiftUI

struct CutWeeklyGoalSetupControls {
    /// The activity slider's position, in minutes or steps per the tracking mode.
    var activity: Binding<Double>
    var activityRange: ClosedRange<Double>
    var activityStep: Double
    var weekStart: Binding<Int>
}

struct CutWeeklyGoalSetupActions {
    var stepAge: (Int) -> Void = { _ in }
    var stepStrength: (Int) -> Void = { _ in }
    var save: () -> Void = {}
}

struct CutWeeklyGoalSetupView: View {
    let model: CutWeeklyGoalSetupModel
    let controls: CutWeeklyGoalSetupControls
    var actions = CutWeeklyGoalSetupActions()

    var body: some View {
        CutSettingsPage(title: model.title, subtitle: model.subtitle) {
            CutSettingsSectionHeader("Age", isFirst: true)
            CutGoalStepperRow(title: "Your age", value: model.age,
                              canDecrease: model.canDecreaseAge, canIncrease: model.canIncreaseAge,
                              step: actions.stepAge)
            CutSettingsFooter(model.ageFooter)

            CutSettingsSectionHeader(model.activityTitle)
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    CutSettingsRowText(title: "Target")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(model.activityValue)
                        .font(DS.Cut.Typography.font(.title, monospacedDigits: true).weight(.semibold))
                        .foregroundStyle(DS.Cut.Colors.textPrimary)
                        .lineLimit(1)
                        .fixedSize()
                }
                .frame(minHeight: 50)
                .padding(.top, 10)
                .accessibilityHidden(true)
                Slider(value: controls.activity, in: controls.activityRange, step: controls.activityStep)
                    .tint(DS.Cut.Colors.lime)
                    .accessibilityLabel(Text(model.activityTitle))
                    .accessibilityValue(Text(model.activityValue))
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                CutSettingsRowHairline()
            }
            CutSettingsFooter(model.activityFooter)

            CutSettingsSectionHeader("Strength training days")
            CutGoalStepperRow(title: "Days per week", value: model.strengthDays,
                              canDecrease: model.canDecreaseStrength, canIncrease: model.canIncreaseStrength,
                              step: actions.stepStrength)
            CutSettingsFooter(model.strengthFooter)

            CutSettingsSectionHeader("Week start day")
            CutSettingsChoiceRow("Week starts", options: model.weekStartOptions, selection: controls.weekStart)
            CutSettingsFooter(model.weekStartFooter)

            Button(model.saveTitle, action: actions.save)
                .buttonStyle(CutPrimaryButtonStyle())
                .padding(.top, 36)
        }
    }
}

/// A value between grey minus and plus pills, as the Preferences rest rows. A candidate to
/// share with CutPreferencesRestRow in DesignSystem/Cut.
struct CutGoalStepperRow: View {
    let title: String
    let value: String
    let canDecrease: Bool
    let canIncrease: Bool
    let step: (Int) -> Void

    @ScaledMetric(relativeTo: .headline) private var valueWidth: CGFloat = 64

    var body: some View {
        CutSettingsRowLayout(title: title) {
            HStack(spacing: 8) {
                pill("minus", label: "Decrease \(title.lowercased())", enabled: canDecrease) { step(-1) }
                Text(value)
                    .font(DS.Cut.Typography.font(.title, monospacedDigits: true).weight(.semibold))
                    .foregroundStyle(DS.Cut.Colors.textPrimary)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(minWidth: valueWidth)
                    .accessibilityLabel(Text(title))
                    .accessibilityValue(Text(value))
                pill("plus", label: "Increase \(title.lowercased())", enabled: canIncrease) { step(1) }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func pill(_ systemImage: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(enabled ? DS.Cut.Colors.textPrimary : DS.Cut.Colors.textSecondary.opacity(0.5))
                .frame(width: 48, height: DS.Cut.Metrics.minTouchTarget)
                .background(Capsule().fill(DS.Cut.Colors.controlFill))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}
