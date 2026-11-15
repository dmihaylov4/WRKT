//
//  CutDiagnosticsModel.swift
//  WRKT
//
//  What the Cut Diagnostics page shows: the footer and the status line after an export or a
//  clear. The copy is DiagnosticsLogView's.
//

import Foundation

struct CutDiagnosticsModel: Equatable {
    var title = "Diagnostics"
    var footer = CutDiagnosticsLogic.footer
    /// The result of the last clear, or why an export or clear failed; nil otherwise.
    var statusMessage: String?
}

enum CutDiagnosticsLogic {
    static let footer = "Exports a local log used for support debugging. It records app events and barbell interaction state, not passwords or tokens."
    static let clearedMessage = "Diagnostics cleared."

    static func exportFailedMessage(_ reason: String) -> String {
        "Could not prepare diagnostics: \(reason)"
    }

    static func clearFailedMessage(_ reason: String) -> String {
        "Could not clear diagnostics: \(reason)"
    }
}
