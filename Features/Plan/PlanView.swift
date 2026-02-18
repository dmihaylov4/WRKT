//
//  PlanView.swift
//  WRKT
//
//  Workout planning and calendar view
//

import SwiftUI

struct PlanView: View {
    var body: some View {
        NavigationStack {
            CalendarMonthView()
                .background(DS.Semantic.surface)
                .scrollContentBackground(.hidden)
        }
    }
}
