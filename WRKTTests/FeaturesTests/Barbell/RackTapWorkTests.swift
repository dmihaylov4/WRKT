import Foundation
import RealityKit
import Testing
import UIKit
@testable import WRKT

/// A tray tap's order and work, counted rather than timed: feedback comes first, the plate is on
/// its way before any face is drawn or anything is saved, a warm plate draws nothing, a load saves
/// only once it has seated (to the slot it swung to), a second tap during the swing does nothing,
/// and the in-memory face cache keeps to its bound without evicting faces in use.
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

    @Test func aLoadMovesBeforeAnyFaceIsDrawnAndSavesOnlyWhenSeated() async {
        let plate = Self.trayPlate()
        let scene = Self.latheScene()
        var events: [String] = []
        let drawn = RackWorkCounters.count(.faceImagesDrawn) + RackWorkCounters.count(.faceImagesReadFromDisk)
        let placeholders = RackWorkCounters.count(.facePlaceholdersShown)

        await withCheckedContinuation { (finished: CheckedContinuation<Void, Never>) in
            CutRackTap.perform(plate, racked: [], scene: scene,
                               feedback: { events.append($0 ? "feedback-load" : "feedback-unload") },
                               save: { _ in events.append("save"); return nil },
                               saveToSlot: { _, slot in events.append("save-slot-\(slot)"); return nil },
                               done: { _ in events.append("done"); finished.resume() })

            // Synchronously: feedback, then the plate is a bar plate with its mirror, swinging,
            // with its body finish on the face; nothing drawn, nothing saved.
            #expect(events == ["feedback-load"])
            #expect(scene.entityMap[plate.id]?.components[PlateRoleComponent.self]?.role == .bar)
            #expect(scene.barMirrorMap[plate.id] != nil)
            #expect(CutRackTap.pendingSlots[plate.id] == 0)
            #expect(RackWorkCounters.count(.faceImagesDrawn) + RackWorkCounters.count(.faceImagesReadFromDisk) == drawn)
            #expect(RackWorkCounters.count(.facePlaceholdersShown) - placeholders == 2)
            #expect(!Self.faceMaterialHasTexture(scene.entityMap[plate.id]))

            // A second tap during the swing does nothing at all.
            CutRackTap.perform(plate, racked: [], scene: scene,
                               feedback: { _ in events.append("feedback-again") },
                               save: { _ in events.append("save-again"); return nil },
                               saveToSlot: { _, _ in events.append("save-again"); return nil },
                               done: { _ in events.append("done-again") })
            #expect(events == ["feedback-load"])
        }
        #expect(events == ["feedback-load", "save-slot-0", "done"])
        #expect(CutRackTap.pendingSlots[plate.id] == nil)

        // The lettering arrives on both the plate and its mirror.
        await LatheFaceCache.waitForPendingFaces()
        #expect(Self.faceMaterialHasTexture(scene.entityMap[plate.id]))
        #expect(Self.faceMaterialHasTexture(scene.barMirrorMap[plate.id]))
    }

    @Test func aTapOnAWarmPlateDrawsNothing() async {
        let plate = Self.trayPlate(tier: 15)
        await prepareLathePlates(latheFirstFrameRequests([plate]) + latheLaterRequests([plate]))
        let scene = Self.latheScene()
        let work = RackWorkCounters.count(.faceImagesDrawn) + RackWorkCounters.count(.faceImagesReadFromDisk)
            + RackWorkCounters.count(.faceTexturesUploaded) + RackWorkCounters.count(.facePlaceholdersShown)
        let load = scene.beginLoadPlateOntoBar(plate, rackSlot: 1)
        #expect(load != nil)
        #expect(Self.faceMaterialHasTexture(scene.entityMap[plate.id]))
        #expect(RackWorkCounters.count(.faceImagesDrawn) + RackWorkCounters.count(.faceImagesReadFromDisk)
            + RackWorkCounters.count(.faceTexturesUploaded) + RackWorkCounters.count(.facePlaceholdersShown) == work)
    }

    @Test func slotsOfLoadsInFlightCountAsTaken() async {
        let scene = Self.latheScene()
        let first = Self.trayPlate(), second = Self.trayPlate()
        var slots: [Int] = []
        await withCheckedContinuation { (finished: CheckedContinuation<Void, Never>) in
            var remaining = 2
            for plate in [first, second] {
                CutRackTap.perform(plate, racked: [], scene: scene, feedback: { _ in },
                                   saveToSlot: { _, slot in slots.append(slot); return nil },
                                   done: { _ in remaining -= 1; if remaining == 0 { finished.resume() } })
            }
            #expect(CutRackTap.pendingSlots[first.id] == 0)
            #expect(CutRackTap.pendingSlots[second.id] == 1)
        }
        #expect(slots.sorted() == [0, 1])
    }

    @Test func aFullBarAnswersAtOnceWithoutMovingAnything() {
        let scene = Self.latheScene()
        let racked = (0..<4).map { index in
            EarnedPlate(id: "full-\(index)", tierID: 14, weightKg: 20, engravingText: "", earnedByEvent: "fixture",
                        isRacked: true, rackPosition: index)
        }
        let plate = Self.trayPlate()
        var notice: CutRackNotice?
        var fed = false
        CutRackTap.perform(plate, racked: racked, scene: scene, feedback: { _ in fed = true },
                           saveToSlot: { _, _ in Issue.record("saved"); return nil }, done: { notice = $0 })
        #expect(notice == .barFull)
        #expect(!fed)
        #expect(scene.entityMap[plate.id] == nil)
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
