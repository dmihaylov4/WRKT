//
//  SkeletonNotificationRow.swift
//  WRKT
//
//  Skeleton loading row for notifications
//

import SwiftUI

struct SkeletonNotificationRow: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 12) {
            // Avatar skeleton
            Circle()
                .fill(DS.Semantic.fillSubtle)
                .frame(width: 40, height: 40)

            // Content skeleton
            VStack(alignment: .leading, spacing: 6) {
                // Message line 1
                RoundedRectangle(cornerRadius: 4)
                    .fill(DS.Semantic.fillSubtle)
                    .frame(height: 14)

                // Message line 2
                RoundedRectangle(cornerRadius: 4)
                    .fill(DS.Semantic.fillSubtle)
                    .frame(width: 200, height: 14)

                // Timestamp
                RoundedRectangle(cornerRadius: 4)
                    .fill(DS.Semantic.fillSubtle)
                    .frame(width: 80, height: 12)
            }

            Spacer()

            // Icon skeleton
            RoundedRectangle(cornerRadius: 4)
                .fill(DS.Semantic.fillSubtle)
                .frame(width: 24, height: 24)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .opacity(isAnimating ? 0.5 : 1.0)
        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isAnimating)
        .onAppear {
            isAnimating = true
        }
    }
}

#Preview {
    SkeletonNotificationRow()
}
