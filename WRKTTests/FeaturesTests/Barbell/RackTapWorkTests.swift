import Foundation
import RealityKit
import Testing
import UIKit
@testable import WRKT

/// The in-memory lathe face cache keeps to its bound without evicting faces in use, and identical
/// plates share their faces.
@MainActor
@Suite(.serialized)
struct RackTapWorkTests {
    /// A tray plate whose faces nothing can have prepared: its own engraving and weight.
    private static func trayPlate(tier: Int = 14) -> EarnedPlate {
        let tag = UUID().uuidString.prefix(8)
        return EarnedPlate(id: "tap-\(tag)", tierID: tier, weightKg: 17.5, engravingText: "Tap \(tag)",
                           earnedByEvent: "fixture", isRacked: false, rackPosition: nil)
    }

    private static func latheScene() -> SceneState {
        let state = SceneState()
        state.plateStyle = .lathe
        return state
    }

    private static func faceMaterialHasTexture(_ entity: Entity?) -> Bool {
        guard let plate = entity?.findEntity(named: "lathePlate") as? ModelEntity ?? entity as? ModelEntity,
              let face = plate.model?.materials.last as? PhysicallyBasedMaterial else { return false }
        return face.baseColor.texture != nil
    }

    @Test func identicalPlatesShareTheirFaces() {
        let twins = (0..<6).map { index in
            EarnedPlate(id: "twin-\(index)", tierID: 14, weightKg: 20, engravingText: "", earnedByEvent: "fixture")
        }
        // One lettered face (no engraving, so the mirror's blank face is the same one).
        #expect(LatheFaceCache.distinctFaces(twins) == 1)
        #expect(LatheFaceCache.distinctFaces(twins + [Self.trayPlate()]) == 3)
    }

    @Test func theFaceCacheKeepsItsBoundAndNeverEvictsAFaceInUse() async throws {
        let limit = LatheFaceCache.limit
        defer { LatheFaceCache.limit = limit }
        let plates = (0..<5).map { _ in Self.trayPlate(tier: 22) }
        // One plate in use, built before its face exists.
        let tier = try #require(PlateTier.all.first { $0.id == 22 })
        let inUse = try #require(makeLathePlateVisual(tier: tier, weightKg: plates[0].weightKg, engravingText: plates[0].engravingText,
                                                      showEngravings: true, projection: BarbellPlateRenderProjection(plate: plates[0])))
        await LatheFaceCache.waitForPendingFaces()
        let inUseSpec = latheFaceSpec(tier: tier, weightKg: plates[0].weightKg, engravingText: plates[0].engravingText,
                                      projection: BarbellPlateRenderProjection(plate: plates[0]), showEngravings: true)
        #expect(LatheFaceCache.contains(inUseSpec))

        LatheFaceCache.limit = max(1, LatheFaceCache.count)
        for plate in plates.dropFirst() {
            await prepareLathePlates(latheFirstFrameRequests([plate]))
            #expect(LatheFaceCache.count <= LatheFaceCache.limit + 1)
        }
        #expect(LatheFaceCache.contains(inUseSpec))
        #expect(LatheFaceCache.isInUse(inUseSpec))
        _ = inUse
    }
}
