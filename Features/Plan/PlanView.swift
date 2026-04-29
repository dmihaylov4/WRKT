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
            CalendarMonthView(
                onProgramLibraryTap: {
                    showProgramLibrary = true
                }
            )
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
}
