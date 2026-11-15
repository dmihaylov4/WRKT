//
//  CutAchievementsDexView.swift
//  WRKT
//
//  The PR Dex in the Cut language: the title with the unlocked count under it in lime and the
//  scope menu beside it, then the dex as a hairline table, three across (two, then one, as the
//  text grows). No cards: each cell is the lift's name over a lime check and date when unlocked,
//  or a padlock and "Locked" in readable grey. The two records rows close the page. The detail
//  is a Settings family page: unlock line, records and the rep ladder as hairline stat columns,
//  Try a PR as the one lime element, Add to current workout, and the muscles. Plain values and
//  closures (see CutAchievementsDexHost).
//

import SwiftUI

struct CutAchievementsDexView: View {
    let model: CutAchievementsDexModel
    var scope: Binding<AchievementsDexVM.Scope> = .constant(.all)
    var open: (String) -> Void = { _ in }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: Int {
        if dynamicTypeSize >= .accessibility3 { return 1 }
        if dynamicTypeSize.isAccessibilitySize { return 2 }
        return 3
    }

    var body: some View {
        CutSettingsPage(title: model.title, subtitle: model.countLine, subtitleIsLime: true) {
            Menu {
                Picker("Show", selection: scope) {
                    ForEach(model.scopeOptions) { Text($0.label).tag($0.value) }
                }
            } label: {
                Label("Filter", systemImage: "line.3.horizontal.decrease")
                    .labelStyle(.iconOnly)
            }
            .accessibilityValue(Text(scope.wrappedValue.rawValue))
        } content: {
            CutHairline().padding(.top, 24)
            if model.isSearching {
                HStack(spacing: 10) {
                    ProgressView().tint(DS.Cut.Colors.textSecondary)
                    Text("Searching")
                        .cutFont(.secondary)
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ForEach(Array(CutAchievementsDexLogic.rows(model.tiles, columns: columns).enumerated()), id: \.offset) { _, row in
                    tileRow(row)
                }
            }

            CutSettingsSectionHeader("Records")
            ForEach(model.records) { row in
                CutSettingsValueRow(row.title, value: row.value)
            }
        }
    }

    private func tileRow(_ row: [CutAchievementsDexModel.Tile]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(0..<columns, id: \.self) { index in
                    if index > 0 {
                        Rectangle().fill(DS.Cut.Colors.hairline).frame(width: 1)
                    }
                    if index < row.count {
                        CutDexCell(tile: row[index], leadingInset: index == 0 ? 0 : 10) { open(row[index].id) }
                    } else {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            CutHairline()
        }
    }
}

/// One dex cell: the name, then the unlock date or the padlock. Equal width, no box.
private struct CutDexCell: View {
    let tile: CutAchievementsDexModel.Tile
    /// The first column lines up with the title; the others clear the divider.
    var leadingInset: CGFloat = 10
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Text(tile.title)
                    .cutFont(.title)
                    .foregroundStyle(tile.isUnlocked ? DS.Cut.Colors.textPrimary : DS.Cut.Colors.textSecondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Image(systemName: tile.isUnlocked ? "checkmark" : "lock.fill")
                        .font(DS.Cut.Typography.font(.secondary).weight(.bold))
                        .imageScale(.small)
                        .foregroundStyle(tile.isUnlocked ? DS.Cut.Colors.lime : DS.Cut.Colors.textSecondary)
                    Text(tile.status)
                        .cutFont(.secondary)
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(.leading, leadingInset)
            .padding(.trailing, 10)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(tile.accessibilityLabel))
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Detail

struct CutDexDetailActions {
    var tryPR: () -> Void = {}
    var addToWorkout: () -> Void = {}
}

struct CutDexDetailView<Muscles: View>: View {
    let model: CutDexDetailModel
    var actions = CutDexDetailActions()
    @ViewBuilder var muscles: () -> Muscles

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        CutSettingsPage(title: model.title, subtitle: model.unlockLine, subtitleIsLime: model.isUnlocked) {
            if !model.records.isEmpty {
                CutSettingsSectionHeader("Records", isFirst: true)
                ForEach(model.records) { row in
                    CutSettingsValueRow(row.title, value: row.value)
                }
            }

            CutSettingsSectionHeader("Rep ladder (best)", isFirst: model.records.isEmpty)
            let perRow = dynamicTypeSize.isAccessibilitySize ? 2 : 4
            ForEach(Array(CutAchievementsDexLogic.rows(model.ladder, columns: perRow).enumerated()), id: \.offset) { _, row in
                ladderRow(row, columns: perRow)
            }

            if model.showsExerciseActions {
                CutSettingsSectionHeader("Train it")
                if let attempt = model.attempt {
                    Button(action: actions.tryPR) {
                        CutSettingsRowLayout(title: "Try a PR", subtitle: attempt) {
                            EmptyView()
                        } accessory: {
                            CutTile(systemImage: "arrow.right", side: 44)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(.isButton)
                }
                CutSettingsActionRow("Add to current workout", systemImage: "plus", action: actions.addToWorkout)

                CutSettingsSectionHeader("Exercise")
                muscles()
                    .padding(.top, 12)
            }
        }
    }

    /// Stat columns with 1 pt hairline dividers, as the app's stat rows.
    private func ladderRow(_ row: [CutDexDetailModel.Cell], columns: Int) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(0..<columns, id: \.self) { index in
                    if index > 0 {
                        Rectangle().fill(DS.Cut.Colors.hairline).frame(width: 1)
                    }
                    if index < row.count {
                        VStack(spacing: 4) {
                            Text(row[index].value)
                                .font(DS.Cut.Typography.font(.title, monospacedDigits: true).weight(.semibold))
                                .foregroundStyle(row[index].value == "-" ? DS.Cut.Colors.textSecondary : DS.Cut.Colors.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(row[index].label)
                                .cutFont(.secondary)
                                .foregroundStyle(DS.Cut.Colors.textSecondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .accessibilityElement(children: .combine)
                    } else {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            CutHairline()
        }
    }
}
