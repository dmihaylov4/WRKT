// Features/Rewards/Views/BarbellRealityView.swift
import SwiftUI
import Combine
import RealityKit
import SwiftData
import UIKit
import os

// Shared across the host, builders and gestures so Instruments has one track.
let barbellSignposter = OSSignposter(subsystem: Bundle.main.bundleIdentifier ?? "WRKT", category: "Barbell")

private var barbellUnloadTraceEnabled: Bool {
    #if DEBUG
    ProcessInfo.processInfo.arguments.contains("-BarbellUnloadTrace")
    #else
    false
    #endif
}

func barbellSpinIncrement(deltaTime: TimeInterval) -> Float {
    Float(deltaTime) * (0.03 / 0.016)
}

struct BarbellFloorSettleState {
    var elapsed: TimeInterval = 0
    let delay: TimeInterval

    mutating func advance(deltaTime: TimeInterval, linearSpeed: Float, angularSpeed: Float) -> Bool {
        elapsed += deltaTime
        guard elapsed >= delay else { return false }
        return (linearSpeed < 0.02 && angularSpeed < 0.05) || elapsed >= delay + 3
    }
}

private let plateBarOrientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 0, 1))
private let plateDisplayOrientation = plateBarOrientation

// MARK: - Debug logging

#if DEBUG
func barbellLog(_ tag: String, _ msg: @autoclosure () -> String) {
    guard barbellUnloadTraceEnabled || isBarbellPlateDebugEnabled else { return }
    print("[Barbell.\(tag)] \(msg())")
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

private func barbellDiagnosticsQ(_ q: simd_quatf) -> String {
    String(format: "(ix=%.3f,iy=%.3f,iz=%.3f,r=%.3f)", q.imag.x, q.imag.y, q.imag.z, q.real)
}

private func barbellDiagnosticsLog(_ event: String, _ message: @autoclosure () -> String) {
    guard barbellUnloadTraceEnabled else { return }
    DiagnosticsLogStore.shared.append("\(event) \(message())", category: "Barbell")
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
    sizeClass: UserInterfaceSizeClass?,
    barOnly: Bool = false,
    barOnlyAspect: Float = 0.75
) -> SIMD3<Float> {
    let isWide = sizeClass == .regular
    switch mode {
    case .welcome:
        return SIMD3(0, 0.16, isWide ? -1.62 : -1.22)
    case .rackRoom:
        if barOnly { return barbellBarOnlyCameraPosition(aspect: barOnlyAspect) }
        return SIMD3(0, isWide ? -0.42 : -0.40, isWide ? -1.72 : -1.30)
    }
}

/// The Cut rack frames the bar alone in a band of the screen: no wall storage above it, so the
/// camera sits closer, centred on the bar with the floor in front of it. The view's field of view
/// is fixed vertically, so a wide, short band shows more width; the distance follows the band's
/// height-to-width `aspect` so a fully loaded bar always nearly spans the width. Calibrated on
/// simulator captures (iPhone, 402 pt wide).
func barbellBarOnlyCameraPosition(aspect: Float) -> SIMD3<Float> {
    let clamped = max(0.4, min(1.6, aspect.isFinite ? aspect : 0.75))
    return SIMD3(0, -0.52, 1.79 - 1.75 * clamped)
}

/// The rack room floor's lines: four strips running back from the camera and four seams across.
let barbellRackRoomFloorLineWidth: Float = 0.025
let barbellRackRoomFloorStripXs: [Float] = [-0.72, -0.24, 0.24, 0.72]
let barbellRackRoomFloorSeamZs: [Float] = [-1.75, -0.95, -0.15, 0.65]

func clampFloorPlateX(_ x: Float, maxAbsX: Float = 0.64) -> Float {
    max(-maxAbsX, min(maxAbsX, x))
}

func barbellRackRoomSlideOutDuration(isReduceMotionEnabled: Bool) -> TimeInterval {
    _ = isReduceMotionEnabled
    return 0.2
}

func barbellRackRoomUnrackSlideTargetX(currentBarLocalX: Float) -> Float {
    let sign: Float = currentBarLocalX < 0 ? -1 : 1
    return sign * 0.74
}

func barbellRackRoomFloorReleasePosition(
    localPosition: SIMD3<Float>,
    maxAbsX: Float,
    minZ: Float,
    maxZ: Float
) -> SIMD3<Float> {
    SIMD3(
        clampFloorPlateX(localPosition.x, maxAbsX: maxAbsX),
        max(localPosition.y, 0.08),
        max(minZ, min(maxZ, localPosition.z))
    )
}

func barbellRackRoomUnloadFloorImpulse(spreadDirection: Float, spinDirection: Float) -> PhysicsMotionComponent {
    var motion = PhysicsMotionComponent()
    motion.angularVelocity = SIMD3(0, spinDirection * 1.35, 0)
    motion.linearVelocity = SIMD3(spreadDirection * 0.34, -0.18, -0.06)
    return motion
}

func barbellRackRoomFloorRestPosition(localPosition: SIMD3<Float>) -> SIMD3<Float> {
    SIMD3(
        clampFloorPlateX(localPosition.x, maxAbsX: 0.64),
        max(localPosition.y, 0.10),
        max(-0.10, min(0.72, localPosition.z))
    )
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
    /// Lathe plates, studio environment and a shadowed key, or the legacy plates and room light.
    /// Read once per scene; Release builds are always legacy (see RackPlateStyle).
    var plateStyle: RackPlateStyle = .current

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

    // MARK: Frame-driven work
    /// Pending floor settles are cancelled when a drag takes ownership of the plate.
    var floorSettles: [String: BarbellFloorSettleState] = [:]
    var cancelFrameUpdates: (() -> Void)?
    var boundaryElapsed: TimeInterval = 0
    var showcaseElapsed: TimeInterval = 0
    var showcaseSpinToken: String?
    var animationDeadline: TimeInterval = 0
    var pendingSaves: [() -> Void] = []
    var isPaused = false
    var preparedMirrors: [String: ModelEntity] = [:]

    func prepareMirror(for entity: Entity, plateID: String) -> ModelEntity {
        if let cached = preparedMirrors[plateID] { return cached }
        let mirror = makeMirrorEntity(from: entity, name: plateID + "_mirror")
        mirror.isEnabled = false
        preparedMirrors[plateID] = mirror
        return mirror
    }

    func deferSave(untilAfter duration: TimeInterval, _ save: @escaping () -> Void) {
        if isPaused { save(); return }
        animationDeadline = max(animationDeadline, ProcessInfo.processInfo.systemUptime + duration)
        pendingSaves.append(save)
    }

    func flushSaves() {
        let saves = pendingSaves
        pendingSaves.removeAll()
        for save in saves { save() }
    }

    // MARK: Unrack guard
    /// Plate IDs currently inside a bar→floor unrack animation (slide + scripted fall).
    /// The bar-swipe handler rejects any plate in this set so rapid repeat swipes on the same
    /// plate don't spawn multiple concurrent snapToFloor Tasks.
    var platesBeingUnracked: Set<String> = []
    /// Timestamp when the bar-plate slide animation started. Captured in onChanged so onEnded
    /// can sleep only the remaining slide time rather than the full duration.
    var barSlideStartTime: Date? = nil
    /// Diagnostic start time and sampler tasks for a single bar→floor unload trace.
    /// Tasks are cancelled when a new trace for the same plate begins or finishes.
    var unloadTraceStartTimes: [String: TimeInterval] = [:]
    var unloadTraceTasks: [String: Task<Void, Never>] = [:]

    // MARK: Welcome spin state
    var plateSpinStates: [String: PlateSpinState] = [:]
    var barbellSpinAngle: Float    = 0
    var barbellSpinVelocity: Float = 0
    var welcomePitchAngle: Float = 0
    var welcomeDragStartAngle: Float = 0
    var welcomeDragStartPitch: Float = 0
    var isDraggingWelcome: Bool = false

    // MARK: Plate showcase
    /// Entity currently levitating in showcase mode. Nil when no showcase is active.
    var showcaseEntity: Entity? = nil
    /// Opaque token updated on every startShowcase() call. Spin and auto-drop frame updates
    /// compare against this value to self-cancel when the showcase changes or ends.
    var showcaseToken: String? = nil
    /// Timestamp of the last startShowcase() call. Guards against the simultaneousGesture
    /// TapGesture firing on the same plate tap and immediately dropping the showcase.
    var showcaseStartTime: Date = .distantPast

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

    // MARK: Mirror entity factory

    /// Creates a mirror entity for the bar's negative-X side using cached resources.
    /// Calls makePlateEntity instead of clone(recursive:) so Metal reuses already-compiled
    /// pipeline states from the primary entity's first render. Skips engravings (not visible
    /// on the mirror side) to avoid text mesh generation.
    func makeMirrorEntity(from source: Entity, name: String) -> ModelEntity {
        let tierID = source.components[TierIDComponent.self]?.tierID ?? 0
        let meta = source.components[PlateDisplayMetaComponent.self]
        let mirror = makePlateEntity(
            tierID: tierID,
            textures: plateTextureCache[tierID],
            material: materialCache[tierID],
            weightKg: meta?.weightKg ?? 0,
            engravingText: "",
            prominentEngraving: false,
            renderProjection: meta?.renderProjection ?? BarbellPlateRenderProjection(),
            role: .bar,
            options: .barMirror(),
            plateStyle: plateStyle
        )
        mirror.name = name
        return mirror
    }

    // MARK: Camera proxy
    /// Positions sceneRoot so the default RealityView perspective camera frames the scene.
    /// Call after scene setup completes and on horizontal size class changes.
    func configureCameraPosition(for mode: BarbellRealityMode, sizeClass: UserInterfaceSizeClass?, barOnly: Bool = false) {
        sceneRoot.position = barbellRealityCameraPosition(for: mode, sizeClass: sizeClass, barOnly: barOnly,
                                                          barOnlyAspect: barOnlyAspect)
    }

    /// Height over width of a bar-only view, measured on layout changes (never per frame).
    var barOnlyAspect: Float = 0.75

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
            role: .floor,
            plateStyle: plateStyle
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

    // MARK: Live plate removal

    /// Removes a storage (floor-role) plate from the scene and frees its wall slot.
    /// Safe to call while the scene is live — guards against bar plates, dragged plates,
    /// and showcased plates.
    @MainActor
    func removeStoragePlate(id: String) {
        guard let entity = entityMap[id] else { return }
        guard entity.components[PlateRoleComponent.self]?.role != .bar else { return }
        // If this plate is being showcased, cancel the showcase first.
        if showcaseEntity === entity {
            showcaseEntity = nil
            showcaseToken = nil
        }
        // Do not remove a plate that is mid-drag — the drag handler owns it.
        if case .draggingPlate(let dragging, _, _) = dragPhase, dragging === entity { return }
        entity.stopAllAnimations(recursive: true)
        entity.removeFromParent()
        entityMap.removeValue(forKey: id)
        originalTransforms.removeValue(forKey: id)
        if let slotIdx = storageSlotByPlate[id] {
            storageSlotByIndex.removeValue(forKey: slotIdx)
            storageSlotByPlate.removeValue(forKey: id)
            setStorageSlotRingEnabled(true, atIndex: slotIdx)
        }
        floorSettles.removeValue(forKey: id)
        preparedMirrors.removeValue(forKey: id)
    }

    // MARK: Welcome spin loop
    /// No-ops immediately when Reduce Motion is enabled.
    @MainActor
    func updateWelcomeSpin(deltaTime: TimeInterval) {
        guard !isReduceMotionEnabled else { return }
        let dt = Float(deltaTime)
        if !isDraggingWelcome {
            barbellSpinAngle += barbellSpinVelocity * dt
            barbellSpinVelocity *= pow(0.992, dt / 0.016)
            if abs(barbellSpinVelocity) < 0.08 { barbellSpinVelocity = 0.18 }
            applyWelcomeLook()
        }
        for (key, spinState) in plateSpinStates {
            spinState.angle += spinState.velocity * dt
            entityMap[key]?.orientation =
                simd_quatf(angle: spinState.angle, axis: SIMD3(0, 1, 0))
                * simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0))
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
        isPaused = true
        cancelFrameUpdates?()
        cancelFrameUpdates = nil
        floorSettles.removeAll()
        showcaseToken = nil
        for task in unloadTraceTasks.values { task.cancel() }
        unloadTraceTasks.removeAll()
        for entity in entityMap.values {
            entity.stopAllAnimations(recursive: true)
            if entity.components[PlateRoleComponent.self]?.role == .floor,
               entity.components[PhysicsBodyComponent.self]?.mode == .dynamic {
                entity.components[PhysicsBodyComponent.self]?.mode = .kinematic
                entity.components[PhysicsMotionComponent.self] = PhysicsMotionComponent()
            }
        }
        flushSaves()
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

        let mirrorEntity = makeMirrorEntity(from: entity, name: plateID + "_mirror")
        // Keep input/collision so the left bar plate can start the same swipe-to-unrack gesture.
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

    /// Places a storage plate directly onto the bar at the given rack slot, no animation.
    /// Used when racking from the collection sheet where SwiftData is already updated.
    @MainActor
    @discardableResult
    func placeOnBarImmediate(plateID: String, rackSlot: Int) -> Bool {
        guard let entity = entityMap[plateID],
              entity.components[PlateRoleComponent.self]?.role == .floor else {
            return false
        }
        let slotOffsets: [Float] = [0.600, 0.652, 0.704, 0.756]
        guard slotOffsets.indices.contains(rackSlot) else { return false }

        if let slotIdx = storageSlotByPlate[plateID] {
            storageSlotByPlate.removeValue(forKey: plateID)
            storageSlotByIndex.removeValue(forKey: slotIdx)
            setStorageSlotRingEnabled(true, atIndex: slotIdx)
        }

        let offset = slotOffsets[rackSlot]
        let rot = plateBarOrientation

        if let existingMirror = barMirrorMap[plateID] {
            existingMirror.removeFromParent()
            barMirrorMap.removeValue(forKey: plateID)
        }

        entity.components[PhysicsBodyComponent.self]?.mode = .kinematic
        entity.components.set(PlateRoleComponent(role: .bar))
        entity.setParent(barAnchor, preservingWorldTransform: true)
        entity.position = SIMD3(offset, 0, 0)
        entity.orientation = rot

        let mirror = makeMirrorEntity(from: entity, name: plateID + "_mirror")
        mirror.position = SIMD3(-offset, 0, 0)
        mirror.orientation = rot
        barAnchor.addChild(mirror)

        barPositionMap[plateID] = SIMD3(offset, 0, 0)
        barMirrorMap[plateID] = mirror
        return true
    }

    /// Builds a racked plate directly onto the bar, no animation.
    /// Used when the collection sheet racks a plate that was owned but not visible in storage.
    @MainActor
    @discardableResult
    func addBarPlateImmediate(_ plate: EarnedPlate, rackSlot: Int) -> Bool {
        if let existing = entityMap[plate.id] {
            if existing.components[PlateRoleComponent.self]?.role == .floor {
                return placeOnBarImmediate(plateID: plate.id, rackSlot: rackSlot)
            }
            return existing.components[PlateRoleComponent.self]?.role == .bar
        }

        let slotOffsets: [Float] = [0.600, 0.652, 0.704, 0.756]
        guard slotOffsets.indices.contains(rackSlot) else { return false }

        if let existingMirror = barMirrorMap[plate.id] {
            existingMirror.removeFromParent()
            barMirrorMap.removeValue(forKey: plate.id)
        }

        let offset = slotOffsets[rackSlot]
        let rot = plateBarOrientation
        let entity = makePlateEntity(
            tierID: plate.tierID,
            textures: plateTextureCache[plate.tierID],
            material: materialCache[plate.tierID],
            weightKg: plate.weightKg,
            engravingText: plate.engravingText,
            prominentEngraving: plate.earnedByEvent.hasPrefix("strength_milestone_"),
            renderProjection: BarbellPlateRenderProjection(plate: plate),
            role: .bar,
            plateStyle: plateStyle
        )
        entity.name = plate.id
        entity.position = SIMD3(offset, 0, 0)
        entity.orientation = rot
        entity.components[PhysicsBodyComponent.self]?.mode = .kinematic
        barAnchor.addChild(entity)

        let mirror = makePlateEntity(
            tierID: plate.tierID,
            textures: plateTextureCache[plate.tierID],
            material: materialCache[plate.tierID],
            weightKg: plate.weightKg,
            engravingText: "",
            prominentEngraving: false,
            renderProjection: BarbellPlateRenderProjection(plate: plate),
            role: .bar,
            options: .barMirror(),
            plateStyle: plateStyle
        )
        mirror.name = plate.id + "_mirror"
        mirror.position = SIMD3(-offset, 0, 0)
        mirror.orientation = rot
        barAnchor.addChild(mirror)

        entityMap[plate.id] = entity
        barPositionMap[plate.id] = SIMD3(offset, 0, 0)
        barMirrorMap[plate.id] = mirror
        return true
    }

    // MARK: Cut rack: tray-driven loads and unloads
    //
    // The Cut rack keeps spare plates in a SwiftUI tray instead of the wall storage. The tray
    // saves through BarbellProgressService first; these two calls then bring the scene in line
    // with the same motions the scene already uses, and never save anything themselves.

    /// Swings a plate and its mirror onto the sleeves (the award animation's hover, drop and settle)
    /// and clinks. A plate already in the scene (lying on the floor after a swipe) is lifted from
    /// where it is, not rebuilt; any other plate is built once, above the framed view, and swung in.
    /// Returns false when the plate is already a bar plate, is being dragged, the slot is invalid,
    /// or the plate is taken off again before it lands.
    @MainActor
    @discardableResult
    func loadPlateOntoBar(_ plate: EarnedPlate, rackSlot: Int) async -> Bool {
        if let existing = entityMap[plate.id] {
            guard existing.components[PlateRoleComponent.self]?.role == .floor else { return false }
            if case .draggingPlate(let dragging, _, _) = dragPhase, dragging === existing { return false }
            if showcaseEntity === existing {
                showcaseEntity = nil
                showcaseToken = nil
            }
            floorSettles[plate.id] = nil
            existing.stopAllAnimations(recursive: true)
        } else {
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
            entity.orientation = plateDisplayOrientation
            // Where the wall storage would be: above the bar-only framing.
            entity.position = SIMD3(0.70, 1.60, 0.12)
            entity.components[PhysicsBodyComponent.self]?.mode = .kinematic
            sceneRoot.addChild(entity)
            entityMap[plate.id] = entity
        }
        let slotOffsets: [Float] = [0.600, 0.652, 0.704, 0.756]
        guard slotOffsets.indices.contains(rackSlot), let entity = entityMap[plate.id] else { return false }
        let offset = slotOffsets[rackSlot]

        // Everything below moves in bar space, the way the swipe does: a move set up relative to
        // the scene root keeps writing scene-root values after the plate joins the bar.
        entity.components[PhysicsBodyComponent.self]?.mode = .kinematic
        entity.components[PhysicsMotionComponent.self] = PhysicsMotionComponent()
        entity.components.set(PlateRoleComponent(role: .bar))
        entity.setParent(barAnchor, preservingWorldTransform: true)
        entity.orientation = plateBarOrientation
        let mirror = makeMirrorEntity(from: entity, name: plate.id + "_mirror")
        // Keep input and collision so the left plate can start the same swipe-to-unrack gesture.
        mirror.components.remove(PhysicsMotionComponent.self)
        mirror.position = SIMD3(-entity.position.x, entity.position.y, entity.position.z)
        mirror.orientation = plateBarOrientation
        barAnchor.addChild(mirror)
        barPositionMap[plate.id] = SIMD3(offset, 0, 0)
        barMirrorMap[plate.id] = mirror

        if !isReduceMotionEnabled {
            let steps: [(SIMD3<Float>, TimeInterval, AnimationTimingFunction)] = [
                (SIMD3(offset + 0.12, 0.22, 0.05), 0.42, .easeInOut),
                (SIMD3(offset, 0.035, 0), 0.18, .easeIn),
                (SIMD3(offset, 0, 0), 0.12, .easeOut)
            ]
            for (target, duration, timing) in steps {
                // Taken off again mid-swing: the release owns the plate now.
                guard barMirrorMap[plate.id] === mirror else { return false }
                for (mover, sign) in [(entity, Float(1)), (mirror as Entity, Float(-1))] {
                    mover.move(
                        to: Transform(scale: mover.scale, rotation: plateBarOrientation,
                                      translation: SIMD3(sign * target.x, target.y, target.z)),
                        relativeTo: barAnchor, duration: duration, timingFunction: timing
                    )
                }
                try? await Task.sleep(for: .milliseconds(Int(duration * 1000)))
            }
        }
        // The last move's final frame can land a frame late: seat both now and once more after it.
        for pass in 0..<2 {
            if pass == 1 { try? await Task.sleep(for: .milliseconds(50)) }
            guard barMirrorMap[plate.id] === mirror else { return false }
            for (seated, x) in [(entity, offset), (mirror as Entity, -offset)] {
                seated.stopAllAnimations(recursive: false)
                seated.position = SIMD3(x, 0, 0)
                seated.orientation = plateBarOrientation
            }
        }
        if let audio = entity.components[PlateAudioCategoryComponent.self] {
            playClinkSound(on: entity, category: audio.category)
        }
        return true
    }

    /// Slides a bar plate and its mirror off the sleeves and drops the plate to the floor: the
    /// motion of a swipe. Returns false when the plate is not a bar plate here, is already sliding
    /// off, or is being dragged.
    @MainActor
    @discardableResult
    func releaseBarPlateToFloor(plateID: String) async -> Bool {
        guard let entity = entityMap[plateID],
              entity.components[PlateRoleComponent.self]?.role == .bar,
              !platesBeingUnracked.contains(plateID) else { return false }
        if case .draggingPlate(let dragging, _, _) = dragPhase, dragging === entity { return false }
        platesBeingUnracked.insert(plateID)
        defer { platesBeingUnracked.remove(plateID) }

        let mirror = barMirrorMap[plateID]
        if !isReduceMotionEnabled {
            let duration = barbellRackRoomSlideOutDuration(isReduceMotionEnabled: false)
            for slider in [entity, mirror].compactMap({ $0 }) {
                let target = Transform(
                    scale: slider.scale,
                    rotation: slider.orientation,
                    translation: SIMD3(
                        barbellRackRoomUnrackSlideTargetX(currentBarLocalX: slider.position.x),
                        slider.position.y - 0.02,
                        0.38
                    )
                )
                slider.move(to: target, relativeTo: barAnchor, duration: duration, timingFunction: .easeOut)
            }
            try? await Task.sleep(for: .milliseconds(Int(duration * 1000)))
        }

        if let mirror {
            mirror.isEnabled = false
            mirror.removeFromParent()
            if let model = mirror as? ModelEntity { preparedMirrors[plateID] = model }
        }
        barMirrorMap.removeValue(forKey: plateID)
        barPositionMap.removeValue(forKey: plateID)
        guard entityMap[plateID] === entity, !isPaused else { return false }

        entity.stopAllAnimations(recursive: false)
        entity.setParent(sceneRoot, preservingWorldTransform: true)
        entity.components.set(PlateRoleComponent(role: .floor))
        var release = barbellRackRoomFloorReleasePosition(localPosition: entity.position, maxAbsX: 0.74, minZ: -0.10, maxZ: 0.82)
        release.z = max(-0.10, min(0.82, release.z + Float.random(in: -0.10 ... 0.10)))
        entity.position = release
        entity.components[PhysicsMotionComponent.self] = PhysicsMotionComponent()
        entity.components[PhysicsBodyComponent.self]?.mode = .dynamic
        floorSettles[plateID] = BarbellFloorSettleState(delay: 0.1)

        if let audio = entity.components[PlateAudioCategoryComponent.self] {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(420))
                guard entity.components[PlateRoleComponent.self]?.role == .floor else { return }
                playDropSound(on: entity, category: audio.category)
                playDropHaptic(category: audio.category)
            }
        }
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

/// The rack room's light rig: one key spot, high and well in front of the bar, aimed at the floor
/// just in front of it, plus the room's light probe.
///
/// Who lights what: the plates' visible surfaces are vertical faces and rims that face the
/// camera or tilt up and away from it, so a high key only grazes them; it mostly sets the floor
/// pool and the wall, and is kept low. The plates take their light from the environment: the
/// soft glow behind the viewer (faces toward the camera) and a broad ceiling panel over the back
/// wall (the tops of plates, which the back wall, facing the viewer, never receives). See
/// RackRoomEnvironment.
///
/// Why the key's shape: the wall is only 24 cm behind the plates, so a cone boundary near the bar
/// draws a dome on the wall or a terminator across the plates. Far away and soft (inner cone
/// well inside the outer), plates, the falling path and the visible wall all sit in the smooth
/// falloff. Positions are in the scene root's space (bar at y 0.6, z 0.12; floor at y 0; back
/// wall face at z -0.12). Angles are RealityKit's spot cone angles in degrees.
struct RackRoomLightingPreset: Equatable {
    var keyIntensity: Float
    var keyPosition: SIMD3<Float>
    var keyTarget: SIMD3<Float>
    var keyInnerAngle: Float
    var keyOuterAngle: Float
    var keyAttenuationRadius: Float
    var imageBasedLightIntensityExponent: Float
    /// A shadow map for the key spot (bar, plates and stands throw real shadows on the floor
    /// and wall). Off: grounding shadows carry the contact cue; see the stage 1 report.
    var keyCastsShadow: Bool
    /// The legacy wall storage only (never built in the Cut bar-only rack): a soft wash on the
    /// plates hanging above the bar, which the overhead key barely reaches.
    var storageWashIntensity: Float
    var storageWashPosition: SIMD3<Float>

    static let readability = RackRoomLightingPreset(
        keyIntensity: 70_000,
        keyPosition: SIMD3(0, 5.0, 1.6),
        keyTarget: SIMD3(0, 0, 0.30),
        keyInnerAngle: 16,
        keyOuterAngle: 74,
        keyAttenuationRadius: 10,
        imageBasedLightIntensityExponent: -0.25,
        keyCastsShadow: false,
        storageWashIntensity: 7_000,
        storageWashPosition: SIMD3(0, 1.60, 1.0)
    )

    /// Light rooms (pale floor or wall) would blow out under the dark gym's key: scale the key
    /// down by how much brighter the room's brightest surface is than the dark gym's floor.
    /// Dark rooms keep the full key so plates stay lit.
    static func keyScale(brightestSurfaceLuminance luminance: CGFloat) -> Float {
        let reference: CGFloat = 0.40
        guard luminance > reference else { return 1 }
        return Float(pow(reference / luminance, 0.75))
    }

    /// The preset the scene uses. In debug builds, VOLIA_RACK_LIGHT="key=40000,ibl=1.2" in the
    /// launch environment overrides values for tuning on a device or in simulator captures. Names:
    /// key, keyY, keyZ, targetZ, inner, outer, atten, ibl, wash, shadow (0 or 1); the environment
    /// reads glow, glowCentre, glowHalf, panel, panelPitch and panelHalf (RackRoomEnvironment).
    /// The lathe plates' rig: the same high soft key, now casting a real shadow (one draw per
    /// plate makes the shadow map affordable), with the studio environment as fill.
    static let studio: RackRoomLightingPreset = {
        var preset = readability
        preset.keyCastsShadow = true
        preset.imageBasedLightIntensityExponent = -0.25
        return preset
    }()

    static var current: RackRoomLightingPreset { current(for: .legacy) }

    static func current(for style: RackPlateStyle) -> RackRoomLightingPreset {
        var preset = style == .lathe ? studio : readability
        #if DEBUG
        let overrides = rackRoomLightingOverrides(ProcessInfo.processInfo.environment["VOLIA_RACK_LIGHT"])
        if let value = overrides["key"] { preset.keyIntensity = value }
        if let value = overrides["keyY"] { preset.keyPosition.y = value }
        if let value = overrides["keyZ"] { preset.keyPosition.z = value }
        if let value = overrides["targetZ"] { preset.keyTarget.z = value }
        if let value = overrides["inner"] { preset.keyInnerAngle = value }
        if let value = overrides["outer"] { preset.keyOuterAngle = value }
        if let value = overrides["atten"] { preset.keyAttenuationRadius = value }
        if let value = overrides["ibl"] { preset.imageBasedLightIntensityExponent = value }
        if let value = overrides["wash"] { preset.storageWashIntensity = value }
        if let value = overrides["shadow"] { preset.keyCastsShadow = value != 0 }
        #endif
        return preset
    }
}

/// "name=value,name=value" into a dictionary; malformed pairs are skipped.
nonisolated func rackRoomLightingOverrides(_ text: String?) -> [String: Float] {
    guard let text else { return [:] }
    var result: [String: Float] = [:]
    for pair in text.split(separator: ",") {
        let parts = pair.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let value = Float(parts[1]) else { continue }
        result[parts[0]] = value
    }
    return result
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

    func scaledBrightness(_ multiplier: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        if getHue(&h, saturation: &s, brightness: &b, alpha: &a) {
            return UIColor(hue: h, saturation: s, brightness: max(0, min(1, b * multiplier)), alpha: a)
        }
        var w: CGFloat = 0
        if getWhite(&w, alpha: &a) {
            return UIColor(white: max(0, min(1, w * multiplier)), alpha: a)
        }
        return self
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
    /// The Cut rack: the bar alone. No wall storage is built and no storage plates are placed
    /// (the screen's tray holds them), dragging toward the wall no longer targets storage slots,
    /// and an upward swipe drops the plate to the floor like any other swipe. `floorPlates` stay
    /// in the mode only so a plate dropped on the floor can be dragged back and saved. Off by
    /// default, so every other caller builds the scene exactly as before.
    var barOnly = false
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
                // The room's light probe is awaited before anything is built, so the first frame
                // is already lit by it (no pop-in) and the build below runs without a suspension.
                // Built once per process; later scenes get it at once.
                // Lathe plates: the photographic studio (procedural room if it fails to load), and
                // every plate's mesh, materials and face textures, all before the first frame.
                RackOpenTrace.mark("make.start")
                let style = sceneState.plateStyle
                let studio = style == .lathe ? await sharedRackStudioEnvironmentResource() : nil
                let environment: EnvironmentResource?
                if let studio {
                    environment = studio
                } else {
                    environment = await sharedRackRoomEnvironmentResource()
                }
                RackOpenTrace.mark("make.environment")
                if style == .lathe {
                    await prepareLathePlates(latheRequests)
                }
                RackOpenTrace.mark("make.prepared")
                let iblExponent = studio != nil
                    ? (mood?.imageBasedLightIntensityExponent
                       ?? RackRoomLightingPreset.current(for: .lathe).imageBasedLightIntensityExponent)
                    : RackRoomLightingPreset.current.imageBasedLightIntensityExponent
                let interval = barbellSignposter.beginInterval("SceneBuild", id: barbellSignposter.makeSignpostID())
                defer { barbellSignposter.endInterval("SceneBuild", interval) }
                sceneState.sceneRoot   = Entity()
                sceneState.floorAnchor = Entity()
                sceneState.barAnchor   = Entity()
                sceneState.sceneRoot.addChild(sceneState.floorAnchor)
                sceneState.sceneRoot.addChild(sceneState.barAnchor)
                content.add(sceneState.sceneRoot)
                // Edges: 4x multisampling for the bar, plate rims and floor lines. No camera
                // effects: motion blur, depth of field and grain only soften a still room.
                content.renderingEffects.antialiasing = .multisample4X
                content.renderingEffects.motionBlur = .disabled
                content.renderingEffects.depthOfField = .disabled
                content.renderingEffects.cameraGrain = .disabled
                setupLighting(in: sceneState.sceneRoot)

                if let environment {
                    let iblEntity = Entity()
                    iblEntity.name = "rackRoomEnvironment"
                    iblEntity.components.set(ImageBasedLightComponent(
                        source: .single(environment),
                        intensityExponent: iblExponent
                    ))
                    // The studio's turn is baked into its pixels; the light entity stays unrotated.
                    sceneState.sceneRoot.addChild(iblEntity)
                    // The receiver applies to the whole subtree, including plates added later.
                    sceneState.sceneRoot.components.set(ImageBasedLightReceiverComponent(imageBasedLight: iblEntity))
                }

                switch mode {
                case .welcome(let plates):
                    setupWelcomeScene(content: &content, plates: plates, barSkinID: barSkinID)
                case .rackRoom(let racked, let floor, _, _):
                    setupRackRoomScene(content: &content, racked: racked, floor: floor, barSkinID: barSkinID, rackStyleID: rackStyleID, roomThemeID: roomThemeID, roomWallText: roomWallText)
                }

                sceneState.configureCameraPosition(for: mode, sizeClass: sizeClass, barOnly: barOnly)
                installFrameUpdates(content: content)
                RackOpenTrace.mark("make.built")
                RackOpenTrace.markNextFrame("firstFrame", content: content)
                if style == .lathe {
                    let later = latheLaterSceneRequests
                    Task(priority: .utility) { await prepareLathePlates(later) }
                }
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-BarbellSceneStats") {
                    var entities = 0, models = 0, plates = 0
                    @MainActor func count(_ entity: Entity) {
                        entities += 1
                        if entity is ModelEntity { models += 1 }
                        if entity.components[TierIDComponent.self] != nil { plates += 1 }
                        for child in entity.children { count(child) }
                    }
                    count(sceneState.sceneRoot)
                    DiagnosticsLogStore.shared.append("Scene entities=\(entities) models=\(models) plates=\(plates)", category: "Barbell")
                }
                #endif
            } update: { _ in
                // Intentionally empty -- scene owns its runtime state
            }
            .gesture(entityDragGesture)
            .gesture(welcomeLookGesture)
            .gesture(floorPanGesture)
            .simultaneousGesture(
                TapGesture().onEnded {
                    guard allowsInteraction, case .rackRoom = mode else { return }
                    dropShowcase()
                }
            )
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                // Bar-only framing follows the view's shape; every other mode ignores it.
                guard barOnly, size.width > 0, size.height > 0 else { return }
                sceneState.barOnlyAspect = Float(size.height / size.width)
                sceneState.configureCameraPosition(for: mode, sizeClass: sizeClass, barOnly: true)
            }
            .onChange(of: sizeClass) { _, _ in
                // Re-apply camera proxy on device rotation / iPad split view changes
                sceneState.configureCameraPosition(for: mode, sizeClass: sizeClass, barOnly: barOnly)
            }
            .onAppear {
                // RealityView can retain its content across navigation. Restart frame work
                // after a pause even when make does not run again.
                guard sceneState.isPaused, let scene = sceneState.sceneRoot.scene else { return }
                sceneState.isPaused = false
                if case .welcome = mode { sceneState.barbellSpinVelocity = 0.18 }
                let subscription = scene.subscribe(to: SceneEvents.Update.self) { event in
                    MainActor.assumeIsolated { updateFrame(deltaTime: event.deltaTime) }
                }
                sceneState.cancelFrameUpdates = { subscription.cancel() }
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

    /// Every face the scene's first frame shows, for prepareLathePlates. The bar-only Cut rack
    /// builds no floor plates (its mode's floor list is the whole tray), so it prepares none.
    private var latheRequests: [LathePlateRequest] {
        Self.latheFirstFrameRequests(mode: mode, barOnly: barOnly)
    }

    static func latheFirstFrameRequests(mode: BarbellRealityMode, barOnly: Bool) -> [LathePlateRequest] {
        switch mode {
        case .welcome(let plates):
            return plates.prefix(4).map {
                LathePlateRequest(tierID: $0.tierID, weightKg: $0.weightKg, engravingText: $0.engravingText,
                                  projection: BarbellPlateRenderProjection())
            }
        case .rackRoom(let racked, let floor, _, _):
            return WRKT.latheFirstFrameRequests(racked + (barOnly ? [] : floor))
        }
    }

    /// The faces the scene's plates need after the first frame: blank mirrors for a reload or a
    /// drag back onto the bar. Prepared in the background once the scene is built.
    private var latheLaterSceneRequests: [LathePlateRequest] {
        Self.latheLaterRequests(mode: mode, barOnly: barOnly)
    }

    static func latheLaterRequests(mode: BarbellRealityMode, barOnly: Bool) -> [LathePlateRequest] {
        guard case .rackRoom(let racked, let floor, _, _) = mode else { return [] }
        return WRKT.latheLaterRequests(racked + (barOnly ? [] : floor))
    }

    private var realityBackgroundColor: Color {
        if case .welcome = mode { return .clear }
        return roomTheme.swiftUIBackground
    }

    /// The home gym mood (lathe plates in the rack room, debug builds), or nil.
    private var mood: RackRoomMood? {
        guard case .rackRoom = mode else { return nil }
        return RackRoomMood.current(for: sceneState.plateStyle)
    }

    /// The room's colours, dimmed to the mood's dark room when there is one.
    private var roomTheme: RoomThemePreset {
        let theme = RoomThemePreset.preset(for: roomThemeID)
        return mood.map { theme.dimmed(by: $0.roomBrightness, floor: $0.floorBrightness) } ?? theme
    }

    @MainActor
    private func installFrameUpdates(content: RealityViewCameraContent) {
        sceneState.isPaused = false
        sceneState.cancelFrameUpdates?()
        if case .welcome = mode, sceneState.barbellSpinVelocity == 0 {
            sceneState.barbellSpinVelocity = 0.18
        }
        let subscription = content.subscribe(to: SceneEvents.Update.self) { event in
            MainActor.assumeIsolated {
                updateFrame(deltaTime: event.deltaTime)
            }
        }
        sceneState.cancelFrameUpdates = { subscription.cancel() }
    }

    private func updateFrame(deltaTime: TimeInterval) {
        if ProcessInfo.processInfo.systemUptime >= sceneState.animationDeadline { sceneState.flushSaves() }
        switch mode {
        case .welcome:
            if !BarbellRealityPerformanceBudget.requiresStaticOnlyRendering {
                sceneState.updateWelcomeSpin(deltaTime: deltaTime)
            }
        case .rackRoom:
            sceneState.boundaryElapsed += deltaTime
            if sceneState.boundaryElapsed >= 0.033 {
                sceneState.boundaryElapsed.formTruncatingRemainder(dividingBy: 0.033)
                recoverDynamicFloorPlates()
            }
            for id in Array(sceneState.floorSettles.keys) {
                guard let entity = sceneState.entityMap[id],
                      entity.components[PlateRoleComponent.self]?.role == .floor,
                      entity.components[PhysicsBodyComponent.self]?.mode == .dynamic else {
                    sceneState.floorSettles[id] = nil
                    continue
                }
                let motion = entity.components[PhysicsMotionComponent.self] ?? PhysicsMotionComponent()
                if sceneState.floorSettles[id]?.advance(deltaTime: deltaTime,
                    linearSpeed: simd_length(motion.linearVelocity),
                    angularSpeed: simd_length(motion.angularVelocity)) == true {
                    entity.components[PhysicsMotionComponent.self] = PhysicsMotionComponent()
                    entity.components[PhysicsBodyComponent.self]?.mode = .kinematic
                    sceneState.originalTransforms[id] = Transform(matrix: entity.transformMatrix(relativeTo: nil))
                    sceneState.floorSettles[id] = nil
                }
            }
            if let token = sceneState.showcaseSpinToken, sceneState.showcaseToken == token,
               let entity = sceneState.showcaseEntity {
                let previous = sceneState.showcaseElapsed
                sceneState.showcaseElapsed += deltaTime
                // Spin starts after levitation: changing transform cancels move animations.
                let spinTime = max(0, sceneState.showcaseElapsed - 0.58) - max(0, previous - 0.58)
                if spinTime > 0 {
                    entity.transform.rotation *= simd_quatf(angle: barbellSpinIncrement(deltaTime: spinTime), axis: SIMD3(0, 1, 0))
                }
                if sceneState.showcaseElapsed >= 3 { dropShowcase(immediate: true) }
            }
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
        let lighting = RackRoomLightingPreset.current(for: sceneState.plateStyle)
        let theme = roomTheme
        let keyScale = RackRoomLightingPreset.keyScale(
            brightestSurfaceLuminance: max(theme.floorLuminance, theme.backdropLuminance))

        // Home gym mood: the lamp over the bar carries the shadowed light; sign and strip add
        // colour. No studio key and no storage wash.
        if let mood {
            mood.addFixtures(to: sceneRoot, signText: barbellNormalizedRoomWallText(roomWallText) ?? "VOLIA",
                             keyScale: keyScale)
            return
        }

        // Key: high and well in front of the bar, aimed at the floor just in front of it.
        let key = Entity()
        key.name = "rackRoomKey"
        key.components.set(SpotLightComponent(
            color: UIColor(red: 1.0, green: 0.985, blue: 0.96, alpha: 1),
            intensity: lighting.keyIntensity * keyScale,
            innerAngleInDegrees: lighting.keyInnerAngle,
            outerAngleInDegrees: lighting.keyOuterAngle,
            attenuationRadius: lighting.keyAttenuationRadius
        ))
        if lighting.keyCastsShadow {
            var shadow = SpotLightComponent.Shadow()
            shadow.depthBias = 2
            key.components.set(shadow)
        }
        sceneRoot.addChild(key)
        key.look(at: lighting.keyTarget, from: lighting.keyPosition, relativeTo: sceneRoot)

        // The legacy wall storage hangs plates above the key's reach: give them a soft wash. The
        // Cut bar-only rack builds no storage and gets no wash.
        if case .rackRoom = mode, showsStorage, !barOnly {
            let wash = Entity()
            wash.name = "rackRoomStorageWash"
            wash.components.set(PointLightComponent(
                color: .white, intensity: lighting.storageWashIntensity, attenuationRadius: 3
            ))
            wash.position = lighting.storageWashPosition
            sceneRoot.addChild(wash)
        }
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
                    role: .bar,
                    plateStyle: sceneState.plateStyle
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

    /// The starter plate is never shown or counted as a bar plate, even if a caller passes it.
    private var allRackedPlates: [EarnedPlate] {
        if case .rackRoom(let racked, _, _, _) = mode { return racked.filter { !$0.isStarterPlate } }
        return []
    }

    private func unloadTraceElapsedMs(for plateID: String) -> Int {
        guard let start = sceneState.unloadTraceStartTimes[plateID] else { return 0 }
        return Int((Date().timeIntervalSinceReferenceDate - start) * 1000)
    }

    private func unloadTraceSnapshot(
        _ stage: String,
        plateID: String,
        entity: Entity,
        extra: @autoclosure () -> String = ""
    ) {
        #if DEBUG
        guard barbellUnloadTraceEnabled else { return }
        let role = entity.components[PlateRoleComponent.self]?.role
        let bodyMode = entity.components[PhysicsBodyComponent.self]?.mode
        let motion = entity.components[PhysicsMotionComponent.self]
        let linear = motion.map { barbellDiagnosticsV3($0.linearVelocity) } ?? "nil"
        let angular = motion.map { barbellDiagnosticsV3($0.angularVelocity) } ?? "nil"
        let rawParentName = entity.parent?.name ?? ""
        let parentName = rawParentName.isEmpty ? "unnamed" : rawParentName
        let collisionShapeCount = entity.components[CollisionComponent.self]?.shapes.count ?? 0
        barbellDiagnosticsLog(
            "UNLOAD_TRACE",
            [
                "stage=\(stage)",
                "id=\(plateID)",
                "t=\(unloadTraceElapsedMs(for: plateID))ms",
                "parent=\(parentName)",
                "role=\(String(describing: role))",
                "physics=\(String(describing: bodyMode))",
                "local=\(barbellDiagnosticsV3(entity.position))",
                "world=\(barbellDiagnosticsV3(entity.position(relativeTo: nil)))",
                "scene=\(barbellDiagnosticsV3(entity.position(relativeTo: sceneState.sceneRoot)))",
                "bar=\(barbellDiagnosticsV3(entity.position(relativeTo: sceneState.barAnchor)))",
                "rotLocal=\(barbellDiagnosticsQ(entity.orientation))",
                "rotWorld=\(barbellDiagnosticsQ(entity.orientation(relativeTo: nil)))",
                "scale=\(barbellDiagnosticsV3(entity.scale))",
                "linear=\(linear)",
                "angular=\(angular)",
                "collisionShapes=\(collisionShapeCount)",
                extra()
            ]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        )
        #endif
    }

    private func startUnloadTrace(plateID: String, entity: Entity, touched: Entity, extra: @autoclosure () -> String) {
        #if DEBUG
        guard barbellUnloadTraceEnabled else { return }
        sceneState.unloadTraceTasks[plateID]?.cancel()
        sceneState.unloadTraceStartTimes[plateID] = Date().timeIntervalSinceReferenceDate
        unloadTraceSnapshot(
            "start",
            plateID: plateID,
            entity: entity,
            extra: "touched=\(touched.name) \(extra()) barAnchorLocal=\(barbellDiagnosticsV3(sceneState.barAnchor.position)) sceneRoot=\(barbellDiagnosticsV3(sceneState.sceneRoot.position))"
        )
        #endif
    }

    private func scheduleUnloadTraceSamples(
        plateID: String,
        entity: Entity,
        mirrorEntity: Entity?,
        stagePrefix: String,
        sampleMilliseconds: [Int],
        finishReason: String? = nil
    ) {
        #if DEBUG
        guard barbellUnloadTraceEnabled else { return }
        sceneState.unloadTraceTasks[plateID]?.cancel()
        sceneState.unloadTraceTasks[plateID] = Task { @MainActor in
            var previous = 0
            for ms in sampleMilliseconds {
                try? await Task.sleep(for: .milliseconds(max(0, ms - previous)))
                previous = ms
                guard !Task.isCancelled else { return }
                unloadTraceSnapshot("\(stagePrefix)_\(ms)ms", plateID: plateID, entity: entity)
                if let mirrorEntity {
                    unloadTraceSnapshot("\(stagePrefix)_mirror_\(ms)ms", plateID: plateID, entity: mirrorEntity)
                }
            }
            if let finishReason {
                finishUnloadTrace(plateID: plateID, entity: entity, reason: finishReason)
            }
        }
        #endif
    }

    private func finishUnloadTrace(plateID: String, entity: Entity, reason: String) {
        #if DEBUG
        guard barbellUnloadTraceEnabled else { return }
        sceneState.unloadTraceTasks[plateID]?.cancel()
        sceneState.unloadTraceTasks[plateID] = nil
        unloadTraceSnapshot("finish", plateID: plateID, entity: entity, extra: "reason=\(reason)")
        sceneState.unloadTraceStartTimes.removeValue(forKey: plateID)
        #endif
    }

    private func settleUnloadedFloorPlate(entity: Entity, plateID: String, delayMs: Int) {
        // Minimum delay avoids sampling before the first physics step. Settle at rest
        // (0.02 m/s, 0.05 rad/s), with a 3 s hard cap so a bounce cannot poll forever.
        // Drag start removes this state so a later fall cannot freeze mid-air.
        sceneState.floorSettles[plateID] = BarbellFloorSettleState(delay: Double(max(delayMs, 100)) / 1000)
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
                    let dx = abs(value.translation.width)
                    let dy = abs(value.translation.height)
                    // Minimum movement guard for all floor plates: short touches (< 8pt) stay
                    // in .idle so onEnded treats them as taps (tap → showcase).
                    // DragGesture(minimumDistance: 1) fires onChanged for any finger wobble,
                    // so without this guard taps commit a drag and skip the tap path entirely.
                    guard (dx + dy) > 8 else { break }
                    // Stored plates additionally require vertical-dominant intent -- a horizontal-
                    // dominant gesture is almost certainly a bar swipe that bled onto this entity.
                    if sceneState.storageSlotByPlate[entity.name] != nil && sceneState.showcaseEntity !== entity {
                        guard dy >= dx else { break }
                    }
                    // One-time: enter dragging state (captures originRole) and reparent to scene root.
                    // transition() rejects .draggingPlate -> .draggingPlate, so call it
                    // unconditionally but only run reparent when it succeeds.
                    if sceneState.transition(to: .draggingPlate(entity, plateID: entity.name, originRole: .floor)) {
                        // If this plate was in showcase, cancel the spin without dropping it --
                        // the drag handler takes over physics from here.
                        if sceneState.showcaseEntity === entity {
                            sceneState.showcaseEntity = nil
                            sceneState.showcaseToken = nil
                        }
                        // Cancel any pending settle for this plate. If not cancelled,
                        // the old settle can fire during a later freeDrop fall and freeze
                        // the plate kinematic mid-air.
                        sceneState.floorSettles[entity.name] = nil
                        _ = sceneState.prepareMirror(for: entity, plateID: entity.name)
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
                    let inStorageZone = !barOnly && entityLocalY > barLocalY + 0.50
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
                    startUnloadTrace(
                        plateID: outermostID,
                        entity: outermostEntity,
                        touched: entity,
                        extra: "gestureTranslation=(\(String(format: "%.1f", value.translation.width)),\(String(format: "%.1f", value.translation.height))) gestureVelocity=(\(String(format: "%.1f", value.velocity.width)),\(String(format: "%.1f", value.velocity.height))) rackPosition=\(outermostPlate?.rackPosition.map(String.init) ?? "nil")"
                    )
                    #if DEBUG
                    barbellLog("DRAG_START", "id=\(outermostID) role=bar(outermost) touched=\(entity.name) world=\(v3(outermostEntity.position(relativeTo: nil)))")
                    #endif
                    barbellDiagnosticsLog(
                        "UNRACK_START",
                        "id=\(outermostID) touched=\(entity.name) dx=\(String(format: "%.1f", dx)) dy=\(String(format: "%.1f", dy)) world=\(barbellDiagnosticsV3(outermostEntity.position(relativeTo: nil)))"
                    )
                    // Slide outward from the current sleeve side. A fixed +0.48 target moved
                    // right-side plates inward through the stack before release, causing visible
                    // clipping and a hitch when physics took over.
                    let outerWorldPos = outermostEntity.position(relativeTo: nil)
                    let slideTargetX = barbellRackRoomUnrackSlideTargetX(currentBarLocalX: outermostEntity.position.x)
                    // barAnchor-local Z 0.38 → sceneRoot-local Z 0.50 (barAnchorZ 0.12 + 0.38).
                    // That keeps the plate inside the physics sandbox (maxZ 0.82) and well clear of
                    // the front wall (inner face Z 1.15). The previous world-space constant 0.22
                    // converted to barAnchor-local Z ~1.40 (sceneRoot Z ~1.52), placing the plate
                    // 37 cm past the front wall and 70 cm outside the sandbox every unrack.
                    let slideBarLocalZ: Float = 0.38
                    let slideOutDuration = barbellRackRoomSlideOutDuration(isReduceMotionEnabled: sceneState.isReduceMotionEnabled)
                    // DO NOT call setParent here. Reparenting cancels any in-flight move() animation.
                    // Entity stays on barAnchor so the slide runs to completion.
                    // snapToFloor (called from onEnded) does the setParent.
                    //
                    // Use relativeTo: barAnchor (local space) instead of relativeTo: nil (world space).
                    // World-space move() calls setTransformMatrix(relativeTo: nil) each frame, which
                    // triggers a full RealityKit render graph re-evaluation and ~12 AR material
                    // re-resolves per frame during the animation. Local-space avoids this.
                    let barWorldPos = sceneState.barAnchor.position(relativeTo: nil)
                    let slideTarget = Transform(
                        scale: outermostEntity.scale,
                        rotation: outermostEntity.orientation,
                        translation: SIMD3(
                            slideTargetX - barWorldPos.x,
                            (outerWorldPos.y - 0.02) - barWorldPos.y,
                            slideBarLocalZ
                        )
                    )
                    unloadTraceSnapshot(
                        "slide_target",
                        plateID: outermostID,
                        entity: outermostEntity,
                        extra: "targetBarLocal=\(barbellDiagnosticsV3(slideTarget.translation)) slideBarLocalZ=\(String(format: "%.3f", slideBarLocalZ)) durationMs=\(Int(slideOutDuration * 1000)) barWorld=\(barbellDiagnosticsV3(barWorldPos))"
                    )
                    outermostEntity.move(to: slideTarget, relativeTo: sceneState.barAnchor, duration: slideOutDuration, timingFunction: .easeOut)
                    sceneState.barSlideStartTime = Date()
                    sceneState.animationDeadline = max(sceneState.animationDeadline, ProcessInfo.processInfo.systemUptime + slideOutDuration)
                    // Mirror slides to -slideTargetX and is removed after the animation.
                    // Removing at 200ms (animation end) prevents the ghost-plate-behind-wall
                    // problem: the mirror has no physics, so it would sit past the wall until
                    // finishUnrack fires at 1400ms.
                    let mirrorEntityForTrace = sceneState.barMirrorMap[outermostID]
                    if let mirrorEntity = mirrorEntityForTrace {
                        let mirrorWorldPos = mirrorEntity.position(relativeTo: nil)
                        let mirrorSlideTarget = Transform(
                            scale: mirrorEntity.scale,
                            rotation: mirrorEntity.orientation,
                            translation: SIMD3(
                                -slideTargetX - barWorldPos.x,
                                (mirrorWorldPos.y - 0.02) - barWorldPos.y,
                                slideBarLocalZ
                            )
                        )
                        mirrorEntity.move(to: mirrorSlideTarget, relativeTo: sceneState.barAnchor, duration: slideOutDuration, timingFunction: .easeOut)
                        let capturedMirror = mirrorEntity
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(Int(slideOutDuration * 1000)))
                            capturedMirror.isEnabled = false
                            capturedMirror.removeFromParent()
                            if let mirror = capturedMirror as? ModelEntity {
                                sceneState.preparedMirrors[outermostID] = mirror
                            }
                            sceneState.barMirrorMap.removeValue(forKey: outermostID)
                        }
                    }
                    scheduleUnloadTraceSamples(
                        plateID: outermostID,
                        entity: outermostEntity,
                        mirrorEntity: mirrorEntityForTrace,
                        stagePrefix: "slide_sample",
                        sampleMilliseconds: [0, 16, 33, 50, 66, 100, 133, 166, 200, 240]
                    )
                }
            }
            .onEnded { value in
                guard allowsInteraction else { return }
                let tapped = value.entity
                // Tap detection: dragPhase stayed .idle means onChanged never committed a drag
                // (storage plate movement < 8pt threshold). Treat as info-card tap.
                if case .rackRoom = mode, case .idle = sceneState.dragPhase {
                    let tapID = tapped.name.replacingOccurrences(of: "_mirror", with: "")
                    if let roleComp = tapped.components[PlateRoleComponent.self],
                       roleComp.role == .floor,
                       tapped.name != "barHitZone",
                       let entity = sceneState.entityMap[tapID] {
                        startShowcase(entity: entity)
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
                    let targetSlot = swipedUpward && !barOnly ? sceneState.findFreeStorageSlot() : nil
                    let plateToUnrack = allRackedPlates.first(where: { $0.id == plateID })
                    // Wait only for the remaining slide time before reparenting.
                    // onChanged recorded barSlideStartTime when the animation started; subtract
                    // elapsed time so a user who holds after swiping gets no extra pause.
                    let slideDuration = barbellRackRoomSlideOutDuration(isReduceMotionEnabled: sceneState.isReduceMotionEnabled)
                    let elapsed = sceneState.barSlideStartTime.map { Date().timeIntervalSince($0) } ?? slideDuration
                    let delay = Int(max(0, slideDuration - elapsed) * 1000)
                    sceneState.barSlideStartTime = nil
                    sceneState.platesBeingUnracked.insert(plateID)
                    unloadTraceSnapshot(
                        "end_bar_origin",
                        plateID: plateID,
                        entity: entity,
                        extra: "swipedUpward=\(swipedUpward) targetSlot=\(targetSlot.map(String.init) ?? "nil") elapsedMs=\(Int(elapsed * 1000)) remainingDelayMs=\(delay) gestureTranslation=(\(String(format: "%.1f", value.translation.width)),\(String(format: "%.1f", value.translation.height))) gestureVelocity=(\(String(format: "%.1f", value.velocity.width)),\(String(format: "%.1f", value.velocity.height))) pendingUnracks=\(sceneState.platesBeingUnracked.count)"
                    )
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(delay))
                        unloadTraceSnapshot("post_slide_delay", plateID: plateID, entity: entity, extra: "targetSlot=\(targetSlot.map(String.init) ?? "nil")")
                        if let slot = targetSlot {
                            // Reparent from barAnchor to sceneRoot before storage snap.
                            entity.setParent(sceneState.sceneRoot, preservingWorldTransform: true)
                            entity.components[PhysicsBodyComponent.self]?.mode = .kinematic
                            unloadTraceSnapshot("storage_reparented", plateID: plateID, entity: entity, extra: "slot=\(slot)")
                            snapToStorageSlot(entity: entity, plateID: plateID, slotIndex: slot)
                            finishUnrack(plateID: plateID, plate: plateToUnrack)
                            sceneState.platesBeingUnracked.remove(plateID)
                            finishUnloadTrace(plateID: plateID, entity: entity, reason: "storage_slot_\(slot)")
                        } else {
                            snapToFloor(entity: entity, plateID: plateID)
                            // snapToFloor clears platesBeingUnracked after the scripted fall animation
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
        let interval = barbellSignposter.beginInterval("snapToBar", id: barbellSignposter.makeSignpostID())
        defer { sceneState.deferSave(untilAfter: sceneState.isReduceMotionEnabled ? 0 : 0.27) { barbellSignposter.endInterval("snapToBar", interval) } }
        #if DEBUG
        barbellLog("SNAP_BAR", "id=\(plateID) pos=\(v3(entity.position)) world=\(v3(entity.position(relativeTo: nil)))")
        #endif
        barbellDiagnosticsLog("SNAP_BAR", "id=\(plateID) local=\(barbellDiagnosticsV3(entity.position)) world=\(barbellDiagnosticsV3(entity.position(relativeTo: nil)))")
        let slotOffsets: [Float] = [0.600, 0.652, 0.704, 0.756]
        let occupiedSlots = Set(allRackedPlates.compactMap(\.rackPosition)).union(
            sceneState.barPositionMap.values.compactMap { position in
                slotOffsets.firstIndex { abs($0 - position.x) < 0.001 }
            }
        )
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
        // Built via makeMirrorEntity (not clone) to reuse cached Metal pipeline states and avoid
        // per-mirror GPU stalls. Flip to opposite X immediately so both sides never share a position.
        let mirrorEntity = sceneState.prepareMirror(for: entity, plateID: plateID)
        mirrorEntity.stopAllAnimations(recursive: true)
        mirrorEntity.transform = Transform()
        mirrorEntity.isEnabled = true
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

        let animDelay = sceneState.isReduceMotionEnabled ? 0.0 : 0.27
        // Capture before the async boundary to avoid stale allFloorPlates reads if the model
        // is mutated by a concurrent onRack callback from a second plate.
        let plateToRack = allFloorPlates.first(where: { $0.id == plateID })
        let audioComp = entity.components[PlateAudioCategoryComponent.self]
        sceneState.deferSave(untilAfter: animDelay) {
            if let plate = plateToRack {
                let interval = barbellSignposter.beginInterval("onRack", id: barbellSignposter.makeSignpostID())
                defer { barbellSignposter.endInterval("onRack", interval) }
                onRackCallback?(plate)
                DiagnosticsLogStore.shared.append("Rack id=\(plateID)", category: "Barbell")
                if let audio = audioComp {
                    playClinkSound(on: entity, category: audio.category)
                    playRackHaptic(category: audio.category)
                }
            }
        }
    }

    private func snapToFloor(entity: Entity, plateID: String) {
        let interval = barbellSignposter.beginInterval("snapToFloor", id: barbellSignposter.makeSignpostID())
        defer { sceneState.deferSave(untilAfter: 0) { barbellSignposter.endInterval("snapToFloor", interval) } }
        #if DEBUG
        barbellLog("SNAP_FLOOR", "id=\(plateID) BEFORE setParent: pos=\(v3(entity.position)) world=\(v3(entity.position(relativeTo: nil))) phys=\(String(describing:entity.components[PhysicsBodyComponent.self]?.mode))")
        #endif
        barbellDiagnosticsLog(
            "SNAP_FLOOR_BEGIN",
            "id=\(plateID) local=\(barbellDiagnosticsV3(entity.position)) world=\(barbellDiagnosticsV3(entity.position(relativeTo: nil))) physics=\(String(describing: entity.components[PhysicsBodyComponent.self]?.mode))"
        )
        unloadTraceSnapshot("snap_floor_begin", plateID: plateID, entity: entity)
        // preservingWorldTransform: true keeps the plate at barbell height in sceneRoot-local space
        // (Y ≈ 0.58, Z ≈ 0.50) so the physics solver drives a full ~58 cm fall to the floor.
        // The previous preservingWorldTransform: false + manual position approach produced
        // barAnchor-local coordinates in sceneRoot space (Y ≈ -0.02), placing the plate
        // 2 cm below the floor collider top — 8 cm after the safety clamp — so the plate
        // barely fell and frequently penetrated the floor.
        entity.setParent(sceneState.sceneRoot, preservingWorldTransform: true)
        entity.components.set(PlateRoleComponent(role: .floor))
        #if DEBUG
        barbellLog("SNAP_FLOOR", "id=\(plateID) AFTER  setParent: pos=\(v3(entity.position)) floorAnchor=\(v3(sceneState.floorAnchor.position))")
        #endif
        barbellDiagnosticsLog(
            "SNAP_FLOOR_REPARENTED",
            "id=\(plateID) local=\(barbellDiagnosticsV3(entity.position)) world=\(barbellDiagnosticsV3(entity.position(relativeTo: nil))) sceneRoot=\(barbellDiagnosticsV3(sceneState.sceneRoot.position))"
        )
        unloadTraceSnapshot("snap_floor_reparented", plateID: plateID, entity: entity)

        // Slide always ends at the same X (±0.74) and Z (≈0.50). Rapidly unracking multiple
        // plates spawns them at identical world positions. Completely-overlapping dynamic bodies
        // produce explosive separation forces that push one plate through the floor in a single
        // physics step. Scatter Z by up to ±10 cm so each plate starts at a distinct position.
        let sceneX = entity.position.x
        let clampedX = clampFloorPlateX(sceneX, maxAbsX: floorPhysicsMaxAbsX)
        if clampedX != sceneX { entity.position.x = clampedX }
        let sceneZ = entity.position.z
        let scatteredZ = max(floorPhysicsMinZ, min(floorPhysicsMaxZ, sceneZ + Float.random(in: -0.10 ... 0.10)))
        entity.position.z = scatteredZ
        unloadTraceSnapshot(
            "snap_floor_release_clamped",
            plateID: plateID,
            entity: entity,
            extra: "bounds=maxAbsX:\(String(format: "%.2f", floorPhysicsMaxAbsX)) scatteredZ=\(String(format: "%.3f", scatteredZ))"
        )

        // Clear any accumulated kinematic velocity then go dynamic immediately — no kinematic
        // pause, no artificial impulse. Plate is at barbell height (Y ≈ 0.58 sceneRoot-local)
        // and falls ~58 cm under gravity alone (~320 ms fall time).
        entity.components[PhysicsMotionComponent.self] = PhysicsMotionComponent()
        entity.components[PhysicsBodyComponent.self]?.mode = .dynamic
        unloadTraceSnapshot("snap_floor_dynamic_enabled", plateID: plateID, entity: entity)
        #if DEBUG
        barbellLog("SNAP_FLOOR", "id=\(plateID) physics=dynamic localPos=\(v3(entity.position))")
        #endif

        sceneState.floorSettles[plateID] = nil
        let plateToUnrack = allRackedPlates.first(where: { $0.id == plateID })
        sceneState.platesBeingUnracked.remove(plateID)
        finishUnrack(plateID: plateID, plate: plateToUnrack)
        finishUnloadTrace(plateID: plateID, entity: entity, reason: "dynamic_released")

        if let audio = entity.components[PlateAudioCategoryComponent.self] {
            // 0.42 s ≈ fall time (0.32 s) + first-bounce settling
            scheduleDropFeedback(on: entity, category: audio.category, delay: 0.42)
        }
        // 1.2 s: fall (~320 ms) + bounces (restitution 0.18, ~2 bounces) + settle margin.
        settleUnloadedFloorPlate(entity: entity, plateID: plateID, delayMs: 100)
    }

    /// plate is pre-captured by the caller before any async gap to avoid stale allRackedPlates reads.
    private func finishUnrack(plateID: String, plate: EarnedPlate?) {
        barbellDiagnosticsLog(
            "FINISH_UNRACK",
            "id=\(plateID) plateFound=\(plate != nil) mirrorFound=\(sceneState.barMirrorMap[plateID] != nil) barPositionFound=\(sceneState.barPositionMap[plateID] != nil)"
        )
        if let plate {
            // A storage return continues moving for 350 ms after the sleeve slide.
            let delay = sceneState.storageSlotByPlate[plateID] == nil ? 0 : 0.35
            sceneState.deferSave(untilAfter: delay) {
                let interval = barbellSignposter.beginInterval("onUnrack", id: barbellSignposter.makeSignpostID())
                defer { barbellSignposter.endInterval("onUnrack", interval) }
                onUnrackCallback?(plate)
                DiagnosticsLogStore.shared.append("Unrack id=\(plateID)", category: "Barbell")
            }
        }
        if let mirror = sceneState.barMirrorMap[plateID] as? ModelEntity {
            mirror.isEnabled = false
            mirror.removeFromParent()
            sceneState.preparedMirrors[plateID] = mirror
        }
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
            sceneState.animationDeadline = max(sceneState.animationDeadline, ProcessInfo.processInfo.systemUptime + 0.35)
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

        sceneState.floorSettles[plateID] = nil
    }

    private func scheduleDropFeedback(on entity: Entity, category: PlateAudioCategory, delay: TimeInterval) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
            guard entity.components[PlateRoleComponent.self]?.role == .floor else { return }
            playDropSound(on: entity, category: category)
            playDropHaptic(category: category)
        }
    }

    // MARK: - Plate showcase

    private func startShowcase(entity: Entity) {
        // If replacing an existing showcase, drop the previous plate.
        if let prev = sceneState.showcaseEntity, prev !== entity {
            prev.components[PhysicsBodyComponent.self]?.mode = .dynamic
        }

        let token = UUID().uuidString
        sceneState.showcaseEntity    = entity
        sceneState.showcaseToken     = token
        sceneState.showcaseStartTime = Date()

        // Ensure kinematic so position animation works.
        entity.components[PhysicsBodyComponent.self]?.mode = .kinematic

        // Snap orientation instantly so the rise animation is position-only.
        // Animating rotation and position at once reads as a "flop" rather than a levitation.
        let upright = simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0))
        entity.transform.rotation = upright

        // Levitate to center-scene (position only — rotation already set above).
        let target = Transform(scale: .one, rotation: upright, translation: SIMD3(0, 0.90, 0.20))
        entity.move(to: target, relativeTo: sceneState.sceneRoot, duration: 0.55, timingFunction: .easeOut)

        // Spin: starts after levitation to avoid cancelling the move() animation.
        // Directly modifying entity.transform cancels any in-flight RealityKit animation,
        // so the spin loop must not start until move() has finished (~0.55 s).
        sceneState.showcaseSpinToken = token
        sceneState.showcaseElapsed = 0
    }

    private func dropShowcase(immediate: Bool = false) {
        guard let entity = sceneState.showcaseEntity else { return }
        // Debounce: the simultaneousGesture TapGesture fires on the same tap that
        // starts the showcase. Without this guard it would immediately drop the plate.
        if !immediate && Date().timeIntervalSince(sceneState.showcaseStartTime) < 0.40 { return }
        sceneState.showcaseEntity = nil
        sceneState.showcaseToken  = nil
        entity.components[PhysicsBodyComponent.self]?.mode = .dynamic
    }

    // MARK: RackRoom scene setup

    /// Grounding shadows apply to the entity's own mesh, not its descendants: a stand is a few
    /// separate parts, so each casts its own.
    private func castGroundingShadows(fromModelsIn root: Entity) {
        if root.components[ModelComponent.self] != nil {
            root.components.set(GroundingShadowComponent(castsShadow: true))
        }
        for child in root.children { castGroundingShadows(fromModelsIn: child) }
    }

    private func makeRoomWallText(_ text: String?, theme: RoomThemePreset) -> Entity? {
        guard let normalized = barbellNormalizedRoomWallText(text) else { return nil }

        let container = Entity()
        container.name = "roomWallText"
        container.position = SIMD3(0, 1.12, -0.100)

        // Recessed plaque behind the text for visual grounding
        let backing = ModelEntity(
            mesh: cachedBox(size: SIMD3(1.15, 0.22, 0.010)),
            materials: [pbrMaterial(
                color: theme.backdropColor.scaledBrightness(0.58),
                metallic: max(0.02, theme.backdropMetallic),
                roughness: min(0.98, theme.backdropRoughness + 0.04)
            )]
        )
        backing.position = SIMD3(0, 0, -0.010)
        container.addChild(backing)

        let textFont = UIFont(name: "BarlowSemiCondensed-Black", size: 0.28)
            ?? .systemFont(ofSize: 0.28, weight: .heavy)
        let mesh = MeshResource.generateText(
            normalized,
            extrusionDepth: 0.006,
            font: textFont,
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
        let textEntity = ModelEntity(mesh: mesh, materials: [material])
        container.addChild(textEntity)

        return container
    }

    // Baseboard and vertical pilasters layered in front of the backdrop to give the flat wall
    // surface architectural depth. Positioned between the backdrop and plateZoneBacking in z
    // so they're visible where the backdrop shows through but hidden behind the storage panel.
    private func addRoomArchitectureDetails(theme: RoomThemePreset) {
        let pilasterColor = theme.backdropColor.scaledBrightness(0.68)
        let baseColor = theme.backdropColor.scaledBrightness(0.60)
        let pilMat = pbrMaterial(
            color: pilasterColor,
            metallic: max(0.02, theme.backdropMetallic),
            roughness: min(0.98, theme.backdropRoughness + 0.03)
        )
        let baseMat = pbrMaterial(
            color: baseColor,
            metallic: theme.backdropMetallic,
            roughness: min(0.99, theme.backdropRoughness + 0.05)
        )

        // Baseboard: darker strip along the bottom of the wall (below the storage zone)
        let baseboard = ModelEntity(
            mesh: cachedBox(size: SIMD3(2.44, 0.11, 0.018)),
            materials: [baseMat]
        )
        baseboard.position = SIMD3(0, 0.049, -0.122)
        sceneState.sceneRoot.addChild(baseboard)

        // Pilasters: vertical accents flanking the sign zone (5 cm: 2 cm shimmered)
        for xPos: Float in [-0.62, 0.62] {
            let pilaster = ModelEntity(
                mesh: cachedBox(size: SIMD3(0.050, 1.52, 0.018)),
                materials: [pilMat]
            )
            pilaster.position = SIMD3(xPos, 0.74, -0.122)
            sceneState.sceneRoot.addChild(pilaster)
        }
    }

    private func setupRackRoomScene(
        content: inout RealityViewCameraContent,
        racked: [EarnedPlate], floor: [EarnedPlate],
        barSkinID: Int = 0,
        rackStyleID: String = "matte_black",
        roomThemeID: String = "dark_gym",
        roomWallText: String? = nil
    ) {
        let theme = roomTheme
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

        // The mood's lit sign takes the wall text's place.
        if mood == nil, let wallText = makeRoomWallText(roomWallText, theme: theme) {
            sceneState.sceneRoot.addChild(wallText)
        }

        addRoomArchitectureDetails(theme: theme)

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

        // Subtle platform strips make sliding/falling easier to read against the floor. Half as
        // many as before and a few centimetres wide: 1 cm strips and 8 mm seams were a pixel or
        // two on screen and shimmered as the camera framing changed.
        let stripMat = pbrMaterial(color: theme.stripColor, metallic: 0.03, roughness: 0.9)
        for x in barbellRackRoomFloorStripXs {
            let strip = ModelEntity(
                mesh: cachedBox(size: SIMD3(barbellRackRoomFloorLineWidth, 0.004, 3.2)),
                materials: [stripMat]
            )
            strip.position = SIMD3(x, 0.0005, -0.5)
            sceneState.sceneRoot.addChild(strip)
        }
        for z in barbellRackRoomFloorSeamZs {
            let seam = ModelEntity(
                mesh: cachedBox(size: SIMD3(1.7, 0.004, barbellRackRoomFloorLineWidth)),
                materials: [stripMat]
            )
            seam.position = SIMD3(0, 0.001, z)
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
            castGroundingShadows(fromModelsIn: stand)
            stand.position = SIMD3(xSign * 0.40, 0.3, barbellZ)
            sceneState.sceneRoot.addChild(stand)
        }

        // Bar
        let bar = makeBarEntity(skinID: barSkinID)
        bar.components.set(GroundingShadowComponent(castsShadow: true))
        bar.position = SIMD3(0, 0.6, barbellZ)
        sceneState.sceneRoot.addChild(bar)
        sceneState.barAnchor.position = SIMD3(0, 0.6, barbellZ)
        sceneState.sceneRoot.addChild(sceneState.barAnchor)

        // Collars sit just inside the plate stack, marking the inner boundary of the loading zone.
        // Layout: stands(±0.40) → collar(±0.54) → plates(0.60-0.756) → bar end(±0.80).
        // 5.2 cm slot spacing accommodates the thickest bumper plates (46 mm) with a 6 mm gap.
        for xSign: Float in [-1, 1] {
            let collar = makeCollarEntity(skinID: barSkinID)
            collar.components.set(GroundingShadowComponent(castsShadow: true))
            collar.position = SIMD3(xSign * 0.54, 0.6, barbellZ)
            sceneState.sceneRoot.addChild(collar)
        }

        // Bar hit zone: invisible input-target spanning the full bar and plate area.
        // Catches swipe-to-unrack gestures on the bar body, sleeves, and left (mirror) side
        // where no interactive plate entity exists.
        // barHitZoneCollisionFilter has empty mask -- no physical collisions with plates or floor.
        let barHitZone = Entity()
        barHitZone.name = "barHitZone"
        barHitZone.components.set(InputTargetComponent())
        barHitZone.components.set(CollisionComponent(
            shapes: [ShapeResource.generateBox(size: SIMD3(1.6, 0.5, 0.12))],
            filter: barHitZoneCollisionFilter
        ))
        barHitZone.components.set(PlateRoleComponent(role: .bar))
        barHitZone.position = SIMD3(0, 0, 0)
        sceneState.barAnchor.addChild(barHitZone)

        // Slot highlight rings -- one per bar slot, hidden until plate is dragged near bar.
        // UnlitMaterial so they always appear bright regardless of scene lighting.
        let slotOffsets: [Float] = [0.600, 0.652, 0.704, 0.756]
        sceneState.slotHighlights.removeAll()
        for offset in slotOffsets {
            var mat = UnlitMaterial()
            mat.color = .init(tint: UIColor(white: 1, alpha: 0.7))
            let ring = ModelEntity(
                mesh: cachedCylinder(height: 0.006, radius: 0.25),
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
        let sorted = racked
            .filter { !$0.isStarterPlate }
            .sorted { ($0.rackPosition ?? 999) < ($1.rackPosition ?? 999) }
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
                    role: .bar,
                    plateStyle: sceneState.plateStyle
                )
                entity.name = xSign == 1 ? plate.id : plate.id + "_mirror"
                entity.position = SIMD3(xSign * offset, 0, 0)
                #if DEBUG
                attachPlateDebugAxes(to: entity, label: "bar_\(rackPosition)_\(xSign)")
                #endif
                if xSign == -1 {
                    // Strip physics from the mirror, but keep input/collision so left-side bar
                    // plates can start the same swipe-to-unrack gesture as right-side plates.
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
        let visibleFloor = barOnly ? [] : Array(floor.prefix(sceneState.storageSlotPositions.count))
        for (idx, plate) in visibleFloor.enumerated() {
            let entity = makePlateEntity(
                tierID: plate.tierID,
                material: sceneState.materialCache[plate.tierID],
                weightKg: plate.weightKg,
                engravingText: plate.engravingText,
                prominentEngraving: plate.earnedByEvent.hasPrefix("strength_milestone_"),
                renderProjection: BarbellPlateRenderProjection(plate: plate),
                role: .floor,
                plateStyle: sceneState.plateStyle
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
        guard showsStorage, !barOnly else { return }

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
                        textures: state.plateTextureCache[tierID],
                        inRackRoom: true
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
