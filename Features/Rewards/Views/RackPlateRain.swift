//
//  RackPlateRain.swift
//  WRKT
//
//  "Drop all" in the Cut rack: stored plates fall into the room from above in a staggered
//  stream, tumble, pile up and then lie loose like any plate swiped off the bar (RackPlatePlay):
//  they can be pushed, thrown and loaded by releasing one at a sleeve end. A play state only:
//  nothing here saves anything, and tidyRainedPlates takes them out of the room again.
//
//  Cost is kept flat. Identical plates share everything the scene already shares (one lathe mesh
//  per profile, one body and hub material per tier, one face material per face spec; one legacy
//  material per tier), so the work per plate is one entity and its components. Faces for every
//  distinct look are prepared before the first plate falls, off the main thread. Plates then
//  spawn one at a time on a fixed interval, so no single frame builds more than one plate. The
//  room puts loose plates to sleep together once they are all at rest (advanceFloorSettles),
//  which bounds the time the pile stays dynamic. How many plates and distinct faces fall at most
//  is Limits, measured on the simulator (see the numbers there). Landing sounds and haptics go
//  through FeedbackLimiter so a pile landing reads as a few thuds, not ninety.
//
//  Kept apart from the scene's load path on purpose: the only entry points are rainPlates and
//  tidyRainedPlates, and the only scene state they touch is what any loose plate uses
//  (entityMap, loosePlateIDs, floorSettles, originalTransforms, preparedMirrors).
//

import Foundation
import RealityKit
import simd
import UIKit

/// Marks a plate that came into the room with the rain, so tidying up removes only those.
struct RackRainedPlateComponent: Component {}

/// How Tidy up takes the rained plates away. Debug builds can force one with the launch argument
/// `-VOLIA_RACK_TIDY tray|wheel|sink` (or the environment variable of that name).
nonisolated enum RackTidyStyle: String, CaseIterable, Equatable, Sendable {
    /// Each plate lifts a little and flies down toward the tray under the scene, shrinking as it
    /// goes, nearest first, about 30 to 40 ms apart; one soft rack sound when the last one is in.
    case tray
    /// Each plate slides off the nearer side of the room and out of frame with a quarter turn,
    /// outermost first, as if wheeled away.
    case wheel
    /// Each plate sinks a few centimetres, shrinks slightly and fades where it lies, nearest first.
    case sink

    static let overrideKey = "VOLIA_RACK_TIDY"
    static let standard: RackTidyStyle = .tray

    static func resolve(isDebugBuild: Bool, argument: String?, environment: [String: String]) -> RackTidyStyle {
        guard isDebugBuild else { return standard }
        if let raw = argument ?? environment[overrideKey], let forced = RackTidyStyle(rawValue: raw) { return forced }
        return standard
    }

    static var current: RackTidyStyle {
        #if DEBUG
        return resolve(isDebugBuild: true, argument: UserDefaults.standard.string(forKey: overrideKey),
                       environment: ProcessInfo.processInfo.environment)
        #else
        return standard
        #endif
    }
}

enum RackPlateRain {
    /// The most plates the rain puts in the room at once, and the most distinct faces it draws.
    /// Measured with CutRackRainHarnessTests on the iOS 27 simulator (iPhone 17 Pro, 402 x 500
    /// point band), 2026-11-25. Frame time is not what limits it: lathe plates held a 16.7 ms
    /// median and 17 to 18 ms p95 at 30, 60 and 90 plates (90 plates: 146 entities, settled in
    /// 10 s). Settling is. With the disc collider and the stable-pose rest rule (re-measured the
    /// same day): 16 lathe plates lie in a heap at most 0.33 m high, 13 to 16 of them within 20
    /// degrees of flat, none on edge, on the bar or out of frame, asleep 2.7 to 4.4 s after the
    /// first plate. At 20 the heap is still low (0.33 m) but takes until the 4.5 s give-up limit
    /// (asleep at 6.4 to 6.6 s) and a plate can stay on its edge; at 24, 11 plates lean. Legacy:
    /// 12 asleep in 2.4 to 2.7 s, 16 in 3.9 s, all flat. Faces: every distinct look is one face set
    /// (memory grew 1 to 13 MB for 16 to 36 faces once the studio was warm), so looks equals
    /// plates for lathe. Legacy plates are about 23 entities each (12 plates: 275 entities) and
    /// their first materials cost: 16 plates gave one 700 ms main-thread stall, 12 at most 36 ms.
    struct Limits: Equatable {
        var plates: Int
        var looks: Int
    }

    static func limits(for style: RackPlateStyle) -> Limits {
        switch style {
        case .lathe: return Limits(plates: 16, looks: 16)
        case .legacy: return Limits(plates: 12, looks: 10)
        }
    }

    /// One plate leaves the sky this often: about 14 a second.
    static let spawnInterval: TimeInterval = 0.07
    /// Under Reduce Motion plates are set down rather than thrown, a little faster.
    static let gentleSpawnInterval: TimeInterval = 0.04

    /// Where plates fall: in front of the bar (it is at z 0.12, the stands at x ±0.40) so the
    /// pile does not bury the sleeves, inside the fully visible floor (RackPlatePlay.frameMaxAbsX
    /// and frameMaxZ), from just under the room's recovery ceiling (1.80).
    static let spawnMaxAbsX: Float = 0.54
    static let spawnMinZ: Float = 0.46
    static let spawnMaxZ: Float = 0.64
    static let spawnMinY: Float = 1.45
    static let spawnMaxY: Float = 1.72

    struct Pose: Equatable {
        var position: SIMD3<Float>
        var orientation: simd_quatf
        var linearVelocity: SIMD3<Float>
        var angularVelocity: SIMD3<Float>
    }

    /// A deterministic spread: x walks the width by the golden ratio so neighbours in time land
    /// apart, z and the tumble come from a small hash of the index. Gentle poses lie flat, low
    /// over the floor, and do not move; the stack they make settles under gravity alone.
    static func pose(index: Int, gentle: Bool) -> Pose {
        let golden: Float = 0.618_034
        let u = (Float(index) * golden).truncatingRemainder(dividingBy: 1)
        let x = (u * 2 - 1) * spawnMaxAbsX
        let z = spawnMinZ + hash(index, 1) * (spawnMaxZ - spawnMinZ)
        if gentle {
            // Six to a layer, never stacked higher than the bar.
            let layer = Float(min(index / 6, 7))
            return Pose(position: SIMD3(x, 0.08 + layer * 0.07, z),
                        orientation: simd_quatf(angle: hash(index, 2) * .pi * 2, axis: SIMD3(0, 1, 0)),
                        linearVelocity: .zero, angularVelocity: .zero)
        }
        let y = spawnMinY + hash(index, 3) * (spawnMaxY - spawnMinY)
        let tilt = simd_quatf(angle: (hash(index, 4) - 0.5) * 0.7, axis: SIMD3(1, 0, 0))
            * simd_quatf(angle: (hash(index, 5) - 0.5) * 0.7, axis: SIMD3(0, 0, 1))
        let spin = SIMD3((hash(index, 6) - 0.5) * 3, (hash(index, 7) - 0.5) * 4, (hash(index, 8) - 0.5) * 3)
        return Pose(position: SIMD3(x, y, z), orientation: tilt,
                    linearVelocity: SIMD3((hash(index, 9) - 0.5) * 0.4, -0.6, (hash(index, 10) - 0.5) * 0.2),
                    angularVelocity: spin)
    }

    /// When a plate spawned at `y` with the pose's downward speed first reaches the floor.
    static func fallTime(fromY y: Float, downwardSpeed: Float = 0.6) -> TimeInterval {
        let g = RackPlatePlay.gravity
        let h = max(0, y - 0.05)
        let t = (-downwardSpeed + sqrt(downwardSpeed * downwardSpeed + 2 * g * h)) / g
        return TimeInterval(max(0.05, t))
    }

    /// 0 ..< 1 from an index and a salt.
    static func hash(_ index: Int, _ salt: Int) -> Float {
        var v = UInt32(truncatingIfNeeded: index &* 0x9E37_79B1 &+ salt &* 0x85EB_CA6B)
        v ^= v >> 16
        v = v &* 0x7FEB_352D
        v ^= v >> 15
        v = v &* 0x846C_A68B
        v ^= v >> 16
        return Float(v % 10_000) / 10_000
    }

    // MARK: Tidy up

    /// The whole exit, first plate leaving to last plate gone, stays inside this.
    static let tidyBudget: TimeInterval = 0.8
    /// The most time between two plates leaving.
    static let tidyMaxStagger: TimeInterval = 0.04

    struct TidyStep: Equatable {
        var id: String
        var delay: TimeInterval
        var duration: TimeInterval
    }

    /// One plate's exit. Under Reduce Motion every style is a plain fade, all at once.
    static func tidyDuration(_ style: RackTidyStyle, reduceMotion: Bool) -> TimeInterval {
        if reduceMotion { return 0.25 }
        switch style {
        case .tray: return 0.36
        case .wheel: return 0.42
        case .sink: return 0.30
        }
    }

    /// Who leaves when. Tray and sink take the plate nearest the camera (largest z) first, wheel
    /// the one nearest its side. Plates leave evenly spaced, at most tidyMaxStagger apart and
    /// closer when there are many, so the last one is gone within tidyBudget.
    static func tidyPlan(_ plates: [(id: String, position: SIMD3<Float>)], style: RackTidyStyle,
                         reduceMotion: Bool) -> [TidyStep] {
        let duration = tidyDuration(style, reduceMotion: reduceMotion)
        let ordered = plates.sorted { a, b in
            switch style {
            case .wheel where !reduceMotion:
                if abs(a.position.x) != abs(b.position.x) { return abs(a.position.x) > abs(b.position.x) }
            default:
                if a.position.z != b.position.z { return a.position.z > b.position.z }
                if abs(a.position.x) != abs(b.position.x) { return abs(a.position.x) < abs(b.position.x) }
            }
            return a.id < b.id
        }
        let gap: TimeInterval = reduceMotion || ordered.count < 2
            ? 0 : min(tidyMaxStagger, (tidyBudget - duration) / Double(ordered.count - 1))
        return ordered.enumerated().map { TidyStep(id: $0.element.id, delay: Double($0.offset) * gap, duration: duration) }
    }

    /// Where an exit goes, in the scene root's space: a lift then a target for tray, a single
    /// target for the others. The camera sits about 2.9 m in front of the bar and 0.5 m above
    /// the floor, so a point low and well in front of the room is below the bottom of the frame:
    /// the tray. Every exit also fades over its last part, so nothing pops out of view.
    static func tidyKeyframes(_ style: RackTidyStyle, from start: Transform) -> [Transform] {
        let p = start.translation
        switch style {
        case .tray:
            var lift = start
            lift.translation = p + SIMD3(0, 0.16, 0.05)
            var end = start
            // Face toward the camera as it goes, like a plate being carried to the tray.
            end.rotation = simd_quatf(from: SIMD3(0, 1, 0), to: simd_normalize(SIMD3(0, 0.35, 1)))
            end.translation = SIMD3(p.x * 0.35, -0.02, 2.05)
            end.scale = start.scale * 0.25
            return [lift, end]
        case .wheel:
            var end = start
            let side: Float = p.x >= 0 ? 1 : -1
            end.translation = SIMD3(side * 1.5, max(0.03, p.y - 0.02), p.z + 0.08)
            end.rotation = simd_quatf(angle: side * -.pi / 2, axis: SIMD3(0, 1, 0)) * start.rotation
            return [end]
        case .sink:
            var end = start
            end.translation = p - SIMD3(0, 0.06, 0)
            end.scale = start.scale * 0.8
            return [end]
        }
    }

    /// Rate limit for landing feedback: a drop sound no more than every 0.15 s, a haptic no more
    /// than every 0.35 s and at most 6 haptics per rain, so a stream of landings reads as a pile
    /// coming down rather than one buzz.
    struct FeedbackLimiter {
        static let soundGap: TimeInterval = 0.15
        static let hapticGap: TimeInterval = 0.35
        static let maxHaptics = 6

        private var lastSound: TimeInterval = -.infinity
        private var lastHaptic: TimeInterval = -.infinity
        private(set) var haptics = 0

        /// Whether a landing at `time` (seconds from the start of the rain) plays a sound and a haptic.
        mutating func admit(at time: TimeInterval) -> (sound: Bool, haptic: Bool) {
            let sound = time - lastSound >= Self.soundGap
            if sound { lastSound = time }
            let haptic = haptics < Self.maxHaptics && time - lastHaptic >= Self.hapticGap
            if haptic {
                lastHaptic = time
                haptics += 1
            }
            return (sound, haptic)
        }
    }
}

extension SceneState {
    /// Rained plates still in the room (lying loose, or loaded since).
    var rainedPlateIDs: [String] {
        entityMap.compactMap { $0.value.components.has(RackRainedPlateComponent.self) ? $0.key : nil }.sorted()
    }

    /// Drops `plates` into the room, in order, one per spawn interval. Plates already in the scene
    /// (on the bar or lying loose) and loaded plates are skipped. Prepares every distinct face first
    /// (lathe) or each tier's material (legacy). Returns how many fell. Stops when the task is
    /// cancelled or the scene pauses; plates already down stay until tidied.
    @MainActor
    @discardableResult
    func rainPlates(_ plates: [EarnedPlate], gentle: Bool, onLanded: (@MainActor (Int) -> Void)? = nil) async -> Int {
        // A tidy still playing ends now: its plates go at once, so the new ones fall into a clear room.
        finishTidy()
        isRaining = true
        defer { isRaining = false }
        let fresh = plates.filter { entityMap[$0.id] == nil && !$0.isRacked && !$0.isStarterPlate }
        guard !fresh.isEmpty, !isPaused else { return 0 }
        if plateStyle == .lathe {
            // Meshes and body materials only: a plate never waits for its face. It falls with its
            // body finish and is lettered when the face is ready (one face per distinct look,
            // shared by every copy; LatheFaceCache keeps faces in use).
            await prepareLathePlates(latheFirstFrameRequests(fresh), faces: false)
        } else {
            for tierID in Set(fresh.map(\.tierID)).sorted() where materialCache[tierID] == nil {
                let textures = await loadPlateTexturesAsync(forTierID: tierID)
                plateTextureCache[tierID] = textures
                materialCache[tierID] = buildMaterial(forTierID: tierID, textures: textures, inRackRoom: true)
            }
        }
        var limiter = RackPlateRain.FeedbackLimiter()
        let interval = gentle ? RackPlateRain.gentleSpawnInterval : RackPlateRain.spawnInterval
        var spawned = 0
        for plate in fresh {
            guard !Task.isCancelled, !isPaused else { break }
            guard entityMap[plate.id] == nil else { continue }
            let pose = RackPlateRain.pose(index: spawned, gentle: gentle)
            let entity = makePlateEntity(
                tierID: plate.tierID,
                textures: plateTextureCache[plate.tierID],
                material: materialCache[plate.tierID],
                weightKg: plate.weightKg,
                engravingText: plate.engravingText,
                prominentEngraving: plate.earnedByEvent.hasPrefix("strength_milestone_"),
                renderProjection: BarbellPlateRenderProjection(plate: plate),
                role: .floor,
                plateStyle: plateStyle
            )
            entity.name = plate.id
            entity.components.set(RackRainedPlateComponent())
            floorAnchor.addChild(entity)
            entity.setPosition(pose.position, relativeTo: sceneRoot)
            entity.setOrientation(pose.orientation, relativeTo: sceneRoot)
            var motion = PhysicsMotionComponent()
            motion.linearVelocity = pose.linearVelocity
            motion.angularVelocity = pose.angularVelocity
            entity.components[PhysicsMotionComponent.self] = motion
            entity.components[PhysicsBodyComponent.self]?.mode = .dynamic
            entityMap[plate.id] = entity
            originalTransforms[plate.id] = Transform(matrix: entity.transformMatrix(relativeTo: nil))
            loosePlateIDs.insert(plate.id)
            floorSettles[plate.id] = BarbellFloorSettleState(delay: RackPlatePlay.settleDelay)
            wakeLoosePlates(except: plate.id)

            if !gentle, let audio = entity.components[PlateAudioCategoryComponent.self] {
                let fall = RackPlateRain.fallTime(fromY: pose.position.y, downwardSpeed: -pose.linearVelocity.y)
                let landing = Double(spawned) * interval + fall
                let feedback = limiter.admit(at: landing)
                if feedback.sound || feedback.haptic {
                    Task { @MainActor [weak entity] in
                        try? await Task.sleep(for: .milliseconds(Int(fall * 1000)))
                        guard let entity, entity.parent != nil,
                              entity.components[PlateRoleComponent.self]?.role == .floor else { return }
                        if feedback.sound { playDropSound(on: entity, category: audio.category) }
                        if feedback.haptic { playDropHaptic(category: audio.category) }
                    }
                }
            }
            spawned += 1
            try? await Task.sleep(for: .milliseconds(Int(interval * 1000)))
        }
        if spawned > 0 {
            // The last plate's fall, then tell the host once.
            let last = gentle ? 0.3 : RackPlateRain.fallTime(fromY: RackPlateRain.spawnMaxY)
            try? await Task.sleep(for: .milliseconds(Int(last * 1000)))
        }
        onLanded?(spawned)
        return spawned
    }

    /// Takes every rained plate that is still lying loose out of the room. A plate in the hand,
    /// sliding off the bar or loaded since stays. Returns how many were taken.
    ///
    /// With `exit` the plates leave with that animation (RackPlateRain.tidyPlan and
    /// tidyKeyframes; a fade under `reduceMotion`), played by RealityKit with no per-frame work
    /// here, then one soft haptic (and for tray one rack sound) when the last is gone. They leave
    /// the scene's bookkeeping at once: they cannot be touched, collide or be loaded on the way
    /// out, and a new drop clears them instantly (finishTidy). Without `exit` (leaving the screen,
    /// a rebuild) they go at once. `timeScale` slows the exit down for frame captures in tests.
    @MainActor
    @discardableResult
    func tidyRainedPlates(exit: RackTidyStyle? = nil, reduceMotion: Bool = false, timeScale: Double = 1) -> Int {
        finishTidy()
        var taken: [(id: String, entity: Entity)] = []
        for id in rainedPlateIDs {
            guard let entity = entityMap[id],
                  entity.components[PlateRoleComponent.self]?.role == .floor,
                  entity !== heldPlate?.entity,
                  !platesBeingUnracked.contains(id) else { continue }
            if case .draggingPlate(let dragging, _, _) = dragPhase, dragging === entity { continue }
            if showcaseEntity === entity {
                showcaseEntity = nil
                showcaseToken = nil
            }
            entity.stopAllAnimations(recursive: true)
            entityMap[id] = nil
            loosePlateIDs.remove(id)
            floorSettles[id] = nil
            originalTransforms[id] = nil
            preparedMirrors[id] = nil
            taken.append((id, entity))
        }
        guard !taken.isEmpty else { return 0 }

        if let exit {
            let positions = taken.map { ($0.id, $0.entity.position(relativeTo: sceneRoot)) }
            let plan = RackPlateRain.tidyPlan(positions.map { (id: $0.0, position: $0.1) }, style: exit, reduceMotion: reduceMotion)
            let byID = Dictionary(taken.map { ($0.id, $0.entity) }, uniquingKeysWith: { first, _ in first })
            var end: TimeInterval = 0
            for step in plan {
                guard let entity = byID[step.id] else { continue }
                // Out of the simulation and out of reach: only the animation moves it now.
                entity.setParent(sceneRoot, preservingWorldTransform: true)
                entity.components.remove(PhysicsBodyComponent.self)
                entity.components.remove(PhysicsMotionComponent.self)
                entity.components.remove(CollisionComponent.self)
                entity.components.remove(InputTargetComponent.self)
                entity.components.set(OpacityComponent(opacity: 1))
                leavingPlates.append(entity)
                let delay = step.delay * timeScale, duration = step.duration * timeScale
                if let animation = Self.tidyAnimation(for: entity, style: exit, reduceMotion: reduceMotion,
                                                      delay: delay, duration: duration) {
                    entity.playAnimation(animation)
                } else {
                    entity.removeFromParent()
                }
                end = max(end, delay + duration)
            }
            let category = taken.last?.entity.components[PlateAudioCategoryComponent.self]?.category ?? .rubber
            tidyTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(Int(end * 1000) + 30))
                guard let self, !Task.isCancelled else { return }
                if !reduceMotion, exit == .tray { playClinkSound(on: self.barAnchor, category: category) }
                UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
                self.finishTidy()
            }
        } else {
            for item in taken { item.entity.removeFromParent() }
            if plateStyle == .lathe { LatheFaceCache.evictIfNeeded() }
        }
        // Anything that was resting on a taken plate falls into the gap and settles again.
        wakeLoosePlates()
        return taken.count
    }

    /// Ends a tidy at once: plates still on their way out are removed and their faces may go.
    @MainActor
    func finishTidy() {
        tidyTask?.cancel()
        tidyTask = nil
        guard !leavingPlates.isEmpty else { return }
        for entity in leavingPlates {
            entity.stopAllAnimations(recursive: true)
            entity.removeFromParent()
        }
        leavingPlates.removeAll()
        if plateStyle == .lathe { LatheFaceCache.evictIfNeeded() }
    }

    /// One plate's exit as a single RealityKit animation: the transform keyframes in sequence,
    /// grouped with a fade over the last part (the whole of it under Reduce Motion).
    @MainActor
    static func tidyAnimation(for entity: Entity, style: RackTidyStyle, reduceMotion: Bool,
                              delay: TimeInterval, duration: TimeInterval) -> AnimationResource? {
        // Sink fades the whole way; tray and wheel only as they leave the frame.
        let fadeLength = reduceMotion || style == .sink ? duration : duration * 0.35
        let fade = FromToByAnimation<Float>(from: 1, to: 0, duration: fadeLength, timing: .easeIn,
                                            bindTarget: .opacity, delay: delay + duration - fadeLength)
        guard let fadeResource = try? AnimationResource.generate(with: fade) else { return nil }
        if reduceMotion { return fadeResource }

        let start = entity.transform
        let keys = RackPlateRain.tidyKeyframes(style, from: start)
        var segments: [AnimationResource] = []
        var from = start
        // Tray: a short lift (a third of the time, easing out), then the flight (easing in).
        let shares: [Double] = keys.count == 2 ? [1.0 / 3, 2.0 / 3] : [1]
        for (index, key) in keys.enumerated() {
            let segment = FromToByAnimation<Transform>(
                from: from, to: key, duration: duration * shares[index],
                timing: keys.count == 2 && index == 0 ? .easeOut : .easeIn,
                bindTarget: .transform, delay: index == 0 ? delay : 0)
            guard let resource = try? AnimationResource.generate(with: segment) else { return nil }
            segments.append(resource)
            from = key
        }
        guard let motion = segments.count == 1 ? segments.first : try? AnimationResource.sequence(with: segments) else { return nil }
        return try? AnimationResource.group(with: [motion, fadeResource])
    }
}
