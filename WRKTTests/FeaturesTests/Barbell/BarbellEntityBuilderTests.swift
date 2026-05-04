import RealityKit
import Testing
@testable import WRKT

@MainActor
struct BarbellEntityBuilderTests {

    @Test func plateTierCatalogHasExpectedIDs() {
        #expect(PlateTier.all.map(\.id) == Array(0...7))
    }

    @Test func starterTierIsLastAndMarkedStarterStyle() throws {
        let starter = try #require(PlateTier.all.last)
        #expect(starter.id == 7)
        #expect(starter.style == .starter)
        #expect(starter.name == "Starter")
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
}
