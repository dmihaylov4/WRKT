import SwiftUI
import RealityKit

/// Shows the earned battle plate spinning on its Y-axis using the same RealityKit
/// showcase animation as the Rack view floor-tap spin.
struct SpinningPlateView: View {
    let plate: EarnedPlateInfo

    @State private var root   = Entity()
    @State private var entity: Entity? = nil

    var body: some View {
        RealityView { content in
            // Build plate entity (visual only — no physics, no interaction)
            let textures = loadPlateTextures(forTierID: plate.tierID)
            let material = buildMaterial(forTierID: plate.tierID, textures: textures)
            let plateEntity = makePlateEntity(
                tierID: plate.tierID,
                textures: textures,
                material: material,
                weightKg: plate.weightKg,
                engravingText: plate.engravingText,
                options: .visualOnly()
            )

            // Stand upright facing camera (same as startShowcase)
            let upright = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
            plateEntity.transform = Transform(
                scale: SIMD3<Float>(repeating: 2.2),
                rotation: upright,
                translation: .zero
            )

            root.addChild(plateEntity)
            content.add(root)
            entity = plateEntity

            // IBL for proper PBR material rendering — same resource as BarbellRealityView
            Task { @MainActor in
                if let ibl = try? await EnvironmentResource(named: "IndoorHDRI") {
                    let iblEntity = Entity()
                    iblEntity.components.set(ImageBasedLightComponent(
                        source: .single(ibl),
                        intensityExponent: 8
                    ))
                    root.addChild(iblEntity)
                    root.components.set(ImageBasedLightReceiverComponent(imageBasedLight: iblEntity))
                }
            }
        }
        .background(.clear)
        .task { @MainActor in
            // Spin at the same rate as the rack showcase (0.03 rad / 16 ms ≈ 112 °/s)
            while true {
                entity?.transform.rotation = (entity?.transform.rotation ?? simd_quatf(angle: 0, axis: [0,1,0]))
                    * simd_quatf(angle: 0.03, axis: SIMD3<Float>(0, 1, 0))
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }
}
