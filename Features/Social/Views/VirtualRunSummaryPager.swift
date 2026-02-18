//
//  VirtualRunSummaryPager.swift
//  WRKT
//
//  TabView pager wrapping the stat comparison (page 1) and
//  dual-map route comparison (page 2) for virtual run summary.
//

import SwiftUI

struct VirtualRunSummaryPager: View {
    let data: VirtualRunCompletionData
    let onDismiss: () -> Void

    var body: some View {
        TabView {
            VirtualRunSummaryView(data: data, onDismiss: {}, showDismissButton: false)
            VirtualRunMapComparisonView(data: data, onDismiss: onDismiss)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .background(Color.black)
        .ignoresSafeArea()
    }
}
