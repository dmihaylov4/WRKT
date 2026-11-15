//
//  CutWeeklyGoalView.swift
//  WRKT
//
//  The weekly goal detail in the Cut language, one family with the Settings pages: a modest
//  title with "This week" under it and the round Edit button beside it, the goal as the V mark
//  beside its two numbers and the pace line (drawn as on the Plan tab), then the quick actions
//  and the goal settings as hairline rows. Start strength is the one lime element; the targets
//  complete line is lime when shown instead. Plain values and closures only (see
//  CutWeeklyGoalHost).
//

import SwiftUI

struct CutWeeklyGoalActions {
    var startStrength: () -> Void = {}
    var viewCardio: () -> Void = {}
    var syncHealth: () -> Void = {}
    /// The legacy toolbar's Edit: opens the goal setup.
    var edit: () -> Void = {}
}

struct CutWeeklyGoalView: View {
    let model: CutWeeklyGoalModel
    var actions = CutWeeklyGoalActions()

    var body: some View {
        CutSettingsPage(title: model.title, subtitle: model.weekLabel) {
            Button(action: actions.edit) {
                Label("Edit goal", systemImage: "pencil")
                    .labelStyle(.iconOnly)
            }
        } content: {
            CutPlanWeekGoalView(goal: model.goal)
                .padding(.top, 28)

            CutSettingsSectionHeader("Quick actions")
            if let action = model.startStrength {
                Button(action: actions.startStrength) {
                    CutSettingsRowLayout(title: action.title, subtitle: action.subtitle) {
                        EmptyView()
                    } accessory: {
                        CutTile(systemImage: "arrow.right", side: 44)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isButton)
            }
            if let action = model.viewCardio {
                CutSettingsLinkRow(action.title, subtitle: action.subtitle, action: actions.viewCardio)
            }
            if let action = model.syncHealth {
                CutSettingsActionRow(action.title, subtitle: action.subtitle,
                                     systemImage: "arrow.triangle.2.circlepath", action: actions.syncHealth)
            }
            if let line = model.completeLine {
                CutSettingsRowLayout(title: line, titleColor: DS.Cut.Colors.lime) {
                    EmptyView()
                } accessory: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(DS.Cut.Colors.lime)
                        .accessibilityHidden(true)
                }
            }

            CutSettingsSectionHeader("Goal settings")
            ForEach(model.settings) { row in
                CutSettingsValueRow(row.title, value: row.value)
            }
        }
    }
}
