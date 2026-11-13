//
//  PlanView.swift
//  WRKT
//
//  Workout planning and calendar view
//

import SwiftUI

struct PlanView: View {
    @Binding var pendingNotification: AppNotification?
    @State private var showProgramLibrary = false

    init(pendingNotification: Binding<AppNotification?> = .constant(nil)) {
        self._pendingNotification = pendingNotification
    }

    var body: some View {
        NavigationStack {
            calendar
                .background(DS.Semantic.surface)
                .scrollContentBackground(.hidden)
                .navigationDestination(isPresented: $showProgramLibrary) {
                    ProgramLibraryView(pendingNotification: $pendingNotification)
                }
        }
        .onChange(of: pendingNotification) { _, newValue in
            guard newValue?.type == .programInvite else { return }
            showProgramLibrary = true
        }
    }

    /// The one Cut branch point: same stores, sheets, destinations and refresh triggers.
    @ViewBuilder
    private var calendar: some View {
        if DS.Redesign.cutEnabled {
            CutPlanHost(onProgramLibraryTap: { showProgramLibrary = true })
        } else {
            CalendarMonthView(
                onProgramLibraryTap: {
                    showProgramLibrary = true
                }
            )
        }
    }
}
