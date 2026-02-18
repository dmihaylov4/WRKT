//
//  SkeletonProfileHeader.swift
//  WRKT
//
//  Skeleton loading header for profile view
//

import SwiftUI

struct SkeletonProfileHeader: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 20) {
            // Avatar skeleton
            Circle()
                .fill(DS.Semantic.fillSubtle)
                .frame(width: 100, height: 100)
                .padding(.top, 20)

            // Username skeleton
            RoundedRectangle(cornerRadius: 4)
                .fill(DS.Semantic.fillSubtle)
                .frame(width: 150, height: 20)

            // Display name skeleton
            RoundedRectangle(cornerRadius: 4)
                .fill(DS.Semantic.fillSubtle)
                .frame(width: 200, height: 16)

            // Bio skeleton
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(DS.Semantic.fillSubtle)
                    .frame(height: 14)

                RoundedRectangle(cornerRadius: 4)
                    .fill(DS.Semantic.fillSubtle)
                    .frame(width: 250, height: 14)
            }
            .padding(.horizontal, 32)

            // Stats skeleton
            HStack(spacing: 32) {
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(DS.Semantic.fillSubtle)
                        .frame(width: 40, height: 24)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(DS.Semantic.fillSubtle)
                        .frame(width: 60, height: 12)
                }

                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(DS.Semantic.fillSubtle)
                        .frame(width: 40, height: 24)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(DS.Semantic.fillSubtle)
                        .frame(width: 60, height: 12)
                }

                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(DS.Semantic.fillSubtle)
                        .frame(width: 40, height: 24)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(DS.Semantic.fillSubtle)
                        .frame(width: 60, height: 12)
                }
            }
            .padding(.top, 8)

            // Action button skeleton
            RoundedRectangle(cornerRadius: 12)
                .fill(DS.Semantic.fillSubtle)
                .frame(height: 44)
                .padding(.horizontal, 40)
                .padding(.top, 8)
        }
        .opacity(isAnimating ? 0.5 : 1.0)
        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isAnimating)
        .onAppear {
            isAnimating = true
        }
    }
}

#Preview {
    SkeletonProfileHeader()
}
