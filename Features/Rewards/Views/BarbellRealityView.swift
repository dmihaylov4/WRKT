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

// MARK: - BarbellRealityView

struct BarbellRealityView: View {
    let mode: BarbellRealityMode
    let sceneState: SceneState

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ZStack {
            RealityView { content in
                setupLighting(content: &content)
                sceneState.sceneRoot   = Entity()
                sceneState.floorAnchor = Entity()
                sceneState.barAnchor   = Entity()
                sceneState.sceneRoot.addChild(sceneState.floorAnchor)
                sceneState.sceneRoot.addChild(sceneState.barAnchor)
                content.add(sceneState.sceneRoot)

                switch mode {
                case .welcome(let plates):
                    setupWelcomeScene(content: &content, plates: plates)
                case .rackRoom(let racked, let floor, _, _):
                    setupRackRoomScene(content: &content, racked: racked, floor: floor)
                }

                sceneState.configureCameraPosition(for: mode, sizeClass: sizeClass)
            } update: { _ in
                // Intentionally empty -- scene owns its runtime state
            }
            .gesture(entityDragGesture)
            .gesture(floorPanGesture)
            .onChange(of: sizeClass) { _, _ in
                // Re-apply camera proxy on device rotation / iPad split view changes
                sceneState.configureCameraPosition(for: mode, sizeClass: sizeClass)
            }

            overlayView

            // Shader warm-up: forces Metal PSO compilation during the loading spinner
            // so the first plate drag is smooth. Self-destructs after 1 second.
            ShaderWarmUpView()
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
        }
    }

    // MARK: Lighting
    // DirectionalLightComponent is required for shadow casting in RealityKit.
    // Point lights do not cast shadows. One directional key light + one point fill.

    private func setupLighting(content: inout RealityViewContent) {
        // Key light -- directional, casts contact shadows
        let keyEntity = Entity()
        var keyLight = DirectionalLightComponent()
        keyLight.color = .white
        keyLight.intensity = 3500
        var shadow = DirectionalLightComponent.Shadow()
        shadow.maximumDistance = 4
        shadow.depthBias = 2.0
        keyLight.shadow = shadow
        keyEntity.components.set(keyLight)
        // 45-degree down, 30-degree from front-left
        keyEntity.orientation = simd_quatf(angle: -.pi / 4, axis: SIMD3(1, 0, 0))
            * simd_quatf(angle: .pi / 6, axis: SIMD3(0, 1, 0))
        content.add(keyEntity)

        // Fill light -- point, no shadow, reduces harsh key-side darkness
        let fillEntity = Entity()
        fillEntity.components[PointLightComponent.self] = PointLightComponent(
            color: UIColor(white: 0.75, alpha: 1), intensity: 600, attenuationRadius: 8
        )
        fillEntity.position = SIMD3(-1.5, -0.5, 0.8)
        content.add(fillEntity)
    }

    // MARK: Welcome scene setup

    private func setupWelcomeScene(content: inout RealityViewContent, plates: [EarnedPlateInfo]) {
        let barbellRoot = Entity()
        barbellRoot.position = SIMD3(0, 0.3, -0.5)
        barbellRoot.scale = SIMD3(repeating: 1.8)

        let bar = makeBarEntity(skinID: 0)
        barbellRoot.addChild(bar)
        for xSign: Float in [-1, 1] {
            let collar = makeCollarEntity()
            collar.position = SIMD3(xSign * 0.475, 0, 0)
            barbellRoot.addChild(collar)
        }
        sceneState.sceneRoot.addChild(barbellRoot)
        sceneState.barbellRoot = barbellRoot

        let cols = 4
        let spacingX: Float = 0.12
        let spacingY: Float = 0.14
        for (i, info) in plates.enumerated() {
            let col = Float(i % cols)
            let row = Float(i / cols)
            let entity = makePlateEntity(
                tierID: info.tierID,
                material: sceneState.materialCache[info.tierID],
                weightKg: info.weightKg,
                engravingText: info.engravingText,
                role: .floor
            )
            entity.name = "welcome_plate_\(i)"
            entity.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0))
            entity.position = SIMD3(
                (col - Float(cols - 1) / 2) * spacingX,
                -0.25 - row * spacingY,
                -0.5
            )
            sceneState.sceneRoot.addChild(entity)
            sceneState.entityMap["welcome_plate_\(i)"] = entity
            sceneState.plateSpinStates["welcome_plate_\(i)"] = PlateSpinState()
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

    // MARK: Gesture stubs (implemented in Tasks 9-11)

    private var entityDragGesture: some Gesture {
        DragGesture()
            .targetedToAnyEntity()
            .onChanged { _ in }
            .onEnded { _ in }
    }

    private var floorPanGesture: some Gesture {
        DragGesture()
            .onChanged { _ in }
            .onEnded { _ in }
    }

    // MARK: RackRoom scene setup stub (Task 8)
    private func setupRackRoomScene(content: inout RealityViewContent,
                                     racked: [EarnedPlate], floor: [EarnedPlate]) {}
}

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
