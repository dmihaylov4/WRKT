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

    var surfaceShape: DS.RoleShape<ChamferedRectangle> {
        DS.RoleShape(.card, legacy: ChamferedRectangle(.hero))
    }

    @State private var isPressed = false

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
                            addExercise?()
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
            .frame(height: UIScreen.main.bounds.height * 0.24) // 24% of screen
            .animation(nil, value: stateIdentifier) // Disable animation on content switch
            .background(dynamicBackground)
            .overlay(leftAccentStripe)
            .overlay(subtlePulseBorder)
            .clipShape(surfaceShape)
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        }
        .buttonStyle(HeroButtonStyle(isPressed: $isPressed))
        .padding(.horizontal)
        .padding(.vertical, 8)
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
                .font(DS.Typography.custom(size: 42, weight: .heavy, relativeTo: .largeTitle))
                .foregroundStyle(.black)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            // Secondary text (smaller, subtle)
            Text(content.secondaryText)
                .font(DS.Typography.custom(size: 15, weight: .medium, relativeTo: .subheadline))
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
            // Traveling border segment capped at 30 fps via TimelineView.
            // Wall-clock time drives the offset so SwiftUI's interpolation engine
            // never runs at the full display refresh rate (up to 120 Hz).
            // The TimelineView is only in the hierarchy when a workout is active,
            // so no paused: flag is needed.
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let chamferSize: CGFloat = 28
                let segmentLength: CGFloat = 40
                let chamferDiag = sqrt(2 * chamferSize * chamferSize)
                let perimeter = DS.Redesign.roundedShapesEnabled
                    ? BroadcastBorderShape.roundedPerimeter(in: CGRect(origin: .zero, size: geo.size))
                    : 2 * (w + h) - 4 * chamferSize + 2 * chamferDiag
                let gap = perimeter - segmentLength

                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let elapsed = context.date.timeIntervalSinceReferenceDate
                    let pulseOffset = CGFloat(elapsed.truncatingRemainder(dividingBy: 8.0) / 8.0)

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
                        .mask {
                            HStack(spacing: 0) {
                                Color.clear.frame(width: 6)
                                Color.white
                            }
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
        if DS.Redesign.roundedShapesEnabled {
            return DS.Radius.roundedChamferPath(DS.Chamfer.hero.size, in: rect)
        }

        return Path { path in
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

    /// Measure the hero's continuous contour, including its actual curve segments.
    static func roundedPerimeter(in rect: CGRect) -> CGFloat {
        let path = DS.Radius.roundedChamferPath(DS.Chamfer.hero.size, in: rect)
        var current = CGPoint.zero
        var start = CGPoint.zero
        var length: CGFloat = 0

        func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
            hypot(b.x - a.x, b.y - a.y)
        }

        func cubicLength(from: CGPoint, control1: CGPoint, control2: CGPoint, to: CGPoint) -> CGFloat {
            var previous = from
            var result: CGFloat = 0
            // Subdivision measures continuous corners without assuming circular arcs.
            let subdivisions = 64
            for index in 1...subdivisions {
                let t = CGFloat(index) / CGFloat(subdivisions)
                let u = 1 - t
                let point = CGPoint(
                    x: u * u * u * from.x + 3 * u * u * t * control1.x + 3 * u * t * t * control2.x + t * t * t * to.x,
                    y: u * u * u * from.y + 3 * u * u * t * control1.y + 3 * u * t * t * control2.y + t * t * t * to.y
                )
                result += distance(previous, point)
                previous = point
            }
            return result
        }

        path.forEach { element in
            switch element {
            case .move(to: let point):
                current = point
                start = point
            case .line(to: let point):
                length += distance(current, point)
                current = point
            case .quadCurve(to: let point, control: let control):
                let control1 = CGPoint(x: current.x + (control.x - current.x) * 2 / 3, y: current.y + (control.y - current.y) * 2 / 3)
                let control2 = CGPoint(x: point.x + (control.x - point.x) * 2 / 3, y: point.y + (control.y - point.y) * 2 / 3)
                length += cubicLength(from: current, control1: control1, control2: control2, to: point)
                current = point
            case .curve(to: let point, control1: let control1, control2: let control2):
                length += cubicLength(from: current, control1: control1, control2: control2, to: point)
                current = point
            case .closeSubpath:
                length += distance(current, start)
                current = start
            }
        }
        return length
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
