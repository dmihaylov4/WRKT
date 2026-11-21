import SwiftUI
import RealityKit

/// Shows the earned battle plate spinning on its Y-axis using the same RealityKit
/// showcase animation as the Rack view floor-tap spin. Under Reduce Motion the plate stands still.
struct SpinningPlateView: View {
    let plate: EarnedPlateInfo

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var root   = Entity()
    @State private var entity: Entity? = nil

    /// Stands the plate upright facing the camera (same as startShowcase).
    private static let upright = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))

    var body: some View {
        RealityView { content in
            // Build plate entity (visual only: no physics, no interaction)
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

            plateEntity.transform = Transform(
                scale: SIMD3<Float>(repeating: 2.2),
                rotation: Self.upright,
                translation: .zero
            )

            root.addChild(plateEntity)
            content.add(root)
            entity = plateEntity

            // IBL for proper PBR material rendering: same resource as BarbellRealityView
            Task { @MainActor in
                if let ibl = await sharedIndoorEnvironmentResource() {
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
        .task(id: reduceMotion) { @MainActor in
            guard !reduceMotion else {
                entity?.transform.rotation = Self.upright
                return
            }
            // Spin at the same rate as the rack showcase (0.03 rad / 16 ms, about 112 deg/s)
            await PlateSpinLoop.run {
                entity?.transform.rotation = (entity?.transform.rotation ?? simd_quatf(angle: 0, axis: [0,1,0]))
                    * simd_quatf(angle: 0.03, axis: SIMD3<Float>(0, 1, 0))
            }
        }
    }
}

/// The spin loop behind SpinningPlateView: one step every interval until the task is cancelled.
/// A cancelled sleep ends the loop; `try?` around the sleep would swallow the cancellation and
/// keep the loop running on the main actor after the view is gone.
enum PlateSpinLoop {
    @MainActor
    static func run(interval: Duration = .milliseconds(16), step: @MainActor () -> Void) async {
        while !Task.isCancelled {
            step()
            do { try await Task.sleep(for: interval) } catch { return }
        }
    }
}
