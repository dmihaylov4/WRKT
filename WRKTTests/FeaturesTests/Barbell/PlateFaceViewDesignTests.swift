import Foundation
import Testing
@testable import WRKT

struct PlateFaceViewDesignTests {
    @Test func plateFaceAndRealityKitUseSameVisualProfiles() {
        for tier in PlateTier.all {
            let profile = PlateVisualDesign.profile(for: tier.style)
            #expect(profile.outerRadius > 0)
            #expect(profile.boreRadius > 0)
            #expect(profile.boreRadius < profile.bossOuterRadius)
            #expect(profile.bossOuterRadius < profile.faceOuterRadius)
            #expect(profile.faceOuterRadius < profile.outerRadius)
        }
    }

    @Test func plateFaceArtworkPolicyMatchesGymPlateGoal() {
        #expect(PlateVisualDesign.faceArtwork(for: .bumper, showEngravings: true).showsBrandText)
        #expect(PlateVisualDesign.faceArtwork(for: .competition, showEngravings: true).showsWeightText)
        #expect(PlateVisualDesign.faceArtwork(for: .starter, showEngravings: true).showsBrandText == false)
    }

    @Test func markingLayoutKeepsTextInsidePhysicalFacePanel() {
        for tier in PlateTier.all {
            let profile = PlateVisualDesign.profile(for: tier.style)
            let layout = PlateVisualDesign.markingLayout(for: tier.style)
            let normalizedFaceRadius = CGFloat(profile.faceOuterRadius / profile.outerRadius)
            #expect(abs(layout.brandYOffsetRatio) < normalizedFaceRadius)
            #expect(abs(layout.weightYOffsetRatio) < normalizedFaceRadius)
            #expect(layout.markingRadiusRatio < normalizedFaceRadius)
            #expect(layout.brandScaleRatio > 0)
            #expect(layout.weightScaleRatio > 0)
        }
    }

    @Test func engravingsGlobalToggleSuppressesAllArtwork() {
        for tier in PlateTier.all {
            let policy = PlateVisualDesign.faceArtwork(for: tier.style, showEngravings: false)
            #expect(policy.showsBrandText == false, "showEngravings=false must suppress brand on \(tier.id)")
            #expect(policy.showsWeightText == false, "showEngravings=false must suppress weight on \(tier.id)")
            #expect(policy.showsLiftGlyph == false, "showEngravings=false must suppress glyph on \(tier.id)")
        }
    }

    @Test func artworkPolicyKeeps2DAnd3DMarkingRulesExplicit() {
        for tier in PlateTier.all {
            let policy = PlateVisualDesign.faceArtwork(for: tier.style, showEngravings: true)
            if tier.style == .starter {
                #expect(policy.showsWeightText == false)
            } else {
                #expect(policy.showsWeightText == true)
            }
            let suppressed = PlateVisualDesign.faceArtwork(for: tier.style, showEngravings: false)
            #expect(suppressed.showsWeightText == false, "Tier \(tier.id): showEngravings=false must suppress weight text")
        }
    }

    @Test func twoDimensionalPlateFaceUsesCurvedVoliaAndSideWeights() {
        let artwork = PlateVisualDesign.faceArtwork(for: .competition, showEngravings: true)
        let layout = PlateVisualDesign.markingLayout(for: .competition)
        let brandSpecs = PlateVisualDesign.arcBrandTextSpecs(artwork: artwork, layout: layout)
        let weightSpecs = PlateVisualDesign.sideWeightTextSpecs(layout: layout)

        #expect(brandSpecs.map(\.text) == ["VOLIA", "VOLIA"])
        #expect(brandSpecs.allSatisfy { $0.radiusRatio > 0.30 && $0.radiusRatio < 0.50 })
        #expect(brandSpecs[0].startDegrees < brandSpecs[0].endDegrees)
        #expect(brandSpecs[1].startDegrees < brandSpecs[1].endDegrees)
        #expect(weightSpecs.count == 2)
        #expect(Set(weightSpecs.map(\.rotationDegrees)) == Set([-90, 90]))
    }

    @Test func editorPreviewPlatesUseVisibleSampleWeightArtwork() {
        for tier in PlateTier.all where tier.style != .starter {
            #expect(PlateVisualDesign.previewWeightKg(for: tier.style) > 0)
        }
    }
}
