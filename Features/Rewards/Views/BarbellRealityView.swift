// Features/Rewards/Views/BarbellRealityView.swift
import SwiftUI
import RealityKit
import SwiftData
import UIKit

private let plateBarOrientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 0, 1))
private let plateDisplayOrientation = plateBarOrientation

// MARK: - Debug logging

#if DEBUG
func barbellLog(_ tag: String, _ msg: String) {
    print("[Barbell.\(tag)] \(msg)")
}
func v3(_ v: SIMD3<Float>) -> String { String(format: "(%.3f, %.3f, %.3f)", v.x, v.y, v.z) }

private var isBarbellPlateDebugEnabled: Bool {
    ProcessInfo.processInfo.arguments.contains("-BarbellPlateDebug")
    || ProcessInfo.processInfo.environment["BARBELL_PLATE_DEBUG"] == "1"
}

private func attachPlateDebugAxes(to entity: Entity, label: String) {
    guard isBarbellPlateDebugEnabled else { return }

    let axisLength: Float = 0.34
    let axisWidth: Float = 0.008
    let red = SimpleMaterial(color: .red, isMetallic: false)
    let green = SimpleMaterial(color: .green, isMetallic: false)
    let blue = SimpleMaterial(color: .blue, isMetallic: false)
    let white = SimpleMaterial(color: .white, isMetallic: false)

    let xAxis = ModelEntity(mesh: .generateBox(size: SIMD3(axisLength, axisWidth, axisWidth)), materials: [red])
    xAxis.name = "\(label)_debug_localX"
    xAxis.position.x = axisLength * 0.5

    let yAxis = ModelEntity(mesh: .generateBox(size: SIMD3(axisWidth, axisLength, axisWidth)), materials: [green])
    yAxis.name = "\(label)_debug_faceNormalY"
    yAxis.position.y = axisLength * 0.5

    let zAxis = ModelEntity(mesh: .generateBox(size: SIMD3(axisWidth, axisWidth, axisLength)), materials: [blue])
    zAxis.name = "\(label)_debug_localZ"
    zAxis.position.z = axisLength * 0.5

    let center = ModelEntity(mesh: .generateSphere(radius: 0.015), materials: [white])
    center.name = "\(label)_debug_center"

    entity.addChild(xAxis)
    entity.addChild(yAxis)
    entity.addChild(zAxis)
    entity.addChild(center)

    let matrix = entity.transformMatrix(relativeTo: nil)
    let faceNormal = simd_normalize(SIMD3<Float>(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z))
    barbellLog("PLATE_DEBUG", "\(label) localY(faceNormal)=\(v3(faceNormal)) worldPos=\(v3(entity.position(relativeTo: nil)))")
}
#endif

private func barbellDiagnosticsV3(_ v: SIMD3<Float>) -> String {
    String(format: "(%.3f, %.3f, %.3f)", v.x, v.y, v.z)
}

private func barbellDiagnosticsLog(_ event: String, _ message: String) {
    DiagnosticsLogStore.shared.append("\(event) \(message)", category: "Barbell")
}

// MARK: - BarbellRealityMode

enum BarbellRealityMode {
    case welcome(plates: [EarnedPlateInfo])
    case rackRoom(
        rackedPlates: [EarnedPlate],
        floorPlates: [EarnedPlate],
        onRack: (EarnedPlate) -> Void,
        onUnrack: (EarnedPlate) -> Void
    )
}

func barbellRealityCameraPosition(
    for mode: BarbellRealityMode,
    sizeClass: UserInterfaceSizeClass?
) -> SIMD3<Float> {
    let isWide = sizeClass == .regular
    switch mode {
    case .welcome:
        return SIMD3(0, 0.16, isWide ? -1.62 : -1.22)
    case .rackRoom:
        return SIMD3(0, isWide ? -0.42 : -0.40, isWide ? -1.72 : -1.30)
    }
}

func clampFloorPlateX(_ x: Float, maxAbsX: Float = 0.64) -> Float {
    max(-maxAbsX, min(maxAbsX, x))
}

func barbellRackRoomSlideOutDuration(isReduceMotionEnabled: Bool) -> TimeInterval {
    _ = isReduceMotionEnabled
    return 0.2
}

// MARK: - DragPhase

enum DragPhase {
    case idle
    /// originRole: the PlateRoleComponent.Role the entity had when the drag began.
    /// Captured at drag-start so onEnded routing is not affected by mid-drag model mutations.
    case draggingPlate(Entity, plateID: String, originRole: PlateRoleComponent.Role)
    case panningFloor
}

// MARK: - PlateSpinState

final class PlateSpinState {
    var angle: Float    = Float.random(in: 0 ..< Float.pi * 2)
    var velocity: Float = Float.random(in: 0.5 ..< 1.8) * (Bool.random() ? 1 : -1)
}

// MARK: - SceneState

final class SceneState {

    // MARK: Scene graph anchors
    var floorAnchor = Entity()
    var barAnchor   = Entity()
    var sceneRoot   = Entity()
    var barbellRoot: Entity?

    // MARK: Entity lookups
    var entityMap: [String: Entity] = [:]
    /// World-space transform captured at scene setup. Used by snapBack to restore floor plates.
    var originalTransforms: [String: Transform] = [:]
    /// Canonical position on barAnchor per plate ID. Used by snapBack for bar plates.
    var barPositionMap: [String: SIMD3<Float>] = [:]
    /// Mirror entity per plate ID. Populated by snapToBar; removed by finishUnrack / snapBack.
    var barMirrorMap: [String: Entity] = [:]
    /// Slot highlight ring entities on barAnchor. Index matches slotOffsets[0...3].
    /// Toggled visible/invisible during drag to show the target slot.
    var slotHighlights: [Entity] = []

    // MARK: Storage slots
    /// Left-post entities for each storage bracket. Right post is a child of each left post,
    /// so material updates and isEnabled propagate to both. Parented to sceneRoot (not floorAnchor)
    /// so they stay fixed while the floor pans.
    var storageSlotRings: [Entity] = []
    /// Fixed positions in sceneRoot-local space. Y=1.60 places the slots well above the bar (Y=0.60)
    /// so they project to the upper black area of the screen. Z=0.12 matches barbellZ so stored
    /// plates sit in front of the backdrop at the same depth as racked plates.
    let storageSlotPositions: [SIMD3<Float>] = [-0.70, -0.50, -0.30, -0.10, 0.10, 0.30, 0.50, 0.70]
        .map { SIMD3($0, 1.60, 0.12) }
    /// slot index -> plate ID for occupied slots.
    var storageSlotByIndex: [Int: String] = [:]
    /// plate ID -> slot index for O(1) lookup at drag start.
    var storageSlotByPlate: [String: Int] = [:]
    /// The slot index whose ring is currently highlighted during a plate drag.
    var hoveredStorageSlotIndex: Int? = nil
    /// Entity position in sceneRoot-local space at drag start.
    /// Stored on first transition so cumulative value.translation can be applied as offset.
    var dragStartEntityPosition: SIMD3<Float> = .zero
    /// Storage slot index the plate came from, captured at drag-start and cleared in onEnded.
    /// Allows snapBack and onEnded routing to return the plate to its original storage slot
    /// when the drag is not committed to the bar.
    var dragOriginStorageSlot: Int? = nil
    /// Tracks whether the dragged plate was in the snap zone on the previous frame.
    /// Prevents snap zone entry haptic from firing every frame.
    var wasInSnapZone: Bool = false

    // MARK: Caches
    /// One PhysicallyBasedMaterial per tierID -- shared across all plates of the same tier.
    /// Populate in .task{} before RealityView make{} runs. Pass entries into makePlateEntity(material:).
    var materialCache: [Int: PhysicallyBasedMaterial] = [:]
    var plateTextureCache: [Int: PlateTextures] = [:]

    // MARK: State machine

    private(set) var dragPhase: DragPhase = .idle

    /// Attempts the transition to `next`. Returns false and leaves dragPhase unchanged
    /// if the transition is invalid.
    /// Invalid transitions: floor pan while dragging a plate; dragging a plate while floor
    /// panning. Both require returning to .idle first.
    @discardableResult
    func transition(to next: DragPhase) -> Bool {
        switch (dragPhase, next) {
        case (.idle, _),
             (.draggingPlate, .idle),
             (.panningFloor, .idle):
            dragPhase = next
            return true
        default:
            return false
        }
    }

    // MARK: Floor pan state
    var floorOffset: Float            = 0
    var floorVelocity: Float          = 0
    var floorMinX: Float              = 0
    var floorMaxX: Float              = 0
    /// Last cumulative translation from the active pan gesture.
    /// DragGesture.translation is cumulative from gesture start, not a per-event delta.
    /// Reset to 0 in onEnded.
    var floorPanLastTranslation: Float = 0

    // MARK: Legacy settle tasks
    /// Retained only so in-flight task cancellation from older drop paths stays safe.
    /// Floor plates now remain dynamic; new code does not schedule settle timers.
    var settleTasks: [String: Task<Void, Never>] = [:]

    // MARK: Unrack guard
    /// Plate IDs currently inside a bar→floor unrack animation (200ms slide + 16ms physics delay).
    /// The bar-swipe handler rejects any plate in this set so rapid repeat swipes on the same
    /// plate don't spawn multiple concurrent snapToFloor Tasks.
    var platesBeingUnracked: Set<String> = []

    // MARK: Welcome spin state
    var plateSpinStates: [String: PlateSpinState] = [:]
    var barbellSpinAngle: Float    = 0
    var barbellSpinVelocity: Float = 0
    var welcomePitchAngle: Float = 0
    var welcomeDragStartAngle: Float = 0
    var welcomeDragStartPitch: Float = 0
    var isDraggingWelcome: Bool = false

    // MARK: Info card
    /// Currently displayed 3D info card entity (child of sceneRoot). Nil when no card shown.
    var infoCardEntity: Entity? = nil
    /// Plate ID whose card is currently visible. Used to detect re-tap for dismiss.
    var infoCardPlateID: String? = nil
    /// Timestamp of last showInfoCard() call. Prevents the dismiss path running within
    /// 400ms of a show -- guards against TapGesture double-fire on some iOS versions.
    var infoCardLastShowTime: Date = .distantPast

    // MARK: Accessibility
    /// Re-read at gesture time so it responds to in-session Reduce Motion changes.
    var isReduceMotionEnabled: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    // MARK: Storage slot helpers
    /// Updates the material on a slot's left post and all children (right post, crossbar) simultaneously.
    func setSlotMaterial(_ mat: RealityKit.Material, atIndex idx: Int) {
        guard storageSlotRings.indices.contains(idx) else { return }
        (storageSlotRings[idx] as? ModelEntity)?.model?.materials = [mat]
        for child in storageSlotRings[idx].children {
            (child as? ModelEntity)?.model?.materials = [mat]
        }
    }

    func isValidStorageSlot(_ idx: Int) -> Bool {
        storageSlotPositions.indices.contains(idx)
    }

    func setStorageSlotRingEnabled(_ isEnabled: Bool, atIndex idx: Int) {
        guard storageSlotRings.indices.contains(idx) else {
            #if DEBUG
            barbellLog("STORAGE_SLOT", "ignoring ring visibility for stale slot=\(idx), rings=\(storageSlotRings.count)")
            #endif
            return
        }
        storageSlotRings[idx].isEnabled = isEnabled
    }

    /// Returns the index of the first empty storage slot, or nil if all are occupied.
    func findFreeStorageSlot() -> Int? {
        (0..<storageSlotPositions.count).first { storageSlotByIndex[$0] == nil }
    }

    // MARK: Camera proxy
    /// Positions sceneRoot so the default RealityView perspective camera frames the scene.
    /// Call after scene setup completes and on horizontal size class changes.
    func configureCameraPosition(for mode: BarbellRealityMode, sizeClass: UserInterfaceSizeClass?) {
        sceneRoot.position = barbellRealityCameraPosition(for: mode, sizeClass: sizeClass)
    }

    // MARK: Live plate addition
    func addPlate(_ plate: EarnedPlate) {
        guard entityMap[plate.id] == nil else { return }
        guard let slotIdx = findFreeStorageSlot() else { return }  // No free slot: drop silently
        let entity = makePlateEntity(
            tierID: plate.tierID,
            textures: plateTextureCache[plate.tierID],
            material: materialCache[plate.tierID],
            weightKg: plate.weightKg,
            engravingText: plate.engravingText,
            prominentEngraving: plate.earnedByEvent.hasPrefix("strength_milestone_"),
            renderProjection: BarbellPlateRenderProjection(plate: plate),
            role: .floor
        )
        entity.name = plate.id
        entity.orientation = plateDisplayOrientation
        entity.position = storageSlotPositions[slotIdx]
        #if DEBUG
        attachPlateDebugAxes(to: entity, label: "storage_add_\(slotIdx)")
        #endif
        entity.components[PhysicsBodyComponent.self]?.mode = .kinematic
        sceneRoot.addChild(entity)
        entityMap[plate.id] = entity
        originalTransforms[plate.id] = Transform(matrix: entity.transformMatrix(relativeTo: nil))
        storageSlotByIndex[slotIdx] = plate.id
        storageSlotByPlate[plate.id] = slotIdx
        setStorageSlotRingEnabled(false, atIndex: slotIdx)
    }

    // MARK: Welcome spin loop
    /// No-ops immediately when Reduce Motion is enabled.
    @MainActor
    func runWelcomeSpinLoop() async {
        guard !isReduceMotionEnabled else { return }
        var lastTime = Date().timeIntervalSinceReferenceDate
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(16))
            let now = Date().timeIntervalSinceReferenceDate
            let dt = Float(min(now - lastTime, 0.05))
            lastTime = now

            if !isDraggingWelcome {
                barbellSpinAngle += barbellSpinVelocity * dt
                barbellSpinVelocity *= 0.992
                if abs(barbellSpinVelocity) < 0.08 {
                    barbellSpinVelocity = 0.18
                }
                applyWelcomeLook()
            }

            for (key, spinState) in plateSpinStates {
                spinState.angle    += spinState.velocity * dt
                entityMap[key]?.orientation =
                    simd_quatf(angle: spinState.angle, axis: SIMD3(0, 1, 0))
                    * simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0))
            }
        }
    }

    func applyWelcomeLook() {
        barbellRoot?.orientation =
            simd_quatf(angle: barbellSpinAngle, axis: SIMD3(0, 1, 0))
            * simd_quatf(angle: welcomePitchAngle, axis: SIMD3(1, 0, 0))
    }

    @MainActor
    func pauseNonessentialRealityWork() {
        barbellSpinVelocity = 0
        for task in settleTasks.values {
            task.cancel()
        }
        settleTasks.removeAll()
        for entity in entityMap.values {
            entity.stopAllAnimations(recursive: true)
            if entity.components[PlateRoleComponent.self]?.role == .floor,
               entity.components[PhysicsBodyComponent.self]?.mode == .dynamic {
                entity.components[PhysicsBodyComponent.self]?.mode = .kinematic
                entity.components[PhysicsMotionComponent.self] = PhysicsMotionComponent()
            }
        }
    }

    @MainActor
    func animateAwardPlateOntoBar(plateID: String, rackSlot: Int) async -> Bool {
        guard let entity = entityMap[plateID],
              entity.components[PlateRoleComponent.self]?.role == .floor else {
            return false
        }

        let slotOffsets: [Float] = [0.600, 0.652, 0.704, 0.756]
        guard slotOffsets.indices.contains(rackSlot) else { return false }

        if let slotIdx = storageSlotByPlate[plateID] {
            storageSlotByPlate.removeValue(forKey: plateID)
            storageSlotByIndex.removeValue(forKey: slotIdx)
            // Slot is now empty -- show the bracket ring again so the user sees an open slot.
            setStorageSlotRingEnabled(true, atIndex: slotIdx)
        }

        let offset = slotOffsets[rackSlot]
        let targetRot = plateBarOrientation
        let barLocal = barAnchor.position
        let rightHigh = SIMD3<Float>(offset + 0.42, barLocal.y + 0.62, barLocal.z + 0.12)
        let rightHover = SIMD3<Float>(offset + 0.12, barLocal.y + 0.22, barLocal.z + 0.05)
        let rightFinal = barLocal + SIMD3<Float>(offset, 0, 0)
        let leftHigh = SIMD3<Float>(-offset - 0.42, barLocal.y + 0.62, barLocal.z + 0.12)
        let leftHover = SIMD3<Float>(-offset - 0.12, barLocal.y + 0.22, barLocal.z + 0.05)
        let leftFinal = barLocal + SIMD3<Float>(-offset, 0, 0)

        entity.components[PhysicsBodyComponent.self]?.mode = .kinematic
        entity.components.set(PlateRoleComponent(role: .bar))
        entity.setParent(sceneRoot, preservingWorldTransform: true)

        let mirrorEntity = entity.clone(recursive: true)
        mirrorEntity.name = plateID + "_mirror"
        mirrorEntity.components.set(PlateRoleComponent(role: .bar))
        mirrorEntity.components.remove(InputTargetComponent.self)
        mirrorEntity.components.remove(CollisionComponent.self)
        mirrorEntity.components.remove(PhysicsBodyComponent.self)
        mirrorEntity.components.remove(PhysicsMotionComponent.self)
        mirrorEntity.position = leftHigh
        mirrorEntity.orientation = targetRot
        sceneRoot.addChild(mirrorEntity)

        entity.orientation = targetRot
        if isReduceMotionEnabled {
            entity.position = rightFinal
            mirrorEntity.position = leftFinal
        } else {
            entity.move(
                to: Transform(scale: entity.scale, rotation: targetRot, translation: rightHigh),
                relativeTo: sceneRoot,
                duration: 0.18,
                timingFunction: .easeOut
            )
            try? await Task.sleep(for: .milliseconds(180))
            entity.move(
                to: Transform(scale: entity.scale, rotation: targetRot, translation: rightHover),
                relativeTo: sceneRoot,
                duration: 0.42,
                timingFunction: .easeInOut
            )
            mirrorEntity.move(
                to: Transform(scale: mirrorEntity.scale, rotation: targetRot, translation: leftHover),
                relativeTo: sceneRoot,
                duration: 0.42,
                timingFunction: .easeInOut
            )
            try? await Task.sleep(for: .milliseconds(420))
            entity.move(
                to: Transform(scale: entity.scale, rotation: targetRot, translation: rightFinal + SIMD3<Float>(0, 0.035, 0)),
                relativeTo: sceneRoot,
                duration: 0.18,
                timingFunction: .easeIn
            )
            mirrorEntity.move(
                to: Transform(scale: mirrorEntity.scale, rotation: targetRot, translation: leftFinal + SIMD3<Float>(0, 0.035, 0)),
                relativeTo: sceneRoot,
                duration: 0.18,
                timingFunction: .easeIn
            )
            try? await Task.sleep(for: .milliseconds(180))
            entity.move(
                to: Transform(scale: entity.scale, rotation: targetRot, translation: rightFinal),
                relativeTo: sceneRoot,
                duration: 0.12,
                timingFunction: .easeOut
            )
            mirrorEntity.move(
                to: Transform(scale: mirrorEntity.scale, rotation: targetRot, translation: leftFinal),
                relativeTo: sceneRoot,
                duration: 0.12,
                timingFunction: .easeOut
            )
            try? await Task.sleep(for: .milliseconds(120))
        }

        entity.setParent(barAnchor, preservingWorldTransform: true)
        mirrorEntity.setParent(barAnchor, preservingWorldTransform: true)
        entity.position = SIMD3(offset, 0, 0)
        entity.orientation = targetRot
        mirrorEntity.position = SIMD3(-offset, 0, 0)
        mirrorEntity.orientation = targetRot
        barPositionMap[plateID] = SIMD3(offset, 0, 0)
        barMirrorMap[plateID] = mirrorEntity
        return true
    }

    /// Plays an in-place celebration animation on a plate that overflowed (bar was full).
    ///
    /// In `BarbellMomentView`, `setupRackRoomScene` has already placed every momentFloorPlate
    /// at one of the canonical `storageSlotPositions`. The earlier implementation ignored that
    /// and animated to a hardcoded set of "celebration" coordinates that didn't line up with the
    /// rack rendering, leaving the plate floating in mid-air with no visual home. Instead, lift
    /// the plate from its assigned slot and settle it back down so the slot accounting and the
    /// final visual stay in lockstep with the rest of the scene.
    ///
    /// Returns the slot index used, or nil if the plate isn't currently parked in storage.
    @MainActor
    @discardableResult
    func animateAwardPlateToStorage(plateID: String) async -> Int? {
        guard let entity = entityMap[plateID],
              entity.components[PlateRoleComponent.self]?.role == .floor else {
            return nil
        }
        guard let slotIndex = storageSlotByPlate[plateID],
              storageSlotPositions.indices.contains(slotIndex) else {
            return nil
        }

        let targetPos = storageSlotPositions[slotIndex]
        let targetRot = plateDisplayOrientation
        entity.components[PhysicsBodyComponent.self]?.mode = .kinematic
        if entity.parent !== sceneRoot {
            entity.setParent(sceneRoot, preservingWorldTransform: true)
        }
        entity.orientation = targetRot

        if isReduceMotionEnabled {
            entity.position = targetPos
        } else {
            let liftPos = targetPos + SIMD3<Float>(0, 0.18, 0.04)
            entity.move(
                to: Transform(scale: entity.scale, rotation: targetRot, translation: liftPos),
                relativeTo: sceneRoot,
                duration: 0.22,
                timingFunction: .easeOut
            )
            try? await Task.sleep(for: .milliseconds(220))
            entity.move(
                to: Transform(scale: entity.scale, rotation: targetRot, translation: targetPos),
                relativeTo: sceneRoot,
                duration: 0.28,
                timingFunction: .easeInOut
            )
            try? await Task.sleep(for: .milliseconds(280))
        }

        entity.stopAllAnimations(recursive: false)
        entity.position = targetPos
        entity.orientation = targetRot
        // Bookkeeping: slot is occupied by this plate, hide the empty-slot indicator ring.
        storageSlotByIndex[slotIndex] = plateID
        storageSlotByPlate[plateID] = slotIndex
        setStorageSlotRingEnabled(false, atIndex: slotIndex)
        originalTransforms[plateID] = Transform(matrix: entity.transformMatrix(relativeTo: nil))
        return slotIndex
    }

    @MainActor
    func dropAwardPlateToFloor(plateID: String, index: Int, total: Int) async -> Bool {
        guard let entity = entityMap[plateID],
              entity.components[PlateRoleComponent.self]?.role == .floor else {
            return false
        }

        if let slotIdx = storageSlotByPlate[plateID] {
            storageSlotByPlate.removeValue(forKey: plateID)
            storageSlotByIndex.removeValue(forKey: slotIdx)
            setStorageSlotRingEnabled(true, atIndex: slotIdx)
        }

        if entity.parent !== sceneRoot {
            entity.setParent(sceneRoot, preservingWorldTransform: true)
        }

        let spread = max(Float(total - 1), 1)
        let t = total > 1 ? (Float(index) / spread) - 0.5 : 0
        let spawnX = max(-0.58, min(0.58, t * 1.10))
        let spawnY = Float.random(in: 1.18...1.50)
        let spawnZ = Float.random(in: 0.16...0.34)
        let targetRot = plateDisplayOrientation

        entity.components.set(PlateRoleComponent(role: .floor))
        entity.components[PhysicsBodyComponent.self]?.mode = .kinematic
        entity.components[PhysicsMotionComponent.self] = PhysicsMotionComponent()
        entity.position = SIMD3(spawnX, spawnY, spawnZ)
        entity.orientation = targetRot
        originalTransforms[plateID] = Transform(matrix: entity.transformMatrix(relativeTo: nil))

        guard !isReduceMotionEnabled else { return true }

        try? await Task.sleep(for: .milliseconds(80))
        var motion = PhysicsMotionComponent()
        motion.linearVelocity = SIMD3(
            Float.random(in: -0.14...0.14),
            Float.random(in: -0.22...(-0.08)),
            Float.random(in: -0.08...0.12)
        )
        motion.angularVelocity = SIMD3(
            Float.random(in: -0.65...0.65),
            Float.random(in: -2.4...2.4),
            Float.random(in: -0.45...0.45)
        )
        entity.components[PhysicsMotionComponent.self] = motion
        entity.components[PhysicsBodyComponent.self]?.mode = .dynamic
        return true
    }
}

// MARK: - BarbellRealityView

struct RackRoomLightingPreset {
    let keyIntensity: Float
    let keyPosition: SIMD3<Float>
    let fillIntensity: Float
    let fillPosition: SIMD3<Float>
    let frontWashIntensity: Float
    let frontWashPosition: SIMD3<Float>
    let barWashIntensity: Float
    let barSideWashIntensity: Float
    let barSideWashX: Float
    let storageWashIntensity: Float
    let storageWashY: Float
    let storageFaceWashIntensity: Float
    let storageFaceWashX: Float
    let storageSideWashIntensity: Float
    let storageSideWashX: Float
    let storageSideWashY: Float
    let rimWashIntensity: Float
    let rimWashPosition: SIMD3<Float>
    let imageBasedLightIntensityExponent: Float
    let castsObjectShadows: Bool
    let usesDirectionalKey: Bool

    static let readability = RackRoomLightingPreset(
        keyIntensity: 6_200,
        keyPosition: SIMD3(0, 2.10, 1.90),
        fillIntensity: 3_400,
        fillPosition: SIMD3(0, 0.42, 0.88),
        frontWashIntensity: 3_800,
        frontWashPosition: SIMD3(0, 0.92, 0.88),
        barWashIntensity: 6_800,
        barSideWashIntensity: 4_600,
        barSideWashX: 0.82,
        storageWashIntensity: 6_400,
        storageWashY: 1.62,
        storageFaceWashIntensity: 4_800,
        storageFaceWashX: 0.78,
        storageSideWashIntensity: 5_000,
        storageSideWashX: 1.10,
        storageSideWashY: 1.58,
        rimWashIntensity: 1_400,
        rimWashPosition: SIMD3(0, 0.92, 0.35),
        imageBasedLightIntensityExponent: 1.95,
        castsObjectShadows: false,
        usesDirectionalKey: false
    )
}

let barbellRoomWallTextMaximumLength = 12

func barbellNormalizedRoomWallText(_ value: String?) -> String? {
    guard let value else { return nil }
    let allowed = CharacterSet.alphanumerics.union(.whitespaces)
    let filteredScalars = value.uppercased().unicodeScalars.map { scalar in
        allowed.contains(scalar) ? Character(scalar) : " "
    }
    let collapsed = String(filteredScalars)
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
    guard !collapsed.isEmpty else { return nil }
    return String(collapsed.prefix(barbellRoomWallTextMaximumLength))
}

struct RoomThemePreset {
    let backdropColor: UIColor
    let backdropMetallic: Float
    let backdropRoughness: Float
    let floorColor: UIColor
    let floorMetallic: Float
    let floorRoughness: Float
    let stripColor: UIColor
    let bumperColor: UIColor
    let bumperMetallic: Float
    let bumperRoughness: Float
    let plateZoneColor: UIColor
    let plateZoneMetallic: Float
    let plateZoneRoughness: Float
    let wallTextColor: UIColor
    let swiftUIBackground: Color

    var floorLuminance: CGFloat {
        floorColor.barbellRelativeLuminance
    }

    var backdropLuminance: CGFloat {
        backdropColor.barbellRelativeLuminance
    }

    var stripLuminance: CGFloat {
        stripColor.barbellRelativeLuminance
    }

    var plateZoneLuminance: CGFloat {
        plateZoneColor.barbellRelativeLuminance
    }

    static func preset(for id: String) -> RoomThemePreset {
        switch id {
        case "concrete_room":
            return RoomThemePreset(
                backdropColor: UIColor(white: 0.46, alpha: 1),
                backdropMetallic: 0, backdropRoughness: 0.96,
                floorColor: UIColor(white: 0.42, alpha: 1),
                floorMetallic: 0.02, floorRoughness: 0.88,
                stripColor: UIColor(white: 0.56, alpha: 1),
                bumperColor: UIColor(white: 0.52, alpha: 1),
                bumperMetallic: 0.06, bumperRoughness: 0.72,
                plateZoneColor: UIColor(white: 0.50, alpha: 1),
                plateZoneMetallic: 0, plateZoneRoughness: 0.94,
                wallTextColor: UIColor(white: 0.30, alpha: 1),
                swiftUIBackground: Color(UIColor(white: 0.34, alpha: 1))
            )
        case "competition_platform":
            return RoomThemePreset(
                backdropColor: UIColor(white: 0.90, alpha: 1),
                backdropMetallic: 0, backdropRoughness: 0.98,
                floorColor: UIColor(red: 0.76, green: 0.58, blue: 0.35, alpha: 1),
                floorMetallic: 0.05, floorRoughness: 0.65,
                stripColor: UIColor(red: 0.86, green: 0.68, blue: 0.43, alpha: 1),
                bumperColor: UIColor(white: 0.82, alpha: 1),
                bumperMetallic: 0.04, bumperRoughness: 0.65,
                plateZoneColor: UIColor(white: 0.96, alpha: 1),
                plateZoneMetallic: 0, plateZoneRoughness: 0.94,
                wallTextColor: UIColor(red: 0.18, green: 0.30, blue: 0.52, alpha: 1),
                swiftUIBackground: Color(UIColor(white: 0.72, alpha: 1))
            )
        case "neon_garage":
            return RoomThemePreset(
                backdropColor: UIColor(red: 0.09, green: 0.10, blue: 0.13, alpha: 1),
                backdropMetallic: 0.02, backdropRoughness: 0.72,
                floorColor: UIColor(red: 0.13, green: 0.15, blue: 0.18, alpha: 1),
                floorMetallic: 0.08, floorRoughness: 0.68,
                stripColor: UIColor(red: 0.16, green: 0.78, blue: 0.94, alpha: 1),
                bumperColor: UIColor(red: 0.18, green: 0.18, blue: 0.24, alpha: 1),
                bumperMetallic: 0.10, bumperRoughness: 0.56,
                plateZoneColor: UIColor(red: 0.16, green: 0.17, blue: 0.22, alpha: 1),
                plateZoneMetallic: 0, plateZoneRoughness: 0.90,
                wallTextColor: UIColor(red: 0.18, green: 0.86, blue: 1.0, alpha: 1),
                swiftUIBackground: Color(UIColor(red: 0.06, green: 0.07, blue: 0.10, alpha: 1))
            )
        case "iron_basement":
            return RoomThemePreset(
                backdropColor: UIColor(red: 0.22, green: 0.21, blue: 0.20, alpha: 1),
                backdropMetallic: 0, backdropRoughness: 0.98,
                floorColor: UIColor(red: 0.18, green: 0.17, blue: 0.16, alpha: 1),
                floorMetallic: 0.03, floorRoughness: 0.90,
                stripColor: UIColor(red: 0.40, green: 0.38, blue: 0.34, alpha: 1),
                bumperColor: UIColor(red: 0.34, green: 0.32, blue: 0.29, alpha: 1),
                bumperMetallic: 0.04, bumperRoughness: 0.78,
                plateZoneColor: UIColor(red: 0.29, green: 0.28, blue: 0.26, alpha: 1),
                plateZoneMetallic: 0, plateZoneRoughness: 0.96,
                wallTextColor: UIColor(red: 0.52, green: 0.50, blue: 0.45, alpha: 1),
                swiftUIBackground: Color(UIColor(red: 0.14, green: 0.13, blue: 0.12, alpha: 1))
            )
        case "daylight_studio":
            return RoomThemePreset(
                backdropColor: UIColor(white: 0.78, alpha: 1),
                backdropMetallic: 0, backdropRoughness: 0.92,
                floorColor: UIColor(white: 0.68, alpha: 1),
                floorMetallic: 0.02, floorRoughness: 0.74,
                stripColor: UIColor(white: 0.88, alpha: 1),
                bumperColor: UIColor(white: 0.74, alpha: 1),
                bumperMetallic: 0.03, bumperRoughness: 0.68,
                plateZoneColor: UIColor(white: 0.86, alpha: 1),
                plateZoneMetallic: 0, plateZoneRoughness: 0.92,
                wallTextColor: UIColor(white: 0.48, alpha: 1),
                swiftUIBackground: Color(UIColor(white: 0.66, alpha: 1))
            )
        case "brick_powerhouse":
            return RoomThemePreset(
                backdropColor: UIColor(red: 0.34, green: 0.16, blue: 0.11, alpha: 1),
                backdropMetallic: 0, backdropRoughness: 0.94,
                floorColor: UIColor(red: 0.24, green: 0.20, blue: 0.18, alpha: 1),
                floorMetallic: 0.04, floorRoughness: 0.82,
                stripColor: UIColor(red: 0.62, green: 0.42, blue: 0.30, alpha: 1),
                bumperColor: UIColor(red: 0.42, green: 0.24, blue: 0.18, alpha: 1),
                bumperMetallic: 0.06, bumperRoughness: 0.70,
                plateZoneColor: UIColor(red: 0.44, green: 0.22, blue: 0.16, alpha: 1),
                plateZoneMetallic: 0, plateZoneRoughness: 0.94,
                wallTextColor: UIColor(red: 0.78, green: 0.58, blue: 0.44, alpha: 1),
                swiftUIBackground: Color(UIColor(red: 0.22, green: 0.11, blue: 0.08, alpha: 1))
            )
        default: // dark_gym
            return RoomThemePreset(
                backdropColor: UIColor(white: 0.27, alpha: 1),
                backdropMetallic: 0, backdropRoughness: 0.88,
                floorColor: UIColor(white: 0.38, alpha: 1),
                floorMetallic: 0.04, floorRoughness: 0.70,
                stripColor: UIColor(white: 0.52, alpha: 1),
                bumperColor: UIColor(white: 0.56, alpha: 1),
                bumperMetallic: 0.08, bumperRoughness: 0.62,
                plateZoneColor: UIColor(white: 0.32, alpha: 1),
                plateZoneMetallic: 0, plateZoneRoughness: 0.96,
                wallTextColor: UIColor(white: 0.50, alpha: 1),
                swiftUIBackground: Color(UIColor(white: 0.29, alpha: 1))
            )
        }
    }
}

private extension UIColor {
    var barbellRelativeLuminance: CGFloat {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 1
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}

struct BarbellRealityView: View {
    let mode: BarbellRealityMode
    let sceneState: SceneState
    var barSkinID: Int = 0
    var rackStyleID: String = "matte_black"
    var roomThemeID: String = "dark_gym"
    var roomWallText: String?
    var allowsInteraction = true
    var showsStorage = true
    /// Floor plates use a 0.38m wide box collider. Keep their centers comfortably inside the
    /// wall inner faces at x=±0.85 so they don't spawn wedged into the side walls.
    private let floorPlateMaxAbsX: Float = 0.64
    /// Last-resort playable bounds for dynamic physics. The visible rails sit wider than the
    /// drag clamp, but still keep plate centers recoverable by touch.
    private let floorPhysicsMaxAbsX: Float = 0.74
    private let floorPhysicsMinZ: Float = -0.10
    private let floorPhysicsMaxZ: Float = 0.82

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ZStack {
            RealityView { content in
                sceneState.sceneRoot   = Entity()
                sceneState.floorAnchor = Entity()
                sceneState.barAnchor   = Entity()
                sceneState.sceneRoot.addChild(sceneState.floorAnchor)
                sceneState.sceneRoot.addChild(sceneState.barAnchor)
                content.add(sceneState.sceneRoot)
                setupLighting(in: sceneState.sceneRoot)

                // IBL: load async after sceneRoot is wired to content.
                // Nested Task so make{} is not blocked -- IBL enhances lighting when available.
                Task { @MainActor in
                    if let ibl = try? await EnvironmentResource(named: "IndoorHDRI") {
                        let iblEntity = Entity()
                        iblEntity.components.set(ImageBasedLightComponent(
                            source: .single(ibl),
                            intensityExponent: RackRoomLightingPreset.readability.imageBasedLightIntensityExponent
                        ))
                        sceneState.sceneRoot.addChild(iblEntity)
                        sceneState.sceneRoot.components.set(
                            ImageBasedLightReceiverComponent(imageBasedLight: iblEntity)
                        )
                    }
                }

                switch mode {
                case .welcome(let plates):
                    setupWelcomeScene(content: &content, plates: plates, barSkinID: barSkinID)
                case .rackRoom(let racked, let floor, _, _):
                    setupRackRoomScene(content: &content, racked: racked, floor: floor, barSkinID: barSkinID, rackStyleID: rackStyleID, roomThemeID: roomThemeID, roomWallText: roomWallText)
                }

                sceneState.configureCameraPosition(for: mode, sizeClass: sizeClass)
            } update: { _ in
                // Intentionally empty -- scene owns its runtime state
            }
            .gesture(entityDragGesture)
            .gesture(welcomeLookGesture)
            .gesture(floorPanGesture)
            .simultaneousGesture(
                TapGesture().onEnded {
                    // Dismiss the info card when the user taps anywhere outside a plate.
                    // Plate taps that show a card are protected by the 400ms debounce in
                    // dismissInfoCard, so same-tap conflicts are suppressed automatically.
                    guard allowsInteraction, case .rackRoom = mode else { return }
                    dismissInfoCard()
                }
            )
            .onChange(of: sizeClass) { _, _ in
                // Re-apply camera proxy on device rotation / iPad split view changes
                sceneState.configureCameraPosition(for: mode, sizeClass: sizeClass)
            }
            .task {
                switch mode {
                case .welcome:
                    guard !BarbellRealityPerformanceBudget.requiresStaticOnlyRendering else { return }
                    sceneState.barbellSpinVelocity = sceneState.barbellSpinVelocity == 0 ? 0.18 : sceneState.barbellSpinVelocity
                    await sceneState.runWelcomeSpinLoop()
                case .rackRoom:
                    await runRackBoundaryLoop()
                }
            }
            .onDisappear {
                sceneState.pauseNonessentialRealityWork()
            }

            overlayView

            // Keep this view to one RealityView. Extra hidden RealityViews can trip
            // RealityKit/Metal debug validation during win-screen presentation.
        }
        // RealityKit's near-clip plane (~0.5m from camera) prevents geometry from reaching
        // the very bottom of the viewport. Fill that gap with a matching floor color so the
        // room appears to extend to the screen edge.
        .background(realityBackgroundColor)
    }

    private var realityBackgroundColor: Color {
        if case .welcome = mode { return .clear }
        return RoomThemePreset.preset(for: roomThemeID).swiftUIBackground
    }

    @MainActor
    private func runRackBoundaryLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(33))
            recoverDynamicFloorPlates()
        }
    }

    @MainActor
    private func recoverDynamicFloorPlates() {
        guard case .rackRoom = mode else { return }
        for entity in sceneState.entityMap.values {
            guard entity.components[PlateRoleComponent.self]?.role == .floor,
                  entity.components[PhysicsBodyComponent.self]?.mode == .dynamic else { continue }

            let scenePos = entity.position(relativeTo: sceneState.sceneRoot)
            let recoveredY: Float
            if scenePos.y < -0.08 {
                recoveredY = 0.08
            } else if scenePos.y > 1.80 {
                recoveredY = 1.80
            } else {
                recoveredY = scenePos.y
            }
            let clamped = SIMD3<Float>(
                max(-floorPhysicsMaxAbsX, min(floorPhysicsMaxAbsX, scenePos.x)),
                recoveredY,
                max(floorPhysicsMinZ, min(floorPhysicsMaxZ, scenePos.z))
            )
            guard clamped != scenePos else { continue }

            // Write in floorAnchor-local space: floorAnchor is a child of sceneRoot with
            // identity rotation and only X translation, so local = sceneRoot_local - floorAnchor.position.
            entity.position = clamped - sceneState.floorAnchor.position
            var motion = entity.components[PhysicsMotionComponent.self] ?? PhysicsMotionComponent()
            if scenePos.x < -floorPhysicsMaxAbsX, motion.linearVelocity.x < 0 { motion.linearVelocity.x *= -0.35 }
            if scenePos.x >  floorPhysicsMaxAbsX, motion.linearVelocity.x > 0 { motion.linearVelocity.x *= -0.35 }
            if scenePos.z < floorPhysicsMinZ, motion.linearVelocity.z < 0 { motion.linearVelocity.z *= -0.25 }
            if scenePos.z > floorPhysicsMaxZ, motion.linearVelocity.z > 0 { motion.linearVelocity.z *= -0.25 }
            motion.linearVelocity.y = min(motion.linearVelocity.y, 0.25)
            motion.angularVelocity *= 0.65
            entity.components[PhysicsMotionComponent.self] = motion
        }
    }

    // MARK: Lighting

    private func setupLighting(in sceneRoot: Entity) {
        let lighting = RackRoomLightingPreset.readability

        // Match BarbellPreviewView's camera-side point light rig so storage plates are lit
        // from the user's viewing direction instead of by a wall-casting directional key.
        let keyEntity = Entity()
        if lighting.usesDirectionalKey {
            var keyLight = DirectionalLightComponent()
            keyLight.color = .white
            keyLight.intensity = lighting.keyIntensity
            keyEntity.components.set(keyLight)
            keyEntity.components.set(DirectionalLightComponent.Shadow(maximumDistance: 2.6, depthBias: 4.5))
            keyEntity.orientation = simd_quatf(angle: -.pi / 4, axis: SIMD3(1, 0, 0))
                * simd_quatf(angle: .pi / 6, axis: SIMD3(0, 1, 0))
        } else {
            keyEntity.components[PointLightComponent.self] = PointLightComponent(
                color: .white, intensity: lighting.keyIntensity, attenuationRadius: 10
            )
            keyEntity.position = lighting.keyPosition
        }
        sceneRoot.addChild(keyEntity)

        // Fill light -- point, no shadow, reduces harsh key-side darkness
        let fillEntity = Entity()
        fillEntity.components[PointLightComponent.self] = PointLightComponent(
            color: UIColor(white: 0.92, alpha: 1), intensity: lighting.fillIntensity, attenuationRadius: 8
        )
        fillEntity.position = lighting.fillPosition
        sceneRoot.addChild(fillEntity)

        let frontWashEntity = Entity()
        frontWashEntity.components[PointLightComponent.self] = PointLightComponent(
            color: UIColor(white: 1.0, alpha: 1), intensity: lighting.frontWashIntensity, attenuationRadius: 7
        )
        frontWashEntity.position = lighting.frontWashPosition
        sceneRoot.addChild(frontWashEntity)

        // Bar wash -- dedicated light at barbell height so racked plates match storage vibrancy.
        // Positioned above and camera-side of the bar (sceneRoot-local y=1.0, z=0.95).
        let barWashEntity = Entity()
        barWashEntity.components[PointLightComponent.self] = PointLightComponent(
            color: .white, intensity: lighting.barWashIntensity, attenuationRadius: 4.5
        )
        barWashEntity.position = SIMD3(0, 1.0, 0.95)
        sceneRoot.addChild(barWashEntity)

        for xSign in [-1.0 as Float, 1.0 as Float] {
            let barSideWashEntity = Entity()
            barSideWashEntity.components[PointLightComponent.self] = PointLightComponent(
                color: UIColor(white: 1.0, alpha: 1),
                intensity: lighting.barSideWashIntensity,
                attenuationRadius: 1.9
            )
            barSideWashEntity.position = SIMD3(xSign * lighting.barSideWashX, 0.92, 0.72)
            sceneRoot.addChild(barSideWashEntity)
        }

        // Storage plates hang high on the wall and are mostly edge-on to camera.
        // Put unshadowed washes at their height so color remains readable.
        let storageWashEntity = Entity()
        storageWashEntity.components[PointLightComponent.self] = PointLightComponent(
            color: UIColor(white: 1.0, alpha: 1), intensity: lighting.storageWashIntensity, attenuationRadius: 5
        )
        storageWashEntity.position = SIMD3(0, lighting.storageWashY, 1.20)
        sceneRoot.addChild(storageWashEntity)

        for xSign in [-1.0 as Float, 1.0 as Float] {
            let storageFaceWashEntity = Entity()
            storageFaceWashEntity.components[PointLightComponent.self] = PointLightComponent(
                color: UIColor(white: 1.0, alpha: 1),
                intensity: lighting.storageFaceWashIntensity,
                attenuationRadius: 1.8
            )
            storageFaceWashEntity.position = SIMD3(xSign * lighting.storageFaceWashX, lighting.storageWashY, 0.82)
            sceneRoot.addChild(storageFaceWashEntity)
        }

        for xSign in [-1.0 as Float, 1.0 as Float] {
            let sideWashEntity = Entity()
            sideWashEntity.components[PointLightComponent.self] = PointLightComponent(
                color: UIColor(white: 1.0, alpha: 1),
                intensity: lighting.storageSideWashIntensity,
                attenuationRadius: 4.5
            )
            sideWashEntity.position = SIMD3(
                xSign * lighting.storageSideWashX,
                lighting.storageSideWashY,
                0.65
            )
            sceneRoot.addChild(sideWashEntity)
        }

        let rimWashEntity = Entity()
        rimWashEntity.components[PointLightComponent.self] = PointLightComponent(
            color: UIColor(red: 0.78, green: 0.88, blue: 1.0, alpha: 1),
            intensity: lighting.rimWashIntensity,
            attenuationRadius: 4.0
        )
        rimWashEntity.position = lighting.rimWashPosition
        sceneRoot.addChild(rimWashEntity)
    }

    // MARK: Welcome scene setup

    private func setupWelcomeScene(content: inout RealityViewCameraContent, plates: [EarnedPlateInfo], barSkinID: Int = 0) {
        let barbellRoot = Entity()
        barbellRoot.position = SIMD3(0, 0.00, -0.02)
        barbellRoot.scale = SIMD3(repeating: 1.78)

        let bar = makeBarEntity(skinID: barSkinID)
        barbellRoot.addChild(bar)
        for xSign: Float in [-1, 1] {
            let collar = makeCollarEntity(skinID: barSkinID)
            collar.position = SIMD3(xSign * 0.475, 0, 0)
            barbellRoot.addChild(collar)
        }
        sceneState.sceneRoot.addChild(barbellRoot)
        sceneState.barbellRoot = barbellRoot
        sceneState.applyWelcomeLook()

        let slotOffsets: [Float] = [0.54, 0.58, 0.62, 0.66]
        for (i, info) in plates.prefix(4).enumerated() {
            let offset = slotOffsets[min(i, slotOffsets.count - 1)]
            for xSign: Float in [-1, 1] {
                let entity = makePlateEntity(
                    tierID: info.tierID,
                    material: sceneState.materialCache[info.tierID],
                    weightKg: info.weightKg,
                    engravingText: info.engravingText,
                    prominentEngraving: info.earnedByEvent.hasPrefix("strength_milestone_"),
                    role: .bar
                )
                entity.name = xSign == 1 ? "welcome_plate_\(i)" : "welcome_plate_\(i)_mirror"
                entity.components.remove(InputTargetComponent.self)
                entity.components.remove(CollisionComponent.self)
                entity.components.remove(PhysicsBodyComponent.self)
                entity.components.remove(PhysicsMotionComponent.self)
                entity.position = SIMD3(xSign * offset, 0, 0)
                #if DEBUG
                attachPlateDebugAxes(to: entity, label: "welcome_\(i)_\(xSign)")
                #endif
                barbellRoot.addChild(entity)
                if xSign == 1 {
                    sceneState.entityMap["welcome_plate_\(i)"] = entity
                }
            }
        }
    }

    // MARK: Overlay

    @ViewBuilder
    private var overlayView: some View {
        switch mode {
        case .welcome:  EmptyView()   // BarbellWelcomeView owns the CTA overlay
        case .rackRoom: EmptyView()   // PlateWallView owns the Done/weight overlay
        }
    }

    // MARK: Mode accessors

    private var onRackCallback: ((EarnedPlate) -> Void)? {
        if case .rackRoom(_, _, let onRack, _) = mode { return onRack }
        return nil
    }

    private var onUnrackCallback: ((EarnedPlate) -> Void)? {
        if case .rackRoom(_, _, _, let onUnrack) = mode { return onUnrack }
        return nil
    }

    private var allFloorPlates: [EarnedPlate] {
        if case .rackRoom(_, let floor, _, _) = mode { return floor }
        return []
    }

    private var allRackedPlates: [EarnedPlate] {
        if case .rackRoom(let racked, _, _, _) = mode { return racked }
        return []
    }

    // MARK: Gestures

    private var entityDragGesture: some Gesture {
        // minimumDistance: 1 (down from 4) so bar swipes fire after just 1pt of movement.
        // Floor plate drags work fine at 1pt -- that threshold is still intentional.
        // Bar unrack additionally gates on horizontal direction (see .bar case below)
        // so vertical scrolls near the bar don't accidentally trigger unrack.
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .targetedToAnyEntity()
            .onChanged { value in
                guard allowsInteraction else { return }
                guard case .rackRoom = mode else { return }
                let entity = value.entity
                guard let roleComp = entity.components[PlateRoleComponent.self] else { return }

                switch roleComp.role {
                case .floor:
                    // Stored plates require clear vertical intent. A horizontal-dominant gesture
                    // is almost certainly a bar swipe that bled onto this entity -- ignore it.
                    if sceneState.storageSlotByPlate[entity.name] != nil {
                        let dx = abs(value.translation.width)
                        let dy = abs(value.translation.height)
                        // Require vertical-dominant AND minimum movement.
                        // Short touches (< 8pt total) stay in .idle so onEnded can treat them as taps.
                        guard dy >= dx, (dx + dy) > 8 else { break }
                    }
                    // One-time: enter dragging state (captures originRole) and reparent to scene root.
                    // transition() rejects .draggingPlate -> .draggingPlate, so call it
                    // unconditionally but only run reparent when it succeeds.
                    if sceneState.transition(to: .draggingPlate(entity, plateID: entity.name, originRole: .floor)) {
                        // Cancel any pending settle timer for this plate. If not cancelled,
                        // the old timer will fire during a later freeDrop fall and freeze
                        // the plate kinematic mid-air.
                        sceneState.settleTasks[entity.name]?.cancel()
                        sceneState.settleTasks[entity.name] = nil
                        // If this plate is in a storage slot, free the slot before dragging.
                        if let slotIdx = sceneState.storageSlotByPlate[entity.name] {
                            sceneState.dragOriginStorageSlot = slotIdx
                            sceneState.storageSlotByPlate.removeValue(forKey: entity.name)
                            sceneState.storageSlotByIndex.removeValue(forKey: slotIdx)
                            var mat = UnlitMaterial()
                            mat.color = .init(tint: UIColor(white: 0.50, alpha: 1))
                            sceneState.setSlotMaterial(mat, atIndex: slotIdx)
                            sceneState.setStorageSlotRingEnabled(true, atIndex: slotIdx)
                        }
                        // Lock kinematic before reparenting so a plate that is still
                        // settling from a previous freeDrop doesn't fight the gesture.
                        entity.components[PhysicsBodyComponent.self]?.mode = .kinematic
                        entity.setParent(sceneState.sceneRoot, preservingWorldTransform: true)
                        sceneState.dragStartEntityPosition = entity.position
                        #if DEBUG
                        barbellLog("DRAG_START", "id=\(entity.name) role=floor local=\(v3(entity.position)) world=\(v3(entity.position(relativeTo: nil)))")
                        #endif
                    }
                    // Guard: ensure we own this drag before updating position each frame.
                    // originRole: .bar drags are slide-and-release -- suppress continued drag so
                    // the 200ms slide animation never fights a concurrent position update loop.
                    guard case .draggingPlate(let dragging, _, let originRole) = sceneState.dragPhase,
                          dragging === entity,
                          originRole == .floor else { return }

                    // Map cumulative screen-space drag to sceneRoot-local world offset.
                    // Scale ~0.004 m/pt: sceneRoot at z=-1.4, ~60deg FOV -> 1.62m visible/~393pt.
                    // Screen Y is inverted relative to world Y.
                    let s: Float = 0.004
                    let rawPos = sceneState.dragStartEntityPosition
                        + SIMD3(Float(value.translation.width) * s,
                                Float(-value.translation.height) * s, 0)
                    // Clamp to physics-safe zone: keep the current floor-plate collider width
                    // clear of the side walls so dragged plates don't get pinned at release.
                    // Y clamped above floor and below top wall.
                    entity.position = SIMD3(
                        clampFloorPlateX(rawPos.x, maxAbsX: floorPlateMaxAbsX),
                        max(0.05, min(1.85, rawPos.y)),
                        rawPos.z
                    )

                    // Zone detection: storage (above bar) takes priority over bar zone.
                    // barAnchor.position is in sceneRoot-local space (its parent).
                    let barLocalY = sceneState.barAnchor.position.y
                    let entityLocalY = entity.position.y
                    // Storage zone: Y above bar by 0.50m (midpoint between bar ~0.60 and slots ~1.60).
                    let inStorageZone = entityLocalY > barLocalY + 0.50
                    // Bar zone: Y within 0.2m below the bar, but not in storage zone above.
                    let inBarZone = !inStorageZone && entityLocalY > barLocalY - 0.2

                    if inStorageZone {
                        // Show storage slot hover; hide bar highlights.
                        sceneState.slotHighlights.forEach { $0.isEnabled = false }
                        sceneState.wasInSnapZone = false

                        let entityX = entity.position.x
                        var newHovered: Int? = nil
                        for (i, pos) in sceneState.storageSlotPositions.enumerated() {
                            guard sceneState.storageSlotByIndex[i] == nil else { continue }
                            if abs(entityX - pos.x) < 0.16 {
                                newHovered = i
                                break
                            }
                        }
                        if newHovered != sceneState.hoveredStorageSlotIndex {
                            if let prev = sceneState.hoveredStorageSlotIndex,
                               sceneState.storageSlotByIndex[prev] == nil {
                                var mat = UnlitMaterial()
                                mat.color = .init(tint: UIColor(white: 0.50, alpha: 1))
                                sceneState.setSlotMaterial(mat, atIndex: prev)
                            }
                            if let curr = newHovered {
                                var mat = UnlitMaterial()
                                mat.color = .init(tint: UIColor(white: 0.90, alpha: 1))
                                sceneState.setSlotMaterial(mat, atIndex: curr)
                            }
                            sceneState.hoveredStorageSlotIndex = newHovered
                        }
                    } else if inBarZone {
                        let occupiedSlots = allRackedPlates.compactMap(\.rackPosition)
                        if let nextSlot = (0..<4).first(where: { !occupiedSlots.contains($0) }),
                           nextSlot < sceneState.slotHighlights.count {
                            sceneState.slotHighlights.forEach { $0.isEnabled = false }
                            sceneState.slotHighlights[nextSlot].isEnabled = true
                        }
                        if !sceneState.wasInSnapZone {
                            playSnapZoneEntryHaptic()
                            sceneState.wasInSnapZone = true
                        }
                        // Clear any storage slot hover when plate enters bar zone.
                        if let prev = sceneState.hoveredStorageSlotIndex,
                           sceneState.storageSlotByIndex[prev] == nil {
                            var mat = UnlitMaterial()
                            mat.color = .init(tint: UIColor(white: 0.50, alpha: 1))
                            sceneState.setSlotMaterial(mat, atIndex: prev)
                            sceneState.hoveredStorageSlotIndex = nil
                        }
                    } else {
                        sceneState.slotHighlights.forEach { $0.isEnabled = false }
                        sceneState.wasInSnapZone = false
                        // Clear storage slot hover when plate is in neither zone.
                        if let prev = sceneState.hoveredStorageSlotIndex,
                           sceneState.storageSlotByIndex[prev] == nil {
                            var mat = UnlitMaterial()
                            mat.color = .init(tint: UIColor(white: 0.50, alpha: 1))
                            sceneState.setSlotMaterial(mat, atIndex: prev)
                            sceneState.hoveredStorageSlotIndex = nil
                        }
                    }

                case .bar:
                    guard case .idle = sceneState.dragPhase else { return }
                    // Direction gate: horizontal component must exceed vertical so a vertical scroll
                    // near the bar doesn't trigger unrack. Checked early so accidental near-vertical
                    // swipes return without consuming the gesture state.
                    let dx = abs(value.translation.width)
                    let dy = abs(value.translation.height)
                    guard dx > dy * 0.8 else { return }
                    // Any swipe on any bar entity (racked plate or hit zone) unracks the outermost
                    // plate (highest rackPosition). Both sides always slide outward simultaneously:
                    // main entity (positive X) slides right, mirror (negative X) slides left.
                    // Subsequent .floor-routed onChanged events are suppressed (originRole: .bar guard
                    // below) so the slide animation never fights the drag position update loop.
                    let outermostPlate = allRackedPlates.max(by: { ($0.rackPosition ?? -1) < ($1.rackPosition ?? -1) })
                    guard let outermostID = outermostPlate?.id,
                          !sceneState.platesBeingUnracked.contains(outermostID),
                          let outermostEntity = sceneState.entityMap[outermostID] else { return }
                    guard sceneState.transition(to: .draggingPlate(outermostEntity, plateID: outermostID, originRole: .bar)) else { return }
                    #if DEBUG
                    barbellLog("DRAG_START", "id=\(outermostID) role=bar(outermost) touched=\(entity.name) world=\(v3(outermostEntity.position(relativeTo: nil)))")
                    #endif
                    barbellDiagnosticsLog(
                        "UNRACK_START",
                        "id=\(outermostID) touched=\(entity.name) dx=\(String(format: "%.1f", dx)) dy=\(String(format: "%.1f", dy)) world=\(barbellDiagnosticsV3(outermostEntity.position(relativeTo: nil)))"
                    )
                    // Target world X = ±0.84: safely inside the wall inner face (±0.85) so
                    // neither plate overshoots the wall. Fixed target instead of +offset because
                    // the offset varies by slot (0.60-0.72) and a relative offset can overshoot.
                    let outerWorldPos = outermostEntity.position(relativeTo: nil)
                    let slideTargetX: Float = 0.78
                    let slideTargetZ: Float = 0.30
                    let slideTarget = Transform(
                        scale: outermostEntity.scale,
                        rotation: outermostEntity.orientation,
                        translation: SIMD3(slideTargetX, outerWorldPos.y - 0.02, slideTargetZ)
                    )
                    let slideOutDuration = barbellRackRoomSlideOutDuration(isReduceMotionEnabled: sceneState.isReduceMotionEnabled)
                    // DO NOT call setParent here. Reparenting cancels any in-flight move() animation.
                    // Entity stays on barAnchor so the slide runs to completion.
                    // snapToFloor (called from onEnded) does the setParent(floorAnchor).
                    outermostEntity.move(to: slideTarget, relativeTo: nil, duration: slideOutDuration, timingFunction: .easeOut)
                    // Mirror slides to -slideTargetX and is removed after the animation.
                    // Removing at 200ms (animation end) prevents the ghost-plate-behind-wall
                    // problem: the mirror has no physics, so it would sit past the wall until
                    // finishUnrack fires at 1400ms. finishUnrack still handles the unrack
                    // callback and barPositionMap cleanup; it no-ops on the already-gone mirror.
                    if let mirrorEntity = sceneState.barMirrorMap[outermostID] {
                        let mirrorWorldPos = mirrorEntity.position(relativeTo: nil)
                        let mirrorSlideTarget = Transform(
                            scale: mirrorEntity.scale,
                            rotation: mirrorEntity.orientation,
                            translation: SIMD3(-slideTargetX, mirrorWorldPos.y - 0.02, slideTargetZ)
                        )
                        mirrorEntity.move(to: mirrorSlideTarget, relativeTo: nil, duration: slideOutDuration, timingFunction: .easeOut)
                        let capturedMirror = mirrorEntity
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(Int(slideOutDuration * 1000)))
                            capturedMirror.removeFromParent()
                            sceneState.barMirrorMap.removeValue(forKey: outermostID)
                        }
                    }
                    outermostEntity.components.set(PlateRoleComponent(role: .floor))
                }
            }
            .onEnded { value in
                guard allowsInteraction else { return }
                let tapped = value.entity
                // Tap detection: dragPhase stayed .idle means onChanged never committed a drag
                // (storage plate movement < 8pt threshold). Treat as info-card tap.
                if case .rackRoom = mode, case .idle = sceneState.dragPhase {
                    let tapID = tapped.name.replacingOccurrences(of: "_mirror", with: "")
                    if tapped.components[PlateRoleComponent.self] != nil,
                       tapped.name != "barHitZone",
                       sceneState.entityMap[tapID] != nil {
                        if sceneState.infoCardPlateID == tapID {
                            dismissInfoCard()
                        } else {
                            showInfoCard(for: tapID)
                        }
                        return
                    }
                }

                guard case .draggingPlate(let entity, let plateID, let originRole) = sceneState.dragPhase else { return }
                sceneState.transition(to: .idle)
                sceneState.slotHighlights.forEach { $0.isEnabled = false }
                sceneState.wasInSnapZone = false

                // Reset any highlighted storage slot back to normal state.
                if let prev = sceneState.hoveredStorageSlotIndex,
                   sceneState.storageSlotByIndex[prev] == nil {
                    var mat = UnlitMaterial()
                    mat.color = .init(tint: UIColor(white: 0.50, alpha: 1))
                    sceneState.setSlotMaterial(mat, atIndex: prev)
                }
                let pendingSlot = sceneState.hoveredStorageSlotIndex
                sceneState.hoveredStorageSlotIndex = nil
                let capturedOriginSlot = sceneState.dragOriginStorageSlot
                sceneState.dragOriginStorageSlot = nil

                // Use originRole captured at drag-start -- not re-querying allFloorPlates,
                // which could reflect a concurrent model mutation.
                let isFromFloor = originRole == .floor
                // Bar-origin plates stay on barAnchor through the slide animation (setParent
                // deferred to snapToFloor). Use world-space Y for the snap-zone check so
                // comparison is coordinate-space-independent regardless of parent.
                let entityY = entity.position(relativeTo: nil).y
                let barWorldY = sceneState.barAnchor.position(relativeTo: nil).y

                #if DEBUG
                let decision = isFromFloor && entityY > barWorldY - 0.15 ? "snapToBar"
                    : !isFromFloor ? "snapToFloor"
                    : "freeDrop"
                barbellLog("DRAG_END", "id=\(plateID) fromFloor=\(isFromFloor) entityY=\(String(format:"%.3f",entityY)) barWorldY=\(String(format:"%.3f",barWorldY)) -> \(decision)")
                barbellLog("DRAG_END", "  entity.pos=\(v3(entity.position)) world=\(v3(entity.position(relativeTo: nil))) phys=\(String(describing:entity.components[PhysicsBodyComponent.self]?.mode))")
                #endif
                let diagnosticDecision: String
                if isFromFloor, pendingSlot != nil {
                    diagnosticDecision = "snapToStorage"
                } else if isFromFloor && entityY > barWorldY - 0.15 && entityY < barWorldY + 0.50 {
                    diagnosticDecision = "snapToBar"
                } else if !isFromFloor {
                    diagnosticDecision = "snapToFloor"
                } else {
                    diagnosticDecision = "freeDrop"
                }
                barbellDiagnosticsLog(
                    "DRAG_END",
                    "id=\(plateID) origin=\(originRole) decision=\(diagnosticDecision) translation=(\(String(format: "%.1f", value.translation.width)),\(String(format: "%.1f", value.translation.height))) velocity=(\(String(format: "%.1f", value.velocity.width)),\(String(format: "%.1f", value.velocity.height))) entityY=\(String(format: "%.3f", entityY)) barY=\(String(format: "%.3f", barWorldY)) local=\(barbellDiagnosticsV3(entity.position)) world=\(barbellDiagnosticsV3(entity.position(relativeTo: nil))) physics=\(String(describing: entity.components[PhysicsBodyComponent.self]?.mode)) pendingSlot=\(pendingSlot.map(String.init) ?? "nil")"
                )
                if isFromFloor, let slotIdx = pendingSlot {
                    snapToStorageSlot(entity: entity, plateID: plateID, slotIndex: slotIdx)
                } else if isFromFloor && entityY > barWorldY - 0.15 && entityY < barWorldY + 0.50 {
                    snapToBar(entity: entity, plateID: plateID, gestureVelocity: value.velocity)
                } else if !isFromFloor {
                    // Swipe direction encodes intent:
                    //   Upward swipe (height < -60 pt, negative = up in UIKit coords) → storage.
                    //   Sideways/downward swipe → physics floor for freeplay.
                    // From the floor the user can drag a plate back up to the storage zone.
                    let swipedUpward = value.translation.height < -60
                    let targetSlot = swipedUpward ? sceneState.findFreeStorageSlot() : nil
                    let plateToUnrack = allRackedPlates.first(where: { $0.id == plateID })
                    // Delay 200ms to let the slide animation finish before reparenting.
                    // setParent cancels in-flight animations, so we must wait.
                    let delay = Int(barbellRackRoomSlideOutDuration(isReduceMotionEnabled: sceneState.isReduceMotionEnabled) * 1000)
                    sceneState.platesBeingUnracked.insert(plateID)
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(delay))
                        if let slot = targetSlot {
                            // Reparent from barAnchor to sceneRoot before storage snap.
                            entity.setParent(sceneState.sceneRoot, preservingWorldTransform: true)
                            entity.components[PhysicsBodyComponent.self]?.mode = .kinematic
                            snapToStorageSlot(entity: entity, plateID: plateID, slotIndex: slot)
                            finishUnrack(plateID: plateID, plate: plateToUnrack)
                            sceneState.platesBeingUnracked.remove(plateID)
                        } else {
                            snapToFloor(entity: entity, plateID: plateID)
                            // snapToFloor clears platesBeingUnracked after its own 16ms physics task
                        }
                    }
                } else if let slotIdx = capturedOriginSlot {
                    // Storage plate not racked and not hovered over a different slot:
                    // return it to its original storage slot.
                    snapToStorageSlot(entity: entity, plateID: plateID, slotIndex: slotIdx)
                } else {
                    // True floor plate (unracked from bar): drop wherever released.
                    // Fling velocity is applied so fast releases travel across the scene.
                    freeDrop(entity: entity, plateID: plateID, gestureVelocity: value.velocity)
                }
            }
    }

    private var welcomeLookGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                guard case .welcome = mode else { return }
                if !sceneState.isDraggingWelcome {
                    sceneState.isDraggingWelcome = true
                    sceneState.welcomeDragStartAngle = sceneState.barbellSpinAngle
                    sceneState.welcomeDragStartPitch = sceneState.welcomePitchAngle
                }
                sceneState.barbellSpinAngle = sceneState.welcomeDragStartAngle + Float(value.translation.width) * 0.010
                let pitch = sceneState.welcomeDragStartPitch + Float(-value.translation.height) * 0.004
                sceneState.welcomePitchAngle = max(-0.28, min(0.22, pitch))
                sceneState.applyWelcomeLook()
            }
            .onEnded { value in
                guard case .welcome = mode else { return }
                sceneState.isDraggingWelcome = false
                sceneState.barbellSpinVelocity = max(-2.2, min(2.2, Float(value.velocity.width) * 0.0025))
            }
    }

    private var floorPanGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                guard allowsInteraction else { return }
                guard case .rackRoom = mode else { return }
                // Attempt transition to .panningFloor; also allow if already panning
                let alreadyPanning: Bool
                if case .panningFloor = sceneState.dragPhase { alreadyPanning = true } else { alreadyPanning = false }
                guard sceneState.transition(to: .panningFloor) || alreadyPanning else { return }

                // translation.width is cumulative from gesture start -- compute real per-event delta
                let current = Float(value.translation.width)
                let delta = (current - sceneState.floorPanLastTranslation) * -0.002
                sceneState.floorPanLastTranslation = current
                let raw = sceneState.floorOffset + delta
                sceneState.floorOffset = max(sceneState.floorMinX, min(sceneState.floorMaxX, raw))
                sceneState.floorAnchor.position.x = -sceneState.floorOffset
                sceneState.floorVelocity = delta * 60
            }
            .onEnded { _ in
                guard allowsInteraction else { return }
                guard case .rackRoom = mode else { return }
                sceneState.floorPanLastTranslation = 0
                sceneState.transition(to: .idle)
                guard !sceneState.isReduceMotionEnabled else {
                    sceneState.floorVelocity = 0
                    return
                }
                Task { @MainActor in
                    while abs(sceneState.floorVelocity) > 0.001 {
                        try? await Task.sleep(for: .milliseconds(16))
                        sceneState.floorVelocity *= 0.90
                        let raw = sceneState.floorOffset - sceneState.floorVelocity * 0.016
                        sceneState.floorOffset = max(sceneState.floorMinX, min(sceneState.floorMaxX, raw))
                        sceneState.floorAnchor.position.x = -sceneState.floorOffset
                    }
                    sceneState.floorVelocity = 0
                }
            }
    }

    // MARK: - Snap animations

    private func snapToBar(entity: Entity, plateID: String, gestureVelocity: CGSize = .zero) {
        #if DEBUG
        barbellLog("SNAP_BAR", "id=\(plateID) pos=\(v3(entity.position)) world=\(v3(entity.position(relativeTo: nil)))")
        #endif
        barbellDiagnosticsLog("SNAP_BAR", "id=\(plateID) local=\(barbellDiagnosticsV3(entity.position)) world=\(barbellDiagnosticsV3(entity.position(relativeTo: nil)))")
        let slotOffsets: [Float] = [0.600, 0.652, 0.704, 0.756]
        let occupiedSlots = allRackedPlates.compactMap(\.rackPosition)
        guard let nextSlot = (0..<4).first(where: { !occupiedSlots.contains($0) }) else {
            #if DEBUG
            barbellLog("SNAP_BAR", "id=\(plateID) NO SLOT AVAILABLE -> freeDrop")
            #endif
            freeDrop(entity: entity, plateID: plateID, gestureVelocity: gestureVelocity)
            return
        }
        let offset = slotOffsets[nextSlot]
        let slotPos = SIMD3<Float>(offset, 0, 0) // bar-anchor local space: y=0 is bar centerline
        let rot = plateBarOrientation

        entity.setParent(sceneState.barAnchor, preservingWorldTransform: true)
        entity.components.set(PlateRoleComponent(role: .bar))

        // Bilateral mirror entity for the opposite side of the bar.
        // Stored in barMirrorMap so finishUnrack / snapBack can remove it without a scene search.
        // Clone copies ALL components -- remove interaction/physics so the mirror is purely visual.
        let mirrorEntity = entity.clone(recursive: true)
        mirrorEntity.name = plateID + "_mirror"
        mirrorEntity.components.set(PlateRoleComponent(role: .bar))
        mirrorEntity.components.remove(InputTargetComponent.self)
        mirrorEntity.components.remove(CollisionComponent.self)
        mirrorEntity.components.remove(PhysicsBodyComponent.self)
        mirrorEntity.components.remove(PhysicsMotionComponent.self)
        // Flip mirror to the opposite X immediately before adding to the scene so it never
        // occupies the same position as the source entity. Without this, both entities share
        // the same world position for the first render frame, producing a doubled/melt artifact.
        let ePos = entity.position
        mirrorEntity.position = SIMD3(-ePos.x, ePos.y, ePos.z)
        sceneState.barAnchor.addChild(mirrorEntity)
        sceneState.barMirrorMap[plateID] = mirrorEntity

        if sceneState.isReduceMotionEnabled {
            entity.position = slotPos
            entity.orientation = rot
            mirrorEntity.position = SIMD3(-offset, 0, 0)
            mirrorEntity.orientation = rot
        } else {
            // Spring snap: overshoot 2.5cm above slot then settle
            for (e, xSign) in [(entity, Float(1)), (mirrorEntity, Float(-1))] {
                let overshoot = Transform(scale: SIMD3(repeating: 1), rotation: rot,
                                          translation: SIMD3(xSign * offset, slotPos.y + 0.025, 0))
                let settle    = Transform(scale: SIMD3(repeating: 1), rotation: rot,
                                          translation: SIMD3(xSign * offset, slotPos.y, 0))
                e.move(to: overshoot, relativeTo: sceneState.barAnchor, duration: 0.15, timingFunction: .easeOut)
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(150))
                    e.move(to: settle, relativeTo: sceneState.barAnchor, duration: 0.12, timingFunction: .easeIn)
                }
            }
        }

        sceneState.barPositionMap[plateID] = slotPos

        let animDelay = sceneState.isReduceMotionEnabled ? 0 : 270
        // Capture before the async boundary to avoid stale allFloorPlates reads if the model
        // is mutated by a concurrent onRack callback from a second plate.
        let plateToRack = allFloorPlates.first(where: { $0.id == plateID })
        let audioComp = entity.components[PlateAudioCategoryComponent.self]
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(animDelay))
            if let plate = plateToRack {
                onRackCallback?(plate)
                if let audio = audioComp {
                    playClinkSound(on: entity, category: audio.category)
                    playRackHaptic(category: audio.category)
                }
            }
        }
    }

    private func snapToFloor(entity: Entity, plateID: String) {
        #if DEBUG
        barbellLog("SNAP_FLOOR", "id=\(plateID) BEFORE setParent: pos=\(v3(entity.position)) world=\(v3(entity.position(relativeTo: nil))) phys=\(String(describing:entity.components[PhysicsBodyComponent.self]?.mode))")
        #endif
        barbellDiagnosticsLog(
            "SNAP_FLOOR_BEGIN",
            "id=\(plateID) local=\(barbellDiagnosticsV3(entity.position)) world=\(barbellDiagnosticsV3(entity.position(relativeTo: nil))) physics=\(String(describing: entity.components[PhysicsBodyComponent.self]?.mode))"
        )
        // Reparent to sceneRoot (not floorAnchor) for bar→floor transitions.
        // floorAnchor is always at local (0,0,0) inside sceneRoot — floor panning is
        // disabled (floorMinX == floorMaxX == 0) so the two are positionally identical.
        // sceneRoot is the grandparent of barAnchor; reparenting child→grandparent is
        // cheaper in RealityKit than sibling→sibling (barAnchor→floorAnchor), which
        // triggers a full render graph re-evaluation and 19 AR material re-resolves.
        // Using local-space setters after setParent(preservingWorldTransform: false)
        // avoids setTransformMatrix(relativeTo: nil) (see earlier fix in this function).
        let worldPos = entity.position(relativeTo: nil)
        let worldRot = entity.orientation(relativeTo: nil)
        let anchorWorldPos = sceneState.sceneRoot.position(relativeTo: nil)
        entity.setParent(sceneState.sceneRoot, preservingWorldTransform: false)
        entity.position = worldPos - anchorWorldPos
        entity.orientation = worldRot
        entity.components.set(PlateRoleComponent(role: .floor))
        #if DEBUG
        barbellLog("SNAP_FLOOR", "id=\(plateID) AFTER  setParent: pos=\(v3(entity.position)) floorAnchor=\(v3(sceneState.floorAnchor.position))")
        #endif
        barbellDiagnosticsLog(
            "SNAP_FLOOR_REPARENTED",
            "id=\(plateID) local=\(barbellDiagnosticsV3(entity.position)) world=\(barbellDiagnosticsV3(entity.position(relativeTo: nil))) sceneRoot=\(barbellDiagnosticsV3(sceneState.sceneRoot.position))"
        )

        // Preserve upright bar orientation -- plate tumbles naturally under physics.
        // Hand physics a clean release pose in front of the bar path. If the dynamic body
        // starts too close to the sleeve/wall/floor, RealityKit can resolve the overlap by
        // pinning the plate at a strange leaning angle.
        let wPos = entity.position(relativeTo: nil)
        let releaseX = max(-floorPhysicsMaxAbsX, min(floorPhysicsMaxAbsX, wPos.x))
        let releaseY = max(wPos.y, sceneState.barAnchor.position(relativeTo: nil).y + 0.04)
        let releaseZ = max(wPos.z, 0.30)
        // Write in floorAnchor-local space to avoid setPosition(relativeTo: nil),
        // which marks the RealityKit render graph dirty and triggers 19 AR material
        // re-resolves per call (confirmed in the setParent fix above).
        let anchorWPos = sceneState.sceneRoot.position(relativeTo: nil)
        entity.position = SIMD3(releaseX - anchorWPos.x, releaseY - anchorWPos.y, releaseZ - anchorWPos.z)

        // Enable physics on the next frame. RealityKit can otherwise start dynamics from an
        // older kinematic body pose even though the visual move() finished at slideTargetX.
        // Clearing motion here avoids drag/animation velocity bleed into the fall.
        entity.components[PhysicsMotionComponent.self] = PhysicsMotionComponent()
        entity.components[PhysicsBodyComponent.self]?.mode = .kinematic
        let spinDir: Float = Bool.random() ? 1 : -1
        let spreadDir: Float = Bool.random() ? 1 : -1
        sceneState.settleTasks[plateID]?.cancel()
        sceneState.settleTasks[plateID] = nil
        let plateToUnrack = allRackedPlates.first(where: { $0.id == plateID })
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(16))
            guard entity.components[PlateRoleComponent.self]?.role == .floor else {
                barbellDiagnosticsLog(
                    "SNAP_FLOOR_DYNAMIC_SKIPPED",
                    "id=\(plateID) reason=roleChanged role=\(String(describing: entity.components[PlateRoleComponent.self]?.role))"
                )
                finishUnrack(plateID: plateID, plate: plateToUnrack)
                sceneState.platesBeingUnracked.remove(plateID)
                return
            }
            var motion = PhysicsMotionComponent()
            motion.angularVelocity = SIMD3(
                Float.random(in: -0.35 ..< 0.35),
                spinDir * Float.random(in: 1.2 ..< 2.2),
                Float.random(in: -0.25 ..< 0.25)
            )
            // Spread unracked plates so they don't all land in the same spot.
            // Every plate slides to the same slideTargetX, so without a lateral nudge
            // they stack on top of each other when multiple plates are removed.
            motion.linearVelocity = SIMD3(spreadDir * Float.random(in: 0.30 ..< 0.65), -0.20, 0.18)
            entity.components[PhysicsMotionComponent.self] = motion
            entity.components[PhysicsBodyComponent.self]?.mode = .dynamic
            sceneState.platesBeingUnracked.remove(plateID)
            if let audio = entity.components[PlateAudioCategoryComponent.self] {
                scheduleDropFeedback(on: entity, category: audio.category, delay: 0.42)
            }
            #if DEBUG
            barbellLog("SNAP_FLOOR", "id=\(plateID) physics=dynamic pos_after_clamp=\(v3(entity.position))")
            #endif
            barbellDiagnosticsLog(
                "SNAP_FLOOR_DYNAMIC",
                "id=\(plateID) local=\(barbellDiagnosticsV3(entity.position)) world=\(barbellDiagnosticsV3(entity.position(relativeTo: nil))) motionLinear=\(barbellDiagnosticsV3(motion.linearVelocity))"
            )
            finishUnrack(plateID: plateID, plate: plateToUnrack)
        }
    }

    /// plate is pre-captured by the caller before any async gap to avoid stale allRackedPlates reads.
    private func finishUnrack(plateID: String, plate: EarnedPlate?) {
        barbellDiagnosticsLog(
            "FINISH_UNRACK",
            "id=\(plateID) plateFound=\(plate != nil) mirrorFound=\(sceneState.barMirrorMap[plateID] != nil) barPositionFound=\(sceneState.barPositionMap[plateID] != nil)"
        )
        if let plate { onUnrackCallback?(plate) }
        sceneState.barMirrorMap[plateID]?.removeFromParent()
        sceneState.barMirrorMap.removeValue(forKey: plateID)
        sceneState.barPositionMap.removeValue(forKey: plateID)
    }

    private func snapToStorageSlot(entity: Entity, plateID: String, slotIndex: Int) {
        guard sceneState.isValidStorageSlot(slotIndex) else {
            #if DEBUG
            barbellLog("SNAP_STORAGE", "id=\(plateID) stale slot=\(slotIndex), positions=\(sceneState.storageSlotPositions.count) -> freeDrop")
            #endif
            freeDrop(entity: entity, plateID: plateID)
            return
        }

        // Ensure entity is in sceneRoot space. Bar-origin plates arrive on barAnchor;
        // floor-origin plates are already in sceneRoot (reparented at drag start).
        if entity.parent !== sceneState.sceneRoot {
            entity.setParent(sceneState.sceneRoot, preservingWorldTransform: true)
        }
        let slotPos = sceneState.storageSlotPositions[slotIndex]
        // Plate floats at slot Y (1.60) -- same height as the bracket markers.
        let targetPos = SIMD3<Float>(slotPos.x, slotPos.y, slotPos.z)
        // Storage slots present plates side-on, matching how plates hang on the bar sleeves.
        let targetRot = plateDisplayOrientation
        let target = Transform(scale: entity.scale, rotation: targetRot, translation: targetPos)

        if sceneState.isReduceMotionEnabled {
            entity.position = targetPos
            entity.orientation = targetRot
        } else {
            // Entity is a child of sceneRoot during drag -- animate in sceneRoot local space.
            entity.move(to: target, relativeTo: sceneState.sceneRoot, duration: 0.35, timingFunction: .easeOut)
        }

        // Record occupancy and hide the ring.
        sceneState.storageSlotByIndex[slotIndex] = plateID
        sceneState.storageSlotByPlate[plateID] = slotIndex
        sceneState.setStorageSlotRingEnabled(false, atIndex: slotIndex)
    }
    private func snapBack(entity: Entity, plateID: String) {
        if let roleComp = entity.components[PlateRoleComponent.self], roleComp.role == .bar,
           let barPos = sceneState.barPositionMap[plateID] {
            // Return bar plate to its slot
            entity.setParent(sceneState.barAnchor, preservingWorldTransform: true)
            let rot = plateBarOrientation
            let target = Transform(scale: SIMD3(repeating: 1), rotation: rot, translation: barPos)
            if sceneState.isReduceMotionEnabled {
                entity.position = barPos
                entity.orientation = rot
            } else {
                entity.move(to: target, relativeTo: sceneState.barAnchor, duration: 0.2, timingFunction: .easeOut)
            }
        } else if let target = sceneState.originalTransforms[plateID] {
            // Storage plates (original Y > 1.0) live in sceneRoot space.
            // Floor plates (unracked from bar) live in floorAnchor space.
            let isStorage = target.translation.y > 1.0
            let parent: Entity = isStorage ? sceneState.sceneRoot : sceneState.floorAnchor
            entity.setParent(parent, preservingWorldTransform: true)
            if sceneState.isReduceMotionEnabled {
                entity.transform = parent.convert(transform: target, from: nil)
            } else {
                entity.move(to: target, relativeTo: nil, duration: 0.2, timingFunction: .easeOut)
            }
            if isStorage {
                // Re-register the storage slot so the ring stays hidden and the slot appears occupied.
                let origX = target.translation.x
                if let match = sceneState.storageSlotPositions.enumerated().min(by: {
                    abs($0.element.x - origX) < abs($1.element.x - origX)
                }) {
                    sceneState.storageSlotByIndex[match.offset] = plateID
                    sceneState.storageSlotByPlate[plateID] = match.offset
                    sceneState.setStorageSlotRingEnabled(false, atIndex: match.offset)
                }
            }
        }
    }

    /// Drops a floor plate wherever the user released it, applying gesture fling velocity.
    /// Used instead of snapBack when the bar is full or the plate was not dragged high enough.
    /// The plate physics-settles and its originalTransform is updated to the new resting position.
    private func freeDrop(entity: Entity, plateID: String, gestureVelocity: CGSize = .zero) {
        entity.setParent(sceneState.floorAnchor, preservingWorldTransform: true)
        entity.components.set(PlateRoleComponent(role: .floor))

        // Physics path: preserve orientation at release so the plate tumbles naturally.
        // Angular velocity is applied below when fling speed is significant.
        // Clamp in sceneRoot space, where floor/walls actually exist.
        let scenePos = entity.position(relativeTo: sceneState.sceneRoot)
        let clampedScene = SIMD3<Float>(
            clampFloorPlateX(scenePos.x, maxAbsX: floorPlateMaxAbsX),
            max(0.10, min(1.5, scenePos.y)),
            scenePos.z
        )
        if clampedScene != scenePos {
            entity.setPosition(clampedScene, relativeTo: sceneState.sceneRoot)
        }

        // Kinematic bodies accumulate implicit velocity from direct entity.position writes
        // during drag. Switching to .dynamic without clearing it causes the plate to shoot
        // upward (bleed from the last drag frame), hang in the air, then get locked kinematic
        // by the settle timer before gravity can pull it back down.
        entity.components[PhysicsMotionComponent.self] = PhysicsMotionComponent()
        entity.components[PhysicsBodyComponent.self]?.mode = .dynamic

        // Apply fling velocity from the gesture so fast releases travel across the scene.
        let hasFling = abs(gestureVelocity.width) > 30 || abs(gestureVelocity.height) > 30
        if hasFling {
            let vScale: Float = 0.0025   // pt/s -> m/s approximation at sceneRoot z=-1.4
            let worldVx = Float(gestureVelocity.width)  * vScale
            let worldVy = Float(-gestureVelocity.height) * vScale
            var motion = PhysicsMotionComponent()
            motion.linearVelocity = SIMD3(worldVx, worldVy, 0)
            // Tumble axis: cross(throwDir, Z-axis) = (vy, -vx, 0).
            // Throw right -> tumble axis points in -Y -> plate cartwheels outward.
            // Throw up   -> tumble axis points in +X -> plate tumbles forward.
            // Scale: 4 rad/s per 1 m/s throw speed feels natural for a heavy disc.
            let throwSpeed = sqrt(worldVx * worldVx + worldVy * worldVy)
            if throwSpeed > 0.05 {
                let tumbleAxis = SIMD3<Float>(worldVy, -worldVx, 0) / throwSpeed
                motion.angularVelocity = tumbleAxis * throwSpeed * 4.0
            }
            entity.components[PhysicsMotionComponent.self] = motion
        }

        if let audio = entity.components[PlateAudioCategoryComponent.self] {
            let releaseY = max(entity.position(relativeTo: sceneState.sceneRoot).y, 0.10)
            let approxFallTime = sqrt(max(releaseY, 0.10) * 2 / 9.8)
            scheduleDropFeedback(on: entity, category: audio.category, delay: TimeInterval(min(max(approxFallTime, 0.18), 0.65)))
        }

        sceneState.settleTasks[plateID]?.cancel()
        sceneState.settleTasks[plateID] = nil
    }

    private func scheduleDropFeedback(on entity: Entity, category: PlateAudioCategory, delay: TimeInterval) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
            guard entity.components[PlateRoleComponent.self]?.role == .floor else { return }
            playDropSound(on: entity, category: category)
            playDropHaptic(category: category)
        }
    }

    // MARK: - Info card

    private func showInfoCard(for plateID: String) {
        let allPlates = allRackedPlates + allFloorPlates
        guard let plate = allPlates.first(where: { $0.id == plateID }) else { return }

        // Dismiss any existing card without animation (new card replaces it instantly)
        dismissInfoCard(animated: false)

        let card = makeInfoCardEntity(plate: plate)

        // Fixed screen-center position in sceneRoot-local space.
        // sceneRoot is at world (0, -0.45, -1.4) in rackRoom mode.
        // (0, 0.80, 0.54) → world (0, 0.35, -0.86): centered horizontally,
        // roughly mid-screen vertically (above bar, below storage wall).
        let centerLocal = SIMD3<Float>(0, 0.80, 0.54)

        card.position = centerLocal
        card.scale    = SIMD3(repeating: 1)
        sceneState.sceneRoot.addChild(card)
        sceneState.infoCardEntity       = card
        sceneState.infoCardPlateID      = plateID
        sceneState.infoCardLastShowTime = Date()
    }

    private func dismissInfoCard(animated: Bool = true) {
        guard let card = sceneState.infoCardEntity else { return }
        // Debounce: ignore dismiss fired within 400ms of showing.
        // Prevents TapGesture double-fire (some iOS versions fire onEnded twice)
        // from immediately collapsing a card that was just shown.
        if animated && Date().timeIntervalSince(sceneState.infoCardLastShowTime) < 0.40 { return }
        sceneState.infoCardEntity  = nil
        sceneState.infoCardPlateID = nil

        guard animated && !sceneState.isReduceMotionEnabled else {
            card.removeFromParent()
            return
        }

        // Scale-out then remove
        let hidden = Transform(scale: SIMD3(repeating: 0.01), rotation: simd_quatf(), translation: card.position)
        card.move(to: hidden, relativeTo: sceneState.sceneRoot, duration: 0.20, timingFunction: .easeIn)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            card.removeFromParent()
        }
    }

    // MARK: RackRoom scene setup

    private func makeRoomWallText(_ text: String?, theme: RoomThemePreset) -> ModelEntity? {
        guard let normalized = barbellNormalizedRoomWallText(text) else { return nil }
        let mesh = MeshResource.generateText(
            normalized,
            extrusionDepth: 0.006,
            font: .systemFont(ofSize: 0.28, weight: .heavy),
            containerFrame: CGRect(x: -1.45, y: -0.16, width: 2.90, height: 0.34),
            alignment: .center,
            lineBreakMode: .byClipping
        )
        let material = pbrMaterial(
            color: theme.wallTextColor,
            metallic: 0,
            roughness: 0.88,
            clearcoat: 0.05,
            clearcoatRoughness: 0.42
        )
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "roomWallText"
        entity.position = SIMD3(0, 1.12, -0.100)
        return entity
    }

    private func setupRackRoomScene(
        content: inout RealityViewCameraContent,
        racked: [EarnedPlate], floor: [EarnedPlate],
        barSkinID: Int = 0,
        rackStyleID: String = "matte_black",
        roomThemeID: String = "dark_gym",
        roomWallText: String? = nil
    ) {
        let theme = RoomThemePreset.preset(for: roomThemeID)
        // Performance budget: 4 racked (bilateral = 8 entities) + 24 floor = 32 plate entities.
        // With shared materialCache, this stays under 150 draw calls on A15+ at 60fps.
        // Plates beyond index 24 are in SwiftData but not rendered.

        // Invisible static physics floor -- plates settle on this after .dynamic release.
        // Keep the top surface slightly above the visual slab so leaning plates do not appear
        // to sink a few millimeters into the rendered floor at rest.
        // Floor collider: 0.20m thick prevents high-velocity plates from tunnelling through
        // in a single physics step. Top surface sits at y=0.006; center at y=-0.094.
        // Z extent 8m covers all plate spawn positions including panned floor plates.
        let floorShape = ShapeResource.generateBox(size: SIMD3(20, 0.20, 8))
        let floorCollider = Entity()
        floorCollider.components.set(CollisionComponent(
            shapes: [floorShape],
            filter: CollisionFilter(group: floorCollisionGroup, mask: plateCollisionGroup)
        ))
        var floorBody = PhysicsBodyComponent()
        floorBody.mode = .static
        floorBody.material = PhysicsMaterialResource.generate(friction: 0.58, restitution: 0.18)
        floorCollider.components.set(floorBody)
        floorCollider.position = SIMD3(0, -0.094, 0)
        sceneState.sceneRoot.addChild(floorCollider)

        // Wall backdrop
        let backdrop = ModelEntity(
            mesh: cachedBox(size: SIMD3(6.0, 6.5, 0.025)),
            materials: [pbrMaterial(color: theme.backdropColor, metallic: theme.backdropMetallic, roughness: theme.backdropRoughness)]
        )
        backdrop.position = SIMD3(0, 0.5, -0.13)
        sceneState.sceneRoot.addChild(backdrop)

        if let wallText = makeRoomWallText(roomWallText, theme: theme) {
            sceneState.sceneRoot.addChild(wallText)
        }

        let plateZoneBacking = ModelEntity(
            mesh: cachedRoundedBox(size: SIMD3(1.72, 1.08, 0.010), cornerRadius: 0.018),
            materials: [
                pbrMaterial(
                    color: theme.plateZoneColor,
                    metallic: theme.plateZoneMetallic,
                    roughness: theme.plateZoneRoughness
                )
            ]
        )
        plateZoneBacking.name = "plateZoneBacking"
        plateZoneBacking.position = SIMD3(0, 0.90, -0.108)
        sceneState.sceneRoot.addChild(plateZoneBacking)

        // Floor plane -- visual only.
        let floorLine = ModelEntity(
            mesh: cachedBox(size: SIMD3(20.0, 0.008, 4.0)),
            materials: [pbrMaterial(color: theme.floorColor, metallic: theme.floorMetallic, roughness: theme.floorRoughness)]
        )
        floorLine.position = SIMD3(0, -0.006, -0.5)
        sceneState.sceneRoot.addChild(floorLine)

        // Subtle platform strips make sliding/falling easier to read against the floor.
        let stripMat = pbrMaterial(color: theme.stripColor, metallic: 0.03, roughness: 0.9)
        for x in stride(from: -0.72, through: 0.72, by: 0.24) {
            let strip = ModelEntity(
                mesh: cachedBox(size: SIMD3(0.010, 0.004, 3.2)),
                materials: [stripMat]
            )
            strip.position = SIMD3(Float(x), 0.0005, -0.5)
            sceneState.sceneRoot.addChild(strip)
        }
        for z in stride(from: -1.75, through: 0.65, by: 0.40) {
            let seam = ModelEntity(
                mesh: cachedBox(size: SIMD3(1.7, 0.004, 0.008)),
                materials: [stripMat]
            )
            seam.position = SIMD3(0, 0.001, Float(z))
            sceneState.sceneRoot.addChild(seam)
        }

        // Low visible bumpers communicate the playable area.
        let bumperMat = pbrMaterial(color: theme.bumperColor, metallic: theme.bumperMetallic, roughness: theme.bumperRoughness)
        var bumperBody = PhysicsBodyComponent()
        bumperBody.mode = .static
        bumperBody.material = PhysicsMaterialResource.generate(friction: 0.34, restitution: 0.18)
        for xSign: Float in [-1, 1] {
            let railSize = SIMD3<Float>(0.018, 0.055, 2.65)
            let sideRail = ModelEntity(
                mesh: cachedBox(size: railSize),
                materials: [bumperMat]
            )
            sideRail.position = SIMD3(xSign * 0.82, 0.025, -0.48)
            sideRail.components.set(CollisionComponent(
                shapes: [ShapeResource.generateBox(size: railSize)],
                filter: floorCollisionFilter
            ))
            sideRail.components.set(bumperBody)
            sceneState.sceneRoot.addChild(sideRail)
        }
        let lipSize = SIMD3<Float>(1.66, 0.045, 0.018)
        let frontLip = ModelEntity(
            mesh: cachedBox(size: lipSize),
            materials: [bumperMat]
        )
        frontLip.position = SIMD3(0, 0.022, 0.86)
        frontLip.components.set(CollisionComponent(
            shapes: [ShapeResource.generateBox(size: lipSize)],
            filter: floorCollisionFilter
        ))
        frontLip.components.set(bumperBody)
        sceneState.sceneRoot.addChild(frontLip)

        // Invisible border walls -- keep plates inside the visible screen area.
        // Visible half-width ~0.81m at sceneRoot z=-1.4 (60deg FOV, 0.004 m/pt, 393pt screen).
        // Plate radius 0.22m -> wall inner face at ±0.85 keeps plate centers on screen.
        // Walls 0.10m thick to prevent fast plates tunnelling through in one physics step.
        // Z extent 8m matches the physics floor. Front wall at z=1.2 stops plates escaping
        // toward the camera (fling velocity is X/Y only, but bounces can add Z motion).
        // Back wall at z=-0.20 (inner face z=-0.15): stops floor plates from drifting into the
        // backdrop. Racked plates are at barbellZ=+0.12 so their back face (z=-0.10) clears this.
        let borderMat = PhysicsMaterialResource.generate(friction: 0.12, restitution: 0.42)
        let borderDefs: [(SIMD3<Float>, SIMD3<Float>)] = [
            (SIMD3(-0.90, 0.5,  0),    SIMD3(0.10, 3.0, 8.0)),  // left  (inner face x=-0.85)
            (SIMD3( 0.90, 0.5,  0),    SIMD3(0.10, 3.0, 8.0)),  // right (inner face x=+0.85)
            (SIMD3( 0,    2.0,  0),    SIMD3(3.0,  0.10, 8.0)), // top
            (SIMD3( 0,    0.5,  1.2),  SIMD3(4.0,  3.0,  0.10)), // front
            (SIMD3( 0,    0.5, -0.20), SIMD3(4.0,  3.0,  0.10)), // back  (inner face z=-0.15)
        ]
        for (pos, size) in borderDefs {
            let wall = Entity()
            wall.components.set(CollisionComponent(
                shapes: [ShapeResource.generateBox(size: size)],
                filter: CollisionFilter(group: floorCollisionGroup, mask: plateCollisionGroup)
            ))
            var wallBody = PhysicsBodyComponent()
            wallBody.mode = .static
            wallBody.material = borderMat
            wall.components.set(wallBody)
            wall.position = pos
            sceneState.sceneRoot.addChild(wall)
        }

        // Rack stands, bar, and collars are all at z=+0.12.
        // Racked plate radius = 0.22m, so back face reaches z = 0.12 - 0.22 = -0.10.
        // Backdrop front face is at z = -0.1175, back wall inner face at z = -0.15.
        // z=+0.12 keeps racked plates in front of both, preventing visual and physics clipping.
        let barbellZ: Float = 0.12

        // Rack stands
        for xSign: Float in [-1, 1] {
            let stand = makeRackStandEntity(rackStyleID: rackStyleID)
            stand.position = SIMD3(xSign * 0.40, 0.3, barbellZ)
            sceneState.sceneRoot.addChild(stand)
        }

        // Bar
        let bar = makeBarEntity(skinID: barSkinID)
        bar.position = SIMD3(0, 0.6, barbellZ)
        sceneState.sceneRoot.addChild(bar)
        sceneState.barAnchor.position = SIMD3(0, 0.6, barbellZ)
        sceneState.sceneRoot.addChild(sceneState.barAnchor)

        // Collars sit just inside the plate stack, marking the inner boundary of the loading zone.
        // Layout: stands(±0.40) → collar(±0.54) → plates(0.60-0.756) → bar end(±0.80).
        // 5.2 cm slot spacing accommodates the thickest bumper plates (46 mm) with a 6 mm gap.
        for xSign: Float in [-1, 1] {
            let collar = makeCollarEntity(skinID: barSkinID)
            collar.position = SIMD3(xSign * 0.54, 0.6, barbellZ)
            sceneState.sceneRoot.addChild(collar)
        }

        // Bar hit zone: invisible input-target spanning the full bar and plate area.
        // Catches swipe-to-unrack gestures on the bar body, sleeves, and left (mirror) side
        // where no interactive plate entity exists. Positioned slightly behind plates (z=-0.05)
        // so racked plate hit-tests take priority when plates are present.
        // barHitZoneCollisionFilter has empty mask -- no physical collisions with plates or floor.
        let barHitZone = Entity()
        barHitZone.name = "barHitZone"
        barHitZone.components.set(InputTargetComponent())
        barHitZone.components.set(CollisionComponent(
            shapes: [ShapeResource.generateBox(size: SIMD3(1.6, 0.5, 0.05))],
            filter: barHitZoneCollisionFilter
        ))
        barHitZone.components.set(PlateRoleComponent(role: .bar))
        barHitZone.position = SIMD3(0, 0, -0.05)
        sceneState.barAnchor.addChild(barHitZone)

        // Slot highlight rings -- one per bar slot, hidden until plate is dragged near bar.
        // UnlitMaterial so they always appear bright regardless of scene lighting.
        let slotOffsets: [Float] = [0.600, 0.652, 0.704, 0.756]
        sceneState.slotHighlights.removeAll()
        for offset in slotOffsets {
            var mat = UnlitMaterial()
            mat.color = .init(tint: UIColor(white: 1, alpha: 0.7))
            let ring = ModelEntity(
                mesh: cachedCylinder(height: 0.003, radius: 0.25),
                materials: [mat]
            )
            ring.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
            ring.position = SIMD3(offset, 0, 0)
            ring.isEnabled = false  // hidden until drag enters snap zone
            sceneState.barAnchor.addChild(ring)
            sceneState.slotHighlights.append(ring)
        }

        // Racked plates -- bilateral rendering, use cached material
        // Primary entity (xSign=1): interactive, tracked in entityMap.
        // Mirror entity (xSign=-1): visual only -- interaction/physics components stripped
        //   to prevent hit-testing on the mirror and match snapToBar behavior.
        //   barMirrorMap populated here so finishUnrack can remove it.
        let sorted = racked.sorted { ($0.rackPosition ?? 999) < ($1.rackPosition ?? 999) }
        var occupiedRackSlots = Set<Int>()
        for plate in sorted {
            guard let rackPosition = plate.rackPosition,
                  slotOffsets.indices.contains(rackPosition),
                  !occupiedRackSlots.contains(rackPosition) else { continue }
            occupiedRackSlots.insert(rackPosition)
            let offset = slotOffsets[rackPosition]
            var primaryEntity: Entity?
            for xSign: Float in [-1, 1] {
                let entity = makePlateEntity(
                    tierID: plate.tierID,
                    material: sceneState.materialCache[plate.tierID],
                    weightKg: plate.weightKg,
                    engravingText: plate.engravingText,
                    prominentEngraving: plate.earnedByEvent.hasPrefix("strength_milestone_"),
                    renderProjection: BarbellPlateRenderProjection(plate: plate),
                    role: .bar
                )
                entity.name = xSign == 1 ? plate.id : plate.id + "_mirror"
                entity.position = SIMD3(xSign * offset, 0, 0)
                #if DEBUG
                attachPlateDebugAxes(to: entity, label: "bar_\(rackPosition)_\(xSign)")
                #endif
                if xSign == -1 {
                    // Strip all interaction and physics from the mirror -- visual only.
                    entity.components.remove(InputTargetComponent.self)
                    entity.components.remove(CollisionComponent.self)
                    entity.components.remove(PhysicsBodyComponent.self)
                    entity.components.remove(PhysicsMotionComponent.self)
                    sceneState.barMirrorMap[plate.id] = entity
                } else {
                    primaryEntity = entity
                }
                sceneState.barAnchor.addChild(entity)
            }
            sceneState.entityMap[plate.id] = primaryEntity
            sceneState.barPositionMap[plate.id] = SIMD3(offset, 0, 0)
        }

        // Floor plates -- place in storage slots so plates are accessible above the rack
        // without blocking the barbell view and without physics-drop overlap.
        // Reward moments hide storage and start earned plates suspended above the floor so
        // they can be released into physics immediately after the scene appears.
        // Slots are 8 positions; plates beyond that count are not rendered at startup.
        // Kinematic physics: no drop needed -- they sit on the storage brackets.
        let visibleFloor = Array(floor.prefix(sceneState.storageSlotPositions.count))
        for (idx, plate) in visibleFloor.enumerated() {
            let entity = makePlateEntity(
                tierID: plate.tierID,
                material: sceneState.materialCache[plate.tierID],
                weightKg: plate.weightKg,
                engravingText: plate.engravingText,
                prominentEngraving: plate.earnedByEvent.hasPrefix("strength_milestone_"),
                renderProjection: BarbellPlateRenderProjection(plate: plate),
                role: .floor
            )
            entity.name = plate.id
            // Same orientation as snapToStorageSlot: side-on like hanging plates.
            entity.orientation = plateDisplayOrientation
            if showsStorage {
                entity.position = sceneState.storageSlotPositions[idx]
            } else {
                let spread = max(Float(visibleFloor.count - 1), 1)
                let t = visibleFloor.count > 1 ? (Float(idx) / spread) - 0.5 : 0
                entity.position = SIMD3(
                    max(-0.58, min(0.58, t * 1.10)),
                    1.34 + Float(idx % 2) * 0.12,
                    0.22 + Float(idx % 3) * 0.05
                )
            }
            #if DEBUG
            attachPlateDebugAxes(to: entity, label: showsStorage ? "storage_initial_\(idx)" : "reward_initial_\(idx)")
            #endif
            entity.components[PhysicsBodyComponent.self]?.mode = .kinematic
            sceneState.sceneRoot.addChild(entity)
            sceneState.entityMap[plate.id] = entity
            sceneState.originalTransforms[plate.id] = Transform(matrix: entity.transformMatrix(relativeTo: nil))
            if showsStorage {
                sceneState.storageSlotByIndex[idx] = plate.id
                sceneState.storageSlotByPlate[plate.id] = idx
            }
        }

        // Floor pan has no initial plates -- pan range is zero until a plate is freed to the floor.
        sceneState.floorMinX = 0
        sceneState.floorMaxX = 0

        // Storage claws -- two vertical arms with inward hooks at the bottom. The plate slides
        // upward between the arms and rests on the hooks. Light-gray PBR metal material.
        // Container-local space: plate center at origin, disc extends ±0.22 in Y (vertical)
        // and ±0.22 in Z (depth). Arms are separated ±0.060 in X so they flank the
        // plate edge (±0.015 X) visibly from the front camera view.
        let clawMat = pbrMaterial(color: UIColor(white: 0.72, alpha: 1), metallic: 0.45, roughness: 0.40)
        let armHalfX: Float = 0.060   // arm center X offset from slot center
        let armWidth: Float = 0.020   // arm thickness in X
        let armDepth: Float = 0.026   // arm thickness in Z
        let armTop: Float   =  0.245  // arm top Y -- 25mm above plate top edge (0.22)
        let armBottom: Float = -0.225 // arm bottom Y -- 5mm below plate bottom edge (-0.22)
        let armLen   = armTop - armBottom     // 0.470
        let armCenterY = (armTop + armBottom) / 2  // 0.010
        let hookLen: Float = 0.044    // hook extends inward from each arm bottom
        let crossbarHalfWidth = armHalfX + armWidth / 2  // 0.070

        sceneState.storageSlotRings.removeAll()
        guard showsStorage else { return }

        for pos in sceneState.storageSlotPositions {
            // Plain Entity container -- isEnabled = false hides all parts together.
            let container = Entity()
            container.position = pos

            // Crossbar: horizontal top piece connecting both arm tops.
            let crossbar = ModelEntity(
                mesh: cachedBox(size: SIMD3(crossbarHalfWidth * 2, 0.020, armDepth)),
                materials: [clawMat]
            )
            crossbar.position = SIMD3(0, armTop + 0.010, 0)
            container.addChild(crossbar)

            // Left arm
            let leftArm = ModelEntity(
                mesh: cachedBox(size: SIMD3(armWidth, armLen, armDepth)),
                materials: [clawMat]
            )
            leftArm.position = SIMD3(-armHalfX, armCenterY, 0)
            container.addChild(leftArm)

            // Right arm
            let rightArm = ModelEntity(
                mesh: cachedBox(size: SIMD3(armWidth, armLen, armDepth)),
                materials: [clawMat]
            )
            rightArm.position = SIMD3(armHalfX, armCenterY, 0)
            container.addChild(rightArm)

            // Left hook: extends inward (+X) from left arm bottom to catch plate edge.
            let leftHook = ModelEntity(
                mesh: cachedBox(size: SIMD3(hookLen, 0.018, armDepth)),
                materials: [clawMat]
            )
            leftHook.position = SIMD3(-armHalfX + hookLen / 2, armBottom, 0)
            container.addChild(leftHook)

            // Right hook: extends inward (-X) from right arm bottom.
            let rightHook = ModelEntity(
                mesh: cachedBox(size: SIMD3(hookLen, 0.018, armDepth)),
                materials: [clawMat]
            )
            rightHook.position = SIMD3(armHalfX - hookLen / 2, armBottom, 0)
            container.addChild(rightHook)

            sceneState.sceneRoot.addChild(container)
            sceneState.storageSlotRings.append(container)
        }

        // Plates placed in storage at startup occupy their slots -- hide those brackets.
        // Slots that have no plate remain visible so the user can see available space.
        for (idx, _) in sceneState.storageSlotByIndex {
            guard idx < sceneState.storageSlotRings.count else { continue }
            sceneState.setStorageSlotRingEnabled(false, atIndex: idx)
        }
    }
}

// MARK: - BarbellDebugHUD

#if DEBUG
/// On-screen debug overlay. Shows entity positions, physics states and drag phase in real time.
/// Refresh rate: 4 Hz (250ms). Toggle with the small "D" button in the top-right corner.
/// Every piece of data is screenshottable -- useful for sharing issues with context.
private struct BarbellDebugHUD: View {
    let sceneState: SceneState
    let mode: BarbellRealityMode
    @Binding var show: Bool

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Button(show ? "D" : "D") {
                    show.toggle()
                    if show { barbellLog("HUD", "debug overlay ON") }
                }
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(show ? .yellow : .white.opacity(0.4))
                .padding(6)
                .background(.black.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(.top, 8)
                .padding(.trailing, 8)
            }
            if show {
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            phaseRow
                            anchorsSection
                            entitiesSection
                        }
                        .padding(8)
                    }
                    .background(.black.opacity(0.75))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(.horizontal, 8)
            }
            Spacer()
        }
        .allowsHitTesting(show) // pass touches through when collapsed
    }

    private var phaseRow: some View {
        let phaseText: String
        switch sceneState.dragPhase {
        case .idle: phaseText = "idle"
        case .panningFloor: phaseText = "panningFloor"
        case .draggingPlate(let e, let id, let role):
            phaseText = "dragging id=\(id.prefix(8)) role=\(role) y=\(String(format:"%.3f", e.position.y))"
        }
        return hudRow(label: "PHASE", value: phaseText, color: .cyan)
    }

    private var anchorsSection: some View {
        Group {
            hudRow(label: "sceneRoot.pos", value: v3(sceneState.sceneRoot.position), color: .green)
            hudRow(label: "barAnchor.local", value: v3(sceneState.barAnchor.position), color: .green)
            hudRow(label: "floorAnchor.local", value: v3(sceneState.floorAnchor.position), color: .green)
        }
    }

    private var entitiesSection: some View {
        let sorted = sceneState.entityMap.sorted(by: { $0.key < $1.key })
        return ForEach(sorted, id: \.key) { id, entity in
            let role = entity.components[PlateRoleComponent.self]?.role
            let phys = entity.components[PhysicsBodyComponent.self]?.mode
            let roleStr = role.map { "\($0)" } ?? "?"
            let physStr = phys.map {
                switch $0 { case .kinematic: return "kin"; case .dynamic: return "DYN"; case .static: return "sta"; @unknown default: return "?" }
            } ?? "none"
            let world = entity.position(relativeTo: nil)
            let col: Color = phys == .dynamic ? .orange : .white
            hudRow(
                label: String(id.prefix(8)),
                value: "\(roleStr) |\(physStr)| L\(v3(entity.position)) W\(v3(world))",
                color: col
            )
        }
    }

    private func hudRow(label: String, value: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(label)
                .frame(width: 96, alignment: .leading)
                .foregroundStyle(.white.opacity(0.55))
            Text(value)
                .foregroundStyle(color)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .font(.system(size: 9, design: .monospaced))
    }
}
#endif

// MARK: - ShaderWarmUpView
//
// Renders one entity per material variant in a 1x1 invisible RealityView.
// Metal compiles and caches shader PSOs on first render -- warming up here prevents
// hitch on first plate drag. Self-destructs after 1 second (shaders stay compiled).

private struct ShaderWarmUpView: View {
    @State private var visible = true

    var body: some View {
        if visible {
            RealityView { content in
                // One entity per shader variant used in the barbell scene
                let variants: [(MeshResource, any RealityKit.Material)] = [
                    (.generateBox(size: .init(repeating: 0.001)), {
                        var m = PhysicallyBasedMaterial()
                        m.baseColor = .init(tint: .clear)
                        return m
                    }()),
                    (.generateCylinder(height: 0.001, radius: 0.001), chromeMaterial()),
                    (.generateBox(size: .init(repeating: 0.001)), UnlitMaterial()),
                ]
                let root = Entity()
                root.position = SIMD3(0, 0, -500)  // far off-screen
                for (mesh, mat) in variants {
                    root.addChild(ModelEntity(mesh: mesh, materials: [mat]))
                }
                content.add(root)
            }
            .task {
                try? await Task.sleep(for: .seconds(1))
                visible = false
            }
        }
    }
}

#if DEBUG
struct BarbellRealityStressScene_Previews: PreviewProvider {
    static var previews: some View {
        BarbellRealityView(
            mode: .rackRoom(
                rackedPlates: stressPlates.prefix(4).map { $0 },
                floorPlates: stressPlates.dropFirst(4).map { $0 },
                onRack: { _ in },
                onUnrack: { _ in }
            ),
            sceneState: {
                let state = SceneState()
                for tierID in PlateTier.all.map(\.id) {
                    state.plateTextureCache[tierID] = loadPlateTextures(forTierID: tierID)
                    state.materialCache[tierID] = buildMaterial(
                        forTierID: tierID,
                        textures: state.plateTextureCache[tierID]
                    )
                }
                return state
            }(),
            allowsInteraction: true,
            showsStorage: true
        )
        .previewDisplayName("Barbell stress: 6 Gold+ plates")
    }

    private static var stressPlates: [EarnedPlate] {
        (0..<6).map { index in
            EarnedPlate(
                tierID: 6,
                weightKg: 20,
                engravingText: "Stress \(index + 1)",
                earnedByEvent: "stress_gold_\(index)",
                isRacked: index < 4,
                rackPosition: index < 4 ? index : nil
            )
        }
    }
}
#endif
