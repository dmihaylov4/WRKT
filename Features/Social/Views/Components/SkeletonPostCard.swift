//
//  SkeletonPostCard.swift
//  WRKT
//
//  Skeleton loading card for feed posts
//

import SwiftUI

struct SkeletonPostCard: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Avatar + Username
            HStack(spacing: 12) {
                // Avatar skeleton
                Circle()
                    .fill(DS.Semantic.fillSubtle)
                    .frame(width: 40, height: 40)

                // Username + time skeleton
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(DS.Semantic.fillSubtle)
                        .frame(width: 120, height: 14)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(DS.Semantic.fillSubtle)
                        .frame(width: 80, height: 12)
                }

                Spacer()
            }

            // Caption skeleton
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(DS.Semantic.fillSubtle)
                    .frame(height: 14)

                RoundedRectangle(cornerRadius: 4)
                    .fill(DS.Semantic.fillSubtle)
                    .frame(width: 200, height: 14)
            }

            // Workout summary skeleton
            VStack(alignment: .leading, spacing: 12) {
                // Workout name
                HStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(DS.Semantic.fillSubtle)
                        .frame(width: 24, height: 24)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(DS.Semantic.fillSubtle)
                        .frame(width: 150, height: 16)

                    Spacer()
                }

                // Stats
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(DS.Semantic.fillSubtle)
                        .frame(width: 100, height: 24)

                    RoundedRectangle(cornerRadius: 12)
                        .fill(DS.Semantic.fillSubtle)
                        .frame(width: 80, height: 24)

                    Spacer()
                }

                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(DS.Semantic.fillSubtle)
                        .frame(width: 90, height: 24)

                    RoundedRectangle(cornerRadius: 12)
                        .fill(DS.Semantic.fillSubtle)
                        .frame(width: 70, height: 24)

                    Spacer()
                }
            }
            .padding(16)
            .background(DS.Semantic.fillSubtle.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Action buttons skeleton
            HStack(spacing: 20) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(DS.Semantic.fillSubtle)
                    .frame(width: 24, height: 24)

                RoundedRectangle(cornerRadius: 4)
                    .fill(DS.Semantic.fillSubtle)
                    .frame(width: 24, height: 24)

                Spacer()

                RoundedRectangle(cornerRadius: 4)
                    .fill(DS.Semantic.fillSubtle)
                    .frame(width: 24, height: 24)
            }
        }
        .padding(16)
        .background(DS.Semantic.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(DS.Semantic.border, lineWidth: 1)
        )
        .opacity(isAnimating ? 0.5 : 1.0)
        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isAnimating)
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Skeleton Modifier (for reusable shimmer effect)

struct ShimmerEffect: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.white.opacity(0.3),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 2)
                    .offset(x: -geometry.size.width + (geometry.size.width * 2 * phase))
                }
            )
            .mask(content)
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerEffect())
    }
}

