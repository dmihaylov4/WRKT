import Foundation
import Observation
import RealityKit
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// Throwing a plate stays smooth, counted rather than timed: no offscreen plate render (rail
/// picture or thumbnail) starts while the scene is in play or within a quiet second after; the
/// scene's play rule covers a touch, a held or awake plate, a rain and a tidy; and the shipped
/// physics policy.
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

    @Test func platesShipWithContinuousCollisionAndTheSixteenSidedDisc() {
        // The DEBUG switches are off in a test run; these are the Release values.
        #expect(RackPhysicsDebug.ccdEnabled)
        #expect(!RackPhysicsDebug.usesBoxCollider)
        #expect(RackPhysicsDebug.discSides == plateDiscColliderSides)
        let plate = makePlateEntity(tierID: 14, weightKg: 20, role: .floor)
        #expect(plate.components[PhysicsBodyComponent.self]?.isContinuousCollisionDetectionEnabled == true)
    }
}
