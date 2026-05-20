// Features/Rewards/Views/BarbellWelcomeView.swift
import SwiftUI
import SwiftData

struct BarbellWelcomeView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var ownedPlates: [EarnedPlate]
    @State private var showPlateWall = false
    @State private var showCollection = false
    @State private var sceneState = SceneState()
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

    private var welcomeScenePlates: [EarnedPlateInfo] {
        if showcasePlateInfos.isEmpty {
            return [
                EarnedPlateInfo(
                    tierID: 7,
                    weightKg: 0,
                    engravingText: "Starter",
                    earnedByEvent: "starter"
                )
            ]
        }
        return showcasePlateInfos
    }

    private var strongestPlate: EarnedPlate? {
        earnedPlates.max {
            if $0.tierID == $1.tierID {
                return $0.weightKg < $1.weightKg
            }
            return $0.tierID < $1.tierID
        }
    }

    private var totalWeightKg: Int {
        Int(earnedPlates.reduce(0) { $0 + $1.weightKg })
    }

    private var tierSpreadCount: Int {
        Set(earnedPlates.map(\.tierID)).count
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: "#080808"),
                    Color(hex: "#141414"),
                    Color(hex: "#201f1a")
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            Circle()
                .fill(DS.Semantic.brand.opacity(0.12))
                .frame(width: 320, height: 320)
                .blur(radius: 70)
                .offset(x: 0, y: -280)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                topBar

                Spacer(minLength: 12)

                heroRealityView

                Spacer(minLength: 16)

                bottomCard
                    .padding(.horizontal, 16)
                    .padding(.bottom, 18)
            }
        }
        .fullScreenCover(isPresented: $showPlateWall) {
            PlateWallView()
                .onDisappear { dismiss() }
        }
        .sheet(isPresented: $showCollection) {
            PlateCollectionView()
        }
        .task { @MainActor in
            guard !assetsReady else { return }
            for tierID in PlateTier.all.map(\.id) {
                sceneState.plateTextureCache[tierID] = loadPlateTextures(forTierID: tierID)
                sceneState.materialCache[tierID] = buildMaterial(
                    forTierID: tierID,
                    textures: sceneState.plateTextureCache[tierID]
                )
            }
            assetsReady = true
        }
    }

    private var heroRealityView: some View {
        ZStack {
            if assetsReady {
                BarbellRealityView(
                    mode: .welcome(plates: welcomeScenePlates),
                    sceneState: sceneState
                )
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(height: 300)
        .padding(.horizontal, 8)
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Reward Unlocked")
                    .font(DS.Typography.font(.caption, weight: .bold))
                    .foregroundStyle(DS.Semantic.brand)
                    .tracking(1.1)

                Text("Build Your Barbell")
                    .font(DS.Typography.font(.title2, weight: .bold))
                    .foregroundStyle(.white)

                Text("Collect plates through workouts and build a rack worth showing off.")
                    .dsFont(.footnote)
                    .foregroundStyle(.white.opacity(0.66))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            statChip(value: "\(earnedPlates.count)", label: "plates")
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(0.34),
                    Color.black.opacity(0.12),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var bottomCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                statChip(value: "\(tierSpreadCount)", label: "tiers")
                statChip(value: "\(totalWeightKg)kg", label: "earned")
                if let strongestPlate {
                    statChip(value: "\(Int(strongestPlate.weightKg))kg", label: "best plate")
                }
            }

            if let strongestPlate {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Top unlock")
                        .font(DS.Typography.font(.caption, weight: .bold))
                        .foregroundStyle(DS.Semantic.brand)
                        .tracking(1.0)

                    Text(strongestPlate.engravingText.isEmpty
                         ? "\(Int(strongestPlate.weightKg))kg plate, tier \(strongestPlate.tierID + 1)"
                         : strongestPlate.engravingText)
                        .font(DS.Typography.font(.headline, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Text("Open your rack to arrange plates, inspect details, and see how your collection is growing.")
                        .dsFont(.footnote)
                        .foregroundStyle(.white.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Starter setup ready")
                        .font(DS.Typography.font(.headline, weight: .semibold))
                        .foregroundStyle(.white)

                    Text("Your first plates are waiting. Start training to unlock rarer builds.")
                        .dsFont(.footnote)
                        .foregroundStyle(.white.opacity(0.68))
                }
            }

            Button {
                showPlateWall = true
            } label: {
                ZStack {
                    Text("Open Your Rack")
                        .frame(maxWidth: .infinity)

                    HStack {
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .padding(.trailing, 2)
                }
                .frame(maxWidth: .infinity, minHeight: 54)
                .font(DS.ButtonSize.large.font)
                .foregroundStyle(.black)
            }
            .background(DS.Semantic.brand)
            .clipShape(ChamferedRectangle(.large))

            viewCollectionButton
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(0.38),
                    Color.black.opacity(0.22)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: ChamferedRectangle(.xl)
        )
        .overlay(
            ChamferedRectangle(.xl)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var viewCollectionButton: some View {
        Button {
            showCollection = true
        } label: {
            Label("View Collection", systemImage: "square.grid.2x2.fill")
                .font(DS.ButtonSize.regular.font)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 46)
        }
        .background(Color.white.opacity(0.08), in: ChamferedRectangle(.medium))
        .overlay(
            ChamferedRectangle(.medium)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func statChip(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(DS.Typography.font(.subheadline, weight: .bold))
                .foregroundStyle(.white)
            Text(label.uppercased())
                .font(DS.Typography.custom(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.55))
                .tracking(0.9)
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
