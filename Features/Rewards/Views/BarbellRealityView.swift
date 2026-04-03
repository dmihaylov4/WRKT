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
    /// Canonical position on barAnchor per plate ID. Used by snapBack for bar plates.
    var barPositionMap: [String: SIMD3<Float>] = [:]
    /// Mirror entity per plate ID. Populated by snapToBar; removed by finishUnrack / snapBack.
    var barMirrorMap: [String: Entity] = [:]
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
    var floorOffset: Float            = 0
    var floorVelocity: Float          = 0
    var floorMinX: Float              = 0
    var floorMaxX: Float              = 0
    /// Last cumulative translation from the active pan gesture.
    /// DragGesture.translation is cumulative from gesture start, not a per-event delta.
    /// Reset to 0 in onEnded.
    var floorPanLastTranslation: Float = 0

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
        shadow.shadowProjection = .automatic(maximumDistance: 4)
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
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .targetedToAnyEntity()
            .onChanged { value in
                let entity = value.entity
                guard let roleComp = entity.components[PlateRoleComponent.self] else { return }

                switch roleComp.role {
                case .floor:
                    // One-time: enter dragging state (captures originRole) and reparent to scene root.
                    // transition() rejects .draggingPlate -> .draggingPlate, so call it
                    // unconditionally but only run reparent when it succeeds.
                    if sceneState.transition(to: .draggingPlate(entity, plateID: entity.name, originRole: .floor)) {
                        entity.setParent(sceneState.sceneRoot, preservingWorldTransform: true)
                    }
                    // Guard: ensure we own this drag before updating position each frame.
                    guard case .draggingPlate(let dragging, _, _) = sceneState.dragPhase,
                          dragging === entity else { return }

                    let worldPos = value.convert(value.location3D, from: .local, to: .scene)
                    entity.position = worldPos

                    // Snap zone feedback
                    let barWorldY = sceneState.barAnchor.position(relativeTo: nil).y
                    let inZone = worldPos.y > barWorldY - 0.2
                    if inZone {
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
                    } else {
                        sceneState.slotHighlights.forEach { $0.isEnabled = false }
                        sceneState.wasInSnapZone = false
                    }

                case .bar:
                    guard case .idle = sceneState.dragPhase else { return }
                    let dx = Float(value.translation.width)
                    guard abs(dx) > 0.04 else { return }
                    guard sceneState.transition(to: .draggingPlate(entity, plateID: entity.name, originRole: .bar)) else { return }
                    let slideTarget = Transform(
                        scale: entity.scale,
                        rotation: entity.orientation,
                        translation: entity.position(relativeTo: nil) + SIMD3(dx > 0 ? 0.6 : -0.6, 0, 0)
                    )
                    if sceneState.isReduceMotionEnabled {
                        entity.position = slideTarget.translation
                    } else {
                        entity.move(to: slideTarget, relativeTo: nil, duration: 0.2, timingFunction: .easeOut)
                    }
                    entity.setParent(sceneState.sceneRoot, preservingWorldTransform: true)
                    entity.components.set(PlateRoleComponent(role: .floor))
                }
            }
            .onEnded { value in
                guard case .draggingPlate(let entity, let plateID, let originRole) = sceneState.dragPhase else { return }
                sceneState.transition(to: .idle)
                sceneState.slotHighlights.forEach { $0.isEnabled = false }
                sceneState.wasInSnapZone = false

                let worldPos = value.convert(value.location3D, from: .local, to: .scene)
                let barWorldY = sceneState.barAnchor.position(relativeTo: nil).y
                // Use originRole captured at drag-start -- not re-querying allFloorPlates,
                // which could reflect a concurrent model mutation.
                let isFromFloor = originRole == .floor

                if isFromFloor && worldPos.y > barWorldY - 0.15 {
                    snapToBar(entity: entity, plateID: plateID)
                } else if !isFromFloor && worldPos.y < barWorldY - 0.2 {
                    snapToFloor(entity: entity, plateID: plateID)
                } else {
                    snapBack(entity: entity, plateID: plateID)
                }
            }
    }

    private var floorPanGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
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

    private func snapToBar(entity: Entity, plateID: String) {
        let slotOffsets: [Float] = [0.34, 0.37, 0.40, 0.43]
        let occupiedSlots = allRackedPlates.compactMap(\.rackPosition)
        guard let nextSlot = (0..<4).first(where: { !occupiedSlots.contains($0) }) else {
            snapBack(entity: entity, plateID: plateID)
            return
        }
        let offset = slotOffsets[nextSlot]
        let slotPos = SIMD3<Float>(offset, 0, 0) // bar-anchor local space: y=0 is bar centerline
        let rot = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))

        entity.setParent(sceneState.barAnchor, preservingWorldTransform: true)
        entity.components.set(PlateRoleComponent(role: .bar))

        // Bilateral mirror entity for the opposite side of the bar.
        // Stored in barMirrorMap so finishUnrack / snapBack can remove it without a scene search.
        let mirrorEntity = entity.clone(recursive: true)
        mirrorEntity.name = plateID + "_mirror"
        mirrorEntity.components.set(PlateRoleComponent(role: .bar))
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

    // Stubs for Task 11
    private func snapToFloor(entity: Entity, plateID: String) {}
    private func snapBack(entity: Entity, plateID: String) {}

    // MARK: RackRoom scene setup

    private func setupRackRoomScene(
        content: inout RealityViewContent,
        racked: [EarnedPlate], floor: [EarnedPlate]
    ) {
        // Performance budget: 4 racked (bilateral = 8 entities) + 24 floor = 32 plate entities.
        // With shared materialCache, this stays under 150 draw calls on A15+ at 60fps.
        // Plates beyond index 24 are in SwiftData but not rendered.

        // Invisible static physics floor -- plates settle on this after .dynamic release
        let floorShape = ShapeResource.generateBox(size: SIMD3(20, 0.02, 4))
        let floorCollider = Entity()
        floorCollider.components.set(CollisionComponent(
            shapes: [floorShape],
            filter: CollisionFilter(group: floorCollisionGroup, mask: plateCollisionGroup)
        ))
        var floorBody = PhysicsBodyComponent()
        floorBody.mode = .static
        floorBody.material = PhysicsMaterialResource.generate(friction: 0.75, restitution: 0.25)
        floorCollider.components.set(floorBody)
        floorCollider.position = SIMD3(0, -0.01, 0)
        sceneState.sceneRoot.addChild(floorCollider)

        // Visual floor line
        let floorLine = ModelEntity(
            mesh: cachedBox(size: SIMD3(1.2, 0.004, 0.08)),
            materials: [pbrMaterial(color: UIColor(white: 0.15, alpha: 1), metallic: 0, roughness: 1)]
        )
        floorLine.position = SIMD3(0, 0, 0)
        sceneState.sceneRoot.addChild(floorLine)

        // Rack stands
        for xSign: Float in [-1, 1] {
            let stand = makeRackStandEntity()
            stand.position = SIMD3(xSign * 0.55, 0.3, 0)
            sceneState.sceneRoot.addChild(stand)
        }

        // Bar
        let bar = makeBarEntity(skinID: 0)
        bar.position = SIMD3(0, 0.6, 0)
        sceneState.sceneRoot.addChild(bar)
        sceneState.barAnchor.position = SIMD3(0, 0.6, 0)
        sceneState.sceneRoot.addChild(sceneState.barAnchor)

        // Collars
        for xSign: Float in [-1, 1] {
            let collar = makeCollarEntity()
            collar.position = SIMD3(xSign * 0.475, 0.6, 0)
            sceneState.sceneRoot.addChild(collar)
        }

        // Slot highlight rings -- one per bar slot, hidden until plate is dragged near bar.
        // UnlitMaterial so they always appear bright regardless of scene lighting.
        let slotOffsets: [Float] = [0.34, 0.37, 0.40, 0.43]
        sceneState.slotHighlights.removeAll()
        for offset in slotOffsets {
            var mat = UnlitMaterial()
            mat.color = .init(tint: UIColor(white: 1, alpha: 0.7))
            let ring = ModelEntity(
                mesh: cachedCylinder(height: 0.003, radius: 0.21),
                materials: [mat]
            )
            ring.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
            ring.position = SIMD3(offset, 0, 0)
            ring.isEnabled = false  // hidden until drag enters snap zone
            sceneState.barAnchor.addChild(ring)
            sceneState.slotHighlights.append(ring)
        }

        // Racked plates -- bilateral rendering, use cached material
        let sorted = racked.sorted { ($0.rackPosition ?? 999) < ($1.rackPosition ?? 999) }
        for (idx, plate) in sorted.prefix(4).enumerated() {
            let offset = slotOffsets[min(idx, slotOffsets.count - 1)]
            for xSign: Float in [-1, 1] {
                let entity = makePlateEntity(
                    tierID: plate.tierID,
                    material: sceneState.materialCache[plate.tierID],
                    weightKg: plate.weightKg,
                    engravingText: plate.engravingText,
                    role: .bar
                )
                entity.name = xSign == 1 ? plate.id : plate.id + "_mirror"
                entity.position = SIMD3(xSign * offset, 0, 0)
                sceneState.barAnchor.addChild(entity)
            }
            sceneState.entityMap[plate.id] = sceneState.barAnchor.children
                .first(where: { $0.name == plate.id })
            sceneState.barPositionMap[plate.id] = SIMD3(offset, 0, 0)
        }

        // Floor plates -- use cached material
        let spacing: Float = 0.15
        let visibleFloor = Array(floor.prefix(24))
        for (idx, plate) in visibleFloor.enumerated() {
            let entity = makePlateEntity(
                tierID: plate.tierID,
                material: sceneState.materialCache[plate.tierID],
                weightKg: plate.weightKg,
                engravingText: plate.engravingText,
                role: .floor
            )
            entity.name = plate.id
            let xPos = Float(idx) * spacing
            entity.position = SIMD3(xPos, 0, 0)
            let leanAngle = Float.random(in: 0.10 ..< 0.23)
            entity.orientation = simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0))
                * simd_quatf(angle: leanAngle, axis: SIMD3(0, 0, 1))
            sceneState.floorAnchor.addChild(entity)
            sceneState.entityMap[plate.id] = entity
        }

        // Floor pan clamp bounds
        let totalWidth = Float(max(visibleFloor.count - 1, 0)) * spacing
        sceneState.floorMinX = 0
        sceneState.floorMaxX = max(totalWidth - 0.8, 0)
    }
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
