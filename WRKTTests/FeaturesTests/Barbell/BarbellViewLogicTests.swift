import Testing
import SwiftUI
import RealityKit
@testable import WRKT

struct BarbellViewLogicTests {

    @Test func plateWallTotalWeightIgnoresStarterPlates() {
        let rackedPlates = [
            EarnedPlate(id: "starter", tierID: 7, weightKg: 0, engravingText: "", earnedByEvent: "starter"),
            EarnedPlate(id: "five", tierID: 0, weightKg: 5, engravingText: "", earnedByEvent: "first_workout"),
            EarnedPlate(id: "ten", tierID: 1, weightKg: 10, engravingText: "", earnedByEvent: "5_workouts")
        ]

        #expect(plateWallTotalWeight(rackedPlates: rackedPlates) == 50)
    }

    @Test func plateWallTotalWeightFallsBackToBareBar() {
        let starterOnly = [
            EarnedPlate(id: "starter", tierID: 7, weightKg: 0, engravingText: "", earnedByEvent: "starter")
        ]

        #expect(plateWallTotalWeight(rackedPlates: starterOnly) == 20)
    }

    @Test func previewSelectionInfoReturnsPlateTierInfo() {
        let info = barbellPreviewSelectionInfo(activeTab: 0, selectedTier: 2, selectedBar: 0, selectedSticker: 0)

        #expect(info?.name == "Black Bumper")
        #expect(info?.rarity == .uncommon)
    }

    @Test func previewSelectionInfoReturnsBarSkinInfo() {
        let info = barbellPreviewSelectionInfo(activeTab: 1, selectedTier: 0, selectedBar: 3, selectedSticker: 0)

        #expect(info?.name == "Cerakote")
        #expect(info?.rarity == .rare)
    }

    @Test func previewSelectionInfoReturnsStickerInfo() {
        let info = barbellPreviewSelectionInfo(activeTab: 2, selectedTier: 0, selectedBar: 0, selectedSticker: 4)

        #expect(info?.name == "Crown")
        #expect(info?.rarity == .legendary)
    }

    @Test func previewSelectionInfoRejectsInvalidIndices() {
        #expect(barbellPreviewSelectionInfo(activeTab: 0, selectedTier: 99, selectedBar: 0, selectedSticker: 0) == nil)
        #expect(barbellPreviewSelectionInfo(activeTab: 1, selectedTier: 0, selectedBar: 99, selectedSticker: 0) == nil)
        #expect(barbellPreviewSelectionInfo(activeTab: 2, selectedTier: 0, selectedBar: 0, selectedSticker: 99) == nil)
        #expect(barbellPreviewSelectionInfo(activeTab: 42, selectedTier: 0, selectedBar: 0, selectedSticker: 0) == nil)
    }

    @Test func showcaseOffsetsLeaveDepthClearanceAroundRedPlates() throws {
        let plates = [
            EarnedPlateInfo(tierID: 0, weightKg: 10, engravingText: "", earnedByEvent: "first_workout"),
            EarnedPlateInfo(tierID: 4, weightKg: 20, engravingText: "", earnedByEvent: "squat_20"),
            EarnedPlateInfo(tierID: 2, weightKg: 15, engravingText: "", earnedByEvent: "bench_15")
        ]
        let offsets = barbellShowcaseRightSideOffsets(for: plates)

        #expect(offsets.count == plates.count)

        for index in 1..<offsets.count {
            let previousTier = try #require(PlateTier.all.first { $0.id == plates[index - 1].tierID })
            let currentTier = try #require(PlateTier.all.first { $0.id == plates[index].tierID })
            let requiredDistance = barbellShowcaseVisualHalfDepth(for: previousTier)
                + barbellShowcaseVisualHalfDepth(for: currentTier)

            #expect(offsets[index] - offsets[index - 1] > requiredDistance)
        }
    }

    @Test func previewBackWallSitsBehindLargestPlateDepth() {
        let largestPlateDepth = PlateTier.all
            .map { PlateVisualDesign.profile(for: $0.style).outerRadius }
            .max() ?? 0

        #expect(barbellPreviewBackWallZ < -(largestPlateDepth + 0.08))
    }

    @Test func barbellRealityCameraPositionUsesWelcomeDefaults() {
        let position = barbellRealityCameraPosition(for: .welcome(plates: []), sizeClass: .compact)

        #expect(position == SIMD3(0, 0.16, -1.22))
    }

    @Test func barbellRealityCameraPositionUsesRackRoomRegularWidthDepth() {
        let position = barbellRealityCameraPosition(
            for: .rackRoom(rackedPlates: [], floorPlates: [], onRack: { _ in }, onUnrack: { _ in }),
            sizeClass: .regular
        )

        #expect(position == SIMD3(0, -0.45, -1.9))
    }

    @Test func clampFloorPlateXUsesConfiguredBounds() {
        #expect(clampFloorPlateX(0.20) == 0.20)
        #expect(clampFloorPlateX(0.90) == 0.64)
        #expect(clampFloorPlateX(-0.90) == -0.64)
        #expect(clampFloorPlateX(0.90, maxAbsX: 0.50) == 0.50)
    }

    @Test func barbellEditorBottomPaddingClearsCustomTabBar() {
        #expect(barbellEditorScrollBottomPadding >= 120)
    }

    @Test func plateCollectionFallbackSummaryKeepsLiftIdentityAfterSourceWorkoutDelete() {
        let plate = EarnedPlate(
            tierID: 0,
            weightKg: 5,
            engravingText: "Bench Press",
            earnedByEvent: "lift_first_bench-press",
            sourceWorkoutID: UUID().uuidString,
            liftTypeID: "bench-press"
        )

        let summary = plateCollectionFallbackSummary(for: plate)

        #expect(summary?.title == "Bench Press")
        #expect(summary?.detail == "SOURCE WORKOUT DELETED")
    }

    @Test func friendShowcaseCancelledRequestIsRecognizedAsCancellation() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)

        #expect(BarbellProgressService.isCancelledRequestError(error))
    }

}
