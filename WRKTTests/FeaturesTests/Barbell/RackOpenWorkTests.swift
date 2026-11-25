import CoreGraphics
import Foundation
import RealityKit
import Testing
import UIKit
@testable import WRKT

/// The rack open's work budget, counted rather than timed: with 90 earned plates and 4 on the bar,
/// opening prepares the bar's faces only, a second open prepares nothing, and the light probe is
/// built at most once per process. Plus the caches that make it so: disk copies are bit-identical
/// to what was drawn, keys are stable, the directory stays bounded, and cached materials are
/// copy on write.
@MainActor
@Suite(.serialized)
struct RackOpenWorkTests {
    /// Plates whose faces no earlier test can have prepared: every engraving carries this run's tag.
    private static func inventory(count: Int = 90, onBar: Int = 4) -> [EarnedPlate] {
        let tag = UUID().uuidString.prefix(6)
        let tiers = PlateTier.all.map(\.id).filter { $0 != 7 }
        let weights: [Double] = [2.5, 5, 10, 15, 20, 25, 45]
        return (0..<count).map { index in
            EarnedPlate(id: "work-\(tag)-\(index)", tierID: tiers[index % tiers.count],
                        weightKg: weights[(index * 3) % weights.count], engravingText: "T\(tag)\(index)",
                        earnedByEvent: "fixture", isRacked: index < onBar, rackPosition: index < onBar ? index : nil,
                        currentTier: BarbellPlateProgressionTier.allCases[index % 6])
        }
    }

    private static func faceWork() -> Int {
        RackWorkCounters.count(.faceImagesDrawn) + RackWorkCounters.count(.faceImagesReadFromDisk)
    }

    @Test func lathePreloadPreparesTheBarFacesOnly() async {
        let plates = Self.inventory()
        let racked = plates.filter(\.isRacked)
        let state = SceneState()
        state.plateStyle = .lathe

        let faces = Self.faceWork(), uploads = RackWorkCounters.count(.faceTexturesUploaded)
        await CutRackPreloader.preload(racked: racked, into: state)
        #expect(Self.faceWork() - faces == racked.count)
        #expect(RackWorkCounters.count(.faceTexturesUploaded) - uploads == racked.count)
        // Lathe plates take no legacy materials.
        #expect(state.materialCache.isEmpty)

        // A second open of the same bar: nothing to draw, read or upload.
        let again = Self.faceWork(), uploadsAgain = RackWorkCounters.count(.faceTexturesUploaded)
        await CutRackPreloader.preload(racked: racked, into: SceneState())
        #expect(Self.faceWork() == again)
        #expect(RackWorkCounters.count(.faceTexturesUploaded) == uploadsAgain)
    }

    @Test func legacyPreloadLoadsTheBarTiersOnly() async {
        let plates = Self.inventory()
        let racked = plates.filter(\.isRacked)
        let state = SceneState()
        state.plateStyle = .legacy
        let faces = Self.faceWork()
        await CutRackPreloader.preload(racked: racked, into: state)
        #expect(Set(state.materialCache.keys) == Set(racked.map(\.tierID)).subtracting([7]))
        #expect(Self.faceWork() == faces)
    }

    @Test func barOnlySceneRequestsTheBarFacesNotTheTray() {
        let plates = Self.inventory()
        let mode = BarbellRealityMode.rackRoom(rackedPlates: plates.filter(\.isRacked),
                                               floorPlates: plates.filter { !$0.isRacked },
                                               onRack: { _ in }, onUnrack: { _ in })
        #expect(BarbellRealityView.latheFirstFrameRequests(mode: mode, barOnly: true).count == 4)
        #expect(BarbellRealityView.latheLaterRequests(mode: mode, barOnly: true).count == 4)
        #expect(BarbellRealityView.latheLaterRequests(mode: mode, barOnly: true).allSatisfy { $0.engravingText.isEmpty })
        // The wall-storage rack still builds its floor plates up front, as before.
        #expect(BarbellRealityView.latheFirstFrameRequests(mode: mode, barOnly: false).count == 90)
    }
}
