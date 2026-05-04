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
    @Query(filter: #Predicate<BarbellConfig> { $0.id == "global" })
    private var configs: [BarbellConfig]

    @State private var sceneState = SceneState()
    @State private var barbellService = BarbellProgressService.shared
    @State private var showingCollection = false
    @State private var showingSelectedPlateDetail = false
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
                            try? BarbellProgressService.shared.addToBar(plate: plate, replacing: nil)
                        },
                        onUnrack: { plate in
                            BarbellProgressService.shared.removeFromBar(plate: plate)
                        }
                    ),
                    sceneState: sceneState,
                    barSkinID: configs.first?.barSkinIndex ?? 0,
                    rackStyleID: configs.first?.effectiveSelectedRackStyleID ?? "matte_black",
                    roomThemeID: configs.first?.effectiveSelectedRoomThemeID ?? "dark_gym"
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

                if sceneState.infoCardPlateID == nil {
                    roomNameLabel
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                }

                if barbellService.remoteSyncState == .syncUnavailable {
                    syncUnavailableBanner
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                }

                bottomTray
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
        .sheet(isPresented: $showingCollection) {
            PlateCollectionView()
        }
        .sheet(isPresented: $showingSelectedPlateDetail) {
            if let selectedPlate {
                PlateDetailView(plate: selectedPlate)
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
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .foregroundStyle(Color.black)
                .padding(.horizontal, 14)
                .frame(minWidth: 98)
                .frame(height: 38)
                .background(DS.Semantic.brand, in: ChamferedRectangle(.medium))
            }

            Spacer(minLength: 8)

            Text("Your Barbell")
                .dsFont(.headline, weight: .semibold)
                .foregroundStyle(.white)

            Spacer(minLength: 8)

            Button {
                showingCollection = true
            } label: {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.08), in: ChamferedRectangle(.medium))
                    .overlay(
                        ChamferedRectangle(.medium)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
            }
            .accessibilityLabel("Collection")

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
                    trayStat(value: selectedPlate.currentTier.rawValue.capitalized, label: "tier")
                    trayStat(value: selectedPlate.isRacked ? "Racked" : "Floor", label: "status")
                }

                Button {
                    showingSelectedPlateDetail = true
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "list.bullet.rectangle.portrait.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text("Details")
                            .dsFont(.caption, weight: .bold)
                    }
                    .foregroundStyle(.black)
                    .frame(height: 34)
                    .padding(.horizontal, 12)
                    .background(DS.Semantic.brand, in: ChamferedRectangle(.medium))
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

    private var syncUnavailableBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.Semantic.brand)

            VStack(alignment: .leading, spacing: 2) {
                Text("Saved locally")
                    .dsFont(.subheadline, weight: .semibold)
                    .foregroundStyle(.white)
                Text("Cloud sync is paused until the server state is safe again.")
                    .dsFont(.caption)
                    .foregroundStyle(.white.opacity(0.62))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.black.opacity(0.62), in: ChamferedRectangle(.medium))
        .overlay(
            ChamferedRectangle(.medium)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var roomNameLabel: some View {
        if let roomName = configs.first?.roomName {
            VStack(spacing: 3) {
                Text(roomName)
                    .dsFont(.subheadline, weight: .bold)
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                if let motto = configs.first?.roomMotto {
                    Text(motto)
                        .dsFont(.caption, weight: .semibold)
                        .foregroundStyle(.white.opacity(0.52))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .italic()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.36), in: ChamferedRectangle(.medium))
            .overlay(
                ChamferedRectangle(.medium)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
        }
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

struct PlateCollectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: WorkoutStoreV2
    @Query(filter: #Predicate<EarnedPlate> { $0.earnedByEvent != "starter" })
    private var earnedPlates: [EarnedPlate]
    @State private var rackErrorMessage: String?
    @State private var selectedPlateForDetail: EarnedPlate?

    private var sortedPlates: [EarnedPlate] {
        earnedPlates.sorted {
            if $0.isRacked != $1.isRacked { return $0.isRacked && !$1.isRacked }
            if $0.tierID != $1.tierID { return $0.tierID > $1.tierID }
            if $0.earnedAt != $1.earnedAt { return $0.earnedAt > $1.earnedAt }
            return $0.earnedByEvent < $1.earnedByEvent
        }
    }

    private var rackedCount: Int {
        earnedPlates.filter(\.isRacked).count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                collectionHeader

                ZStack {
                    DS.Semantic.surface.ignoresSafeArea()

                    if sortedPlates.isEmpty {
                        emptyState
                    } else {
                        ScrollView {
                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), spacing: 12),
                                    GridItem(.flexible(), spacing: 12)
                                ],
                                spacing: 12
                            ) {
                                ForEach(sortedPlates) { plate in
                                    PlateCollectionCell(
                                        plate: plate,
                                        workoutSummary: workoutSummary(for: plate),
                                        onOpenDetail: { selectedPlateForDetail = plate },
                                        onPrimaryAction: { handlePrimaryAction(for: plate) }
                                    )
                                }
                            }
                            .padding(16)
                        }
                    }
                }
            }
            .background(DS.Semantic.surface.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $selectedPlateForDetail) { plate in
                PlateDetailView(plate: plate)
                    .environmentObject(store)
            }
        }
        .alert("Rack is full", isPresented: Binding(
            get: { rackErrorMessage != nil },
            set: { if !$0 { rackErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(rackErrorMessage ?? "")
        }
    }

    private var collectionHeader: some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 13, weight: .bold))
                Text("\(earnedPlates.count)")
                    .font(DS.Typography.font(.subheadline, weight: .bold))
                Text("owned")
                    .dsFont(.caption, weight: .semibold)
                    .foregroundStyle(.white.opacity(0.58))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(Color.white.opacity(0.08), in: ChamferedRectangle(.medium))
            .overlay(
                ChamferedRectangle(.medium)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )

            Spacer(minLength: 8)

            Text("Plate Collection")
                .font(DS.Typography.font(.headline, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Text("\(rackedCount)/4")
                    .font(DS.Typography.font(.subheadline, weight: .bold))
                    .foregroundStyle(DS.Semantic.brand)
                    .frame(width: 44, height: 42)
                    .background(Color.white.opacity(0.08), in: ChamferedRectangle(.medium))
                    .overlay(
                        ChamferedRectangle(.medium)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(Color.white.opacity(0.08), in: ChamferedRectangle(.medium))
                        .overlay(
                            ChamferedRectangle(.medium)
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )
                }
                .accessibilityLabel("Close")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.84), Color.black.opacity(0.40)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "circle.hexagongrid.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(DS.Semantic.brand)
            Text("No plates yet")
                .dsFont(.headline, weight: .semibold)
                .foregroundStyle(DS.Semantic.textPrimary)
            Text("Complete strength workouts to earn plates.")
                .dsFont(.footnote)
                .foregroundStyle(DS.Semantic.textSecondary)
        }
        .padding(24)
    }

    private func handlePrimaryAction(for plate: EarnedPlate) {
        if plate.isRacked {
            BarbellProgressService.shared.removeFromBar(plate: plate)
            return
        }

        do {
            try BarbellProgressService.shared.addToBar(plate: plate, replacing: nil)
        } catch BarbellProgressService.RackError.barIsFull {
            rackErrorMessage = "Remove a plate from the rack before adding another one."
        } catch {
            rackErrorMessage = "The plate could not be added to the rack."
        }
    }

    private func sourceWorkout(for plate: EarnedPlate) -> CompletedWorkout? {
        guard let sourceWorkoutID = plate.sourceWorkoutID,
              let uuid = UUID(uuidString: sourceWorkoutID) else { return nil }
        return store.completedWorkouts.first(where: { $0.id == uuid })
    }

    private func workoutSummary(for plate: EarnedPlate) -> PlateWorkoutSummary? {
        guard let workout = sourceWorkout(for: plate) else {
            return plateCollectionFallbackSummary(for: plate).map(PlateWorkoutSummary.init(fallback:))
        }
        return PlateWorkoutSummary(plate: plate, workout: workout)
    }

}

struct PlateCollectionFallbackSummary: Equatable {
    let title: String
    let detail: String
}

func plateCollectionFallbackSummary(for plate: EarnedPlate) -> PlateCollectionFallbackSummary? {
    let title: String
    if !plate.engravingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        title = plate.engravingText
    } else if let liftTypeID = plate.liftTypeID,
              !BarbellPlateProgressionScope.isGlobal(liftTypeID) {
        title = liftTypeID
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
    } else {
        return nil
    }

    return PlateCollectionFallbackSummary(
        title: title,
        detail: plate.sourceWorkoutID == nil ? "EARNED HISTORY" : "SOURCE WORKOUT DELETED"
    )
}

private struct PlateDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let plate: EarnedPlate
    @Query private var allEvents: [BarbellPlateEvent]

    private var progress: BarbellPlateTierProgress {
        BarbellPlateTierProgress(plate: plate)
    }

    private var events: [BarbellPlateEvent] {
        allEvents
            .filter { $0.plateID == plate.id }
            .sorted { $0.occurredAt > $1.occurredAt }
    }

    private var title: String {
        if !plate.engravingText.isEmpty { return plate.engravingText }
        return "\(Int(plate.weightKg))kg Plate"
    }

    private var acquiredText: String {
        plate.effectiveFirstEarnedAt.formatted(date: .abbreviated, time: .omitted)
    }

    private var historyScopeTitle: String {
        isGlobalPlate
            ? "Global plate: overall barbell history"
            : "\(Self.displayLiftName(plate.liftTypeID)) history"
    }

    private var isGlobalPlate: Bool {
        BarbellPlateProgressionScope.isGlobal(plate.liftTypeID)
    }

    private var scopeSubtitle: String {
        isGlobalPlate
            ? "Tracks all strength workouts"
            : "Tracks \(Self.displayLiftName(plate.liftTypeID)) workouts"
    }

    private var tierProgressTitle: String {
        isGlobalPlate ? "Global Tier Progress" : "Tier Progress"
    }

    private var countersTitle: String {
        isGlobalPlate ? "Global Training Wear" : "Training Wear"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    detailHero
                    tierProgressSection
                    countersSection
                    biographySection
                }
                .padding(16)
            }
            .background(DS.Semantic.surface.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.08), in: ChamferedRectangle(.medium))
                    }
                    .accessibilityLabel("Close")
                }
            }
            .navigationTitle("Plate Detail")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var detailHero: some View {
        HStack(alignment: .center, spacing: 14) {
            PlateMedallionView(plate: plate, accentColor: tierAccent)
                .scaleEffect(1.32)
                .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .dsFont(.headline, weight: .bold)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                HStack(spacing: 8) {
                    detailPill(text: "\(Int(plate.weightKg))kg")
                    detailPill(text: plate.currentTier.rawValue.capitalized)
                    detailPill(text: isGlobalPlate ? "Global" : "Lift")
                    detailPill(text: plate.isRacked ? "Racked" : "Stored")
                }

                Text("Earned \(acquiredText)")
                    .dsFont(.caption, weight: .semibold)
                    .foregroundStyle(.white.opacity(0.58))

                Text(scopeSubtitle)
                    .dsFont(.caption, weight: .semibold)
                    .foregroundStyle(tierAccent.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.075), in: ChamferedRectangle(.large))
        .overlay(
            ChamferedRectangle(.large)
                .stroke(tierAccent.opacity(0.24), lineWidth: 1)
        )
    }

    private var tierProgressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(tierProgressTitle)
            Text(historyScopeTitle)
                .dsFont(.caption, weight: .semibold)
                .foregroundStyle(.white.opacity(0.58))

            HStack(alignment: .firstTextBaseline) {
                Text(plate.currentTier.rawValue.capitalized)
                    .dsFont(.title3, weight: .bold)
                    .foregroundStyle(.white)
                Spacer()
                if let nextTier = progress.nextTier {
                    Text(nextTier.rawValue.capitalized)
                        .dsFont(.subheadline, weight: .bold)
                        .foregroundStyle(tierAccent)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule()
                        .fill(tierAccent)
                        .frame(width: max(8, proxy.size.width * progress.progressFraction))
                }
            }
            .frame(height: 10)

            Text(progress.primaryText)
                .dsFont(.subheadline, weight: .semibold)
                .foregroundStyle(.white)
            if let secondaryText = progress.secondaryText {
                Text(secondaryText)
                    .dsFont(.caption)
                    .foregroundStyle(.white.opacity(0.60))
            }
        }
        .detailPanel()
    }

    private var countersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(countersTitle)

            HStack(spacing: 10) {
                detailCounter(value: "\(plate.workoutsUsedCount)", label: "workouts")
                detailCounter(value: "\(plate.prCount)", label: "PRs")
                detailCounter(value: "\(plate.chalkUseCount)", label: "chalk")
            }
            HStack(spacing: 10) {
                detailCounter(value: "\(plate.gripWearCount)", label: "grip")
                detailCounter(value: "\(plate.pressUseCount)", label: "press")
                detailCounter(value: plate.lastUsedAt?.formatted(date: .numeric, time: .omitted) ?? "-", label: "last used")
            }
        }
        .detailPanel()
    }

    private var biographySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Biography")

            if events.isEmpty {
                Text("No biography events yet. Progression rebuild will add earned, tier-up, PR, and milestone history when source workouts are available.")
                    .dsFont(.footnote)
                    .foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 10) {
                    ForEach(events) { event in
                        biographyRow(event)
                    }
                }
            }
        }
        .detailPanel()
    }

    private var tierAccent: Color {
        Color(uiColor: BarbellPlateRenderProjection(plate: plate).tierAccentColor)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(DS.Typography.custom(size: 11, weight: .bold))
            .foregroundStyle(DS.Semantic.brand)
            .tracking(0.9)
    }

    private func detailPill(text: String) -> some View {
        Text(text)
            .dsFont(.caption, weight: .bold)
            .foregroundStyle(.white.opacity(0.82))
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(Color.white.opacity(0.08), in: Capsule())
    }

    private func detailCounter(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .dsFont(.subheadline, weight: .bold)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(label.uppercased())
                .font(DS.Typography.custom(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.50))
                .tracking(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.065), in: ChamferedRectangle(.medium))
    }

    private func biographyRow(_ event: BarbellPlateEvent) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName(for: event.kind))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tierAccent)
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.08), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(event.summary)
                    .dsFont(.subheadline, weight: .semibold)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Text(event.occurredAt.formatted(date: .abbreviated, time: .omitted))
                    if let tierRaw = event.tierRaw {
                        Text("/")
                        Text(tierRaw.capitalized)
                    }
                }
                .font(DS.Typography.custom(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.48))
                .tracking(0.5)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.white.opacity(0.055), in: ChamferedRectangle(.medium))
    }

    private func iconName(for kind: BarbellPlateEvent.Kind) -> String {
        switch kind {
        case .earned: return "plus.circle.fill"
        case .tieredUp: return "arrow.up.circle.fill"
        case .personalRecord: return "bolt.fill"
        case .milestoneVolume: return "flag.checkered"
        case .anniversary: return "calendar"
        }
    }

    private static func displayLiftName(_ liftTypeID: String?) -> String {
        BarbellPlateProgressionScope.normalizedLiftTypeID(liftTypeID)
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

private extension View {
    func detailPanel() -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.07), in: ChamferedRectangle(.large))
            .overlay(
                ChamferedRectangle(.large)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
    }
}

private struct PlateCollectionCell: View {
    let plate: EarnedPlate
    let workoutSummary: PlateWorkoutSummary?
    let onOpenDetail: () -> Void
    let onPrimaryAction: () -> Void

    private var tier: PlateTier? {
        PlateTier.all.first(where: { $0.id == plate.tierID })
    }

    private var tierName: String {
        tier?.name ?? "Tier \(plate.tierID + 1)"
    }

    private var rarityLabel: String {
        guard let tier else { return "Earned" }
        switch tier.rarity {
        case .common: return "Common"
        case .uncommon: return "Uncommon"
        case .rare: return "Rare"
        case .epic: return "Epic"
        case .legendary: return "Legendary"
        }
    }

    private var accentColor: Color {
        guard let tier else { return DS.Semantic.brand }
        switch tier.rarity {
        case .common: return .white.opacity(0.70)
        case .uncommon: return Color(hex: "#80E6A2")
        case .rare: return Color(hex: "#6CB7FF")
        case .epic: return Color(hex: "#C694FF")
        case .legendary: return DS.Semantic.brand
        }
    }

    private var displayTitle: String {
        plate.engravingText.isEmpty ? tierName : plate.engravingText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            tappableContent

            Spacer(minLength: 0)

            Button(action: onPrimaryAction) {
                HStack(spacing: 7) {
                    Image(systemName: plate.isRacked ? "arrow.down.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text(plate.isRacked ? "Remove" : "Rack")
                        .dsFont(.caption, weight: .bold)
                }
                .foregroundStyle(plate.isRacked ? .white : .black)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(
                    plate.isRacked ? Color.white.opacity(0.10) : DS.Semantic.brand,
                    in: ChamferedRectangle(.medium)
                )
                .overlay(
                    ChamferedRectangle(.medium)
                        .stroke(Color.white.opacity(plate.isRacked ? 0.10 : 0), lineWidth: 1)
                )
            }
        }
        .frame(minHeight: 214, alignment: .top)
        .padding(14)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.10),
                    Color.white.opacity(0.055)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: ChamferedRectangle(.large)
        )
        .overlay(
            ChamferedRectangle(.large)
                .stroke(accentColor.opacity(0.28), lineWidth: 1)
        )
    }

    private var tappableContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Int(plate.weightKg))kg")
                        .font(DS.Typography.custom(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                    Text(tierName)
                        .dsFont(.caption, weight: .semibold)
                        .foregroundStyle(.white.opacity(0.62))
                }

                Spacer(minLength: 8)

                PlateMedallionView(plate: plate, accentColor: accentColor)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(displayTitle)
                    .dsFont(.subheadline, weight: .semibold)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)

                HStack(spacing: 6) {
                    Text(rarityLabel.uppercased())
                    Text("/")
                    Text(plate.isRacked ? "RACKED" : "STORED")
                }
                .font(DS.Typography.custom(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.48))
                .tracking(0.7)
            }

            if let workoutSummary {
                VStack(alignment: .leading, spacing: 3) {
                    Text(workoutSummary.title)
                        .dsFont(.caption, weight: .semibold)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Text(workoutSummary.detail)
                        .font(DS.Typography.custom(size: 10, weight: .bold))
                        .foregroundStyle(DS.Semantic.brand.opacity(0.90))
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)
                        .tracking(0.5)
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            onOpenDetail()
        }
    }
}

private struct PlateWorkoutSummary {
    let title: String
    let detail: String

    init(fallback: PlateCollectionFallbackSummary) {
        title = fallback.title
        detail = fallback.detail
    }

    init(plate: EarnedPlate, workout: CompletedWorkout) {
        let bestSet = workout.entries
            .flatMap { entry in entry.sets.map { (entry: entry, set: $0) } }
            .filter { $0.set.tag == .working && $0.set.hasData }
            .sorted {
                if $0.set.weight != $1.set.weight { return $0.set.weight > $1.set.weight }
                return $0.set.reps > $1.set.reps
            }
            .first

        if plate.earnedByEvent.hasPrefix("pr_"), let bestSet {
            title = bestSet.entry.exerciseName
            detail = "PR \(bestSet.set.displayValue.uppercased())"
            return
        }

        title = workout.workoutName ?? workout.workoutTypeDisplayName
        if let bestSet {
            detail = "\(bestSet.entry.exerciseName.uppercased()) / \(bestSet.set.displayValue.uppercased())"
        } else {
            detail = workout.date.formatted(date: .abbreviated, time: .omitted).uppercased()
        }
    }
}

private struct PlateMedallionView: View {
    let plate: EarnedPlate
    let accentColor: Color

    var body: some View {
        PlateFaceView(
            tierID: plate.tierID,
            progressionTier: plate.currentTier,
            liftTypeID: plate.liftTypeID,
            weightKg: plate.weightKg
        )
        .frame(width: 44, height: 44)
        .shadow(color: accentColor.opacity(0.30), radius: 10, x: 0, y: 4)
        .accessibilityHidden(true)
    }
}
