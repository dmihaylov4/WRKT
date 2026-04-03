// Features/Rewards/Views/BarbellRealityView.swift
import SwiftUI
import RealityKit
import SwiftData

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

// MARK: - DragPhase

enum DragPhase {
    case idle
    case draggingPlate(Entity, plateID: String)
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
    /// Canonical position on barAnchor per plate ID. Used by snapBack for bar plates.
    var barPositionMap: [String: SIMD3<Float>] = [:]
    /// Slot highlight ring entities on barAnchor. Index matches slotOffsets[0...3].
    /// Toggled visible/invisible during drag to show the target slot.
    var slotHighlights: [Entity] = []
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
    var floorOffset: Float   = 0
    var floorVelocity: Float = 0
    var floorMinX: Float     = 0
    var floorMaxX: Float     = 0

    // MARK: Welcome spin state
    var plateSpinStates: [String: PlateSpinState] = [:]
    var barbellSpinAngle: Float    = 0
    var barbellSpinVelocity: Float = 0.35

    // MARK: Accessibility
    /// Re-read at gesture time so it responds to in-session Reduce Motion changes.
    var isReduceMotionEnabled: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    // MARK: Camera proxy
    /// Positions sceneRoot so the default RealityView perspective camera frames the scene.
    /// Call after scene setup completes and on horizontal size class changes.
    func configureCameraPosition(for mode: BarbellRealityMode, sizeClass: UserInterfaceSizeClass?) {
        let isWide = sizeClass == .regular   // iPad or split view
        switch mode {
        case .welcome:
            sceneRoot.position = SIMD3(0, -0.1, -1.2)
            if isWide { sceneRoot.position.z = -1.6 }
        case .rackRoom:
            sceneRoot.position = SIMD3(0, -0.3, -1.4)
            if isWide { sceneRoot.position.z = -1.9 }
        }
    }

    // MARK: Live plate addition
    func addPlate(_ plate: EarnedPlate) {
        guard entityMap[plate.id] == nil else { return }
        let entity = makePlateEntity(
            tierID: plate.tierID,
            textures: plateTextureCache[plate.tierID],
            material: materialCache[plate.tierID],
            weightKg: plate.weightKg,
            engravingText: plate.engravingText,
            role: .floor
        )
        entity.name = plate.id
        let xPos = Float(floorAnchor.children.count) * 0.15
        entity.position = SIMD3(xPos, 0, 0)
        let leanAngle = Float.random(in: 0.10 ..< 0.23)
        entity.orientation = simd_quatf(angle: leanAngle, axis: SIMD3(0, 0, 1))
        floorAnchor.addChild(entity)
        entityMap[plate.id] = entity
        if xPos > floorMaxX { floorMaxX = xPos }
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

            for (key, spinState) in plateSpinStates {
                spinState.velocity *= pow(0.995, dt * 60)
                spinState.angle    += spinState.velocity * dt
                entityMap[key]?.orientation =
                    simd_quatf(angle: spinState.angle, axis: SIMD3(0, 1, 0))
                    * simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0))
            }

            barbellSpinVelocity *= pow(0.992, dt * 60)
            barbellSpinAngle    += barbellSpinVelocity * dt
            barbellRoot?.orientation =
                simd_quatf(angle: barbellSpinAngle, axis: SIMD3(0, 1, 0))
        }
    }
}

// MARK: - BarbellRealityView (stub -- body implemented in Task 6)

struct BarbellRealityView: View {
    let mode: BarbellRealityMode
    let sceneState: SceneState

    var body: some View {
        Text("BarbellRealityView -- not yet implemented")
            .foregroundStyle(.white)
    }
}
