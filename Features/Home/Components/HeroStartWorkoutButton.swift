//
//  HeroStartWorkoutButton.swift
//  WRKT
//
//  THE MAIN COMPONENT - Hero button for Home screen (40-50% of screen)
//

import SwiftUI

struct HeroStartWorkoutButton: View {
    let content: HeroButtonContent
    let onTap: () -> Void
    var showLiveWorkoutSheet: (() -> Void)? = nil
    var skipRest: (() -> Void)? = nil
    var addExercise: (() -> Void)? = nil
    var extendRest: (() -> Void)? = nil

    @State private var isPressed = false
    @State private var pulseOffset: CGFloat = 0

    var body: some View {
        Button {
            // Only trigger haptics and onTap for the main button press (not for nested buttons)
            if case .noWorkout = content.workoutState {
                Haptics.medium()
                onTap()
            }
        } label: {
            Group {
                switch content.workoutState {
                case .noWorkout:
                    staticHeroContent

                case .activeWorkout(let exercises, let completedSets, _, let startDate):
                    LiveWorkoutHeroContent(
                        exercises: exercises,
                        completedSets: completedSets,
                        startDate: startDate,
                        onAddExercise: {
                            Haptics.medium()
                            onTap()
                        },
                        onViewWorkout: {
                            Haptics.light()
                            showLiveWorkoutSheet?()
                        }
                    )
                    .padding(.horizontal, 20)

                case .activeWorkoutWithRest(let exercises, let completedSets, _,
                                             let startDate, let restTime, let exerciseName):
                    RestTimerHeroContent(
                        exercises: exercises,
                        completedSets: completedSets,
                        startDate: startDate,
                        restTimeRemaining: restTime,
                        exerciseName: exerciseName,
                        onSkipRest: {
                            Haptics.medium()
                            skipRest?()
                        },
                        onAddExercise: {
                            Haptics.light()
                            addExercise?()
                        },
                        onViewWorkout: {
                            Haptics.light()
                            showLiveWorkoutSheet?()
                        },
                        onExtendRest: {
                            extendRest?()
                        }
                    )
                    .padding(.horizontal, 20)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: UIScreen.main.bounds.height * 0.26) // 26% of screen
            .animation(nil, value: stateIdentifier) // Disable animation on content switch
            .background(dynamicBackground)
            .overlay(leftAccentStripe)
            .overlay(subtlePulseBorder)
            .clipShape(ChamferedRectangle(.hero))
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        }
        .buttonStyle(HeroButtonStyle(isPressed: $isPressed))
        .padding(.horizontal)
        .padding(.vertical, 8)
        .task(id: stateIdentifier) {
            // This task runs whenever stateIdentifier changes
            // Simple rule: if not in default state, animate. Otherwise stop.
            if !isDefaultState {
                // IMPORTANT: Always reset to 0 first, otherwise animation from 1->1 does nothing
                pulseOffset = 0

                // Small delay to ensure state is reset before starting animation
                try? await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds

                withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                    pulseOffset = 1
                }
            } else {
                // Stop animation
                withAnimation(.linear(duration: 0)) {
                    pulseOffset = 0
                }
            }
        }
    }

    private var isDefaultState: Bool {
        if case .noWorkout = content.workoutState {
            return true
        }
        return false
    }

    // Simple state identifier that doesn't include changing values
    private var stateIdentifier: String {
        switch content.workoutState {
        case .noWorkout:
            return "no_workout"
        case .activeWorkout:
            return "active_workout"
        case .activeWorkoutWithRest:
            return "active_workout_rest"
        }
    }

    // MARK: - Static Hero Content (No Workout)

    private var staticHeroContent: some View {
        VStack(spacing: 8) {
            // Large bold "START WORKOUT" text with serious font
            Text(content.mainText)
                .font(.system(size: 42, weight: .heavy, design: .default))
                .foregroundStyle(.black)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            // Secondary text (smaller, subtle)
            Text(content.secondaryText)
                .font(.system(size: 15, weight: .medium, design: .default))
                .foregroundStyle(.black.opacity(0.65))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Dynamic Styling

    private var dynamicBackground: some View {
        Group {
            if case .noWorkout = content.workoutState {
                // Default solid color for no workout
                DS.tint
            } else {
                // Black background for active workout
                Color.black
            }
        }
    }

    @ViewBuilder
    private var leftAccentStripe: some View {
        if case .noWorkout = content.workoutState {
            // No stripe for default state
            EmptyView()
        } else {
            // Left accent stripe for live workout (like grab tab)
            HStack {
                Capsule()
                    .fill(DS.Theme.accent)
                    .frame(width: 4)
                    .padding(.leading, 0.5)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var subtlePulseBorder: some View {
        if case .noWorkout = content.workoutState {
            EmptyView()
        } else {
            // Traveling border segment using dash pattern for consistent visual length.
            // Uses the full closed path so the segment wraps smoothly around corners.
            // The left edge is masked out so the segment appears to pass behind
            // the yellow accent stripe.
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let chamferSize: CGFloat = 28
                let segmentLength: CGFloat = 40

                // Full closed perimeter
                let chamferDiag = sqrt(2 * chamferSize * chamferSize)
                let perimeter = 2 * (w + h) - 4 * chamferSize + 2 * chamferDiag

                let gap = perimeter - segmentLength

                BroadcastBorderShape(chamferSize: chamferSize)
                    .stroke(
                        DS.Theme.accent,
                        style: StrokeStyle(
                            lineWidth: 4,
                            lineCap: .round,
                            dash: [segmentLength, gap],
                            dashPhase: -pulseOffset * perimeter
                        )
                    )
                    // Mask hides the left edge so the segment disappears behind the accent stripe
                    .mask {
                        HStack(spacing: 0) {
                            Color.clear.frame(width: 6) // Hide left edge area
                            Color.white
                        }
                    }
            }
        }
    }
}

/// Closed chamfered rectangle border path.
/// The segment travels the full perimeter; the left edge is hidden via mask.
private struct BroadcastBorderShape: Shape {
    let chamferSize: CGFloat

    func path(in rect: CGRect) -> Path {
        Path { path in
            let w = rect.width
            let h = rect.height

            // Start at top-left corner (square)
            path.move(to: CGPoint(x: 0, y: 0))

            // Top edge → top-right chamfer
            path.addLine(to: CGPoint(x: w - chamferSize, y: 0))
            path.addLine(to: CGPoint(x: w, y: chamferSize))

            // Right edge
            path.addLine(to: CGPoint(x: w, y: h))

            // Bottom edge → bottom-left chamfer
            path.addLine(to: CGPoint(x: chamferSize, y: h))
            path.addLine(to: CGPoint(x: 0, y: h - chamferSize))

            // Left edge back to start
            path.closeSubpath()
        }
    }
}

// MARK: - HeroStartWorkoutButton Continued

extension HeroStartWorkoutButton {
    private var gradientShadowColor: Color {
        if case .noWorkout = content.workoutState {
            return DS.tint.opacity(0.3)
        } else {
            return DS.Theme.accent.opacity(0.4)
        }
    }
}

// MARK: - Button Style

struct HeroButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, newValue in
                isPressed = newValue
            }
    }
}

// MARK: - View Extension for Conditional Modifiers

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

