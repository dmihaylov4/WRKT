//
//  CutConnectionsView.swift
//  WRKT
//
//  Apple Health in the Cut language: the title with the status line under it, one lime pill
//  for the action the state allows (Connect, Sync now, Syncing, Retry), Disconnect in the round
//  menu beside the title while connected, and the explanation under a hairline. Plain values
//  and closures only.
//

import SwiftUI

struct CutConnectionsActions {
    var connect: () -> Void = {}
    var sync: () -> Void = {}
    var disconnect: () -> Void = {}
}

struct CutConnectionsView: View {
    let model: CutConnectionsModel
    var actions = CutConnectionsActions()

    var body: some View {
        CutSettingsPage(title: model.title, subtitle: model.statusLine) {
            if model.showsDisconnect {
                Menu {
                    Button("Disconnect", systemImage: "xmark", role: .destructive, action: actions.disconnect)
                } label: {
                    Label("Manage", systemImage: "ellipsis")
                }
            }
        } content: {
            Button(action: primaryAction) {
                HStack(spacing: 10) {
                    if model.primary == .syncing {
                        ProgressView()
                            .tint(DS.Cut.Colors.ink)
                            .accessibilityHidden(true)
                    }
                    Text(model.primary.title)
                }
            }
            .buttonStyle(CutPrimaryButtonStyle())
            // Full lime while syncing (a dimmed pill read as a different control); taps are ignored.
            .allowsHitTesting(model.primary.isEnabled)
            .accessibilityAddTraits(model.primary.isEnabled ? [] : .updatesFrequently)
            .accessibilityHint(model.primary.isEnabled ? Text("") : Text("A sync is running"))
            .padding(.top, 24)

            CutHairline()
                .padding(.top, 28)
            CutSettingsFooter(model.footer)
        }
    }

    private func primaryAction() {
        switch model.primary {
        case .connect, .retry: actions.connect()
        case .sync: actions.sync()
        case .syncing: break
        }
    }
}
