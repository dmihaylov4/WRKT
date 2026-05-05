import RealityKit
import Testing
import CoreFoundation
import UIKit
@testable import WRKT

@MainActor
struct BarbellEntityBuilderTests {

    @Test func plateTierCatalogHasExpectedIDs() {
        #expect(PlateTier.all.map(\.id) == [0, 1, 2, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 3, 4, 5, 6, 8, 9, 13, 10, 11, 12, 7])
    }

    @Test func starterTierIsLastAndMarkedStarterStyle() throws {
        let starter = try #require(PlateTier.all.last)
        #expect(starter.id == 7)
        #expect(starter.style == .starter)
        #expect(starter.name == "Starter")
    }

    @Test func plateTierCatalogIncludesPremiumColorways() {
        let names = Set(PlateTier.all.map(\.name))

        #expect(names.contains("Purple"))
        #expect(names.contains("Rose Gold"))
        #expect(names.contains("Emerald"))
        #expect(names.contains("Copper"))
        #expect(names.contains("Rusty Iron"))
        #expect(names.contains("Royal Gold"))
        #expect(names.contains("Diamond"))
    }

    @Test func plateTierCatalogIncludesBumperColorways() throws {
        let colorwayNames = [
            "Red Bumper", "Blue Bumper", "Green Bumper", "Yellow Bumper", "Pink Bumper",
            "Orange Bumper", "White Bumper", "Teal Bumper", "Lime Bumper", "Navy Bumper"
        ]

        for name in colorwayNames {
            let tier = try #require(PlateTier.all.first { $0.name == name })
            #expect(tier.style == .bumper)
            #expect(tier.metallic == 0)
            #expect(tier.roughness >= 0.72)
            #expect(tier.clearcoat <= 0.35)
        }
    }

    @Test func roseGoldReadsPinkInsteadOfCopper() throws {
        let tier = try #require(PlateTier.all.first { $0.name == "Rose Gold" })
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 1
        tier.plateColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        #expect(red >= 0.95)
        #expect(blue >= 0.55)
        #expect(green <= 0.42)
        #expect(blue > green, "Rose Gold should skew pink, not copper-orange")
    }

    @Test func diamondReadsMinecraftBlue() throws {
        let tier = try #require(PlateTier.all.first { $0.name == "Diamond" })
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 1
        tier.plateColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        #expect(red <= 0.35)
        #expect(green >= 0.80)
        #expect(blue >= 0.95)
        #expect(blue > green)
    }

    @Test func premiumMetalColorwaysAreFullyShiny() throws {
        let shinyNames = ["Gold", "Polished Steel", "Rose Gold", "Emerald", "Copper", "Royal Gold", "Diamond", "Rusty Iron"]
        for name in shinyNames {
            let tier = try #require(PlateTier.all.first { $0.name == name })
            #expect(tier.metallic >= 0.85, "\(name) should read as metal in RealityKit")
            #expect(tier.roughness <= 0.08, "\(name) should have sharp shiny highlights")
            #expect(tier.clearcoat >= 0.75, "\(name) should have a glossy coat")
        }
    }

    @Test func premiumMetalSidewallsUseReadableSurfacePolicy() throws {
        let shinyNames = ["Gold", "Polished Steel", "Rose Gold", "Emerald", "Copper", "Royal Gold", "Diamond", "Rusty Iron"]
        for name in shinyNames {
            let tier = try #require(PlateTier.all.first { $0.name == name })
            let sidewall = PlateSidewallSurface.sidewall(for: tier)
            let lip = PlateSidewallSurface.lip(for: tier)

            #expect(sidewall.metallic >= 0.42, "\(name) side should still read as metal")
            #expect(sidewall.metallic <= 0.68, "\(name) side should keep enough diffuse color for storage")
            #expect(sidewall.roughness >= 0.20, "\(name) side should avoid mirror-black reflections")
            #expect(sidewall.roughness <= 0.34, "\(name) side should not become flat plastic")
            #expect(sidewall.clearcoat <= 0.78, "\(name) side should avoid blown-out glare")
            #expect(lip.metallic >= 0.42, "\(name) lip should still read as metal")
            #expect(lip.metallic <= 0.72, "\(name) lip should keep enough diffuse color for storage")
            #expect(lip.roughness >= 0.18, "\(name) lip should avoid mirror-black reflections")
        }
    }

    @Test func premiumMetalDisplayMaterialPrioritizesReadableColor() throws {
        let shinyNames = ["Gold", "Polished Steel", "Rose Gold", "Emerald", "Copper", "Royal Gold", "Diamond", "Rusty Iron"]
        for name in shinyNames {
            let tier = try #require(PlateTier.all.first { $0.name == name })

            #expect(PlateDisplaySurface.metallic(for: tier) >= 0.38, "\(name) should still read metallic")
            #expect(PlateDisplaySurface.metallic(for: tier) <= 0.58, "\(name) should not mirror the dark room")
            #expect(PlateDisplaySurface.roughness(for: tier) >= 0.18, "\(name) should keep labels and color readable")
            #expect(PlateDisplaySurface.roughness(for: tier) <= 0.34, "\(name) should retain a polished finish")
            #expect(PlateDisplaySurface.clearcoat(for: tier) <= 0.72, "\(name) should avoid blown-out glare")
        }
    }

    @Test func colorfulPlateDisplayColorsStayVividInRackRoom() throws {
        let colorfulNames = ["Rusty Iron", "Brass", "Competition", "Gold", "Rose Gold", "Emerald", "Copper", "Purple", "Royal Gold"]
        for name in colorfulNames {
            let tier = try #require(PlateTier.all.first { $0.name == name })
            let baseHSB = tier.plateColor.barbellHSB
            let faceHSB = PlateDisplaySurface.faceColor(for: tier).barbellHSB

            #expect(faceHSB.saturation >= min(1, baseHSB.saturation + 0.20), "\(name) needs saturated display color")
            #expect(faceHSB.brightness >= min(1, max(baseHSB.brightness + 0.20, 0.72)), "\(name) needs enough brightness in RealityKit")
        }
    }

    @Test func darkPlateDisplayColorsHaveDimensionalContrast() throws {
        let darkNames = ["Cast Iron", "Black Bumper"]
        for name in darkNames {
            let tier = try #require(PlateTier.all.first { $0.name == name })
            let faceHSB = PlateDisplaySurface.faceColor(for: tier).barbellHSB
            let sideHSB = PlateDisplaySurface.sidewallColor(for: tier).barbellHSB
            let lipHSB = PlateDisplaySurface.lipColor(for: tier).barbellHSB

            #expect(faceHSB.brightness >= 0.32, "\(name) face should not disappear in the rack room")
            #expect(sideHSB.brightness >= 0.34, "\(name) side should stay visible in storage")
            #expect(lipHSB.brightness >= sideHSB.brightness, "\(name) lip should catch more light than the sidewall")
            #expect(lipHSB.brightness - faceHSB.brightness >= 0.04, "\(name) lip needs enough contrast to avoid looking flat")
        }
    }

    @Test func bumperPlateCentersUseMatteRubberNotChrome() throws {
        for tier in PlateTier.all where tier.style == .bumper {
            let hub = BumperPlateSurface.centerHub(for: tier)

            #expect(hub.metallic == 0, "\(tier.name) center should not be shiny metal")
            #expect(hub.roughness >= 0.86, "\(tier.name) center should read as matte rubber")
            #expect(hub.clearcoat <= 0.12, "\(tier.name) center should not have glossy clearcoat")
        }
    }

    @Test func premiumMetalDisplayColorsAreVibrant() throws {
        let colorfulMetalNames = ["Gold", "Rose Gold", "Emerald", "Copper", "Royal Gold", "Rusty Iron"]
        for name in colorfulMetalNames {
            let tier = try #require(PlateTier.all.first { $0.name == name })
            let baseHSB = tier.plateColor.barbellHSB
            let faceHSB = PlateDisplaySurface.faceColor(for: tier).barbellHSB
            let sideHSB = PlateDisplaySurface.sidewallColor(for: tier).barbellHSB

            #expect(faceHSB.saturation >= min(1, baseHSB.saturation + 0.08), "\(name) face should be more saturated")
            #expect(sideHSB.saturation >= min(1, baseHSB.saturation + 0.12), "\(name) side should be more saturated")
            #expect(sideHSB.brightness >= baseHSB.brightness, "\(name) side should not be darker than base")
        }
    }

    @Test func rackRoomLightingIncludesSubjectAndRimSeparation() {
        let lighting = RackRoomLightingPreset.readability

        #expect(lighting.keyIntensity >= 6_000)
        #expect(lighting.keyPosition.y >= 1.8)
        #expect(lighting.keyPosition.z >= 1.85)
        #expect(lighting.fillIntensity >= 2_600)
        #expect(abs(lighting.fillPosition.x) <= 0.05)
        #expect(lighting.fillPosition.z < 1.0)
        #expect(lighting.frontWashIntensity >= 3_600)
        #expect(abs(lighting.frontWashPosition.x) <= 0.05)
        #expect(lighting.frontWashPosition.z < 1.0)
        #expect(lighting.barWashIntensity >= 6_600)
        #expect(lighting.barSideWashIntensity >= 4_400)
        #expect(lighting.barSideWashX >= 0.72)
        #expect(lighting.storageWashIntensity >= 6_200)
        #expect(lighting.storageWashY >= 1.55)
        #expect(lighting.storageFaceWashIntensity >= 4_600)
        #expect(lighting.storageFaceWashX >= 0.70)
        #expect(lighting.storageSideWashIntensity >= 4_800)
        #expect(lighting.storageSideWashX >= 0.9)
        #expect(lighting.storageSideWashY >= 1.45)
        #expect(lighting.rimWashIntensity <= 1_600)
        #expect(abs(lighting.rimWashPosition.x) <= 0.05)
        #expect(lighting.rimWashPosition.z <= 0.40)
        #expect(lighting.imageBasedLightIntensityExponent >= 1.2)
        #expect(lighting.castsObjectShadows == false)
        #expect(lighting.usesDirectionalKey == false)
    }

    @Test func roomThemesProvidePlateZoneContrast() {
        for id in ["dark_gym", "concrete_room", "competition_platform", "neon_garage", "iron_basement", "daylight_studio", "brick_powerhouse"] {
            let theme = RoomThemePreset.preset(for: id)

            #expect(theme.plateZoneLuminance >= theme.backdropLuminance + 0.04, "\(id) should separate plates from the wall")
            #expect(theme.plateZoneLuminance <= theme.backdropLuminance + 0.12, "\(id) should not look like a random light patch")
            #expect(theme.plateZoneRoughness >= 0.78, "\(id) plate zone should stay matte instead of mirror-dark")
            #expect(theme.plateZoneMetallic == 0, "\(id) plate zone should not pick up dark metal reflections")
        }
    }

    @Test func roomThemeCatalogIncludesExpandedOptions() {
        let ids = Set(BarbellCosmeticCatalog.current.items.filter { $0.kind == .roomTheme }.map(\.id))

        #expect(ids.isSuperset(of: [
            "dark_gym",
            "concrete_room",
            "competition_platform",
            "neon_garage",
            "iron_basement",
            "daylight_studio",
            "brick_powerhouse"
        ]))
    }

    @Test func roomWallTextIsUppercaseShortAndWallSafe() {
        #expect(barbellNormalizedRoomWallText("room 204!") == "ROOM 204")
        #expect(barbellNormalizedRoomWallText("deadlift dungeon") == "DEADLIFT DUN")
        #expect(barbellNormalizedRoomWallText("   ") == nil)
        #expect(barbellNormalizedRoomWallText("A-B_C") == "A B C")
    }

    @Test func darkGymThemeUsesReadableFloorAndWallValues() {
        let theme = RoomThemePreset.preset(for: "dark_gym")

        #expect(theme.floorLuminance >= 0.30)
        #expect(theme.backdropLuminance >= 0.25)
        #expect(theme.stripLuminance >= 0.42)
    }

    @Test func goldAndPremiumMetalColorwaysDoNotUseBrassTexture() {
        #expect(loadPlateTextures(forTierID: 3).albedo != nil)
        for tierID in [0, 5, 6, 8, 9, 11, 12, 13] {
            #expect(loadPlateTextures(forTierID: tierID).albedo == nil, "Tier \(tierID) should use distinct tint material, not Brass texture")
        }
    }

    @Test func plateAudioCategoryMapsExpectedTiers() {
        #expect(PlateAudioCategory.from(tierID: 0) == .iron)
        #expect(PlateAudioCategory.from(tierID: 1) == .iron)
        #expect(PlateAudioCategory.from(tierID: 2) == .rubber)
        #expect(PlateAudioCategory.from(tierID: 3) == .brass)
        #expect(PlateAudioCategory.from(tierID: 4) == .iron)
        #expect(PlateAudioCategory.from(tierID: 5) == .iron)
        #expect(PlateAudioCategory.from(tierID: 6) == .brass)
        #expect(PlateAudioCategory.from(tierID: 7) == .starter)
        #expect(PlateAudioCategory.from(tierID: 8) == .brass)
        #expect(PlateAudioCategory.from(tierID: 9) == .brass)
        #expect(PlateAudioCategory.from(tierID: 10) == .rubber)
        #expect(PlateAudioCategory.from(tierID: 11) == .brass)
        #expect(PlateAudioCategory.from(tierID: 12) == .brass)
        #expect(PlateAudioCategory.from(tierID: 13) == .brass)
        for tierID in [14, 15, 16, 17, 18, 19, 20, 21, 22, 23] {
            #expect(PlateAudioCategory.from(tierID: tierID) == .rubber)
        }
    }

    @Test func progressionRenderProjectionMapsTierToRings() {
        #expect(BarbellPlateRenderProjection(progressionTier: .iron).tierRingCount == 0)
        #expect(BarbellPlateRenderProjection(progressionTier: .steel).tierRingCount == 1)
        #expect(BarbellPlateRenderProjection(progressionTier: .chrome).tierRingCount == 2)
        #expect(BarbellPlateRenderProjection(progressionTier: .gold).tierRingCount == 3)
        #expect(BarbellPlateRenderProjection(progressionTier: .obsidian).tierRingCount == 3)
        #expect(BarbellPlateRenderProjection(progressionTier: .cosmic).tierRingCount == 3)
    }

    @Test func progressionRenderProjectionCapsAndClampsWearMarks() {
        let empty = BarbellPlateRenderProjection(
            chalkUseCount: -4,
            gripWearCount: -5,
            pressUseCount: -6
        )
        #expect(empty.chalkMarkCount == 0)
        #expect(empty.gripWearMarkCount == 0)
        #expect(empty.pressPolishMarkCount == 0)

        let saturated = BarbellPlateRenderProjection(
            chalkUseCount: 100,
            gripWearCount: 100,
            pressUseCount: 100
        )
        #expect(saturated.chalkMarkCount == 8)
        #expect(saturated.gripWearMarkCount == 6)
        #expect(saturated.pressPolishMarkCount == 5)
    }

    @Test func barSkinCatalogHasUniqueIDs() {
        let ids = BarSkin.all.map(\.id)
        #expect(Set(ids).count == BarSkin.all.count)
        #expect(ids == Array(0..<(BarSkin.all.count)))
    }

    @Test func barSkinCatalogIncludesChromeDefault() throws {
        let chrome = try #require(BarSkin.all.first)
        #expect(chrome.id == 0)
        #expect(chrome.name == "Chrome")
        #expect(chrome.earnedBy == "Default")
    }

    @Test func stickerCatalogHasNoneOptionFirst() throws {
        let none = try #require(StickerOption.all.first)
        #expect(none.id == 0)
        #expect(none.name == "None")
        #expect(none.emoji == nil)
    }

    @Test func stickerCatalogContainsLegendaryCrown() {
        let crown = StickerOption.all.first(where: { $0.name == "Crown" })
        #expect(crown?.rarity == .legendary)
        #expect(crown?.emoji == "👑")
    }

    @Test func plateVisualProfilesMatchCurrentTierStyles() throws {
        #expect(PlateVisualDesign.profile(for: .rawIron).outerRadius == 0.22)
        #expect(PlateVisualDesign.profile(for: .rawIron).thickness == 0.030)
        #expect(PlateVisualDesign.profile(for: .castIron).dishDepth > 0)
        #expect(PlateVisualDesign.profile(for: .bumper).thickness > PlateVisualDesign.profile(for: .rawIron).thickness)
        #expect(PlateVisualDesign.profile(for: .competition).outerBandRadius > 0.22)
        #expect(PlateVisualDesign.profile(for: .starter).outerRadius < 0.18)
    }

    @Test func allPlateTiersBuildNonEmptyVisualEntities() {
        for tier in PlateTier.all {
            let entity = makePlateEntity(tierID: tier.id, weightKg: 20)
            #expect(entity.children.count >= 3, "Tier \(tier.id) should have layered gym-plate visual detail")
            #expect(entity.components[InputTargetComponent.self] != nil)
            #expect(entity.components[CollisionComponent.self] != nil)
            #expect(entity.components[PhysicsBodyComponent.self] != nil)
            #expect(entity.components[PhysicsMotionComponent.self] != nil)
            #expect(entity.components[PlateRoleComponent.self] != nil)
            #expect(entity.components[TierIDComponent.self]?.tierID == tier.id)
        }
    }

    @Test func bumperAndCompetitionPlatesHaveMoldedDetailLayers() {
        let bumperTiers = PlateTier.all.filter { $0.style == .bumper }
        let competitionTiers = PlateTier.all.filter { $0.style == .competition }
        #expect(!bumperTiers.isEmpty, "Test assumes at least one bumper tier exists")
        #expect(!competitionTiers.isEmpty, "Test assumes at least one competition tier exists")

        for tier in bumperTiers {
            let entity = makePlateEntity(tierID: tier.id, weightKg: 20)
            #expect(entity.children.contains { $0.name == "outerRubberBand" }, "Tier \(tier.id)")
            #expect(entity.children.contains { $0.name == "moldedFaceRing_outer" }, "Tier \(tier.id)")
            #expect(entity.children.contains { $0.name == "moldedFaceRing_inner" }, "Tier \(tier.id)")
        }

        for tier in competitionTiers {
            let entity = makePlateEntity(tierID: tier.id, weightKg: 20)
            #expect(entity.children.contains { $0.name == "outerRubberBand" }, "Tier \(tier.id)")
            #expect(entity.children.contains { $0.name == "competitionChromeRing_outer" }, "Tier \(tier.id)")
            #expect(entity.children.contains { $0.name == "competitionChromeRing_inner" }, "Tier \(tier.id)")
        }
    }

    @Test func faceDetailLayersSitOnPlateFacesNotCenterline() {
        let faceDetailNames = [
            "moldedFaceRing_outer",
            "moldedFaceRing_inner",
            "competitionChromeRing_outer",
            "competitionChromeRing_inner",
            "centerBoss",
            "chromeHub"
        ]

        for tier in PlateTier.all {
            let entity = makePlateEntity(tierID: tier.id, weightKg: 20)
            for name in faceDetailNames {
                guard let detail = entity.children.first(where: { $0.name == name }) else { continue }
                #expect(abs(detail.position.y) > 0.001, "\(name) on tier \(tier.id) should sit on the plate face")
                let backName = "\(name)_back"
                #expect(entity.children.contains { $0.name == backName }, "\(backName) missing on tier \(tier.id)")
            }
        }
    }

    @Test func ironStylePlatesHaveRaisedRimAndDishLayers() {
        let ironTiers = PlateTier.all.filter {
            switch $0.style {
            case .rawIron, .castIron, .brass, .polishedSteel, .gold, .starter:
                return true
            case .bumper, .competition:
                return false
            }
        }
        #expect(!ironTiers.isEmpty, "Test assumes metal/iron-style tiers exist")

        for tier in ironTiers {
            let entity = makePlateEntity(tierID: tier.id, weightKg: 20)
            #expect(entity.children.contains { $0.name == "raisedOuterRim" }, "Tier \(tier.id) missing raised rim")
            #expect(entity.children.contains { $0.name == "recessedFacePanel" }, "Tier \(tier.id) missing recessed face")
            #expect(entity.children.contains { $0.name == "centerBoss" }, "Tier \(tier.id) missing center boss")
        }
    }

    @Test func plateRealismPassPreservesProgressionAndWeightLayers() {
        let entity = makePlateEntity(
            tierID: 2,
            weightKg: 20,
            renderProjection: BarbellPlateRenderProjection(
                progressionTier: .gold,
                chalkUseCount: 40,
                gripWearCount: 40,
                pressUseCount: 40
            )
        )

        #expect(entity.children.count >= 8)
        #expect(entity.components[InputTargetComponent.self] != nil)
        #expect(entity.components[CollisionComponent.self] != nil)
        #expect(entity.components[PhysicsMotionComponent.self] != nil)
        #expect(entity.components[PlateAudioCategoryComponent.self]?.category == .rubber)
    }

    @Test func visualOnlyPlateBuildSkipsInteractiveRuntimeComponents() {
        let entity = makePlateEntity(
            tierID: 2,
            weightKg: 20,
            options: .visualOnly(role: .bar)
        )

        #expect(entity.children.count >= 3)
        #expect(entity.components[InputTargetComponent.self] == nil)
        #expect(entity.components[CollisionComponent.self] == nil)
        #expect(entity.components[PhysicsBodyComponent.self] == nil)
        #expect(entity.components[PhysicsMotionComponent.self] == nil)
        #expect(entity.components[PlateRoleComponent.self]?.role == .bar)
        #expect(entity.components[TierIDComponent.self]?.tierID == 2)
        #expect(entity.components[PlateAudioCategoryComponent.self]?.category == .rubber)
    }

    @Test func plateWithEngravingTextHasEngravingDiscOnBothFaces() {
        let entity = makePlateEntity(tierID: 3, weightKg: 15, engravingText: "25 Workouts")
        #expect(entity.children.contains { $0.name == "engravingDisc" })
        #expect(entity.children.contains { $0.name == "engravingDisc_back" })
    }

    @Test func plateWithEmptyEngravingTextHasNoEngravingDisc() {
        let entity = makePlateEntity(tierID: 3, weightKg: 15, engravingText: "")
        #expect(!entity.children.contains { $0.name == "engravingDisc" })
    }

    @Test func starterPlateSkipsEngravingDisc() {
        let entity = makePlateEntity(tierID: 7, weightKg: 0, engravingText: "Starter")
        #expect(!entity.children.contains { $0.name == "engravingDisc" })
    }

    @Test func engravingDiscHiddenWhenShowEngravingsIsFalse() {
        let entity = makePlateEntity(tierID: 3, weightKg: 15, engravingText: "25 Workouts", showEngravings: false)
        #expect(!entity.children.contains { $0.name == "engravingDisc" })
    }

    @Test func newBumperColorwaysAllBuildWithRubberDetails() {
        for tierID in [19, 20, 21, 22, 23] {
            let entity = makePlateEntity(tierID: tierID, weightKg: 20)
            #expect(entity.children.contains { $0.name == "outerRubberBand" }, "Tier \(tierID) missing rubber band")
            #expect(entity.children.contains { $0.name == "moldedFaceRing_outer" }, "Tier \(tierID) missing face ring")
        }
    }
}
