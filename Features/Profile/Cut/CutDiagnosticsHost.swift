//
//  CutDiagnosticsHost.swift
//  WRKT
//
//  DiagnosticsLogView's flows behind the Cut page: the same DiagnosticsLogStore export handed
//  to the system share sheet, the same clear (no confirmation, as before), and the same status
//  messages.
//

import SwiftUI

struct CutDiagnosticsHost: View {
    @State private var shareItem: CutDiagnosticsShareItem?
    @State private var statusMessage: String?

    var body: some View {
        CutDiagnosticsView(
            model: CutDiagnosticsModel(statusMessage: statusMessage),
            actions: CutDiagnosticsActions(export: exportDiagnostics, clear: clearDiagnostics)
        )
        .sheet(item: $shareItem) { item in
            CutSettingsShareSheet(url: item.url)
        }
    }

    private func exportDiagnostics() {
        do {
            shareItem = CutDiagnosticsShareItem(url: try DiagnosticsLogStore.shared.exportFileURL())
            statusMessage = nil
        } catch {
            statusMessage = CutDiagnosticsLogic.exportFailedMessage(error.localizedDescription)
        }
    }

    private func clearDiagnostics() {
        do {
            try DiagnosticsLogStore.shared.clear()
            statusMessage = CutDiagnosticsLogic.clearedMessage
        } catch {
            statusMessage = CutDiagnosticsLogic.clearFailedMessage(error.localizedDescription)
        }
    }
}

private struct CutDiagnosticsShareItem: Identifiable {
    let id = UUID()
    let url: URL
}
