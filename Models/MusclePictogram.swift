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
            let w = geo.size.width
            let h = geo.size.height

            // Base silhouette (very stylized)
            RoundedRectangle(cornerRadius: w*0.12, style: .continuous)
                .fill(background)
                .overlay(RoundedRectangle(cornerRadius: w*0.12).stroke(foreground.opacity(0.18), lineWidth: 1))
                .padding(w*0.08)

            // Regions
            Group {
                // Shoulders (front dome)
                capsule(x: 0.50, y: 0.23, w: 0.70, h: 0.12)
                    .fill(color(for: .shoulders))

                // Chest upper/mid/lower as stacked bands
                capsule(x: 0.50, y: 0.36, w: 0.72, h: 0.08)
                    .fill(color(for: .chestUpper))
                capsule(x: 0.50, y: 0.46, w: 0.72, h: 0.08)
                    .fill(color(for: .chestMid))
                capsule(x: 0.50, y: 0.56, w: 0.72, h: 0.08)
                    .fill(color(for: .chestLower))

                // Biceps / Triceps / Forearms represented as side bars
                // (front view favors biceps/forearms)
                sideBar(left: true,  y: 0.45, h: 0.38).fill(color(for: .biceps))
                sideBar(left: false, y: 0.45, h: 0.38).fill(color(for: .biceps))
                sideBar(left: true,  y: 0.58, h: 0.25).fill(color(for: .forearms))
                sideBar(left: false, y: 0.58, h: 0.25).fill(color(for: .forearms))

                // Abs / Obliques
                capsule(x: 0.50, y: 0.66, w: 0.52, h: 0.10).fill(color(for: .abs))
                oblique(left: true).fill(color(for: .obliques))
                oblique(left: false).fill(color(for: .obliques))

                // Quads / Adductors / Abductors
                legBand(y: 0.80, w: 0.70, h: 0.10).fill(color(for: .quads))
                sideBand(y: 0.80, left: true).fill(color(for: .abductors))
                sideBand(y: 0.80, left: false).fill(color(for: .abductors))
                innerBand(y: 0.80).fill(color(for: .adductors))

                // Calves
                legBand(y: 0.92, w: 0.55, h: 0.08).fill(color(for: .calves))
            }
        }
    }

    // MARK: Drawing helpers (front)
    func isPrimary(_ r: MuscleRegion) -> Bool { primary.contains(r) }
    func isSecondary(_ r: MuscleRegion) -> Bool { secondary.contains(r) }

    func fillFor(_ r: MuscleRegion) -> Color {
        if isPrimary(r) { return accent }
        if isSecondary(r) { return accent.opacity(0.35) }
        return .clear
    }

    func color(for r: MuscleRegion) -> Color {
        // faint grid for non-empty background
        fillFor(r)
    }

    func capsule(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> some Shape {
        RoundedRectangle(cornerRadius: 999)
            .path(in: CGRect(x: x - w/2, y: y - h/2, width: w, height: h))
    }

    func sideBar(left: Bool, y: CGFloat, h: CGFloat) -> some Shape {
        let x: CGFloat = left ? 0.12 : 0.88
        return RoundedRectangle(cornerRadius: 999)
            .path(in: CGRect(x: x - 0.08, y: y - h/2, width: 0.16, height: h))
    }

    func oblique(left: Bool) -> some Shape {
        let x: CGFloat = left ? 0.27 : 0.73
        return RoundedRectangle(cornerRadius: 6)
            .path(in: CGRect(x: x - 0.10, y: 0.62, width: 0.20, height: 0.10))
    }

    func legBand(y: CGFloat, w: CGFloat, h: CGFloat) -> some Shape {
        RoundedRectangle(cornerRadius: 6)
            .path(in: CGRect(x: 0.50 - w/2, y: y - h/2, width: w, height: h))
    }

    func sideBand(y: CGFloat, left: Bool) -> some Shape {
        let x: CGFloat = left ? 0.18 : 0.82
        return RoundedRectangle(cornerRadius: 6)
            .path(in: CGRect(x: x - 0.08, y: y - 0.05, width: 0.16, height: 0.10))
    }

    func innerBand(y: CGFloat) -> some Shape {
        RoundedRectangle(cornerRadius: 6)
            .path(in: CGRect(x: 0.50 - 0.10, y: y - 0.05, width: 0.20, height: 0.10))
    }
}

// MARK: - Back silhouette
private struct BodyBack: View {
    let primary: Set<MuscleRegion>
    let secondary: Set<MuscleRegion>
    let accent: Color
    let foreground: Color
    let background: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width

            RoundedRectangle(cornerRadius: w*0.12, style: .continuous)
                .fill(background)
                .overlay(RoundedRectangle(cornerRadius: w*0.12).stroke(foreground.opacity(0.18), lineWidth: 1))
                .padding(w*0.08)

            Group {
                // Traps / rear delts band
                band(y: 0.26, w: 0.70, h: 0.10).fill(color(for: .trapsRear))

                // Lats, Mid, Lower back bands
                band(y: 0.40, w: 0.72, h: 0.10).fill(color(for: .lats))
                band(y: 0.52, w: 0.72, h: 0.10).fill(color(for: .midBack))
                band(y: 0.62, w: 0.72, h: 0.10).fill(color(for: .lowerBack))

                // Triceps emphasized on back view
                sideBar(y: 0.50, h: 0.36, left: true).fill(color(for: .triceps))
                sideBar(y: 0.50, h: 0.36, left: false).fill(color(for: .triceps))

                // Glutes
                band(y: 0.72, w: 0.55, h: 0.12).fill(color(for: .glutes))

                // Hamstrings
                band(y: 0.84, w: 0.65, h: 0.10).fill(color(for: .hamstrings))

                // Calves
                band(y: 0.92, w: 0.55, h: 0.08).fill(color(for: .calves))
            }
        }
    }

    // MARK: helpers (back)
    func isPrimary(_ r: MuscleRegion) -> Bool { primary.contains(r) }
    func isSecondary(_ r: MuscleRegion) -> Bool { secondary.contains(r) }

    func color(for r: MuscleRegion) -> Color {
        if isPrimary(r) { return accent }
        if isSecondary(r) { return accent.opacity(0.35) }
        return .clear
    }

    func band(y: CGFloat, w: CGFloat, h: CGFloat) -> some Shape {
        RoundedRectangle(cornerRadius: 6)
            .path(in: CGRect(x: 0.50 - w/2, y: y - h/2, width: w, height: h))
    }

    func sideBar(y: CGFloat, h: CGFloat, left: Bool) -> some Shape {
        let x: CGFloat = left ? 0.12 : 0.88
        return RoundedRectangle(cornerRadius: 999)
            .path(in: CGRect(x: x - 0.08, y: y - h/2, width: 0.16, height: h))
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