//
//  FloatingActionButton.swift
//  WRKT
//
//  Expandable floating action button with quick actions
//

import SwiftUI

struct FloatingActionButton: View {
    @Binding var isExpanded: Bool
    let onCreatePost: () -> Void
    let onLogWorkout: () -> Void
    let onStartBattle: () -> Void

    @State private var showLabels = false

    var body: some View {
        VStack(spacing: 16) {
            if isExpanded {
                // Quick actions (shown when expanded)
                VStack(alignment: .trailing, spacing: 12) {
                    FABActionButton(
                        icon: "dumbbell.fill",
                        label: "Log Workout",
                        color: DS.Semantic.brand,
                        showLabel: showLabels,
                        iconOffset: CGSize(width: -1, height: 0) // Dumbbell icon visual adjustment
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            isExpanded = false
                        }
                        onLogWorkout()
                    }

                    FABActionButton(
                        icon: "bolt.fill",
                        label: "Start Battle",
                        color: DS.Semantic.accentWarm,
                        showLabel: showLabels
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            isExpanded = false
                        }
                        onStartBattle()
                    }

                    FABActionButton(
                        icon: "square.and.pencil",
                        label: "Create Post",
                        color: DS.Semantic.brand,
                        showLabel: showLabels
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            isExpanded = false
                        }
                        onCreatePost()
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }

            // Main FAB button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                    if isExpanded {
                        // Delay label appearance for staggered animation
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(.spring(response: 0.3)) {
                                showLabels = true
                            }
                        }
                    } else {
                        showLabels = false
                    }
                }
                Haptics.light()
            } label: {
                ZStack {
                    ChamferedRectangleAlt(.large)
                        .fill(DS.Semantic.brand)
                        .frame(width: 56, height: 56)
                        .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)

                    Image(systemName: isExpanded ? "xmark" : "plus")
                        .font(.title2.bold())
                        .foregroundStyle(.black)
                        .rotationEffect(.degrees(isExpanded ? 0 : 0))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.trailing, 20)
        .padding(.bottom, 20)
    }
}

// MARK: - FAB Action Button

private struct FABActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let showLabel: Bool
    var iconOffset: CGSize = .zero
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if showLabel {
                    Text(label)
                        .font(.subheadline.bold())
                        .foregroundStyle(DS.Semantic.textPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(DS.Semantic.card)
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                ZStack {
                    ChamferedRectangleAlt(.large)
                        .fill(color)
                        .frame(width: 48, height: 48)
                        .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)

                    Image(systemName: icon)
                        .font(.title3.bold())
                        .foregroundStyle(.black)
                        .offset(iconOffset)
                }
            }
            .fixedSize() // Prevent HStack from expanding
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            Spacer()
            HStack {
                Spacer()
                FloatingActionButton(
                    isExpanded: .constant(true),
                    onCreatePost: {},
                    onLogWorkout: {},
                    onStartBattle: {}
                )
            }
        }
    }
}

#Preview("Collapsed") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            Spacer()
            HStack {
                Spacer()
                FloatingActionButton(
                    isExpanded: .constant(false),
                    onCreatePost: {},
                    onLogWorkout: {},
                    onStartBattle: {}
                )
            }
        }
    }
}
