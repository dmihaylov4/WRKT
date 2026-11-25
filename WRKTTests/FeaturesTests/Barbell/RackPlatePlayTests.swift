import CoreGraphics
import RealityKit
import Testing
@testable import WRKT

/// The rack room's free-play rules: a loose plate goes back on the bar only when it is released
/// while held at a sleeve end with a free slot (or from the tray); everything else leaves it loose.
struct RackPlatePlayTests {
    private let bar = SIMD3<Float>(0, 0.6, 0.12)

    private func facts(origin: RackTouchKind = .loosePlate, didDrag: Bool = true, sleeveSide: Float? = nil,
                       barHasFreeSlot: Bool = true, releaseSpeed: CGFloat = 0,
                       hovered: Int? = nil, originSlot: Int? = nil) -> RackPlateReleaseFacts {
        RackPlateReleaseFacts(origin: origin, didDrag: didDrag, sleeveSide: sleeveSide, barHasFreeSlot: barHasFreeSlot,
                              releaseSpeed: releaseSpeed, hoveredStorageSlot: hovered, originStorageSlot: originSlot)
    }

    // MARK: Touch classification

    @Test func touchesOnLoosePlatesDragThePlateAndTouchesOnTheBarKeepTheSwipe() {
        #expect(RackPlatePlay.classifyTouch(role: .floor, isStored: false) == .loosePlate)
        #expect(RackPlatePlay.classifyTouch(role: .floor, isStored: true) == .storedPlate)
        #expect(RackPlatePlay.classifyTouch(role: .bar, isStored: false) == .bar)
        #expect(RackPlatePlay.classifyTouch(role: nil, isStored: false) == .other)
    }

    // MARK: Drop zone

    @Test func sleeveEndsAreDropZonesOnBothSides() {
        #expect(RackPlatePlay.sleeveSide(plate: SIMD3(0.62, 0.62, 0.45), bar: bar, barHasFreeSlot: true) == 1)
        #expect(RackPlatePlay.sleeveSide(plate: SIMD3(-0.60, 0.55, 0.30), bar: bar, barHasFreeSlot: true) == -1)
    }

    @Test func theMiddleOfTheBarTheFloorAndAboveTheBarAreNotDropZones() {
        // Between the stands, at bar height.
        #expect(RackPlatePlay.sleeveSide(plate: SIMD3(0.20, 0.60, 0.40), bar: bar, barHasFreeSlot: true) == nil)
        // Under the sleeve, on or near the floor.
        #expect(RackPlatePlay.sleeveSide(plate: SIMD3(0.62, 0.22, 0.45), bar: bar, barHasFreeSlot: true) == nil)
        #expect(RackPlatePlay.sleeveSide(plate: SIMD3(0.62, 0.45, 0.45), bar: bar, barHasFreeSlot: true) == nil)
        // Well above it: the old rule racked anything up to 50 cm above the bar.
        #expect(RackPlatePlay.sleeveSide(plate: SIMD3(0.62, 0.80, 0.45), bar: bar, barHasFreeSlot: true) == nil)
        // Far out toward the camera.
        #expect(RackPlatePlay.sleeveSide(plate: SIMD3(0.62, 0.60, 1.00), bar: bar, barHasFreeSlot: true) == nil)
    }

    @Test func aFullBarHasNoDropZone() {
        #expect(RackPlatePlay.sleeveSide(plate: SIMD3(0.62, 0.60, 0.40), bar: bar, barHasFreeSlot: false) == nil)
        #expect(RackPlatePlay.sleeveSide(plate: SIMD3(-0.62, 0.60, 0.40), bar: bar, barHasFreeSlot: false) == nil)
    }

    // MARK: Release

    @Test func releaseFarFromTheSleeveStaysLoose() {
        #expect(RackPlatePlay.releaseDecision(facts()) == .loose)
        // At bar height but not at a sleeve end: the old rule's snap band.
        let midBar = RackPlatePlay.sleeveSide(plate: SIMD3(0.10, 0.62, 0.40), bar: bar, barHasFreeSlot: true)
        #expect(RackPlatePlay.releaseDecision(facts(sleeveSide: midBar)) == .loose)
    }

    @Test func releaseInTheZoneRacks() {
        let side = RackPlatePlay.sleeveSide(plate: SIMD3(0.62, 0.60, 0.40), bar: bar, barHasFreeSlot: true)
        #expect(RackPlatePlay.releaseDecision(facts(sleeveSide: side, releaseSpeed: 120)) == .rack)
        #expect(RackPlatePlay.releaseDecision(facts(sleeveSide: -1)) == .rack)
    }

    @Test func aFullBarNeverRacks() {
        #expect(RackPlatePlay.releaseDecision(facts(sleeveSide: 1, barHasFreeSlot: false)) == .loose)
        #expect(RackPlatePlay.releaseDecision(facts(sleeveSide: nil, barHasFreeSlot: false)) == .loose)
    }

    @Test func aThrowThroughTheZoneStaysLoose() {
        #expect(RackPlatePlay.releaseDecision(facts(sleeveSide: 1, releaseSpeed: 1500)) == .loose)
        #expect(RackPlatePlay.releaseDecision(facts(sleeveSide: 1, releaseSpeed: RackPlatePlay.maxRackReleaseSpeed)) == .rack)
    }

    @Test func aTapNeverRacks() {
        #expect(RackPlatePlay.releaseDecision(facts(didDrag: false)) == .nudge)
        #expect(RackPlatePlay.releaseDecision(facts(didDrag: false, sleeveSide: 1)) == .nudge)
        #expect(RackPlatePlay.releaseDecision(facts(origin: .storedPlate, didDrag: false)) == .showcase)
        #expect(RackPlatePlay.releaseDecision(facts(origin: .bar, didDrag: false)) == .ignore)
        #expect(RackPlatePlay.releaseDecision(facts(origin: .other, didDrag: false)) == .ignore)
    }

    @Test func aSwipeOnTheBarStillDropsTheOuterPlate() {
        #expect(RackPlatePlay.releaseDecision(facts(origin: .bar)) == .swipeOff)
        // Whatever the release looks like, a bar swipe is never a rack or a loose drop.
        #expect(RackPlatePlay.releaseDecision(facts(origin: .bar, sleeveSide: 1, releaseSpeed: 2000)) == .swipeOff)
    }

    @Test func legacyStorageRulesAreKept() {
        #expect(RackPlatePlay.releaseDecision(facts(origin: .storedPlate, hovered: 3, originSlot: 1)) == .store(slot: 3))
        #expect(RackPlatePlay.releaseDecision(facts(origin: .storedPlate, sleeveSide: 1, originSlot: 1)) == .rack)
        #expect(RackPlatePlay.releaseDecision(facts(origin: .storedPlate, originSlot: 1)) == .returnToStorage(slot: 1))
    }

    // MARK: Following and throwing

    @Test func aHeldPlateIsPulledTowardTheFingerWithoutTeleporting() {
        let position = SIMD3<Float>(0, 0.2, 0.5)
        let target = SIMD3<Float>(0.1, 0.2, 0.5)
        let velocity = RackPlatePlay.followVelocity(position: position, target: target, deltaTime: 1.0 / 60)
        #expect(velocity.x > 0)
        // One frame closes only part of the gap.
        #expect(velocity.x / 60 < 0.1)
        // Gravity for the frame is cancelled.
        #expect(abs(velocity.y - RackPlatePlay.gravity / 60) < 0.0001)
        let far = RackPlatePlay.followVelocity(position: .zero, target: SIMD3(5, 0, 0), deltaTime: 0)
        #expect(abs(simd_length(far) - RackPlatePlay.maxFollowSpeed) < 0.0001)
    }

    @Test func theHeldTargetStaysInsideTheRoom() {
        let start = SIMD3<Float>(0.3, 0.2, 0.5)
        let wild = RackPlatePlay.heldTarget(start: start, translation: CGSize(width: 900, height: 900), maxAbsX: 0.64)
        #expect(wild.x == 0.64)
        #expect(wild.y == 0.05)
        #expect(wild.z == 0.5)
        let up = RackPlatePlay.heldTarget(start: start, translation: CGSize(width: 0, height: -100), maxAbsX: 0.64)
        #expect(abs(up.y - 0.6) < 0.0001)
        // A plate picked up near the camera is carried back into full view; one tight against the
        // loaded plates is carried clear of them.
        let near = RackPlatePlay.heldTarget(start: SIMD3(0, 0.2, 0.82), translation: .zero, maxAbsX: 0.64)
        #expect(near.z == RackPlatePlay.frameMaxZ)
        let back = RackPlatePlay.heldTarget(start: SIMD3(0, 0.2, 0.1), translation: .zero, maxAbsX: 0.64)
        #expect(back.z == RackPlatePlay.carryMinZ)
    }

    @Test func aReleaseKeepsTheFlickAndCapsIt() {
        let flick = RackPlatePlay.releaseVelocity(fingerVelocity: CGSize(width: 400, height: -200), bodyVelocity: SIMD3(0, 0, 0.1))
        #expect(abs(flick.x - 1.2) < 0.0001)
        #expect(abs(flick.y - 0.6) < 0.0001)
        #expect(flick.z == 0.1)
        let gentle = RackPlatePlay.releaseVelocity(fingerVelocity: CGSize(width: 5, height: 5), bodyVelocity: SIMD3(0.2, 0, 0))
        #expect(gentle == SIMD3(0.2, 0, 0))
        let wild = RackPlatePlay.releaseVelocity(fingerVelocity: CGSize(width: 9000, height: 0), bodyVelocity: .zero)
        #expect(abs(simd_length(wild) - RackPlatePlay.maxReleaseSpeed) < 0.0001)
        #expect(RackPlatePlay.releaseSpin(for: .zero) == .zero)
        #expect(simd_length(RackPlatePlay.releaseSpin(for: SIMD3(1, 0, 0))) > 0)
    }

    @Test func aNudgeHopsTowardTheMiddle() {
        let right = RackPlatePlay.nudge(plateX: 0.5)
        #expect(right.linear.x < 0)
        #expect(right.linear.y > 0)
        #expect(RackPlatePlay.nudge(plateX: -0.5).linear.x > 0)
    }

    // MARK: Staying in frame

    @Test func aPlateRestingWhereTheFrameCutsItOffSlidesBackIn() {
        let corner = RackPlatePlay.frameReturnVelocity(position: SIMD3(0.74, 0.3, 0.82), velocity: .zero)
        #expect(corner == SIMD3(-RackPlatePlay.frameReturnSpeed, 0, -RackPlatePlay.frameReturnSpeed))
        let left = RackPlatePlay.frameReturnVelocity(position: SIMD3(-0.70, 0.1, 0.3), velocity: .zero)
        #expect(left?.x == RackPlatePlay.frameReturnSpeed)
        // Already on its way back fast enough: left alone.
        #expect(RackPlatePlay.frameReturnVelocity(position: SIMD3(0.70, 0.1, 0.3), velocity: SIMD3(-1, 0, 0)) == nil)
        // In view, or still flying: left alone.
        #expect(RackPlatePlay.frameReturnVelocity(position: SIMD3(0.3, 0.1, 0.5), velocity: .zero) == nil)
        #expect(RackPlatePlay.frameReturnVelocity(position: SIMD3(0.74, 1.0, 0.82), velocity: .zero) == nil)
    }

    // MARK: Sleep

    @Test func loosePlatesSleepTogetherOnlyWhenTheRoomIsStill() {
        #expect(RackPlatePlay.platesToSleep(readiness: ["a": true, "b": true], isHoldingPlate: false) == ["a", "b"])
        #expect(RackPlatePlay.platesToSleep(readiness: ["a": true, "b": false], isHoldingPlate: false).isEmpty)
        #expect(RackPlatePlay.platesToSleep(readiness: ["a": true], isHoldingPlate: true).isEmpty)
        #expect(RackPlatePlay.platesToSleep(readiness: [:], isHoldingPlate: false).isEmpty)
    }

    // MARK: Scene state

    @Test @MainActor func theSleeveCueShowsTheNextSlotOnTheHeldSide() {
        let state = SceneState()
        state.slotHighlights = (0..<4).map { _ in Entity() }
        state.showSleeveCue(side: -1, slot: 2)
        #expect(state.slotHighlights[2].isEnabled)
        #expect(abs(state.slotHighlights[2].position.x + 0.704) < 0.0001)
        #expect(state.slotHighlights.enumerated().allSatisfy { $0.offset == 2 || !$0.element.isEnabled })
        #expect(state.wasInSnapZone)
        state.showSleeveCue(side: nil, slot: 2)
        #expect(state.slotHighlights.allSatisfy { !$0.isEnabled })
        #expect(!state.wasInSnapZone)
    }

    @Test @MainActor func aHeldPlateOutsideTheZoneShowsNoCueAndEndsLoose() {
        let state = SceneState()
        state.slotHighlights = (0..<4).map { _ in Entity() }
        state.barAnchor.position = bar
        state.sceneRoot.addChild(state.barAnchor)
        let plate = ModelEntity()
        plate.name = "p"
        plate.components.set(PhysicsBodyComponent(massProperties: .default, material: nil, mode: .kinematic))
        plate.components.set(PhysicsMotionComponent())
        plate.position = SIMD3(0.2, 0.05, 0.5)
        state.sceneRoot.addChild(plate)
        state.entityMap["p"] = plate

        state.beginHold(entity: plate, plateID: "p", barSlot: 1)
        #expect(plate.components[PhysicsBodyComponent.self]?.mode == .dynamic)
        state.updateHold(translation: CGSize(width: 0, height: -100), maxAbsX: 0.64)
        state.stepHeldPlate(deltaTime: 1.0 / 60)
        #expect(state.heldPlate?.sleeveSide == nil)
        #expect(state.slotHighlights.allSatisfy { !$0.isEnabled })
        #expect((plate.components[PhysicsMotionComponent.self]?.linearVelocity.y ?? 0) > 0)

        // Carried to the right sleeve end at bar height: the cue shows slot 1 on that side.
        plate.position = SIMD3(0.62, 0.60, 0.45)
        state.stepHeldPlate(deltaTime: 1.0 / 60)
        #expect(state.heldPlate?.sleeveSide == 1)
        #expect(state.slotHighlights[1].isEnabled)

        let held = state.endHold()
        #expect(held?.sleeveSide == 1)
        #expect(state.heldPlate == nil)
        #expect(state.slotHighlights.allSatisfy { !$0.isEnabled })
    }

    @Test @MainActor func releasingLooseKeepsAFloorPlateThatWakesAndSleepsWithTheRoom() {
        let state = SceneState()
        state.sceneRoot.addChild(state.floorAnchor)
        func makePlate(_ id: String, x: Float) -> ModelEntity {
            let plate = ModelEntity()
            plate.name = id
            plate.components.set(PhysicsBodyComponent(massProperties: .default, material: nil, mode: .kinematic))
            plate.components.set(PhysicsMotionComponent())
            plate.components.set(PlateRoleComponent(role: .floor))
            plate.position = SIMD3(x, 0.05, 0.5)
            state.sceneRoot.addChild(plate)
            state.entityMap[id] = plate
            return plate
        }
        let thrown = makePlate("thrown", x: 0)
        let sleeper = makePlate("sleeper", x: 0.4)
        state.loosePlateIDs = ["sleeper"]

        state.beginHold(entity: thrown, plateID: "thrown", barSlot: nil)
        // Picking a plate up wakes the plate lying asleep next to it.
        #expect(sleeper.components[PhysicsBodyComponent.self]?.mode == .dynamic)
        state.endHold()
        state.releaseLoose(entity: thrown, plateID: "thrown", fingerVelocity: CGSize(width: 300, height: 0), maxAbsX: 0.64)
        #expect(thrown.components[PlateRoleComponent.self]?.role == .floor)
        #expect(thrown.components[PhysicsBodyComponent.self]?.mode == .dynamic)
        #expect((thrown.components[PhysicsMotionComponent.self]?.linearVelocity.x ?? 0) > 0.8)
        #expect(state.loosePlateIDs == ["thrown", "sleeper"])

        // Both at rest after the delay: they go to sleep together.
        thrown.components[PhysicsMotionComponent.self] = PhysicsMotionComponent()
        state.advanceFloorSettles(deltaTime: RackPlatePlay.settleDelay + 0.01)
        #expect(thrown.components[PhysicsBodyComponent.self]?.mode == .kinematic)
        #expect(sleeper.components[PhysicsBodyComponent.self]?.mode == .kinematic)
        #expect(state.floorSettles.isEmpty)
    }

    @Test @MainActor func aMovingPlateKeepsTheOthersAwake() {
        let state = SceneState()
        for (id, speed) in [("still", Float(0)), ("rolling", Float(1))] {
            let plate = ModelEntity()
            plate.name = id
            plate.components.set(PhysicsBodyComponent(massProperties: .default, material: nil, mode: .dynamic))
            var motion = PhysicsMotionComponent()
            motion.linearVelocity = SIMD3(speed, 0, 0)
            plate.components.set(motion)
            plate.components.set(PlateRoleComponent(role: .floor))
            state.sceneRoot.addChild(plate)
            state.entityMap[id] = plate
            state.floorSettles[id] = BarbellFloorSettleState(delay: 0.1)
        }
        state.advanceFloorSettles(deltaTime: 0.2)
        #expect(state.entityMap["still"]?.components[PhysicsBodyComponent.self]?.mode == .dynamic)
        #expect(state.floorSettles.count == 2)
    }
}
