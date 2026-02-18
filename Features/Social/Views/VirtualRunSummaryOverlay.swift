//
//  VirtualRunSummaryOverlay.swift
//  WRKT
//
//  Thin wrapper placed in AppShellView to show the virtual run summary
//  when both runners have finished. Waits silently in the background
//  without blocking the app.
//

import SwiftUI

struct VirtualRunSummaryOverlay: View {
    @State private var coordinator = VirtualRunSummaryCoordinator.shared

    var body: some View {
        Group {
            if let data = coordinator.pendingSummary {
                VirtualRunSummaryPager(data: data) {
                    coordinator.dismiss()
                }
                .transition(.opacity.combined(with: .scale))
                .zIndex(999)
            }
        }
        .allowsHitTesting(coordinator.pendingSummary != nil)
    }
}
