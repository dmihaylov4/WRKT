//
//  CutDiagnosticsView.swift
//  WRKT
//
//  Diagnostics in the Cut language: Export as a hairline row, Clear as red text, the
//  explanation under them, and the last result as a secondary line. Plain values and closures.
//

import SwiftUI

struct CutDiagnosticsActions {
    var export: () -> Void = {}
    var clear: () -> Void = {}
}

struct CutDiagnosticsView: View {
    let model: CutDiagnosticsModel
    var actions = CutDiagnosticsActions()

    var body: some View {
        CutSettingsPage(title: model.title) {
            // The rows start a little below the bar; with no section title above them.
            Color.clear
                .frame(height: 12)
                .accessibilityHidden(true)
            CutSettingsActionRow("Export diagnostics", systemImage: "square.and.arrow.up", action: actions.export)
            CutSettingsActionRow("Clear diagnostics", role: .destructive, action: actions.clear)
            CutSettingsFooter(model.footer)
            if let status = model.statusMessage {
                Text(status)
                    .cutFont(.body)
                    .foregroundStyle(DS.Cut.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 24)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }
}
