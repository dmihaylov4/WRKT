//
//  RackPlatePlay.swift
//  WRKT
//
//  Free play with loose plates in the rack room. A loose plate (one lying on the floor) is only
//  ever moved by touching it: it follows the finger with weight, leaves the hand with the
//  finger's velocity and collides with the room like any other body. It goes back on the bar
//  only when it is released while held at the end of a sleeve (the drop zone, shown by a ring on
//  that sleeve and a selection tick on entry) and the bar has a free slot, or when its tray
//  thumbnail is tapped. A tap on a loose plate gives it a small hop and never loads it.
//
//  RackPlatePlay holds the rules as plain values so they can be tested without a scene. The
//  SceneState extension applies them to the live entities; BarbellRealityView's gestures and
//  frame update call it. Nothing here saves anything: racking still goes through snapToBar and
//  its onRack save, as before.
//

import CoreGraphics
import RealityKit
import simd
import UIKit

/// What a touch in the rack room started on.
enum RackTouchKind: Equatable {
    /// A plate lying loose in the room: the touch drags that plate.
    case loosePlate
    /// A plate parked in the legacy wall storage (or levitating in its showcase).
    case storedPlate
    /// The bar, its hit zone or a loaded plate: the swipe that drops the outer plate.
    case bar
    /// Anything else (the room itself).
    case other
}

/// What lifting the finger does.
enum RackPlateRelease: Equatable {
    /// Nothing happens.
    case ignore
    /// A tap on a loose plate: a small hop.
    case nudge
    /// A tap on a stored plate: the existing levitate and spin.
    case showcase
    /// Released in a sleeve drop zone with a free slot: load it onto the bar.
    case rack
    /// Released over a free wall storage slot (legacy rack only).
    case store(slot: Int)
    /// A stored plate released anywhere else goes back to its slot (legacy rack only).
    case returnToStorage(slot: Int)
    /// Released anywhere else: it stays loose and keeps the throw.
    case loose
    /// A swipe on the bar: the outer plate slides off (today's behaviour).
    case swipeOff
}

struct RackPlateReleaseFacts: Equatable {
    var origin: RackTouchKind
    /// True when the touch moved past the tap tolerance and picked the plate up.
    var didDrag: Bool
    /// The sleeve side (-1 left, +1 right) the held plate was in at release, nil outside the zone.
    var sleeveSide: Float?
    var barHasFreeSlot: Bool
    /// The finger's speed at release, in points per second.
    var releaseSpeed: CGFloat
    var hoveredStorageSlot: Int?
    var originStorageSlot: Int?
}

enum RackPlatePlay {
    /// A touch that moves less than this (points, |dx| + |dy|) is a tap.
    static let tapTolerance: CGFloat = 8
    /// Screen points to scene metres while a plate is held (the room's existing drag scale).
    static let dragScale: Float = 0.004
    /// Bar slot centres on the right sleeve, innermost first (the mirror uses -x).
    static let slotOffsets: [Float] = [0.600, 0.652, 0.704, 0.756]

    // MARK: Drop zone
    /// The zone around each sleeve end, relative to the bar's centre: outside the stands and
    /// collars (|x| from 0.46 m; the stands are at 0.40, the collars at 0.54) and within 14 cm of
    /// the bar's height. Depth is loose (a plate is carried in front of the bar), but a plate far
    /// out toward the camera is not "at the sleeve".
    static let sleeveInnerX: Float = 0.46
    static let sleeveOuterX: Float = 1.00
    static let sleeveHalfHeight: Float = 0.14
    static let sleeveMaxDepth: Float = 0.80
    /// A release faster than this (points per second) is a throw, even inside the zone.
    static let maxRackReleaseSpeed: CGFloat = 700

    // MARK: Following the finger
    /// How hard a held plate is pulled toward the finger (per second): it closes about 63% of the
    /// gap every 1/16 s, so it trails a fast finger a little and feels heavy, never teleports.
    static let followStiffness: Float = 16
    static let maxFollowSpeed: Float = 6
    /// How quickly a held plate's spin dies away (per second), so it hangs from the finger
    /// instead of tumbling.
    static let heldSpinDamping: Float = 8
    static let gravity: Float = 9.81

    // MARK: Leaving the hand
    /// Finger points per second to metres per second at release.
    static let releaseVelocityScale: Float = 0.003
    /// Below this finger speed (points per second) the plate keeps its own (spring) velocity.
    static let minFlingSpeed: CGFloat = 30
    static let maxReleaseSpeed: Float = 4.5

    // MARK: Staying in frame
    /// The part of the floor that is fully on screen in the bar-only framing. The camera sits about
    /// 2.8 m in front of the bar, so the view narrows toward the camera: a plate at the front of
    /// the room (z 0.82) and out at the side rails (x 0.74) is half off the edge. A loose plate
    /// resting outside this box is slid back in. Measured on simulator captures of the Cut rack.
    static let frameMaxAbsX: Float = 0.58
    static let frameMaxZ: Float = 0.68
    static let frameReturnSpeed: Float = 0.4
    /// Plates higher than this are in flight: the walls keep them in, the slide waits for landing.
    static let frameReturnMaxY: Float = 0.45

    // MARK: Sleep
    /// A loose plate is checked for rest this long after the room last moved.
    static let settleDelay: TimeInterval = 0.5

    /// How far a plate is from lying flat, in degrees: 0 flat on either face, 90 on its edge.
    /// A plate's disc axis is its local y (the lathe and legacy meshes and the collider share it).
    static func tiltDegrees(_ orientation: simd_quatf) -> Float {
        let axis = orientation.act(SIMD3<Float>(0, 1, 0))
        let cosine = min(1, abs(axis.y) / max(simd_length(axis), 1e-6))
        return acos(cosine) * 180 / .pi
    }

    // MARK: Rules

    /// What a touch on this entity drags. Loaded plates and the bar keep the swipe.
    static func classifyTouch(role: PlateRoleComponent.Role?, isStored: Bool) -> RackTouchKind {
        switch role {
        case .some(.bar): return .bar
        case .some(.floor): return isStored ? .storedPlate : .loosePlate
        case .none: return .other
        }
    }

    /// The sleeve side (-1 or +1) whose drop zone holds a plate centred at `plate`, or nil.
    /// Both positions are in the scene root's space. Never a side when the bar is full.
    static func sleeveSide(plate: SIMD3<Float>, bar: SIMD3<Float>, barHasFreeSlot: Bool) -> Float? {
        guard barHasFreeSlot else { return nil }
        let offset = plate - bar
        let along = abs(offset.x)
        guard along >= sleeveInnerX, along <= sleeveOuterX,
              abs(offset.y) <= sleeveHalfHeight,
              abs(offset.z) <= sleeveMaxDepth else { return nil }
        return offset.x < 0 ? -1 : 1
    }

    static func releaseDecision(_ facts: RackPlateReleaseFacts) -> RackPlateRelease {
        switch facts.origin {
        case .bar:
            return facts.didDrag ? .swipeOff : .ignore
        case .other:
            return .ignore
        case .loosePlate, .storedPlate:
            break
        }
        guard facts.didDrag else { return facts.origin == .storedPlate ? .showcase : .nudge }
        if let slot = facts.hoveredStorageSlot { return .store(slot: slot) }
        if facts.sleeveSide != nil, facts.barHasFreeSlot, facts.releaseSpeed <= maxRackReleaseSpeed {
            return .rack
        }
        if let slot = facts.originStorageSlot { return .returnToStorage(slot: slot) }
        return .loose
    }

    /// The depth band a held plate is carried in: in front of the loaded plates (their front edge is
    /// at z 0.34) and no nearer the camera than the fully visible floor.
    static let carryMinZ: Float = 0.36

    /// Where the finger wants a held plate: its position at pick-up plus the drag, kept inside the
    /// room (clear of the side walls, above the floor, below the ceiling) and in the carry band.
    static func heldTarget(start: SIMD3<Float>, translation: CGSize, maxAbsX: Float) -> SIMD3<Float> {
        let raw = start + SIMD3(Float(translation.width) * dragScale, Float(-translation.height) * dragScale, 0)
        return SIMD3(max(-maxAbsX, min(maxAbsX, raw.x)), max(0.05, min(1.85, raw.y)),
                     max(carryMinZ, min(frameMaxZ, raw.z)))
    }

    /// The velocity that carries a held plate toward its target over the next step: a spring
    /// toward the finger, capped, with this step's gravity cancelled so it does not sag.
    static func followVelocity(position: SIMD3<Float>, target: SIMD3<Float>, deltaTime: TimeInterval) -> SIMD3<Float> {
        var velocity = (target - position) * followStiffness
        let speed = simd_length(velocity)
        if speed > maxFollowSpeed { velocity *= maxFollowSpeed / speed }
        velocity.y += gravity * Float(min(max(deltaTime, 0), 1.0 / 30))
        return velocity
    }

    /// The fraction of a held plate's spin kept after one step.
    static func heldSpinRetention(deltaTime: TimeInterval) -> Float {
        exp(-heldSpinDamping * Float(min(max(deltaTime, 0), 0.1)))
    }

    /// The velocity a plate leaves the hand with: the finger's, when it was moving, otherwise the
    /// plate's own. Capped so a wild flick cannot tunnel through a wall.
    static func releaseVelocity(fingerVelocity: CGSize, bodyVelocity: SIMD3<Float>) -> SIMD3<Float> {
        var velocity = bodyVelocity
        if hypot(fingerVelocity.width, fingerVelocity.height) >= minFlingSpeed {
            velocity = SIMD3(Float(fingerVelocity.width) * releaseVelocityScale,
                             Float(-fingerVelocity.height) * releaseVelocityScale,
                             bodyVelocity.z)
        }
        let speed = simd_length(velocity)
        if speed > maxReleaseSpeed { velocity *= maxReleaseSpeed / speed }
        return velocity
    }

    /// A tumble that matches a throw: about the axis across the throw, 4 rad/s per m/s.
    static func releaseSpin(for velocity: SIMD3<Float>) -> SIMD3<Float> {
        let planar = SIMD2(velocity.x, velocity.y)
        let speed = simd_length(planar)
        guard speed > 0.05 else { return .zero }
        return SIMD3(velocity.y, -velocity.x, 0) / speed * speed * 4
    }

    /// A tap's hop: a little up and toward the middle of the room, with a small spin.
    static func nudge(plateX: Float) -> (linear: SIMD3<Float>, angular: SIMD3<Float>) {
        let inward: Float = plateX > 0 ? -1 : 1
        return (SIMD3(inward * 0.25, 1.1, 0), SIMD3(0, inward * 2.0, inward * 1.5))
    }

    /// The velocity that slides a loose plate on the floor back into the fully visible part of
    /// the room, or nil when it is already there (or still in the air).
    static func frameReturnVelocity(position: SIMD3<Float>, velocity: SIMD3<Float>) -> SIMD3<Float>? {
        guard position.y < frameReturnMaxY else { return nil }
        var result = velocity
        var changed = false
        if position.x > frameMaxAbsX, result.x > -frameReturnSpeed { result.x = -frameReturnSpeed; changed = true }
        if position.x < -frameMaxAbsX, result.x < frameReturnSpeed { result.x = frameReturnSpeed; changed = true }
        if position.z > frameMaxZ, result.z > -frameReturnSpeed { result.z = -frameReturnSpeed; changed = true }
        return changed ? result : nil
    }

    /// The push that tips a plate out of a pose it should not rest in (on its edge, leaning, or
    /// propped up on the bar or a stand): a roll about the horizontal axis that turns its face
    /// toward the nearer of up or down, a small hop to unwedge it, and a slide away from the bar
    /// (z 0.12) and in from the sides so it comes down on open floor.
    static func tipOver(orientation: simd_quatf, position: SIMD3<Float>) -> (linear: SIMD3<Float>, angular: SIMD3<Float>) {
        let normal = orientation.act(SIMD3<Float>(0, 1, 0))
        let target = SIMD3<Float>(0, normal.y >= 0 ? 1 : -1, 0)
        var axis = simd_cross(normal, target)
        if simd_length(axis) < 1e-3 { axis = SIMD3(1, 0, 0) }
        let angular = simd_normalize(axis) * 3.2
        var linear = SIMD3<Float>(0, 0.35, 0)
        if position.z < 0.45 { linear.z = 0.45 }
        if abs(position.x) > 0.45 { linear.x = position.x > 0 ? -0.25 : 0.25 }
        return (linear, angular)
    }

    /// The plates to put to sleep this frame. Loose plates sleep together, once every one of them
    /// is at rest and none is held, so a plate never freezes while another can still hit it.
    static func platesToSleep(readiness: [String: Bool], isHoldingPlate: Bool) -> [String] {
        guard !isHoldingPlate, !readiness.isEmpty, readiness.values.allSatisfy({ $0 }) else { return [] }
        return readiness.keys.sorted()
    }
}

/// The plate under the finger.
struct RackHeldPlate {
    let entity: Entity
    let plateID: String
    /// Scene root position at pick-up.
    let start: SIMD3<Float>
    var target: SIMD3<Float>
    /// The bar slot a release in the drop zone would load, nil when the bar is full.
    let barSlot: Int?
    /// The sleeve side whose zone the plate is in now, nil outside.
    var sleeveSide: Float?
}

// MARK: - Applying the rules

extension SceneState: RackPlayActivity {
    /// A touch down in the scene, a plate held, dragged or awake, a rain or a tidy: offscreen
    /// renders wait (PlateSnapshotService.playActivity).
    var isPlayActive: Bool {
        let touching = touchIsDown && ProcessInfo.processInfo.systemUptime - touchMovedAt < 3
        if touching || heldPlate != nil || isRaining || tidyTask != nil || !floorSettles.isEmpty { return true }
        if case .idle = dragPhase { return false }
        return true
    }

    /// Picks a plate up: it stays a dynamic body (so it collides with the room) and is steered by
    /// velocity toward the finger every frame. Other loose plates wake so it can push them.
    func beginHold(entity: Entity, plateID: String, barSlot: Int?) {
        floorSettles[plateID] = nil
        entity.stopAllAnimations(recursive: false)
        entity.setParent(sceneRoot, preservingWorldTransform: true)
        entity.components[PhysicsMotionComponent.self] = PhysicsMotionComponent()
        entity.components[PhysicsBodyComponent.self]?.mode = .dynamic
        heldPlate = RackHeldPlate(entity: entity, plateID: plateID, start: entity.position,
                                  target: entity.position, barSlot: barSlot, sleeveSide: nil)
        showSleeveCue(side: nil, slot: nil)
        wakeLoosePlates(except: plateID)
    }

    func updateHold(translation: CGSize, maxAbsX: Float) {
        guard let held = heldPlate else { return }
        heldPlate?.target = RackPlatePlay.heldTarget(start: held.start, translation: translation, maxAbsX: maxAbsX)
    }

    /// One frame of a hold: steer the plate, then show or hide the sleeve cue for where it is.
    func stepHeldPlate(deltaTime: TimeInterval) {
        guard let held = heldPlate else { return }
        let entity = held.entity
        guard entity.parent != nil else { heldPlate = nil; return }
        let position = entity.position(relativeTo: sceneRoot)
        var motion = entity.components[PhysicsMotionComponent.self] ?? PhysicsMotionComponent()
        motion.linearVelocity = RackPlatePlay.followVelocity(position: position, target: held.target, deltaTime: deltaTime)
        motion.angularVelocity *= RackPlatePlay.heldSpinRetention(deltaTime: deltaTime)
        entity.components[PhysicsMotionComponent.self] = motion

        let side = RackPlatePlay.sleeveSide(plate: position, bar: barAnchor.position,
                                            barHasFreeSlot: held.barSlot != nil)
        guard side != held.sleeveSide else { return }
        heldPlate?.sleeveSide = side
        showSleeveCue(side: side, slot: held.barSlot)
        if side != nil { playSnapZoneEntryHaptic() }
    }

    /// Ends the hold and hides the cue. Returns the plate as it was at release.
    @discardableResult
    func endHold() -> RackHeldPlate? {
        let held = heldPlate
        heldPlate = nil
        showSleeveCue(side: nil, slot: nil)
        return held
    }

    /// Stops a released plate's physics before a scripted move (onto the bar or into storage).
    func freezeForSnap(_ entity: Entity) {
        entity.components[PhysicsMotionComponent.self] = PhysicsMotionComponent()
        entity.components[PhysicsBodyComponent.self]?.mode = .kinematic
    }

    /// The ring on the sleeve where a release would load the plate (the next free slot, on the
    /// side the plate is held), or nothing.
    func showSleeveCue(side: Float?, slot: Int?) {
        for ring in slotHighlights { ring.isEnabled = false }
        wasInSnapZone = side != nil
        guard let side, let slot, slotHighlights.indices.contains(slot),
              RackPlatePlay.slotOffsets.indices.contains(slot) else { return }
        let ring = slotHighlights[slot]
        ring.position = SIMD3(side * RackPlatePlay.slotOffsets[slot], 0, 0)
        ring.isEnabled = true
    }

    /// Lets a plate go where it is, loose, with the throw. Clamped into the room first.
    func releaseLoose(entity: Entity, plateID: String, fingerVelocity: CGSize, maxAbsX: Float) {
        let bodyVelocity = entity.components[PhysicsMotionComponent.self]?.linearVelocity ?? .zero
        entity.setParent(floorAnchor, preservingWorldTransform: true)
        entity.components.set(PlateRoleComponent(role: .floor))
        let scenePos = entity.position(relativeTo: sceneRoot)
        let clamped = SIMD3<Float>(max(-maxAbsX, min(maxAbsX, scenePos.x)), max(0.10, min(1.5, scenePos.y)), scenePos.z)
        if clamped != scenePos { entity.setPosition(clamped, relativeTo: sceneRoot) }

        var motion = PhysicsMotionComponent()
        motion.linearVelocity = RackPlatePlay.releaseVelocity(fingerVelocity: fingerVelocity, bodyVelocity: bodyVelocity)
        motion.angularVelocity = RackPlatePlay.releaseSpin(for: motion.linearVelocity)
        entity.components[PhysicsMotionComponent.self] = motion
        entity.components[PhysicsBodyComponent.self]?.mode = .dynamic

        if let audio = entity.components[PlateAudioCategoryComponent.self] {
            let releaseY = max(entity.position(relativeTo: sceneRoot).y, 0.10)
            let fall = sqrt(releaseY * 2 / RackPlatePlay.gravity)
            scheduleDropFeedback(on: entity, category: audio.category, delay: TimeInterval(min(max(fall, 0.18), 0.65)))
        }
        loosePlateIDs.insert(plateID)
        wakeLoosePlates()
    }

    /// A tap's hop for a loose plate (and a wake for its neighbours).
    func nudgeLoosePlate(_ entity: Entity) {
        guard entity.components[PhysicsBodyComponent.self] != nil else { return }
        let hop = RackPlatePlay.nudge(plateX: entity.position(relativeTo: sceneRoot).x)
        entity.components[PhysicsBodyComponent.self]?.mode = .dynamic
        var motion = entity.components[PhysicsMotionComponent.self] ?? PhysicsMotionComponent()
        motion.linearVelocity += hop.linear
        motion.angularVelocity += hop.angular
        entity.components[PhysicsMotionComponent.self] = motion
        loosePlateIDs.insert(entity.name)
        wakeLoosePlates()
    }

    /// Makes every sleeping loose plate a dynamic body again and restarts every loose plate's rest
    /// check, so the room only goes back to sleep once it is still.
    func wakeLoosePlates(except held: String? = nil) {
        for id in loosePlateIDs where id != held {
            guard let entity = entityMap[id],
                  entity.components[PlateRoleComponent.self]?.role == .floor,
                  entity !== showcaseEntity,
                  storageSlotByPlate[id] == nil,
                  !platesBeingUnracked.contains(id),
                  entity.components[PhysicsBodyComponent.self] != nil else {
                loosePlateIDs.remove(id)
                continue
            }
            entity.components[PhysicsBodyComponent.self]?.mode = .dynamic
            floorSettles[id] = BarbellFloorSettleState(delay: RackPlatePlay.settleDelay)
        }
    }

    /// The per-frame rest check: loose plates go kinematic (asleep) together once all are resting in
    /// a stable pose. A plate balanced on its edge or propped up high is tipped over first.
    func advanceFloorSettles(deltaTime: TimeInterval) {
        var readiness: [String: Bool] = [:]
        for id in Array(floorSettles.keys) {
            guard let entity = entityMap[id],
                  entity.components[PlateRoleComponent.self]?.role == .floor,
                  entity.components[PhysicsBodyComponent.self]?.mode == .dynamic,
                  entity !== heldPlate?.entity else {
                floorSettles[id] = nil
                continue
            }
            var motion = entity.components[PhysicsMotionComponent.self] ?? PhysicsMotionComponent()
            let orientation = entity.orientation(relativeTo: sceneRoot)
            let position = entity.position(relativeTo: sceneRoot)
            let verdict = floorSettles[id]?.advance(deltaTime: deltaTime,
                                                    linearSpeed: simd_length(motion.linearVelocity),
                                                    angularSpeed: simd_length(motion.angularVelocity),
                                                    tiltDegrees: RackPlatePlay.tiltDegrees(orientation),
                                                    height: position.y) ?? .resting
            if verdict == .nudge {
                let push = RackPlatePlay.tipOver(orientation: orientation, position: position)
                motion.linearVelocity += push.linear
                motion.angularVelocity += push.angular
                entity.components[PhysicsMotionComponent.self] = motion
            }
            readiness[id] = verdict == .resting
        }
        for id in RackPlatePlay.platesToSleep(readiness: readiness, isHoldingPlate: heldPlate != nil) {
            guard let entity = entityMap[id] else { continue }
            entity.components[PhysicsMotionComponent.self] = PhysicsMotionComponent()
            entity.components[PhysicsBodyComponent.self]?.mode = .kinematic
            originalTransforms[id] = Transform(matrix: entity.transformMatrix(relativeTo: nil))
            floorSettles[id] = nil
        }
    }

    func scheduleDropFeedback(on entity: Entity, category: PlateAudioCategory, delay: TimeInterval) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
            guard entity.components[PlateRoleComponent.self]?.role == .floor else { return }
            playDropSound(on: entity, category: category)
            playDropHaptic(category: category)
        }
    }
}
