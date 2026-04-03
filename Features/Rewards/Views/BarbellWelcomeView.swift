// Features/Rewards/Views/BarbellWelcomeView.swift
import SwiftUI
import SwiftData

struct BarbellWelcomeView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var ownedPlates: [EarnedPlate]
    @State private var showPlateWall = false
    @State private var sceneState = SceneState()
    /// Guards against the .task{} / RealityView make{} race condition.
    /// BarbellRealityView is only rendered after the material cache is fully populated,
    /// guaranteeing make{} never runs against an empty cache.
    @State private var assetsReady = false

    private var earnedPlates: [EarnedPlate] {
        ownedPlates.filter { $0.earnedByEvent != "starter" }
    }

    private var showcasePlateInfos: [EarnedPlateInfo] {
        earnedPlates
            .sorted { $0.tierID > $1.tierID }
            .prefix(4)
            .map { EarnedPlateInfo(tierID: $0.tierID, weightKg: $0.weightKg,
                                   engravingText: $0.engravingText, earnedByEvent: $0.earnedByEvent) }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if assetsReady {
                BarbellRealityView(
                    mode: .welcome(plates: showcasePlateInfos),
                    sceneState: sceneState
                )
                .ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(.white)
            }

            // Run asset loading in .task{}. Set assetsReady = true only after cache
            // is fully populated -- this is what makes the gate safe.
            Color.clear.task { @MainActor in
                for tierID in 0...6 {
                    sceneState.plateTextureCache[tierID] = loadPlateTextures(forTierID: tierID)
                    sceneState.materialCache[tierID] = buildMaterial(
                        forTierID: tierID,
                        textures: sceneState.plateTextureCache[tierID]
                    )
                }
                assetsReady = true
                await sceneState.runWelcomeSpinLoop()
            }

            VStack {
                Spacer()
                VStack(spacing: 8) {
                    Text("Your workouts have paid off.")
                        .font(.title.weight(.bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text("\(earnedPlates.count) plates earned")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

                Button {
                    showPlateWall = true
                } label: {
                    Text("Build Your Rack")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .background(DS.Semantic.brand)
                .foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .fullScreenCover(isPresented: $showPlateWall) {
            PlateWallView()
                .onDisappear { dismiss() }
        }
    }
}
