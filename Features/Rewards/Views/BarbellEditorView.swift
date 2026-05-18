import SwiftData
import SwiftUI

let barbellEditorScrollBottomPadding: CGFloat = 128

func configuredBarbellDisplayPlates(
    loadout: DisplayLoadout?,
    earnedPlates: [EarnedPlate],
    maximumBarPlateCount: Int = 4
) -> [EarnedPlate]? {
    guard let loadout else { return nil }
    let sanitizedLoadout = loadout.sanitized(
        earnedPlateIDs: Set(earnedPlates.map(\.id)),
        maximumBarPlateCount: maximumBarPlateCount
    )
    let platesByID = Dictionary(grouping: earnedPlates, by: \.id)
        .compactMapValues { $0.first }
    return sanitizedLoadout.onBar.compactMap { platesByID[$0] }
}

struct BarbellEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<BarbellConfig> { $0.id == "global" })
    private var configs: [BarbellConfig]
    @Query private var cosmeticUnlocks: [BarbellCosmeticUnlock]
    @Query private var earnedPlates: [EarnedPlate]

    @State private var selectedTab: Tab = .bar
    var openOnStorage: Bool = false
    @EnvironmentObject private var store: WorkoutStoreV2
    @State private var selectedPlateForDetail: EarnedPlate?
    @State private var storageRackErrorMessage: String?

    private let catalog = BarbellCosmeticCatalog.current

    private var config: BarbellConfig? {
        configs.first
    }

    private var unlockedIDs: Set<String> {
        catalog.defaultUnlockIDs.union(cosmeticUnlocks.map(\.cosmeticID))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                previewPanel
                tabPicker
                tabContent
            }
            .padding(.horizontal, 16)
            .padding(.top, 46)
            .padding(.bottom, barbellEditorScrollBottomPadding)
        }
        .background(DS.Semantic.surface.ignoresSafeArea())
        .navigationTitle("My Barbell")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            ensureConfig()
            if openOnStorage {
                selectedTab = .display
            }
        }
    }

    private var previewPanel: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Editor")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DS.Semantic.brand)
                    Text(selectedCosmeticName)
                        .font(.system(size: 28, weight: .black))
                        .foregroundStyle(.white)
                }
                Spacer()
                Text(catalog.version.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DS.Semantic.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(DS.Semantic.fillSubtle)
                    .clipShape(Capsule())
            }

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.045))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )

                BarbellPreviewView(
                    mode: .showcase(plates: previewPlateInfos),
                    selectedBarID: selectedBarSkinIndex,
                    selectedRoomThemeID: config?.effectiveSelectedRoomThemeID ?? BarbellCustomizationDefaults.roomThemeID,
                    selectedRackStyleID: config?.effectiveSelectedRackStyleID ?? BarbellCustomizationDefaults.rackStyleID,
                    showPlateEngravings: config?.showPlateEngravings ?? BarbellCustomizationDefaults.showPlateEngravings
                )
                .id(previewIdentity)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .frame(height: 220)
        }
        .padding(18)
        .background(DS.Semantic.card)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(DS.Semantic.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var tabPicker: some View {
        HStack(spacing: 8) {
            ForEach(Tab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Image(systemName: tab.symbolName)
                        .font(.system(size: 15, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .foregroundStyle(selectedTab == tab ? Color.black : DS.Semantic.textSecondary)
                        .background(selectedTab == tab ? DS.Semantic.brand : DS.Semantic.fillSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .accessibilityLabel(tab.title)
            }
        }
    }

    private var editorBarPreview: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let centerY = geo.size.height * 0.58
            let sleeveLength = min(width * 0.24, 106)

            ZStack {
                subtleFloor(width: width * 0.78)
                    .position(x: width * 0.5, y: centerY + 34)

                barShaft(width: width * 0.86, height: 6)
                    .position(x: width * 0.5, y: centerY)

                barSleeve(width: sleeveLength, height: 13)
                    .position(x: width * 0.25, y: centerY)
                barSleeve(width: sleeveLength, height: 13)
                    .position(x: width * 0.75, y: centerY)

                plateStack(side: .left)
                    .position(x: width * 0.235, y: centerY)
                plateStack(side: .right)
                    .position(x: width * 0.765, y: centerY)

                collar
                    .position(x: width * 0.385, y: centerY)
                collar
                    .position(x: width * 0.615, y: centerY)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
    }

    private func plateStack(side: PreviewSide) -> some View {
        let plates = Array(previewPlates.prefix(4))
        return ZStack {
            ForEach(Array(plates.enumerated()), id: \.element.id) { index, plate in
                let offset = CGFloat(index * 13) * side.direction
                sidePlate(plate: plate, index: index)
                .offset(x: offset)
                .zIndex(Double(plates.count - index))
            }
        }
    }

    private func sidePlate(plate: EarnedPlate, index: Int) -> some View {
        let tier = PlateTier.all.first { $0.id == plate.tierID }
        let base = tier.map { Color(uiColor: $0.plateColor) } ?? Color(hex: "#B12A24")
        let width = CGFloat(max(14, 18 - index * 2))
        let height = CGFloat(max(76, 92 - index * 4))

        return RoundedRectangle(cornerRadius: width * 0.45)
            .fill(
                LinearGradient(
                    colors: [
                        base.brightenedForEditor(by: 0.22),
                        base,
                        base.darkenedForEditor(by: 0.24),
                        base.brightenedForEditor(by: 0.10)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: width, height: height)
            .overlay(
                RoundedRectangle(cornerRadius: width * 0.45)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    .padding(.leading, 2)
                    .padding(.trailing, 5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: width * 0.45)
                    .stroke(Color.black.opacity(0.42), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.34), radius: 4, x: 0, y: 3)
    }

    private func barShaft(width: CGFloat, height: CGFloat) -> some View {
        Capsule()
            .fill(metalGradient)
            .frame(width: width, height: height)
            .overlay(Capsule().fill(Color.white.opacity(0.45)).frame(height: 1.5), alignment: .top)
            .overlay(Capsule().stroke(Color.black.opacity(0.25), lineWidth: 1))
            .shadow(color: .black.opacity(0.24), radius: 3, x: 0, y: 2)
    }

    private func barSleeve(width: CGFloat, height: CGFloat) -> some View {
        Capsule()
            .fill(metalGradient)
            .frame(width: width, height: height)
            .overlay(Capsule().stroke(Color.white.opacity(0.20), lineWidth: 1))
            .overlay(Capsule().stroke(Color.black.opacity(0.24), lineWidth: 1).padding(2))
            .shadow(color: .black.opacity(0.22), radius: 3, x: 0, y: 2)
    }

    private var collar: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(
                LinearGradient(
                    colors: [
                        selectedBarColor.brightenedForEditor(by: 0.22),
                        selectedBarColor.darkenedForEditor(by: 0.28)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 11, height: 46)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.black.opacity(0.42), lineWidth: 1))
    }

    private func subtleFloor(width: CGFloat) -> some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [.clear, Color.white.opacity(0.12), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: width, height: 2)
            .blur(radius: 2)
    }

    private var metalGradient: LinearGradient {
        LinearGradient(
            colors: [
                selectedBarColor.brightenedForEditor(by: 0.38),
                selectedBarColor.brightenedForEditor(by: 0.12),
                selectedBarColor.darkenedForEditor(by: 0.20),
                selectedBarColor.brightenedForEditor(by: 0.18)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .bar:
            cosmeticGrid(kind: .barSkin, selectedID: config?.effectiveSelectedBarSkinID)
        case .room:
            roomPanel
        case .rack:
            cosmeticGrid(kind: .rackStyle, selectedID: config?.effectiveSelectedRackStyleID)
        case .plates:
            platesPanel
        case .display:
            displayPanel
        }
    }

    private func cosmeticGrid(kind: BarbellCosmeticKind, selectedID: String?) -> some View {
        let items = catalog.items.filter { $0.kind == kind }
        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: selectedTab.title, subtitle: selectedTab.subtitle)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                ForEach(items) { item in
                    cosmeticButton(item: item, selectedID: selectedID)
                }
            }
        }
    }

    private func cosmeticButton(item: BarbellCosmetic, selectedID: String?) -> some View {
        let isUnlocked = isCosmeticUnlocked(item)
        let isSelected = selectedID == item.id

        return Button {
            guard isUnlocked else { return }
            applySelection(item)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    cosmeticSwatch(for: item)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : (isUnlocked ? "circle" : "lock.fill"))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(isSelected ? DS.Semantic.brand : DS.Semantic.textSecondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(isUnlocked ? .white : DS.Semantic.textSecondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                    Text(item.rarity.rawValue)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(item.rarity.color)
                    Text(item.unlockRequirement)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Semantic.textSecondary)
                        .lineLimit(2)
                }
            }
            .padding(12)
            .frame(minHeight: 136, alignment: .top)
            .background(isSelected ? DS.Semantic.brandSoft : DS.Semantic.fillSubtle)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? DS.Semantic.brand : DS.Semantic.border, lineWidth: isSelected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(isUnlocked ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!isUnlocked)
    }

    private func isCosmeticUnlocked(_ item: BarbellCosmetic) -> Bool {
        if item.kind == .barSkin, !item.isDefault {
            return config?.unlockedSkinIDs.contains(item.id) == true
        }
        return unlockedIDs.contains(item.id)
    }

    private var roomPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            cosmeticGrid(kind: .roomTheme, selectedID: config?.effectiveSelectedRoomThemeID)

            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(title: "Room Text", subtitle: "Visible in your barbell showcase")
                if let config {
                    TextField("Room name", text: roomNameBinding(config))
                        .textInputAutocapitalization(.words)
                        .textFieldStyle(EditorTextFieldStyle())
                    TextField("Motto", text: roomMottoBinding(config))
                        .textInputAutocapitalization(.sentences)
                        .textFieldStyle(EditorTextFieldStyle())
                }
            }
        }
    }

    private var platesPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Plates", subtitle: "Display options for earned plates")
            if let config {
                Toggle(isOn: showEngravingsBinding(config)) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Show engravings")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                        Text("Names and earned labels remain local display settings")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }
                }
                .tint(DS.Semantic.brand)
                .padding(14)
                .background(DS.Semantic.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 10)], spacing: 10) {
                ForEach(previewPlates.prefix(12)) { plate in
                    PlateFaceView(
                        tierID: plate.tierID,
                        progressionTier: plate.currentTier,
                        liftTypeID: plate.liftTypeID,
                        weightKg: plate.weightKg,
                        showEngravings: config?.showPlateEngravings ?? BarbellCustomizationDefaults.showPlateEngravings
                    )
                    .frame(width: 64, height: 64)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var displayPanel: some View {
        let loadout = resolvedDisplayLoadout
        let barPlates = displayBarPlates(loadout: loadout)
        let wallPlates = displayWallPlates(loadout: loadout)
        let barFull = barPlates.count >= 4

        return VStack(alignment: .leading, spacing: 20) {
            // On Bar section
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("On Bar")
                            .font(.system(size: 18, weight: .black))
                            .foregroundStyle(.white)
                        Text(barFull
                            ? "Bar full - remove a plate to swap"
                            : "Tap a plate to remove it from the bar")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }
                    Spacer()
                    Text("\(barPlates.count)/4")
                        .font(.system(size: 13, weight: .black).monospacedDigit())
                        .foregroundStyle(barFull ? DS.Semantic.brand : DS.Semantic.textSecondary)
                }

                if barPlates.isEmpty {
                    storageEmptyHint("No plates on the bar - rack a plate from storage below")
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(barPlates) { plate in
                            PlateCollectionCell(
                                plate: plate,
                                workoutSummary: workoutSummary(for: plate),
                                onOpenDetail: { selectedPlateForDetail = plate },
                                onPrimaryAction: { moveToWall(plate) }
                            )
                        }
                    }
                }
            }

            // Stored section
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Stored")
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(.white)
                    Text(barFull
                        ? "Bar full (4/4) - remove a bar plate first"
                        : "Tap a plate to rack it on the bar")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.Semantic.textSecondary)
                }

                if wallPlates.isEmpty {
                    storageEmptyHint("All earned plates are on the bar")
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(wallPlates) { plate in
                            PlateCollectionCell(
                                plate: plate,
                                workoutSummary: workoutSummary(for: plate),
                                onOpenDetail: { selectedPlateForDetail = plate },
                                onPrimaryAction: {
                                    guard !barFull else {
                                        storageRackErrorMessage = "Remove a plate from the bar before adding another one."
                                        return
                                    }
                                    moveToBar(plate)
                                }
                            )
                            .opacity(barFull ? 0.35 : 1.0)
                        }
                    }
                }
            }
        }
        .alert("Bar is full", isPresented: Binding(
            get: { storageRackErrorMessage != nil },
            set: { if !$0 { storageRackErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(storageRackErrorMessage ?? "")
        }
        .sheet(item: $selectedPlateForDetail) { plate in
            PlateDetailView(plate: plate)
                .environmentObject(store)
        }
    }

    private func storageEmptyHint(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(DS.Semantic.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(DS.Semantic.fillSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func workoutSummary(for plate: EarnedPlate) -> PlateWorkoutSummary? {
        if let workout = sourceWorkout(for: plate) {
            return PlateWorkoutSummary(plate: plate, workout: workout)
        }
        if let run = sourceRun(for: plate),
           let summary = plateCollectionHealthKitSummary(for: plate, run: run) {
            return PlateWorkoutSummary(fallback: summary)
        }
        return plateCollectionFallbackSummary(for: plate).map(PlateWorkoutSummary.init(fallback:))
    }

    private func sourceWorkout(for plate: EarnedPlate) -> CompletedWorkout? {
        guard let sourceWorkoutID = plate.sourceWorkoutID,
              let uuid = UUID(uuidString: sourceWorkoutID) else { return nil }
        return store.completedWorkouts.first(where: { $0.id == uuid })
    }

    private func sourceRun(for plate: EarnedPlate) -> Run? {
        guard let sourceWorkoutID = plate.sourceWorkoutID,
              let uuid = UUID(uuidString: sourceWorkoutID) else { return nil }
        return store.runs.first { $0.healthKitUUID == uuid || $0.id == uuid }
    }

    private var nonStarterPlates: [EarnedPlate] {
        earnedPlates.filter { $0.earnedByEvent != "starter" }
    }

    private var resolvedDisplayLoadout: DisplayLoadout {
        guard let config else { return DisplayLoadout() }
        return config.displayLoadout.sanitized(
            earnedPlateIDs: Set(nonStarterPlates.map(\.id)),
            maximumBarPlateCount: 4
        )
    }

    private func displayBarPlates(loadout: DisplayLoadout) -> [EarnedPlate] {
        let byID = Dictionary(uniqueKeysWithValues: earnedPlates.map { ($0.id, $0) })
        return loadout.onBar.compactMap { byID[$0] }
    }

    private func displayWallPlates(loadout: DisplayLoadout) -> [EarnedPlate] {
        let onBarSet = Set(loadout.onBar)
        let onWallSet = Set(loadout.onWall)
        let byID = Dictionary(uniqueKeysWithValues: nonStarterPlates.map { ($0.id, $0) })
        var result: [EarnedPlate] = []
        for id in loadout.onWall {
            if let plate = byID[id] { result.append(plate) }
        }
        for plate in nonStarterPlates.sorted(by: { $0.earnedAt < $1.earnedAt }) {
            if !onBarSet.contains(plate.id) && !onWallSet.contains(plate.id) {
                result.append(plate)
            }
        }
        return result
    }

    private func moveToBar(_ plate: EarnedPlate) {
        guard let config else { return }
        var loadout = resolvedDisplayLoadout
        guard loadout.onBar.count < 4, !loadout.onBar.contains(plate.id) else { return }
        loadout.onWall.removeAll { $0 == plate.id }
        loadout.onBar.append(plate.id)
        config.setDisplayLoadout(loadout)
        BarbellProgressService.shared.applyDisplayLoadoutToRackedPlates(loadout)
        persistAndSync(config)
    }

    private func moveToWall(_ plate: EarnedPlate) {
        guard let config else { return }
        var loadout = resolvedDisplayLoadout
        guard !loadout.onWall.contains(plate.id) else { return }
        loadout.onBar.removeAll { $0 == plate.id }
        loadout.onWall.insert(plate.id, at: 0)
        config.setDisplayLoadout(loadout)
        BarbellProgressService.shared.applyDisplayLoadoutToRackedPlates(loadout)
        persistAndSync(config)
    }

    private func loadoutPlateTile(plate: EarnedPlate, isOnBar: Bool, barFull: Bool) -> some View {
        Button {
            if isOnBar { moveToWall(plate) } else { moveToBar(plate) }
        } label: {
            ZStack(alignment: .topTrailing) {
                PlateFaceView(
                    tierID: plate.tierID,
                    progressionTier: plate.currentTier,
                    liftTypeID: plate.liftTypeID,
                    weightKg: plate.weightKg,
                    showEngravings: config?.showPlateEngravings ?? BarbellCustomizationDefaults.showPlateEngravings
                )
                .frame(width: 64, height: 64)
                .clipped()

                Circle()
                    .fill(DS.Semantic.card)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Image(systemName: isOnBar ? "minus" : "plus")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(isOnBar ? DS.Semantic.textSecondary : DS.Semantic.brand)
                    )
                    .offset(x: 4, y: -4)
            }
        }
        .buttonStyle(.plain)
        .opacity((!isOnBar && barFull) ? 0.35 : 1.0)
        .disabled(!isOnBar && barFull)
        .accessibilityLabel(plate.engravingText.isEmpty ? "Plate" : plate.engravingText)
        .accessibilityHint(
            isOnBar
                ? "Move to wall"
                : barFull ? "Bar full, move a bar plate to make room" : "Move to bar"
        )
    }

    private func loadoutEmptyHint(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(DS.Semantic.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(DS.Semantic.fillSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.Semantic.textSecondary)
        }
    }

    private func cosmeticSwatch(for item: BarbellCosmetic) -> some View {
        Group {
            if item.kind == .barSkin, let skin = BarSkin.skin(forCosmeticID: item.id) {
                BarSkinPreviewTile(skin: skin)
                    .frame(width: 54, height: 18)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(cosmeticColor(for: item))
                    .frame(width: 34, height: 34)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.18), lineWidth: 1))
            }
        }
    }

    private var selectedCosmeticName: String {
        guard let config else { return "Build Your Barbell" }
        switch selectedTab {
        case .bar:
            return catalog.item(id: config.effectiveSelectedBarSkinID)?.name ?? "Bar"
        case .room:
            return catalog.item(id: config.effectiveSelectedRoomThemeID)?.name ?? "Room"
        case .rack:
            return catalog.item(id: config.effectiveSelectedRackStyleID)?.name ?? "Rack"
        case .plates:
            return config.showPlateEngravings ? "Engravings On" : "Engravings Off"
        case .display:
            return "Display Loadout"
        }
    }

    private var selectedBarColor: Color {
        guard let config else { return Color(hex: "#B8BEC8") }
        return cosmeticColor(for: catalog.item(id: config.effectiveSelectedBarSkinID))
    }

    private var previewIdentity: String {
        [
            "\(selectedBarSkinIndex)",
            config?.effectiveSelectedRoomThemeID ?? BarbellCustomizationDefaults.roomThemeID,
            config?.effectiveSelectedRackStyleID ?? BarbellCustomizationDefaults.rackStyleID,
            "\(config?.showPlateEngravings ?? BarbellCustomizationDefaults.showPlateEngravings)",
            previewPlateInfos.map(\.earnedByEvent).joined(separator: "|")
        ].joined(separator: "-")
    }

    private var previewPlates: [EarnedPlate] {
        if let configured = configuredBarPlates {
            return configured
        }

        let racked = earnedPlates
            .filter(\.isRacked)
            .sorted {
                let leftPosition = $0.rackPosition ?? Int.max
                let rightPosition = $1.rackPosition ?? Int.max
                if leftPosition != rightPosition { return leftPosition < rightPosition }
                return $0.earnedAt > $1.earnedAt
            }
        if !racked.isEmpty { return racked }

        let nonStarter = earnedPlates
            .filter { $0.earnedByEvent != "starter" }
            .sorted { $0.earnedAt > $1.earnedAt }
        if !nonStarter.isEmpty { return nonStarter }
        return earnedPlates.sorted { $0.earnedAt > $1.earnedAt }
    }

    private var configuredBarPlates: [EarnedPlate]? {
        guard let config else { return nil }
        return configuredBarbellDisplayPlates(loadout: config.displayLoadout, earnedPlates: earnedPlates)
    }

    private var previewPlateInfos: [EarnedPlateInfo] {
        previewPlates.prefix(4).map {
            EarnedPlateInfo(
                tierID: $0.tierID,
                weightKg: $0.weightKg,
                engravingText: $0.engravingText,
                earnedByEvent: $0.earnedByEvent,
                liftTypeID: $0.liftTypeID
            )
        }
    }

    private var selectedBarSkinIndex: Int {
        config?.barSkinIndex ?? 0
    }

    private func applySelection(_ item: BarbellCosmetic) {
        guard let config else { return }
        switch item.kind {
        case .barSkin:
            config.selectedBarSkinIDRaw = item.id
        case .roomTheme:
            config.selectedRoomThemeIDRaw = item.id
        case .rackStyle:
            config.selectedRackStyleIDRaw = item.id
        case .collar:
            config.selectedCollarIDRaw = item.id
        case .banner:
            config.selectedBannerIDRaw = item.id
        }
        BarbellProgressService.shared.playCosmeticEquipFeedback()
        persistAndSync(config)
    }

    private func persistAndSync(_ config: BarbellConfig) {
        config.needsSupabaseSync = true
        try? modelContext.save()
        BarbellCustomizationService.shared.enqueueSyncCurrentSettingsToSupabase()
    }

    private func ensureConfig() {
        guard configs.isEmpty else { return }
        let config = BarbellConfig()
        modelContext.insert(config)
        try? modelContext.save()
        BarbellCustomizationService.shared.enqueueSyncCurrentSettingsToSupabase()
    }

    private func roomNameBinding(_ config: BarbellConfig) -> Binding<String> {
        Binding {
            config.roomName ?? ""
        } set: { value in
            config.roomName = barbellNormalizedRoomWallText(value)
            persistAndSync(config)
        }
    }

    private func roomMottoBinding(_ config: BarbellConfig) -> Binding<String> {
        Binding {
            config.roomMotto ?? ""
        } set: { value in
            config.roomMotto = normalizedText(value, maximumLength: 64)
            persistAndSync(config)
        }
    }

    private func showEngravingsBinding(_ config: BarbellConfig) -> Binding<Bool> {
        Binding {
            config.showPlateEngravings
        } set: { value in
            config.showPlateEngravingsRaw = value
            persistAndSync(config)
        }
    }

    private func normalizedText(_ value: String, maximumLength: Int) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maximumLength))
    }

    private func cosmeticColor(for item: BarbellCosmetic?) -> Color {
        guard let item else { return Color(hex: "#B8BEC8") }
        switch item.id {
        case "steel_default", "chrome", "brushed_steel":
            return Color(hex: "#B8BEC8")
        case "black_oxide", "matte_black":
            return Color(hex: "#151515")
        case "gold", "brass_accent", "brass_accent_rack":
            return Color(hex: "#C8A246")
        case "cerakote", "concrete_room":
            return Color(hex: "#57624E")
        case "dark_gym":
            return Color(hex: "#101010")
        case "competition_platform":
            return Color(hex: "#244C89")
        case "neon_garage":
            return Color(hex: "#2EDBFF")
        case "iron_basement":
            return Color(hex: "#565149")
        case "daylight_studio":
            return Color(hex: "#D7DDE3")
        case "brick_powerhouse":
            return Color(hex: "#8F3A28")
        default:
            return DS.Semantic.brand
        }
    }

    private enum Tab: String, CaseIterable, Identifiable {
        case bar
        case room
        case rack
        case plates
        case display

        var id: String { rawValue }

        var title: String {
            switch self {
            case .bar: return "Bar"
            case .room: return "Room"
            case .rack: return "Rack"
            case .plates: return "Plates"
            case .display: return "Storage"
            }
        }

        var subtitle: String {
            switch self {
            case .bar: return "Choose the bar finish"
            case .room: return "Set room style and showcase text"
            case .rack: return "Choose the rack finish"
            case .plates: return "Tune plate presentation"
            case .display: return "Manage plates on bar and in storage"
            }
        }

        var symbolName: String {
            switch self {
            case .bar: return "minus"
            case .room: return "square.grid.2x2"
            case .rack: return "rectangle.split.3x1"
            case .plates: return "circle.grid.2x2"
            case .display: return "rectangle.on.rectangle"
            }
        }
    }

    private enum PreviewSide {
        case left
        case right

        var direction: CGFloat {
            switch self {
            case .left: return -1
            case .right: return 1
            }
        }
    }
}

private struct EditorTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(DS.Semantic.fillSubtle)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(DS.Semantic.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private extension Color {
    func brightenedForEditor(by amount: Double) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(
            hue: Double(h),
            saturation: Double(s),
            brightness: min(1, Double(b) + amount),
            opacity: Double(a)
        )
    }

    func darkenedForEditor(by amount: Double) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(
            hue: Double(h),
            saturation: Double(s),
            brightness: max(0, Double(b) - amount),
            opacity: Double(a)
        )
    }
}
