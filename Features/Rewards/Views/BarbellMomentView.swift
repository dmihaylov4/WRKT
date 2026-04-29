// Features/Rewards/Views/BarbellMomentView.swift
import SwiftUI
import SwiftData

/// WinScreen Page 2: newly earned plates drop into the rack room.
/// Shown only when earnedPlates is non-empty.
struct BarbellMomentView: View {
    let plates: [EarnedPlateInfo]
    let onDismiss: () -> Void

    @Query(filter: #Predicate<EarnedPlate> { $0.isRacked == true })
    private var rackedPlates: [EarnedPlate]

    @Query(filter: #Predicate<EarnedPlate> { $0.earnedByEvent != "starter" && $0.isRacked == false })
    private var floorPlates: [EarnedPlate]

    @State private var sceneState = SceneState()
    @State private var assetsReady = false
    @State private var showDoneButton = false
    @State private var dropTask: Task<Void, Never>? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if assetsReady {
                BarbellRealityView(
                    mode: .rackRoom(
                        rackedPlates: rackedPlates,
                        floorPlates: momentFloorPlates,
                        onRack: { plate in
                            try? BarbellProgressService.shared.rackPlate(plate)
                        },
                        onUnrack: { plate in
                            BarbellProgressService.shared.unrackPlate(plate)
                        }
                    ),
                    sceneState: sceneState,
                    allowsInteraction: true,
                    showsStorage: false
                )
                .ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(DS.Theme.accent)
            }

            VStack(spacing: 0) {
                // Title
                VStack(spacing: 6) {
                    Text("Added to your Barbell")
                        .dsFont(.title2, weight: .bold)
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .dsFont(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.top, 48)
                .padding(.bottom, 24)

                Spacer()

                // Done button
                if showDoneButton {
                    Button {
                        onDismiss()
                    } label: {
                        Text("Done")
                            .dsFont(.headline)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .background(DS.Semantic.brand)
                    .foregroundStyle(.black)
                    .clipShape(ChamferedRectangle(.medium))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .onAppear {
            rebuildSceneState()
            dropTask = startPlateDrop()
        }
        .onDisappear {
            dropTask?.cancel()
        }
    }

    private var subtitle: String {
        return "\(plates.count) new plate\(plates.count == 1 ? "" : "s")"
    }

    private var sceneSignature: String {
        (rackedPlates + floorPlates)
            .map { "\($0.id):\($0.isRacked):\($0.rackPosition ?? -1)" }
            .sorted()
            .joined(separator: "|")
    }

    private var momentFloorPlates: [EarnedPlate] {
        var usedIDs = Set<String>()
        return plates.compactMap { info in
            guard let plate = matchingFloorPlate(for: info, excluding: usedIDs) else { return nil }
            usedIDs.insert(plate.id)
            return plate
        }
    }

    private func rebuildSceneState() {
        let newState = SceneState()

        for tierID in 0...6 {
            newState.plateTextureCache[tierID] = loadPlateTextures(forTierID: tierID)
            newState.materialCache[tierID] = buildMaterial(
                forTierID: tierID,
                textures: newState.plateTextureCache[tierID]
            )
        }
        for tierID in 0...7 {
            let cat = PlateAudioCategory.from(tierID: tierID)
            _ = loadAudioResource(named: cat.clinkSoundName)
            _ = loadAudioResource(named: cat.dropSoundName)
        }

        sceneState = newState
        assetsReady = true
    }

    // MARK: - Drop sequence

    @discardableResult
    private func startPlateDrop() -> Task<Void, Never> {
        Task { @MainActor in
            var consumedPlateIDs = Set<String>()
            try? await Task.sleep(for: .milliseconds(250))

            for (index, info) in plates.enumerated() {
                guard let plate = matchingFloorPlate(for: info, excluding: consumedPlateIDs) else { continue }
                consumedPlateIDs.insert(plate.id)

                let didDrop = await sceneState.dropAwardPlateToFloor(
                    plateID: plate.id,
                    index: index,
                    total: plates.count
                )
                if didDrop {
                    BarbellProgressService.shared.playClinkHaptic()
                }
                try? await Task.sleep(for: .milliseconds(220))
            }
            try? await Task.sleep(for: .seconds(1.0))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showDoneButton = true
            }
        }
    }

    private func matchingFloorPlate(for info: EarnedPlateInfo, excluding consumedPlateIDs: Set<String>) -> EarnedPlate? {
        floorPlates
            .filter {
                !$0.isRacked &&
                !consumedPlateIDs.contains($0.id) &&
                $0.tierID == info.tierID &&
                $0.weightKg == info.weightKg &&
                $0.engravingText == info.engravingText &&
                $0.earnedByEvent == info.earnedByEvent
            }
            .sorted { $0.earnedAt < $1.earnedAt }
            .first
    }
}
