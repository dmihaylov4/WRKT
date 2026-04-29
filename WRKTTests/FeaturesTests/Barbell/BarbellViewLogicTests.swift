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

    @Test func barbellRealityCameraPositionUsesWelcomeDefaults() {
        let position = barbellRealityCameraPosition(for: .welcome(plates: []), sizeClass: .compact)

        #expect(position == SIMD3(0, 0.15, -1.2))
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

}
