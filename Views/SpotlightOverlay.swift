//
//  SpotlightOverlay.swift
//  WRKT
//
//  Reusable spotlight tutorial overlay that highlights specific UI elements
//

import SwiftUI

// MARK: - Tutorial Step Model

struct TutorialStep: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
    let spotlightFrame: CGRect?  // nil = no spotlight, just overlay with tooltip
    let tooltipPosition: TooltipPosition
    let highlightCornerRadius: CGFloat

    init(
        title: String,
        message: String,
        spotlightFrame: CGRect? = nil,
        tooltipPosition: TooltipPosition = .bottom,
        highlightCornerRadius: CGFloat = 16
    ) {
        self.title = title
        self.message = message
        self.spotlightFrame = spotlightFrame
        self.tooltipPosition = tooltipPosition
        self.highlightCornerRadius = highlightCornerRadius
    }

    enum TooltipPosition {
        case top, bottom, center
    }
}

// MARK: - Main Spotlight Overlay

struct SpotlightOverlay: View {
    let currentStep: TutorialStep
    let currentIndex: Int
    let totalSteps: Int
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var scale: CGFloat = 0.9
    @State private var opacity: Double = 0.0

    var body: some View {
        ZStack {
            // Semi-transparent background with spotlight cutout
            if let frame = currentStep.spotlightFrame, frame != .zero, frame.width > 0, frame.height > 0 {
                SpotlightMask(highlightFrame: frame, cornerRadius: currentStep.highlightCornerRadius)
                    .ignoresSafeArea()
            } else {
                // No spotlight or invalid frame, just dimmed background
                Color.black.opacity(0.75)
                    .ignoresSafeArea()
            }

            // Tooltip
            VStack(spacing: 0) {
                switch currentStep.tooltipPosition {
                case .top:
                    tooltipCard
                        .padding(.top, 60)
                    Spacer()
                case .bottom:
                    Spacer()
                    tooltipCard
                        .padding(.bottom, 100)
                case .center:
                    Spacer()
                    tooltipCard
                    Spacer()
                }
            }
            .padding(.horizontal, 24)
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                scale = 1.0
                opacity = 1.0
            }
        }
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onNext()
        }
    }

    private var tooltipCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with progress
            HStack {
                Text(currentStep.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)

                Spacer()

                Text("\(currentIndex + 1)/\(totalSteps)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }

            // Message
            Text(currentStep.message)
                .font(.body)
                .foregroundStyle(.white.opacity(0.9))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            // Actions
            HStack(spacing: 12) {
                Button {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    onSkip()
                } label: {
                    Text("Skip")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }

                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onNext()
                } label: {
                    HStack(spacing: 6) {
                        Text(currentIndex + 1 < totalSteps ? "Next" : "Got it!")
                            .font(.subheadline.weight(.bold))

                        if currentIndex + 1 < totalSteps {
                            Image(systemName: "arrow.right")
                                .font(.caption.weight(.bold))
                        }
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [DS.Palette.marone, DS.Palette.marone.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
            }
            .padding(.top, 8)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        )
        .scaleEffect(scale)
        .opacity(opacity)
    }
}

// MARK: - Spotlight Mask

private struct SpotlightMask: View {
    let highlightFrame: CGRect
    let cornerRadius: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Dark overlay covering entire screen
                Color.black.opacity(0.85)

                // Cut out the spotlight area
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .frame(width: highlightFrame.width, height: highlightFrame.height)
                    .position(x: highlightFrame.midX, y: highlightFrame.midY)
                    .blendMode(.destinationOut)

                // Glowing ring around spotlight
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(DS.Palette.marone.opacity(0.6), lineWidth: 3)
                    .frame(width: highlightFrame.width, height: highlightFrame.height)
                    .position(x: highlightFrame.midX, y: highlightFrame.midY)
                    .shadow(color: DS.Palette.marone.opacity(0.4), radius: 12, x: 0, y: 0)
            }
        }
        .compositingGroup()
    }
}

// MARK: - PreferenceKey for Frame Tracking

struct FramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

// MARK: - View Extension for Easy Frame Tracking

extension View {
    func captureFrame(in coordinateSpace: CoordinateSpace = .global, onChange: @escaping (CGRect) -> Void) -> some View {
        overlay(
            GeometryReader { geo in
                Color.clear
                    .task {
                        // Delay to ensure layout is complete
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                        let frame = geo.frame(in: coordinateSpace)
                        await MainActor.run {
                            onChange(frame)
                        }
                    }
            }
        )
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        // Mock background content
        VStack {
            Text("Some Content")
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gray)

        // Spotlight overlay
        SpotlightOverlay(
            currentStep: TutorialStep(
                title: "Equipment Filters",
                message: "Tap any equipment type to filter exercises. Double-tap a chip to clear the filter.",
                spotlightFrame: CGRect(x: 20, y: 100, width: 300, height: 60),
                tooltipPosition: .bottom
            ),
            currentIndex: 0,
            totalSteps: 3,
            onNext: {},
            onSkip: {}
        )
    }
}
