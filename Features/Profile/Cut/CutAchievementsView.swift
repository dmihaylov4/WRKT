//
//  CutAchievementsView.swift
//  WRKT
//
//  Milestones in the Cut language: the title with the unlocked count under it in lime and the
//  filter menu beside it, then In progress as hairline rows with a slanted bar and the a/b count,
//  and Unlocked as rows with a lime check and the date. No cards, no icons in boxes. Plain values
//  and a filter binding (see CutAchievementsHost).
//

import SwiftUI

struct CutAchievementsView: View {
    let model: CutAchievementsModel
    var filter: Binding<CutAchievementsFilter> = .constant(.all)

    var body: some View {
        CutSettingsPage(title: model.title, subtitle: model.countLine, subtitleIsLime: true) {
            Menu {
                Picker("Filter", selection: filter) {
                    ForEach(model.filterOptions) { Text($0.label).tag($0.value) }
                }
            } label: {
                Label("Filter", systemImage: "line.3.horizontal.decrease")
                    .labelStyle(.iconOnly)
            }
            .accessibilityValue(Text(filter.wrappedValue.rawValue))
        } content: {
            if model.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.emptyTitle)
                        .cutFont(.title)
                        .foregroundStyle(DS.Cut.Colors.textPrimary)
                    Text(model.emptyMessage)
                        .cutFont(.secondary)
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 36)
                .accessibilityElement(children: .combine)
            }
            if !model.inProgress.isEmpty {
                CutSettingsSectionHeader("In progress", isFirst: true)
                ForEach(model.inProgress) { CutMilestoneRow(row: $0) }
            }
            if !model.unlocked.isEmpty {
                CutSettingsSectionHeader("Unlocked", isFirst: model.inProgress.isEmpty)
                ForEach(model.unlocked) { CutMilestoneRow(row: $0) }
            }
        }
    }
}

private struct CutMilestoneRow: View {
    let row: CutAchievementsModel.Row

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                CutSettingsRowText(title: row.title, subtitle: row.detail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if row.isUnlocked {
                    Image(systemName: "checkmark")
                        .font(DS.Cut.Typography.font(.title).weight(.bold))
                        .foregroundStyle(DS.Cut.Colors.lime)
                        .accessibilityHidden(true)
                }
            }
            if let fraction = row.fraction {
                HStack(spacing: 12) {
                    CutSplitBar(fraction: fraction)
                    Text(row.value)
                        .font(DS.Cut.Typography.font(.secondary, monospacedDigits: true).weight(.semibold))
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                        .fixedSize()
                }
                .padding(.top, 10)
            } else {
                Text(row.value)
                    .cutFont(.secondary)
                    .foregroundStyle(DS.Cut.Colors.textSecondary)
                    .padding(.top, 6)
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { CutSettingsRowHairline() }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(row.isUnlocked ? "Unlocked \(row.value)" : "\(row.value) done"))
    }
}
