import Foundation
import UIKit

struct PlateVisualProfile: Equatable {
    let outerRadius: Float
    let thickness: Float
    let boreRadius: Float
    /// Outer band protrudes slightly past outerRadius (rubber wrap or chrome ring).
    let outerBandRadius: Float
    let rimOuterRadius: Float
    let rimInnerRadius: Float
    let faceOuterRadius: Float
    let faceInnerRadius: Float
    let bossOuterRadius: Float
    /// Depth by which the face panel is shorter than the base plate height.
    let dishDepth: Float
    let hasGripCues: Bool
}

struct PlateFaceArtworkPolicy: Equatable {
    let showsBrandText: Bool
    let showsWeightText: Bool
    let showsLiftGlyph: Bool
    let brandText: String
}

struct PlateMarkingLayout: Equatable {
    /// Vertical position in 2D face space: -1 top, 0 center, +1 bottom.
    let brandYOffsetRatio: CGFloat
    let weightYOffsetRatio: CGFloat
    let glyphYOffsetRatio: CGFloat
    /// Text/glyph size as a fraction of total plate diameter.
    let brandScaleRatio: CGFloat
    let weightScaleRatio: CGFloat
    let glyphScaleRatio: CGFloat
    /// Radius from center where markings should sit.
    let markingRadiusRatio: CGFloat
}

struct PlateArcTextSpec: Equatable {
    let text: String
    let radiusRatio: CGFloat
    let startDegrees: CGFloat
    let endDegrees: CGFloat
}

struct PlateSideWeightTextSpec: Equatable {
    let rotationDegrees: CGFloat
}

struct PlateFaceRingSpec: Equatable {
    let outerRadius: Float
    let innerRadius: Float
}

struct PlateFaceRingDrawingMetrics: Equatable {
    let pathDiameterRatio: CGFloat
    let strokeWidthRatio: CGFloat
}

enum PlateVisualDesign {
    static func profile(for style: PlateTier.PlateStyle) -> PlateVisualProfile {
        switch style {
        case .bumper:
            return PlateVisualProfile(
                outerRadius: 0.22,
                thickness: 0.046,
                boreRadius: 0.034,
                outerBandRadius: 0.224,
                rimOuterRadius: 0.204,
                rimInnerRadius: 0.174,
                faceOuterRadius: 0.188,
                faceInnerRadius: 0.060,
                bossOuterRadius: 0.056,
                dishDepth: 0.004,
                hasGripCues: false
            )
        case .competition:
            return PlateVisualProfile(
                outerRadius: 0.22,
                thickness: 0.044,
                boreRadius: 0.034,
                outerBandRadius: 0.225,
                rimOuterRadius: 0.198,
                rimInnerRadius: 0.166,
                faceOuterRadius: 0.184,
                faceInnerRadius: 0.060,
                bossOuterRadius: 0.058,
                dishDepth: 0.003,
                hasGripCues: false
            )
        case .castIron:
            return PlateVisualProfile(
                outerRadius: 0.22,
                thickness: 0.034,
                boreRadius: 0.034,
                outerBandRadius: 0.222,
                rimOuterRadius: 0.218,
                rimInnerRadius: 0.190,
                faceOuterRadius: 0.176,
                faceInnerRadius: 0.070,
                bossOuterRadius: 0.064,
                dishDepth: 0.008,
                hasGripCues: true
            )
        case .starter:
            return PlateVisualProfile(
                outerRadius: 0.150,
                thickness: 0.026,
                boreRadius: 0.034,
                outerBandRadius: 0.152,
                rimOuterRadius: 0.146,
                rimInnerRadius: 0.124,
                faceOuterRadius: 0.116,
                faceInnerRadius: 0.054,
                bossOuterRadius: 0.050,
                dishDepth: 0.003,
                hasGripCues: false
            )
        case .rawIron, .brass, .polishedSteel, .gold:
            return PlateVisualProfile(
                outerRadius: 0.22,
                thickness: 0.030,
                boreRadius: 0.034,
                outerBandRadius: 0.222,
                rimOuterRadius: 0.216,
                rimInnerRadius: 0.188,
                faceOuterRadius: 0.176,
                faceInnerRadius: 0.064,
                bossOuterRadius: 0.058,
                dishDepth: 0.005,
                hasGripCues: false
            )
        }
    }

    static func faceArtwork(for style: PlateTier.PlateStyle, showEngravings: Bool = true) -> PlateFaceArtworkPolicy {
        guard showEngravings else {
            return PlateFaceArtworkPolicy(showsBrandText: false, showsWeightText: false, showsLiftGlyph: false, brandText: "VOLIA")
        }
        switch style {
        case .starter:
            return PlateFaceArtworkPolicy(showsBrandText: false, showsWeightText: false, showsLiftGlyph: false, brandText: "VOLIA")
        default:
            return PlateFaceArtworkPolicy(showsBrandText: true, showsWeightText: true, showsLiftGlyph: true, brandText: "VOLIA")
        }
    }

    static func markingLayout(for style: PlateTier.PlateStyle) -> PlateMarkingLayout {
        switch style {
        case .bumper, .competition:
            return PlateMarkingLayout(
                brandYOffsetRatio: -0.46,
                weightYOffsetRatio: 0.48,
                glyphYOffsetRatio: 0.00,
                brandScaleRatio: 0.105,
                weightScaleRatio: 0.085,
                glyphScaleRatio: 0.145,
                markingRadiusRatio: 0.62
            )
        case .starter:
            return PlateMarkingLayout(
                brandYOffsetRatio: -0.42,
                weightYOffsetRatio: 0.44,
                glyphYOffsetRatio: 0.00,
                brandScaleRatio: 0.085,
                weightScaleRatio: 0.070,
                glyphScaleRatio: 0.120,
                markingRadiusRatio: 0.56
            )
        default:
            return PlateMarkingLayout(
                brandYOffsetRatio: -0.44,
                weightYOffsetRatio: 0.46,
                glyphYOffsetRatio: 0.00,
                brandScaleRatio: 0.095,
                weightScaleRatio: 0.078,
                glyphScaleRatio: 0.130,
                markingRadiusRatio: 0.58
            )
        }
    }

    static func arcBrandTextSpecs(
        artwork: PlateFaceArtworkPolicy,
        layout: PlateMarkingLayout
    ) -> [PlateArcTextSpec] {
        guard artwork.showsBrandText else { return [] }
        return [
            PlateArcTextSpec(
                text: artwork.brandText,
                radiusRatio: layout.markingRadiusRatio * 0.60,
                startDegrees: -140,
                endDegrees: -40
            ),
            PlateArcTextSpec(
                text: artwork.brandText,
                radiusRatio: layout.markingRadiusRatio * 0.60,
                startDegrees: 40,
                endDegrees: 140
            )
        ]
    }

    static func sideWeightTextSpecs(layout: PlateMarkingLayout) -> [PlateSideWeightTextSpec] {
        [
            PlateSideWeightTextSpec(rotationDegrees: -90),
            PlateSideWeightTextSpec(rotationDegrees: 90)
        ]
    }

    static func faceRingSpecs(for style: PlateTier.PlateStyle) -> [PlateFaceRingSpec] {
        let profile = profile(for: style)
        switch style {
        case .bumper:
            return [
                PlateFaceRingSpec(outerRadius: profile.rimOuterRadius, innerRadius: profile.rimInnerRadius),
                PlateFaceRingSpec(outerRadius: profile.bossOuterRadius + 0.030, innerRadius: profile.bossOuterRadius)
            ]
        case .competition:
            return [
                PlateFaceRingSpec(outerRadius: profile.rimOuterRadius, innerRadius: profile.rimInnerRadius),
                PlateFaceRingSpec(outerRadius: profile.bossOuterRadius + 0.036, innerRadius: profile.bossOuterRadius)
            ]
        default:
            return []
        }
    }

    static func faceRingDrawingMetrics(
        for spec: PlateFaceRingSpec,
        profile: PlateVisualProfile
    ) -> PlateFaceRingDrawingMetrics {
        let pathRadius = (spec.outerRadius + spec.innerRadius) * 0.5
        return PlateFaceRingDrawingMetrics(
            pathDiameterRatio: CGFloat(pathRadius / profile.outerRadius),
            strokeWidthRatio: CGFloat((spec.outerRadius - spec.innerRadius) / profile.outerRadius)
        )
    }

    static func previewWeightKg(for style: PlateTier.PlateStyle) -> Double {
        switch style {
        case .starter:
            return 0
        case .bumper, .competition:
            return 20
        default:
            return 10
        }
    }
}
