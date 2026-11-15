//
//  CutDataPortabilityView.swift
//  WRKT
//
//  Data portability and Import history in the Cut language. Export and Import are hairline
//  rows that turn into a quiet progress line while busy; the strategy is a choice row; the last
//  import's counts are value rows; Import history is a link. Each past import is a row with its
//  file, strategy, date and counts, and an outlined Restore pill (the legacy swipe still works).
//  Plain values, a binding for the strategy, and closures.
//

import SwiftUI

struct CutDataPortabilityActions {
    var export: () -> Void = {}
    var importBackup: () -> Void = {}
    var openHistory: () -> Void = {}
}

struct CutDataPortabilityView: View {
    let model: CutDataPortabilityModel
    @Binding var strategy: String
    var actions = CutDataPortabilityActions()

    var body: some View {
        CutSettingsPage(title: model.title) {
            CutSettingsSectionHeader("Export", isFirst: true)
            if let busy = model.exportBusyLine {
                CutSettingsBusyRow(title: busy)
            } else {
                CutSettingsActionRow("Export backup", systemImage: "square.and.arrow.up", action: actions.export)
            }
            CutSettingsFooter(model.exportFooter)

            CutSettingsSectionHeader("Import")
            CutSettingsChoiceRow("Strategy", options: model.strategyOptions, selection: $strategy)
            if let busy = model.importBusyLine {
                CutSettingsBusyRow(title: busy)
            } else {
                CutSettingsActionRow("Import backup", systemImage: "square.and.arrow.down", action: actions.importBackup)
            }
            CutSettingsFooter(model.importFooter)

            if !model.lastImport.isEmpty {
                CutSettingsSectionHeader("Last import")
                ForEach(model.lastImport) { count in
                    CutSettingsValueRow(count.title, value: count.value)
                }
            }

            CutSettingsSectionHeader("History")
            CutSettingsLinkRow("Import history", action: actions.openHistory)
        }
    }
}

/// A row that stands in for an action while it runs: a spinner and a secondary line.
struct CutSettingsBusyRow: View {
    let title: String

    var body: some View {
        CutSettingsRowLayout(title: title, titleColor: DS.Cut.Colors.textSecondary) {
            EmptyView()
        } accessory: {
            ProgressView()
                .tint(DS.Cut.Colors.textSecondary)
        }
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - Import history

struct CutImportHistoryView: View {
    let model: CutImportHistoryModel
    var restore: (UUID) -> Void = { _ in }

    var body: some View {
        CutSettingsPage(title: model.title) {
            CutHairline()
                .padding(.top, 24)
            if model.isLoading {
                CutSettingsBusyRow(title: "Restoring")
            }
            if model.showsEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.emptyTitle)
                        .cutFont(.title)
                        .foregroundStyle(DS.Cut.Colors.textPrimary)
                    Text(model.emptyLine)
                        .cutFont(.secondary)
                        .foregroundStyle(DS.Cut.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 16)
            }
            ForEach(model.rows) { row in
                CutImportHistoryRow(row: row, isEnabled: !model.isLoading) { restore(row.id) }
                    .swipeActions(edge: .trailing) {
                        Button { restore(row.id) } label: {
                            Label("Restore", systemImage: "arrow.uturn.backward")
                        }
                        .tint(.orange)
                    }
            }
        }
    }
}

private struct CutImportHistoryRow: View {
    let row: CutImportHistoryModel.Row
    let isEnabled: Bool
    let restore: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 10) {
                        text
                        button
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(alignment: .center, spacing: 12) {
                        text.frame(maxWidth: .infinity, alignment: .leading)
                        button
                    }
                }
            }
            .padding(.vertical, 14)
            CutHairline()
        }
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.fileName)
                .cutFont(.title)
                .foregroundStyle(DS.Cut.Colors.textPrimary)
                .lineLimit(2)
                .truncationMode(.middle)
            Text(row.detail)
                .cutFont(.secondary)
                .foregroundStyle(DS.Cut.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(row.counts)
                .cutFont(.secondary, monospacedDigits: true)
                .foregroundStyle(DS.Cut.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var button: some View {
        Button("Restore", action: restore)
            .buttonStyle(CutSecondaryButtonStyle(size: .compact, fillsWidth: false))
            .fixedSize()
            .disabled(!isEnabled)
            .accessibilityLabel(Text("Restore to before \(row.fileName)"))
    }
}
