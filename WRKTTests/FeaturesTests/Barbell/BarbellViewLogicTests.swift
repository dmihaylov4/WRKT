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

    @Test func barbellRealityCameraPositionUsesWelcomeDefaults() {
        let position = barbellRealityCameraPosition(for: .welcome(plates: []), sizeClass: .compact)

        #expect(position == SIMD3(0, 0.16, -1.22))
    }

    @Test func barbellRealityCameraPositionBringsRackRoomCloserOnCompactWidth() {
        let position = barbellRealityCameraPosition(
            for: .rackRoom(rackedPlates: [], floorPlates: [], onRack: { _ in }, onUnrack: { _ in }),
            sizeClass: .compact
        )

        #expect(position == SIMD3(0, -0.40, -1.30))
    }

    @Test func barbellRealityCameraPositionKeepsRackRoomUsableOnRegularWidth() {
        let position = barbellRealityCameraPosition(
            for: .rackRoom(rackedPlates: [], floorPlates: [], onRack: { _ in }, onUnrack: { _ in }),
            sizeClass: .regular
        )

        #expect(position == SIMD3(0, -0.42, -1.72))
    }

    @Test func barbellPreviewSceneIdentityChangesWhenShowcaseChanges() {
        let first = barbellPreviewSceneIdentity(
            selectedTier: 0,
            selectedBar: 0,
            selectedSticker: 0,
            selectedRoomThemeID: "dark_gym",
            selectedRackStyleID: "matte_black",
            showPlateEngravings: true,
            showcaseSignature: "plate-a"
        )
        let second = barbellPreviewSceneIdentity(
            selectedTier: 0,
            selectedBar: 0,
            selectedSticker: 0,
            selectedRoomThemeID: "dark_gym",
            selectedRackStyleID: "matte_black",
            showPlateEngravings: true,
            showcaseSignature: "plate-b"
        )

        #expect(first != second)
    }

    @Test func barbellPreviewSceneIdentityIgnoresAssetRevisionChanges() {
        let initial = barbellPreviewSceneIdentity(
            selectedTier: 0,
            selectedBar: 0,
            selectedSticker: 0,
            selectedRoomThemeID: "dark_gym",
            selectedRackStyleID: "matte_black",
            showPlateEngravings: true,
            showcaseSignature: "plate-a",
            assetRevision: 0
        )
        let afterTexturePreload = barbellPreviewSceneIdentity(
            selectedTier: 0,
            selectedBar: 0,
            selectedSticker: 0,
            selectedRoomThemeID: "dark_gym",
            selectedRackStyleID: "matte_black",
            showPlateEngravings: true,
            showcaseSignature: "plate-a",
            assetRevision: 1
        )

        #expect(initial == afterTexturePreload)
    }

    @Test func socialProfileShowcaseUsesSettingsBarbellRenderer() {
        #expect(barbellShowcasePreviewRenderer(for: .socialProfileCard) == .realityKit)
        #expect(barbellShowcasePreviewRenderer(for: .socialProfileRoom) == .realityKit)
    }

    @Test func editorShowcaseKeepsRealityKitRenderer() {
        #expect(barbellShowcasePreviewRenderer(for: .editor) == .realityKit)
    }

    @Test func clampFloorPlateXUsesConfiguredBounds() {
        #expect(clampFloorPlateX(0.20) == 0.20)
        #expect(clampFloorPlateX(0.90) == 0.64)
        #expect(clampFloorPlateX(-0.90) == -0.64)
        #expect(clampFloorPlateX(0.90, maxAbsX: 0.50) == 0.50)
    }

    @Test func rackRoomSlideOutAnimationRemainsEnabledWithReduceMotion() {
        #expect(barbellRackRoomSlideOutDuration(isReduceMotionEnabled: false) == 0.2)
        #expect(barbellRackRoomSlideOutDuration(isReduceMotionEnabled: true) == 0.2)
    }

    @Test func barbellEditorBottomPaddingClearsCustomTabBar() {
        #expect(barbellEditorScrollBottomPadding >= 120)
    }

    @Test func configuredDisplayPlatesPreservesEmptyConfiguredBar() {
        let plates = [
            EarnedPlate(id: "earned", tierID: 0, weightKg: 10, engravingText: "", earnedByEvent: "first_workout", isRacked: true)
        ]

        let configured = configuredBarbellDisplayPlates(
            loadout: DisplayLoadout(onBar: [], onWall: ["earned"]),
            earnedPlates: plates
        )

        #expect(configured != nil)
        #expect(configured?.isEmpty == true)
    }

    @Test func playgroundBuildsEveryPlateTierAndProgressionVariant() {
        let variants = barbellPlaygroundPlateVariants(weightKg: 20, liftTypeID: "bench-press")

        #expect(variants.count == PlateTier.all.count * BarbellPlateProgressionTier.allCases.count)
        #expect(Set(variants.map(\.tierID)) == Set(PlateTier.all.map(\.id)))
        #expect(Set(variants.map(\.currentTier)) == Set(BarbellPlateProgressionTier.allCases))
    }

    @Test func playgroundInitialRackRoomUsesRealEarnedPlateModels() {
        let plates = barbellPlaygroundInitialPlates(
            selectedTierID: 4,
            progressionTier: .chrome,
            weightKg: 25,
            liftTypeID: "squat",
            engravingText: "Squat 25"
        )

        let allRackedPlatesAreOnBar = plates.racked.filter { $0.isRacked }.count == plates.racked.count
        let allFloorPlatesAreStored = plates.floor.filter { !$0.isRacked }.count == plates.floor.count
        let allRackedPlatesUseSelection = plates.racked.filter {
            $0.tierID == 4 && $0.currentTier == .chrome
        }.count == plates.racked.count

        #expect(plates.racked.count == 2)
        #expect(plates.floor.count == PlateTier.all.count)
        #expect(allRackedPlatesAreOnBar)
        #expect(allFloorPlatesAreStored)
        #expect(allRackedPlatesUseSelection)
    }

    @Test func playgroundRackMutationKeepsBarAtFourPlates() {
        var state = BarbellPlaygroundRackState(
            racked: (0..<4).map {
                EarnedPlate(id: "racked-\($0)", tierID: 0, weightKg: 20, engravingText: "", earnedByEvent: "playground", isRacked: true, rackPosition: $0)
            },
            floor: [
                EarnedPlate(id: "floor", tierID: 1, weightKg: 20, engravingText: "", earnedByEvent: "playground")
            ]
        )

        let didRack = state.rackPlate(id: "floor")

        #expect(didRack == false)
        #expect(state.racked.count == 4)
        #expect(state.floor.count == 1)
    }

    @Test func playgroundControlsHeightShrinksWhenMinimized() {
        #expect(barbellPlaygroundControlsMaxHeight(isMinimized: false) == 390)
        #expect(barbellPlaygroundControlsMaxHeight(isMinimized: true) < 90)
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

    @Test func plateCollectionHealthKitSummaryShowsWorkoutCategoryAndType() {
        let healthKitUUID = UUID()
        let plate = EarnedPlate(
            tierID: 1,
            weightKg: 5,
            engravingText: "5 Sessions",
            earnedByEvent: "hk_milestone_5",
            sourceWorkoutID: healthKitUUID.uuidString
        )
        let run = Run(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            distanceKm: 0,
            durationSec: 1_800,
            healthKitUUID: healthKitUUID,
            workoutType: "High Intensity Interval Training"
        )

        let summary = plateCollectionHealthKitSummary(for: plate, run: run)

        #expect(summary?.title == "Hybrid")
        #expect(summary?.detail == "HIGH INTENSITY INTERVAL TRAINING")
    }

    @Test func friendShowcaseCancelledRequestIsRecognizedAsCancellation() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)

        #expect(BarbellProgressService.isCancelledRequestError(error))
    }

}
