import Foundation
import Observation
import RealityKit
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// Throwing a plate stays smooth, counted rather than timed: no offscreen plate render (rail
/// picture or thumbnail) starts while the scene is in play or within a quiet second after; the
/// scene's play rule covers a touch, a held or awake plate, a rain and a tidy; a new rail picture
/// invalidates only the views that show it; the shipped physics policy; and the rail's flattened
/// art.
@MainActor
@Suite(.serialized)
struct RackThrowWorkTests {
    private final class FakePlay: RackPlayActivity {
        var isPlayActive = true
    }

    @Test func noRenderStartsWhileTheSceneIsInPlayOrJustAfter() async throws {
        let service = PlateSnapshotService.shared
        let play = FakePlay()
        service.playActivity = play
        defer { service.playActivity = nil }
        var started = 0
        let render = Task { @MainActor in
            _ = await service.renderQueued { started += 1; return nil }
        }
        try await Task.sleep(for: .milliseconds(700))
        #expect(started == 0)
        #expect(service.isHeld)

        // Play ends: nothing for the quiet period, then the render runs.
        play.isPlayActive = false
        try await Task.sleep(for: .milliseconds(Int(PlateSnapshotService.quietAfterPlay * 1000) / 2))
        #expect(started == 0)
        await render.value
        #expect(started == 1)
        #expect(!service.isHeld)
    }

    @Test func theSceneIsInPlayWhileTouchedHeldAwakeRainingOrTidying() {
        let state = SceneState()
        #expect(!state.isPlayActive)

        state.touchIsDown = true
        state.touchMovedAt = ProcessInfo.processInfo.systemUptime
        #expect(state.isPlayActive)
        // A touch whose gesture never ended stops counting 3 s after its last move.
        state.touchMovedAt = ProcessInfo.processInfo.systemUptime - 4
        #expect(!state.isPlayActive)
        state.touchIsDown = false

        state.floorSettles["plate"] = BarbellFloorSettleState(delay: 0.1)
        #expect(state.isPlayActive)
        state.floorSettles = [:]

        state.isRaining = true
        #expect(state.isPlayActive)
        state.isRaining = false

        state.tidyTask = Task {}
        #expect(state.isPlayActive)
        state.tidyTask = nil

        let plate = ModelEntity()
        #expect(state.transition(to: .draggingPlate(plate, plateID: "plate", originRole: .floor)))
        #expect(state.isPlayActive)
        #expect(state.transition(to: .idle))
        #expect(!state.isPlayActive)
    }

    @Test func aNewRailPictureInvalidatesOnlyItsOwnViews() {
        let service = RackRailSpriteService.shared
        let shown = LathePlateRequest(tierID: 14, weightKg: 20, engravingText: "Shown \(UUID().uuidString.prefix(4))",
                                      projection: BarbellPlateRenderProjection())
        let other = LathePlateRequest(tierID: 15, weightKg: 20, engravingText: "Other \(UUID().uuidString.prefix(4))",
                                      projection: BarbellPlateRenderProjection())
        var shownChanged = false
        var otherChanged = false
        withObservationTracking {
            _ = service.slot(for: RackRailSpriteService.standKey(shown)).version
        } onChange: { shownChanged = true }
        withObservationTracking {
            _ = service.slot(for: RackRailSpriteService.standKey(other)).version
        } onChange: { otherChanged = true }

        service.storeForTesting(UIImage(systemName: "circle.fill")!, request: other)
        #expect(otherChanged)
        #expect(!shownChanged)
    }

    @Test func platesShipWithContinuousCollisionAndTheSixteenSidedDisc() {
        // The DEBUG switches are off in a test run; these are the Release values.
        #expect(RackPhysicsDebug.ccdEnabled)
        #expect(!RackPhysicsDebug.usesBoxCollider)
        #expect(RackPhysicsDebug.discSides == plateDiscColliderSides)
        let plate = makePlateEntity(tierID: 14, weightKg: 20, role: .floor)
        #expect(plate.components[PhysicsBodyComponent.self]?.isContinuousCollisionDetectionEnabled == true)
    }

    @Test func theFlatArtDarkensTheFeetOnlyWhereThePlateIs() throws {
        // A 10 x 20 picture: opaque white on the left, clear on the right.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let picture = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 20), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 5, height: 20))
        }
        let shaded = try #require(RackRailFlatArt.shaded(picture))
        func pixel(_ x: Int, _ y: Int) -> (r: UInt8, a: UInt8) {
            let cg = shaded.cgImage!
            var bytes = [UInt8](repeating: 0, count: 4)
            let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(cg, in: CGRect(x: -x, y: -(cg.height - 1 - y), width: cg.width, height: cg.height))
            return (bytes[0], bytes[3])
        }
        // Top of the plate untouched, its feet darkened by about 32 %, the clear side still clear.
        #expect(pixel(2, 1).r == 255)
        #expect(pixel(2, 19).r < 190 && pixel(2, 19).r > 160)
        #expect(pixel(7, 19).a == 0)
        #expect(RackRailFlatArt.contactShadow(side: 100, scale: 2) != nil)
    }
}
