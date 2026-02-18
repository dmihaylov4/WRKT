//
//  HomeHeaderView.swift
//  WRKT
//
//  Compact header with greeting and optional streak
//

import SwiftUI

struct HomeHeaderView: View {
    let greeting: String
    let currentStreak: Int

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Greeting
            Text(greeting)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
                .layoutPriority(1)

            Spacer(minLength: 8)

            // Weekly Streak (only if > 0)
            if currentStreak > 0 {
                HStack(spacing: 6) {
                    Text("\(currentStreak) week\(currentStreak == 1 ? "" : "s")")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                .fixedSize()
            }
        }
        .padding(.horizontal)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
}

