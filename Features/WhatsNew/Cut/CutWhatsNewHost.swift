//
//  CutWhatsNewHost.swift
//  WRKT
//
//  Wires the Cut What's New sheet. Close and "Got it" call the presenter's onDismiss, which marks
//  the release seen (WhatsNewManager.dismiss) exactly as the legacy button did. "See your rack"
//  opens the rack the way the Me tab does (PlateWallView in a sheet), stacked on this one; when the
//  rack closes, onDismiss marks the release seen and both sheets go.
//

import SwiftUI

struct CutWhatsNewHost: View {
    let release: WhatsNewRelease
    let currentVersion: String
    let onDismiss: () -> Void

    @State private var showsRack = false

    var body: some View {
        let model = CutWhatsNewLogic.model(release: release, currentVersion: currentVersion)
        CutWhatsNewView(
            model: model,
            primary: {
                switch model.destination {
                case .rack: showsRack = true
                case nil: onDismiss()
                }
            },
            close: onDismiss
        )
        .sheet(isPresented: $showsRack, onDismiss: onDismiss) {
            PlateWallView()
        }
    }
}
