//
//  CutRackHost.swift
//  WRKT
//
//  PlateWallView's state behind the Cut rack. The same SwiftData reads, the same texture and
//  sound preload, the same RealityKit scene and the same save path (BarbellProgressService
//  addToBar and removeFromBar) as the legacy rack. Differences: the scene runs bar only (its wall
//  storage is replaced by the tray), and a tray tap saves first and then brings the live scene in
//  line with the scene's own motions: a plate on the floor is lifted back, a new plate swings
//  in, and an unloaded plate slides off and drops. Edit opens the existing bar and collar editor;
//  a cosmetic change from it rebuilds the scene once. Tray changes never rebuild the scene.
//

import RealityKit
import SwiftData
import SwiftUI

struct CutRackHost: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dependencies) private var dependencies

    @Query(filter: #Predicate<EarnedPlate> { $0.isRacked == true && $0.earnedByEvent != "starter" })
    private var rackedPlates: [EarnedPlate]
    @Query(filter: #Predicate<EarnedPlate> { $0.earnedByEvent != "starter" })
    private var ownedPlates: [EarnedPlate]
    @Query(filter: #Predicate<BarbellConfig> { $0.id == "global" })
    private var configs: [BarbellConfig]

    @AppStorage("weight_unit") private var weightUnitRaw: String = WeightUnit.kg.rawValue

    @State private var sceneState = SceneState()
    @State private var assetsReady = false
    @State private var sceneRevision = 0
    @State private var notice: CutRackNotice?
    @State private var showsEditor = false
    @State private var showsCollection = false
    @State private var detail: CutRackPlateID?

    private var unit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .kg }

    var body: some View {
        CutRackView(
            model: CutRackLogic.model(CutRackFacts(
                plates: ownedPlates.map(CutRackPlateFacts.init),
                occupiedSlots: rackedPlates.count,
                unit: unit,
                notice: notice
            )),
            actions: CutRackActions(
                back: { dismiss() },
                edit: { showsEditor = true },
                showAll: { showsCollection = true },
                toggle: { id in toggle(id) },
                details: { id in detail = CutRackPlateID(id: id) }
            ),
            scene: { scene },
            thumbnail: { id in thumbnail(id) }
        )
        .task { await preloadAssets() }
        .onChange(of: sceneSyncKey) { old, new in syncScene(from: old, to: new) }
        .onChange(of: cosmeticKey) { _, _ in rebuildScene() }
        .sheet(isPresented: $showsEditor) {
            BarbellEditorView()
                .environmentObject(dependencies.workoutStore)
        }
        .sheet(isPresented: $showsCollection) {
            CutRackCollectionHost(toggle: toggle)
        }
        .sheet(item: $detail) { item in
            CutRackPlateDetailHost(plateID: item.id, toggle: toggle)
        }
    }

    // MARK: Scene

    @ViewBuilder
    private var scene: some View {
        if assetsReady {
            BarbellRealityView(
                mode: .rackRoom(
                    rackedPlates: rackedPlates,
                    // Not built in bar-only mode; kept so a plate dropped on the floor can be
                    // dragged back onto the bar and saved, as in the legacy rack.
                    floorPlates: ownedPlates.filter { !$0.isRacked },
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
                roomThemeID: configs.first?.effectiveSelectedRoomThemeID ?? "dark_gym",
                roomWallText: configs.first?.roomName,
                barOnly: true
            )
            .id(sceneRevision)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Your bar in 3D"))
        } else {
            ProgressView()
                .tint(DS.Cut.Colors.textPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private struct CosmeticKey: Equatable {
        var barSkin: Int
        var rackStyle: String
        var roomTheme: String
        var wallText: String?
    }

    private var cosmeticKey: CosmeticKey {
        let config = configs.first
        return CosmeticKey(
            barSkin: config?.barSkinIndex ?? 0,
            rackStyle: config?.effectiveSelectedRackStyleID ?? "matte_black",
            roomTheme: config?.effectiveSelectedRoomThemeID ?? "dark_gym",
            wallText: config?.roomName
        )
    }

    private var sceneSyncKey: [BarbellRackSceneSyncPlate] {
        rackedPlates
            .map { BarbellRackSceneSyncPlate(id: $0.id, rackPosition: $0.rackPosition) }
            .sorted { $0.id < $1.id }
    }

    /// The legacy preload: plate textures and materials for every owned tier, then the clink and
    /// drop sounds, before the scene is first built.
    @MainActor
    private func preloadAssets() async {
        guard !assetsReady else { return }
        for tierID in Set((rackedPlates + ownedPlates).map(\.tierID)).sorted() where tierID != 7 {
            await cacheMaterial(tierID: tierID)
        }
        if sceneState.plateStyle == .lathe {
            // Every owned plate's lathe face, so a tray load never draws on the main thread.
            await prepareLathePlates((rackedPlates + ownedPlates).filter { !$0.isStarterPlate }.flatMap { plate in
                Set([plate.engravingText, ""]).map {
                    LathePlateRequest(tierID: plate.tierID, weightKg: plate.weightKg, engravingText: $0,
                                      projection: BarbellPlateRenderProjection(plate: plate))
                }
            })
        }
        for tierID in PlateTier.all.map(\.id) {
            let category = PlateAudioCategory.from(tierID: tierID)
            _ = loadAudioResource(named: category.clinkSoundName)
            _ = loadAudioResource(named: category.dropSoundName)
        }
        guard !Task.isCancelled else { return }
        assetsReady = true
    }

    @MainActor
    private func cacheMaterial(tierID: Int) async {
        guard sceneState.materialCache[tierID] == nil else { return }
        let textures = await loadPlateTexturesAsync(forTierID: tierID)
        sceneState.plateTextureCache[tierID] = textures
        sceneState.materialCache[tierID] = buildMaterial(forTierID: tierID, textures: textures, inRackRoom: true)
    }

    /// A saved bar change, from the tray, a sheet, the editor or the scene itself. Plates newly on
    /// the bar are lifted or swung in; plates that left it slide off. Plates the scene already
    /// moved (a swipe or a drag) are bar or floor entities already and are left alone.
    private func syncScene(from old: [BarbellRackSceneSyncPlate], to new: [BarbellRackSceneSyncPlate]) {
        notice = nil
        guard assetsReady, !sceneState.isPaused else { return }
        let state = sceneState
        let barEntities = Set(state.entityMap.compactMap { id, entity in
            entity.components[PlateRoleComponent.self]?.role == .bar ? id : nil
        })
        let roles = state.entityMap.reduce(into: [String: BarbellRackSceneEntityRole]()) { result, entry in
            switch entry.value.components[PlateRoleComponent.self]?.role {
            case .some(.floor): result[entry.key] = .floor
            case .some(.bar): result[entry.key] = .bar
            case .none: break
            }
        }
        for id in CutRackLogic.sceneReleases(previouslyLoaded: Set(old.map(\.id)), loaded: Set(new.map(\.id)),
                                             barEntities: barEntities, unloading: state.platesBeingUnracked) {
            Task { @MainActor in await state.releaseBarPlateToFloor(plateID: id) }
        }
        let actions = barbellRackSceneSyncActions(previousVisibleFloorIDs: [], currentVisibleFloorIDs: [],
                                                  rackedPlates: new, entityRolesByPlateID: roles)
        for action in actions {
            let plateID: String, slot: Int
            switch action {
            case .placeExistingOnBar(let id, let rackSlot), .addBarPlate(let id, let rackSlot):
                plateID = id
                slot = rackSlot
            case .removeStoragePlate, .addStoragePlate:
                continue
            }
            guard let plate = rackedPlates.first(where: { $0.id == plateID }) else { continue }
            Task { @MainActor in
                if plate.tierID != 7 { await cacheMaterial(tierID: plate.tierID) }
                guard !state.isPaused else { return }
                await state.loadPlateOntoBar(plate, rackSlot: slot)
            }
        }
    }

    /// The editor changed the bar, rack or room: build the scene again with the cached materials.
    private func rebuildScene() {
        guard assetsReady else { return }
        let fresh = SceneState()
        fresh.materialCache = sceneState.materialCache
        fresh.plateTextureCache = sceneState.plateTextureCache
        sceneState = fresh
        sceneRevision += 1
    }

    // MARK: Tray

    private func toggle(_ id: String) {
        guard let plate = ownedPlates.first(where: { $0.id == id }) else { return }
        let result = CutRackSaving.toggle(plate)
        notice = result
        if result != nil {
            AccessibilityNotification.Announcement(CutRackLogic.hint(
                CutRackFacts(plates: [], occupiedSlots: 0, unit: unit, notice: result), loaded: 0) ?? ""
            ).post()
        }
    }

    @ViewBuilder
    private func thumbnail(_ id: String) -> some View {
        if let plate = ownedPlates.first(where: { $0.id == id }) {
            CutRackThumbnail(plate: plate)
        }
    }
}

/// Identifies the plate whose detail sheet is open.
struct CutRackPlateID: Identifiable, Hashable {
    var id: String
}

/// The legacy rack's save path for one plate, nothing more.
enum CutRackSaving {
    @MainActor
    static func toggle(_ plate: EarnedPlate) -> CutRackNotice? {
        if plate.isRacked {
            BarbellProgressService.shared.removeFromBar(plate: plate)
            return nil
        }
        do {
            try BarbellProgressService.shared.addToBar(plate: plate, replacing: nil)
            return nil
        } catch BarbellProgressService.RackError.barIsFull {
            return .barFull
        } catch {
            return .loadFailed
        }
    }
}

/// The cached plate snapshot (rendered once per plate look, then read from disk).
struct CutRackThumbnail: View {
    let plate: EarnedPlate

    var body: some View {
        CachedPlateThumbnail(
            tierID: plate.tierID,
            progressionTier: plate.currentTier,
            liftTypeID: plate.liftTypeID,
            weightKg: plate.weightKg,
            engravingText: plate.engravingText
        )
    }
}

extension CutRackPlateFacts {
    init(_ plate: EarnedPlate) {
        self.init(
            id: plate.id,
            tierName: PlateTier.all.first { $0.id == plate.tierID }?.name ?? "Plate",
            engraving: plate.engravingText,
            weightKg: plate.weightKg,
            isLoaded: plate.isRacked,
            rackPosition: plate.rackPosition,
            displayOrder: plate.displayOrder,
            earnedAt: plate.effectiveFirstEarnedAt
        )
    }
}

// MARK: - Plate detail

/// PlateDetailView's facts in the Cut choice sheet: when and for what the plate was earned, its
/// tier and use, and one load or take-off action through the same save path as the tray.
struct CutRackPlateDetailHost: View {
    let plateID: String
    let toggle: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dependencies) private var dependencies
    @Query(filter: #Predicate<EarnedPlate> { $0.isRacked == true && $0.earnedByEvent != "starter" })
    private var rackedPlates: [EarnedPlate]
    @Query(filter: #Predicate<EarnedPlate> { $0.earnedByEvent != "starter" })
    private var ownedPlates: [EarnedPlate]
    @AppStorage("weight_unit") private var weightUnitRaw: String = WeightUnit.kg.rawValue

    var body: some View {
        if let plate = ownedPlates.first(where: { $0.id == plateID }) {
            CutRackPlateDetailView(
                model: CutRackPlateDetailLogic.model(CutRackPlateDetailFacts(
                    plate: CutRackPlateFacts(plate),
                    source: source(for: plate),
                    progressionTier: plate.currentTier.rawValue.capitalized,
                    workoutsUsed: plate.workoutsUsedCount,
                    prCount: plate.prCount,
                    barIsFull: CutRackLogic.isBarFull(occupiedSlots: rackedPlates.count),
                    unit: WeightUnit(rawValue: weightUnitRaw) ?? .kg
                )),
                toggle: { toggle(plateID) },
                close: { dismiss() },
                thumbnail: { CutRackThumbnail(plate: plate) }
            )
        }
    }

    /// The workout or lift the legacy collection names for this plate.
    private func source(for plate: EarnedPlate) -> String? {
        let store = dependencies.workoutStore
        if let id = plate.sourceWorkoutID.flatMap(UUID.init(uuidString:)) {
            if let workout = store.completedWorkouts.first(where: { $0.id == id }) {
                return PlateWorkoutSummary(plate: plate, workout: workout).title
            }
            if let run = store.runSummaries.first(where: { $0.healthKitUUID == id || $0.id == id }),
               let summary = plateCollectionHealthKitSummary(for: plate, run: run) {
                return summary.title
            }
        }
        return plateCollectionFallbackSummary(for: plate)?.title
    }
}

// MARK: - Collection

/// PlateCollectionView's list in the Cut browser sheet: every earned plate, bar plates first. A
/// row opens the plate's detail on top.
struct CutRackCollectionHost: View {
    let toggle: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<EarnedPlate> { $0.earnedByEvent != "starter" })
    private var ownedPlates: [EarnedPlate]
    @AppStorage("weight_unit") private var weightUnitRaw: String = WeightUnit.kg.rawValue
    @State private var detail: CutRackPlateID?

    var body: some View {
        CutRackCollectionView(
            model: CutRackCollectionLogic.model(plates: ownedPlates.map(CutRackPlateFacts.init),
                                                unit: WeightUnit(rawValue: weightUnitRaw) ?? .kg),
            open: { detail = CutRackPlateID(id: $0) },
            close: { dismiss() },
            thumbnail: { id in
                if let plate = ownedPlates.first(where: { $0.id == id }) { CutRackThumbnail(plate: plate) }
            }
        )
        .sheet(item: $detail) { item in
            CutRackPlateDetailHost(plateID: item.id, toggle: toggle)
        }
    }
}
