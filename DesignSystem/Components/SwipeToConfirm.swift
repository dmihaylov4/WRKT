
//
//  SwipeToConfirm.swift
//  WRKT
//

import SwiftUI

// Local theme to keep this file self-contained
private enum Theme {
    static let bg        = DS.Semantic.surface
    static let surface   = DS.Theme.cardTop
    static let surface2  = DS.Theme.cardBottom
    static let border    = DS.Semantic.border
    static let text      = Color.white
    static let secondary = Color.white.opacity(0.65)
    static let accent    = DS.Theme.accent
}

struct SwipeToConfirm: View {
    // Required
    let text: String
    let systemImage: String

    // Style & behavior
    var background: Material = .thinMaterial
    var trackColor: Color? = nil
    var knobSize: CGFloat = 52
    var onConfirm: () -> Void
    var isEnabled: Bool = true

    // State
    @State private var dragX: CGFloat = 0
    @GestureState private var isPressing = false

    init(
        text: String,
        systemImage: String,
        background: Material = .thinMaterial,
        trackColor: Color? = nil,
        knobSize: CGFloat = 52,
        onConfirm: @escaping () -> Void,
        isEnabled: Bool = true
    ) {
        self.text = text
        self.systemImage = systemImage
        self.background = background
        self.trackColor = trackColor
        self.knobSize = knobSize
        self.onConfirm = onConfirm
        self.isEnabled = isEnabled
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let inset: CGFloat = 6
            let corner: CGFloat = height / 2
            let maxX = max(0, width - inset * 2 - knobSize)
            let progress = (dragX / maxX).clamped(to: 0...1)

            ZStack(alignment: .leading) {
                // TRACK
                let track = RoundedRectangle(cornerRadius: corner, style: .continuous)

                // Single hairline stroke to avoid double-border look
                track
                    .fill(trackColor ?? Theme.surface2)
                    .overlay(track.stroke(Theme.border, lineWidth: 1))

                // Accent progress (fills from left → knob)
                // ✅ Knob halo: lives under the knob only (no mid-track glow at rest)
                Circle()
                    .fill(Theme.accent.opacity(0.18))
                    .frame(width: knobSize * 1.2, height: knobSize * 1.2)
                    // center the halo under the knob
                    .offset(x: inset + dragX - (knobSize * 0.1))
                    .blur(radius: 10)
                    .allowsHitTesting(false)

                // LABEL (fades as you slide)
                HStack(spacing: 8) {
                 
                    Text(text)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .foregroundStyle(Theme.text)
                .opacity(isEnabled ? (1.0 - Double(progress) * 0.9) : 0.45)
                .allowsHitTesting(false)

                // KNOB
                Circle()
                    .fill(Theme.accent) // solid accent knob
                    .overlay(
                        Image(systemName: "chevron.right")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Color.black)
                    )
                    .shadow(color: Theme.accent.opacity(0.45), radius: isPressing ? 10 : 6, x: 0, y: 0)
                    .frame(width: knobSize, height: knobSize)
                    .offset(x: inset + dragX)
                    .scaleEffect(isPressing ? 0.98 : 1.0)
                    .animation(.easeOut(duration: 0.12), value: isPressing)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .updating($isPressing) { _, st, _ in st = true }
                            .onChanged { value in
                                guard isEnabled else { return }
                                dragX = (value.translation.width).clamped(to: 0...maxX)
                            }
                            .onEnded { _ in
                                guard isEnabled else { return }
                                let threshold = maxX * 0.65
                                if dragX >= threshold {
                                    // snap to end, confirm, reset
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                                        dragX = maxX
                                    }
                                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                        onConfirm()
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                                            dragX = 0
                                        }
                                    }
                                } else {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                                        dragX = 0
                                    }
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                            }
                    )
                    .accessibilityLabel(text)
                    .accessibilityHint("Swipe right to confirm")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityValue("\(Int(progress * 100)) percent")
                    .accessibilityAdjustableAction { dir in
                        guard isEnabled else { return }
                        let step = maxX / 4
                        switch dir {
                        case .increment: dragX = min(maxX, dragX + step)
                        case .decrement: dragX = max(0, dragX - step)
                        default: break
                        }
                    }
                    .opacity(isEnabled ? 1 : 0.5)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: max(48, knobSize + 12))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
