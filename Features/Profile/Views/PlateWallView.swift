// Features/Profile/Views/PlateWallView.swift
import SwiftUI
import SwiftData

struct PlateWallView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<EarnedPlate> { $0.isRacked == true })
    private var rackedPlates: [EarnedPlate]
    @Query(filter: #Predicate<EarnedPlate> { $0.earnedByEvent != "starter" && $0.isRacked == false })
    private var floorPlates: [EarnedPlate]
    @Query(filter: #Predicate<EarnedPlate> { $0.earnedByEvent != "starter" })
    private var ownedPlates: [EarnedPlate]

    @State private var sceneState = SceneState()
    /// Guards against the .task{} / RealityView make{} race condition.
    /// Same pattern as BarbellWelcomeView: make{} only runs after cache is populated.
    @State private var assetsReady = false

    private var totalWeight: Double {
        let racked = rackedPlates.filter { $0.earnedByEvent != "starter" }
        return 20 + racked.reduce(0) { $0 + $1.weightKg } * 2
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if assetsReady {
                BarbellRealityView(
                    mode: .rackRoom(
                        rackedPlates: rackedPlates,
                        floorPlates: floorPlates,
                        onRack: { plate in
                            try? BarbellProgressService.shared.rackPlate(plate)
                        },
                        onUnrack: { plate in
                            BarbellProgressService.shared.unrackPlate(plate)
                        }
                    ),
                    sceneState: sceneState
                )
                .ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(.white)
            }

            Color.clear.task { @MainActor in
                // Populate caches, then set assetsReady = true before RealityView renders
                for tierID in 0...6 {
                    sceneState.plateTextureCache[tierID] = loadPlateTextures(forTierID: tierID)
                    sceneState.materialCache[tierID] = buildMaterial(
                        forTierID: tierID,
                        textures: sceneState.plateTextureCache[tierID]
                    )
                }
                // Preload audio into process-level cache so first interaction has no latency
                for tierID in 0...7 {
                    let cat = PlateAudioCategory.from(tierID: tierID)
                    _ = loadAudioResource(named: cat.clinkSoundName)
                    _ = loadAudioResource(named: cat.dropSoundName)
                }
                // IBL if available
                if let ibl = try? await EnvironmentResource(named: "IndoorHDRI") {
                    let iblEntity = Entity()
                    iblEntity.components.set(
                        ImageBasedLightComponent(source: .single(ibl), intensityExponent: 0.5)
                    )
                    sceneState.sceneRoot.addChild(iblEntity)
                    sceneState.sceneRoot.components.set(
                        ImageBasedLightReceiverComponent(imageBasedLight: iblEntity)
                    )
                }
                assetsReady = true  // Cache is populated -- safe for make{} to run
            }
            .onChange(of: ownedPlates.count) { oldCount, newCount in
                guard newCount > oldCount else { return }
                let existing = Set(sceneState.entityMap.keys)
                if let newPlate = ownedPlates.first(where: { !existing.contains($0.id) }) {
                    sceneState.addPlate(newPlate)
                }
            }

            VStack {
                HStack {
                    Button("Done") { dismiss() }
                        .foregroundStyle(DS.Semantic.brand)
                    Spacer()
                    Text("Your Barbell")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer()
                    Text("Done").opacity(0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Spacer()

                Text("Bar 20kg + \(Int(totalWeight - 20))kg = \(Int(totalWeight))kg total")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.bottom, 12)
            }
        }
    }
}
