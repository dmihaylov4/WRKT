// Features/Profile/Views/PlateWallView.swift
import RealityKit
import SwiftUI
import SwiftData

func plateWallTotalWeight(rackedPlates: [EarnedPlate]) -> Double {
    let earnedRackedPlates = rackedPlates.filter { $0.earnedByEvent != "starter" }
    return 20 + earnedRackedPlates.reduce(0) { $0 + $1.weightKg } * 2
}

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
        plateWallTotalWeight(rackedPlates: rackedPlates)
    }

    private var selectedPlate: EarnedPlate? {
        guard let selectedID = sceneState.infoCardPlateID else { return nil }
        return (rackedPlates + floorPlates).first(where: { $0.id == selectedID })
    }

    private var selectedTierName: String? {
        guard let selectedPlate,
              let tier = PlateTier.all.first(where: { $0.id == selectedPlate.tierID }) else { return nil }
        return tier.name
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
                assetsReady = true  // Cache is populated -- safe for make{} to run
                // IBL is applied inside BarbellRealityView.make{} after sceneRoot is initialized.
            }
            .onChange(of: ownedPlates.count) { oldCount, newCount in
                guard newCount > oldCount else { return }
                let existing = Set(sceneState.entityMap.keys)
                if let newPlate = ownedPlates.first(where: { !existing.contains($0.id) }) {
                    sceneState.addPlate(newPlate)
                }
            }

            VStack {
                topBar
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                Spacer()

                bottomTray
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .heavy))
                    Text("Done")
                        .dsFont(.subheadline, weight: .semibold)
                }
                .foregroundStyle(Color.black)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(DS.Semantic.brand, in: ChamferedRectangle(.medium))
            }

            Spacer(minLength: 8)

            Text("Your Barbell")
                .dsFont(.headline, weight: .semibold)
                .foregroundStyle(.white)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Text("\(Int(totalWeight))")
                    .dsFont(.subheadline, weight: .bold)
                    .foregroundStyle(.white)
                Text("kg")
                    .dsFont(.caption, weight: .bold)
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Color.white.opacity(0.08), in: ChamferedRectangle(.medium))
            .overlay(
                ChamferedRectangle(.medium)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
        }
        .padding(8)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.78), Color.black.opacity(0.46)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: ChamferedRectangle(.large)
        )
        .overlay(
            ChamferedRectangle(.large)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var bottomTray: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let selectedPlate {
                Text("Selected Plate")
                    .font(DS.Typography.font(.caption, weight: .bold))
                    .foregroundStyle(DS.Semantic.brand)
                    .tracking(0.9)

                Text(selectedPlate.engravingText.isEmpty
                     ? (selectedTierName ?? "\(Int(selectedPlate.weightKg))kg plate")
                     : selectedPlate.engravingText)
                    .font(DS.Typography.font(.headline, weight: .semibold))
                    .foregroundStyle(.white)

                HStack(spacing: 10) {
                    trayStat(value: "\(Int(selectedPlate.weightKg))kg", label: "weight")
                    if let selectedTierName {
                        trayStat(value: selectedTierName, label: "tier")
                    }
                    trayStat(value: selectedPlate.isRacked ? "Racked" : "Floor", label: "status")
                }

                Text("Tap empty space to dismiss. Drag to rack, unrack, or reposition this plate.")
                    .dsFont(.footnote)
                    .foregroundStyle(.white.opacity(0.64))
            } else {
                Text("Current Load")
                    .font(DS.Typography.font(.caption, weight: .bold))
                    .foregroundStyle(DS.Semantic.brand)
                    .tracking(0.9)

                Text("\(Int(totalWeight))kg total")
                    .font(DS.Typography.font(.headline, weight: .semibold))
                    .foregroundStyle(.white)

                HStack(spacing: 10) {
                    trayStat(value: "20kg", label: "bar")
                    trayStat(value: "\(Int(totalWeight - 20))kg", label: "plates")
                    trayStat(value: "\(rackedPlates.count)", label: "racked")
                }

                Text("Tap a plate for details. Swipe a bar plate outward to drop it. Drag floor plates back to the rack.")
                    .dsFont(.footnote)
                    .foregroundStyle(.white.opacity(0.64))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(0.34),
                    Color.black.opacity(0.22)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: ChamferedRectangle(.xl)
        )
        .overlay(
            ChamferedRectangle(.xl)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func trayStat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(DS.Typography.font(.subheadline, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label.uppercased())
                .font(DS.Typography.custom(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.55))
                .tracking(0.8)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.08), in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
