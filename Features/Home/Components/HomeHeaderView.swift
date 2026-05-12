//
//  HomeHeaderView.swift
//  WRKT
//
//  Compact header with greeting
//

import SwiftUI

struct HomeHeaderView: View {
    let greeting: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Greeting
            Text(greeting)
                .font(DS.Typography.font(.title2, weight: .semibold))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
                .layoutPriority(1)

            Spacer(minLength: 8)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}
