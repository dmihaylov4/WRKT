import SwiftUI
import UIKit

/// Procedural 2D plate face rendered with concentric raised rings, lift glyph,
/// convex depth lighting, and a collar hole. Scales to any square frame.
struct PlateFaceView: View {
    let tierID: Int
    let progressionTier: BarbellPlateProgressionTier
    let liftTypeID: String?
    let weightKg: Double
    var showEngravings: Bool = true

    // MARK: - Derived properties

    private var plateTier: PlateTier? { PlateTier.all.first { $0.id == tierID } }

    private var baseColor: Color {
        plateTier.map { Color(uiColor: $0.plateColor) } ?? .gray
    }

    private var specular: Double {
        max(0.10, Double(plateTier?.metallic ?? 0.10))
    }

    private var isLightBase: Bool {
        guard let t = plateTier else { return false }
        switch t.style {
        case .brass, .polishedSteel, .gold: return true
        default: return false
        }
    }

    private var isRubberStyle: Bool {
        guard let t = plateTier else { return false }
        return t.style == .bumper || t.style == .competition
    }

    private var ringCount: Int {
        progressionTier == .iron ? 2 : 3
    }

    private var markColor: Color {
        isLightBase ? Color.black.opacity(0.62) : Color.white.opacity(0.82)
    }

    private var mutedMarkColor: Color {
        isLightBase ? Color.black.opacity(0.42) : Color.white.opacity(0.52)
    }

    private var liftSymbolName: String? {
        switch liftTypeID {
        case "squat":          return "figure.strengthtraining.traditional"
        case "bench-press":    return "figure.strengthtraining.functional"
        case "deadlift":       return "figure.strengthtraining.traditional"
        case "overhead-press": return "figure.arms.open"
        case "row":            return "figure.rowing"
        default:               return nil
        }
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let style = plateTier?.style ?? .rawIron
            let profile = PlateVisualDesign.profile(for: style)
            let artwork = PlateVisualDesign.faceArtwork(for: style, showEngravings: showEngravings)
            let layout = PlateVisualDesign.markingLayout(for: style)
            ZStack {
                dropShadow
                outerRim(s: s, profile: profile)
                rimSheen
                faceGradient(s: s, profile: profile)
                raisedOuterLip(s: s, profile: profile)
                if !isRubberStyle { rings(s: s, profile: profile) }
                chromeBossRing(s: s, profile: profile)
                brandText(s: s, artwork: artwork, layout: layout)
                glossHighlight(s: s, profile: profile)
                glyphLayer(s: s, artwork: artwork, layout: layout)
                collarHole(s: s, profile: profile)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // MARK: - Layers

    private var dropShadow: some View {
        Circle()
            .fill(Color.black.opacity(0.38))
            .blur(radius: 2)
            .offset(x: 0, y: 2)
    }

    private func radiusPadding(s: CGFloat, visualRadius: Float, profile: PlateVisualProfile) -> CGFloat {
        let normalized = CGFloat(visualRadius / profile.outerRadius)
        return max(0, (1 - normalized) * s * 0.5)
    }

    private func radiusDiameter(s: CGFloat, visualRadius: Float, profile: PlateVisualProfile) -> CGFloat {
        CGFloat(visualRadius / profile.outerRadius) * s
    }

    private func outerRim(s: CGFloat, profile: PlateVisualProfile) -> some View {
        let rimColors: [Color] = isRubberStyle
            ? [Color(white: 0.16), Color(white: 0.06), Color(white: 0.02)]
            : [baseColor.darkened(by: 0.14), baseColor.darkened(by: 0.32), Color.black.opacity(0.90)]
        return Circle()
            .fill(
                RadialGradient(
                    colors: rimColors,
                    center: .init(x: 0.32, y: 0.26),
                    startRadius: s * 0.08,
                    endRadius: s * 0.54
                )
            )
            .padding(radiusPadding(s: s, visualRadius: min(profile.outerBandRadius, profile.outerRadius), profile: profile))
    }

    private var rimSheen: some View {
        Circle()
            .fill(
                AngularGradient(
                    colors: [
                        .white.opacity(specular * 0.65),
                        .white.opacity(0.02),
                        .white.opacity(specular * 0.10),
                        .white.opacity(0.02),
                        .white.opacity(specular * 0.30),
                        .white.opacity(specular * 0.65),
                    ],
                    center: .center,
                    startAngle: .degrees(-65),
                    endAngle: .degrees(295)
                )
            )
            .blendMode(.overlay)
    }

    @ViewBuilder
    private func faceGradient(s: CGFloat, profile: PlateVisualProfile) -> some View {
        let brightBoost: Double = isRubberStyle ? 0.28 : 0.18
        let darkDrop: Double   = isRubberStyle ? 0.22 : 0.38
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        baseColor.brightened(by: brightBoost),
                        baseColor,
                        baseColor.darkened(by: darkDrop),
                    ],
                    center: .init(x: 0.36, y: 0.30),
                    startRadius: 0,
                    endRadius: s * 0.50
                )
            )
            .padding(radiusPadding(s: s, visualRadius: profile.faceOuterRadius, profile: profile))
    }

    @ViewBuilder
    private func raisedOuterLip(s: CGFloat, profile: PlateVisualProfile) -> some View {
        if isRubberStyle {
            // Rubber: single bright chrome edge where face meets outer band
            Circle()
                .stroke(Color.white.opacity(0.55), lineWidth: s * 0.012)
                .padding(radiusPadding(s: s, visualRadius: profile.faceOuterRadius, profile: profile))
            Circle()
                .stroke(Color.black.opacity(0.70), lineWidth: s * 0.020)
                .padding(radiusPadding(s: s, visualRadius: profile.rimInnerRadius, profile: profile))
        } else {
            // Metal: triple-stroke suggesting raised outer rim and dish edge
            Circle()
                .stroke(Color.black.opacity(0.62), lineWidth: s * 0.055)
                .padding(radiusPadding(s: s, visualRadius: profile.rimOuterRadius, profile: profile))
            Circle()
                .stroke(Color.white.opacity(specular * 0.32), lineWidth: s * 0.018)
                .padding(radiusPadding(s: s, visualRadius: profile.rimInnerRadius, profile: profile))
            Circle()
                .stroke(Color.black.opacity(0.46), lineWidth: s * 0.020)
                .padding(radiusPadding(s: s, visualRadius: profile.faceInnerRadius, profile: profile))
        }
    }

    @ViewBuilder
    private func rings(s: CGFloat, profile: PlateVisualProfile) -> some View {
        let rim = radiusPadding(s: s, visualRadius: profile.rimInnerRadius, profile: profile)
        let limit = radiusPadding(s: s, visualRadius: profile.bossOuterRadius + 0.020, profile: profile)
        let step  = (limit - rim) / Double(ringCount + 1)
        ForEach(1...ringCount, id: \.self) { i in
            let pad = rim + step * Double(i)
            // Groove shadow: outer dark stroke
            Circle()
                .stroke(Color.black.opacity(0.48), lineWidth: s * 0.026)
                .padding(pad)
            // Groove highlight: thin bright inner stroke
            Circle()
                .stroke(Color.white.opacity(0.20), lineWidth: s * 0.010)
                .padding(pad + s * 0.017)
        }
    }

    @ViewBuilder
    private func brandText(s: CGFloat, artwork: PlateFaceArtworkPolicy, layout: PlateMarkingLayout) -> some View {
        ZStack {
            if artwork.showsBrandText {
                Text(artwork.brandText)
                .font(.system(size: s * layout.brandScaleRatio, weight: .black, design: .rounded))
                .tracking(0)
                .foregroundStyle(markColor.opacity(0.86))
                .shadow(color: Color.black.opacity(isLightBase ? 0 : 0.28), radius: 0.5, x: 0, y: 0.5)
                .offset(y: s * layout.brandYOffsetRatio * 0.5)
            }
            if artwork.showsWeightText {
                Text(weightLabel)
                    .font(.system(size: s * layout.weightScaleRatio, weight: .black, design: .rounded))
                    .tracking(0)
                    .foregroundStyle(mutedMarkColor.opacity(0.78))
                    .offset(y: s * layout.weightYOffsetRatio * 0.5)
            }
        }
    }

    @ViewBuilder
    private func chromeBossRing(s: CGFloat, profile: PlateVisualProfile) -> some View {
        let bossSize = radiusDiameter(s: s, visualRadius: profile.bossOuterRadius, profile: profile)
        let boreSize = radiusDiameter(s: s, visualRadius: profile.boreRadius, profile: profile)
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.92),
                            Color(white: 0.78),
                            Color(white: 0.52),
                        ],
                        center: .init(x: 0.36, y: 0.28),
                        startRadius: 0,
                        endRadius: bossSize * 0.5
                    )
                )
                .frame(width: bossSize, height: bossSize)
            // Inner shadow ring at bore edge to separate chrome from bore
            Circle()
                .stroke(Color.black.opacity(0.55), lineWidth: s * 0.016)
                .frame(width: boreSize + s * 0.016, height: boreSize + s * 0.016)
        }
    }

    @ViewBuilder
    private func glossHighlight(s: CGFloat, profile: PlateVisualProfile) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [.white.opacity(0.25), .clear],
                    center: .init(x: 0.30, y: 0.26),
                    startRadius: 0,
                    endRadius: s * 0.36
                )
            )
            .padding(radiusPadding(s: s, visualRadius: profile.faceOuterRadius, profile: profile))
    }

    @ViewBuilder
    private func glyphLayer(s: CGFloat, artwork: PlateFaceArtworkPolicy, layout: PlateMarkingLayout) -> some View {
        if artwork.showsLiftGlyph, let name = liftSymbolName {
            Image(systemName: name)
                .font(.system(size: s * layout.glyphScaleRatio, weight: .black))
                .foregroundStyle(
                    isLightBase
                        ? Color.black.opacity(0.36)
                        : Color.white.opacity(0.58)
                )
                .shadow(
                    color: isLightBase ? .clear : .black.opacity(0.50),
                    radius: s * 0.025,
                    x: 0,
                    y: s * 0.012
                )
                .offset(y: s * layout.glyphYOffsetRatio * 0.5)
        }
    }

    private func collarHole(s: CGFloat, profile: PlateVisualProfile) -> some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.black, Color.black.opacity(0.82), Color.white.opacity(0.16)],
                        center: .center,
                        startRadius: 0,
                        endRadius: s * 0.13
                    )
                )
            Circle()
                .stroke(Color.black.opacity(0.70), lineWidth: s * 0.020)
                .padding(s * 0.020)
            Circle()
                .stroke(Color.white.opacity(0.26), lineWidth: s * 0.010)
                .padding(s * 0.035)
        }
        .frame(
            width: radiusDiameter(s: s, visualRadius: profile.boreRadius, profile: profile),
            height: radiusDiameter(s: s, visualRadius: profile.boreRadius, profile: profile)
        )
    }

    private var weightLabel: String {
        if weightKg.rounded() == weightKg {
            return "\(Int(weightKg)) KG"
        }
        return "\(weightKg.formatted(.number.precision(.fractionLength(1)))) KG"
    }
}

// MARK: - Color helpers

private extension Color {
    func brightened(by amount: Double) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: Double(h), saturation: Double(s),
                     brightness: min(1, Double(b) + amount), opacity: Double(a))
    }

    func darkened(by amount: Double) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: Double(h), saturation: Double(s),
                     brightness: max(0, Double(b) - amount), opacity: Double(a))
    }
}
