//
//  MusclePictogram.swift
//  WRKT
//
//  Created by Dimitar Mihaylov on 09.10.25.
//


import SwiftUI

struct MusclePictogram: View {
    let primary: Set<MuscleRegion>
    let secondary: Set<MuscleRegion>
    var size: CGFloat = 36
    var accent: Color = Color(hex: "#F4E409") // your brand yellow
    var foreground: Color = .white.opacity(0.85)
    var background: Color = .white.opacity(0.08)

    var body: some View {
        HStack(spacing: 6) {
            // FRONT
            BodyFront(primary: primary, secondary: secondary, accent: accent, foreground: foreground, background: background)
                .frame(width: size, height: size)

            // BACK
            BodyBack(primary: primary, secondary: secondary, accent: accent, foreground: foreground, background: background)
                .frame(width: size, height: size)
        }
        .accessibilityLabel("Muscle highlight")
    }
}

// MARK: - Front silhouette
private struct BodyFront: View {
    let primary: Set<MuscleRegion>
    let secondary: Set<MuscleRegion>
    let accent: Color
    let foreground: Color
    let background: Color

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width

            ZStack {
                
                RoundedRectangle(cornerRadius: W*0.12, style: .continuous)
                    .fill(background)
                    .overlay(
                        RoundedRectangle(cornerRadius: W*0.12, style: .continuous)
                            .stroke(foreground.opacity(0.18), lineWidth: 1)
                    )
                    .padding(W*0.08)

                // Shoulders
                RoundedRectangle(cornerRadius: 999)
                    .path(in: unitRect(0.50, 0.23, 0.70, 0.12, in: geo.size))
                    .fill(color(for: .shoulders))

                // Chest upper/mid/lower
                RoundedRectangle(cornerRadius: 999)
                    .path(in: unitRect(0.50, 0.36, 0.72, 0.08, in: geo.size))
                    .fill(color(for: .chestUpper))
                RoundedRectangle(cornerRadius: 999)
                    .path(in: unitRect(0.50, 0.46, 0.72, 0.08, in: geo.size))
                    .fill(color(for: .chestMid))
                RoundedRectangle(cornerRadius: 999)
                    .path(in: unitRect(0.50, 0.56, 0.72, 0.08, in: geo.size))
                    .fill(color(for: .chestLower))

                // Biceps / Forearms
                RoundedRectangle(cornerRadius: 999)
                    .path(in: unitRect(0.12, 0.45, 0.16, 0.38, in: geo.size))
                    .fill(color(for: .biceps))
                RoundedRectangle(cornerRadius: 999)
                    .path(in: unitRect(0.88, 0.45, 0.16, 0.38, in: geo.size))
                    .fill(color(for: .biceps))
                RoundedRectangle(cornerRadius: 999)
                    .path(in: unitRect(0.12, 0.58, 0.16, 0.25, in: geo.size))
                    .fill(color(for: .forearms))
                RoundedRectangle(cornerRadius: 999)
                    .path(in: unitRect(0.88, 0.58, 0.16, 0.25, in: geo.size))
                    .fill(color(for: .forearms))

                // Abs / Obliques
                RoundedRectangle(cornerRadius: 999)
                    .path(in: unitRect(0.50, 0.66, 0.52, 0.10, in: geo.size))
                    .fill(color(for: .abs))
                RoundedRectangle(cornerRadius: 6)
                    .path(in: unitRect(0.27, 0.62, 0.20, 0.10, in: geo.size))
                    .fill(color(for: .obliques))
                RoundedRectangle(cornerRadius: 6)
                    .path(in: unitRect(0.73, 0.62, 0.20, 0.10, in: geo.size))
                    .fill(color(for: .obliques))

                // Quads / Adductors / Abductors
                RoundedRectangle(cornerRadius: 6)
                    .path(in: unitRect(0.50, 0.80, 0.70, 0.10, in: geo.size))
                    .fill(color(for: .quads))
                RoundedRectangle(cornerRadius: 6)
                    .path(in: unitRect(0.18, 0.80, 0.16, 0.10, in: geo.size))
                    .fill(color(for: .abductors))
                RoundedRectangle(cornerRadius: 6)
                    .path(in: unitRect(0.82, 0.80, 0.16, 0.10, in: geo.size))
                    .fill(color(for: .abductors))
                RoundedRectangle(cornerRadius: 6)
                    .path(in: unitRect(0.50, 0.80, 0.20, 0.10, in: geo.size))
                    .fill(color(for: .adductors))

                // Calves
                RoundedRectangle(cornerRadius: 6)
                    .path(in: unitRect(0.50, 0.92, 0.55, 0.08, in: geo.size))
                    .fill(color(for: .calves))
            }
        }
    }

    private func isPrimary(_ r: MuscleRegion) -> Bool { primary.contains(r) }
    private func isSecondary(_ r: MuscleRegion) -> Bool { secondary.contains(r) }
    private func color(for r: MuscleRegion) -> Color {
        if isPrimary(r) { return accent }
        if isSecondary(r) { return accent.opacity(0.35) }
        return .clear
    }

    /// Map normalized coords (0...1) to actual CGRect in the given size.
    private func unitRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, in size: CGSize) -> CGRect {
        CGRect(x: (x - w/2) * size.width,
               y: (y - h/2) * size.height,
               width:  w * size.width,
               height: h * size.height)
    }
}
private struct BodyBack: View {
    let primary: Set<MuscleRegion>
    let secondary: Set<MuscleRegion>
    let accent: Color
    let foreground: Color
    let background: Color

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width

            ZStack {
                RoundedRectangle(cornerRadius: W*0.12, style: .continuous)
                    .fill(background)
                    .overlay(
                        RoundedRectangle(cornerRadius: W*0.12, style: .continuous)
                            .stroke(foreground.opacity(0.18), lineWidth: 1)
                    )
                    .padding(W*0.08)

                // Traps / rear delts
                RoundedRectangle(cornerRadius: 6)
                    .path(in: unitRect(0.50, 0.26, 0.70, 0.10, in: geo.size))
                    .fill(color(for: .trapsRear))

                // Lats / Mid / Lower back
                RoundedRectangle(cornerRadius: 6)
                    .path(in: unitRect(0.50, 0.40, 0.72, 0.10, in: geo.size))
                    .fill(color(for: .lats))
                RoundedRectangle(cornerRadius: 6)
                    .path(in: unitRect(0.50, 0.52, 0.72, 0.10, in: geo.size))
                    .fill(color(for: .midBack))
                RoundedRectangle(cornerRadius: 6)
                    .path(in: unitRect(0.50, 0.62, 0.72, 0.10, in: geo.size))
                    .fill(color(for: .lowerBack))

                // Triceps (back)
                RoundedRectangle(cornerRadius: 999)
                    .path(in: unitRect(0.12, 0.50, 0.16, 0.36, in: geo.size))
                    .fill(color(for: .triceps))
                RoundedRectangle(cornerRadius: 999)
                    .path(in: unitRect(0.88, 0.50, 0.16, 0.36, in: geo.size))
                    .fill(color(for: .triceps))

                // Glutes / Hamstrings / Calves
                RoundedRectangle(cornerRadius: 6)
                    .path(in: unitRect(0.50, 0.72, 0.55, 0.12, in: geo.size))
                    .fill(color(for: .glutes))
                RoundedRectangle(cornerRadius: 6)
                    .path(in: unitRect(0.50, 0.84, 0.65, 0.10, in: geo.size))
                    .fill(color(for: .hamstrings))
                RoundedRectangle(cornerRadius: 6)
                    .path(in: unitRect(0.50, 0.92, 0.55, 0.08, in: geo.size))
                    .fill(color(for: .calves))
            }
        }
    }

    private func isPrimary(_ r: MuscleRegion) -> Bool { primary.contains(r) }
    private func isSecondary(_ r: MuscleRegion) -> Bool { secondary.contains(r) }
    private func color(for r: MuscleRegion) -> Color {
        if isPrimary(r) { return accent }
        if isSecondary(r) { return accent.opacity(0.35) }
        return .clear
    }

    private func unitRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, in size: CGSize) -> CGRect {
        CGRect(x: (x - w/2) * size.width,
               y: (y - h/2) * size.height,
               width:  w * size.width,
               height: h * size.height)
    }
}
// MARK: - Tiny hex helper (reuse from your codebase if present)
private extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { _ = s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >>  8) & 0xFF) / 255.0
        let b = Double( v        & 0xFF) / 255.0
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}
