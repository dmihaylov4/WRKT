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
    @State private var preload = CutRackPreload()
    @State private var showsScene = false
    @State private var sceneRevision = 0
    @State private var notice: CutRackNotice?
    @State private var showsEditor = false
    @State private var showsCollection = false
    @State private var detail: CutRackPlateID?
    @State private var playPhase: CutRackPlayPhase = .idle
    @State private var rain = CutRackRainTask()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The card tray or the storage rail (CutRackTrayStyle: the rail in debug builds only).
    private let trayStyle = CutRackTrayStyle.current
    private let railTap = CutRackRailTap.current
    /// Rail: the group lifted out and shown face on.
    @State private var lifted: String?
    /// Rail: plates a tap started swinging onto the bar, not saved yet.
    @State private var inFlight: Set<String> = []
    /// Rail: stored plates lying in the room after "Drop all".
    @State private var onFloor: Set<String> = []

    private var unit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .kg }

    var body: some View {
        let _ = RackWorkCounters.debugTick(.hostBodies)
        screen
        .task {
            #if DEBUG
            Self.testScene = sceneState
            Self.testToggle = { id in trayStyle == .rail ? railToggle(id) : toggle(id) }
            Self.testRail = CutRackRailTestHooks(
                lift: { id in lifted = id },
                drop: { dropAll() },
                groupIDs: { railModel.groups.map(\.id) }
            )
            #endif
            let preload = startPreload()
            // The screen's first frame (header, summary, tray) is drawn before RealityKit sets
            // up, which is the longest main-thread step of an open; the preload already runs.
            try? await Task.sleep(for: .milliseconds(1))
            guard !Task.isCancelled else { return }
            showsScene = true
            await preload.value
        }
        .onDisappear {
            if !assetsReady { preload.task?.cancel() }
            preload.releaseThumbnails()
            CutRackWarmUp.sceneIsUp = false
            // Dropped plates are play only: leaving the screen clears them at once (an exit
            // animation would only play behind the navigation).
            if playPhase != .idle { tidyUp(animated: false, announce: false) }
            sceneState.finishTidy()
        }
        .onChange(of: sceneSyncKey) { old, new in syncScene(from: old, to: new) }
        .onChange(of: cosmeticKey) { _, _ in rebuildScene() }
        .sheet(isPresented: $showsEditor) {
            BarbellEditorView()
                .environmentObject(dependencies.workoutStore)
        }
        .sheet(isPresented: $showsCollection) {
            CutRackCollectionHost(toggle: sheetToggle)
        }
        .sheet(item: $detail) { item in
            CutRackPlateDetailHost(plateID: item.id, toggle: sheetToggle)
        }
    }

    /// A load or take-off from the detail or collection sheet.
    private func sheetToggle(_ id: String) {
        trayStyle == .rail ? railToggle(id) : toggle(id)
    }

    private var model: CutRackModel {
        CutRackLogic.model(CutRackFacts(
            plates: ownedPlates.map(CutRackPlateFacts.init),
            occupiedSlots: rackedPlates.count,
            unit: unit,
            notice: notice,
            playPhase: playPhase,
            rainCap: RackPlateRain.limits(for: sceneState.plateStyle).plates
        ))
    }

    @ViewBuilder
    private var screen: some View {
        if trayStyle == .rail {
            railScreen
        } else {
            CutRackView(
                model: model,
                actions: CutRackActions(
                    back: { dismiss() },
                    edit: { showsEditor = true },
                    showAll: { showsCollection = true },
                    toggle: { id in toggle(id) },
                    details: { id in detail = CutRackPlateID(id: id) },
                    play: { playPhase == .idle ? dropAll() : tidyUp() }
                ),
                scene: { scene },
                thumbnail: { id in thumbnail(id) }
            )
        }
    }

    // MARK: Rail

    private var railModel: CutRackRailModel {
        CutRackRailLogic.model(CutRackRailFacts(
            plates: ownedPlates.map(CutRackPlateFacts.init),
            unit: unit,
            notice: notice,
            playPhase: playPhase,
            inFlight: inFlight,
            onFloor: onFloor,
            tap: railTap
        ))
    }

    private var railScreen: some View {
        let rail = railModel
        let preview = lifted.flatMap(rail.group).map {
            CutRackRailLogic.preview($0, barIsFull: CutRackRailLogic.isBarFull(occupiedSlots: rackedPlates.count,
                                                                               inFlight: inFlight.count), unit: unit)
        }
        return CutRackRailScreen(
            model: model,
            rail: rail,
            lifted: preview,
            tapMode: railTap,
            actions: CutRackRailActions(
                back: { dismiss() },
                edit: { showsEditor = true },
                showAll: { showsCollection = true },
                play: { playPhase == .idle ? dropAll() : tidyUp() },
                tap: { id in
                    guard let group = railModel.group(id) else { return }
                    apply(CutRackRailLogic.tap(group, lifted: lifted, mode: railTap))
                },
                hold: { id in
                    guard let group = railModel.group(id) else { return }
                    apply(CutRackRailLogic.hold(group))
                },
                load: { id in apply(.load(id)) },
                unload: { id in apply(.unload(id)) },
                details: { id in detail = CutRackPlateID(id: id) },
                closeLift: { lifted = nil }
            ),
            scene: { scene },
            stand: { group in standArt(group.plateID) },
            face: { group in faceArt(group.plateID) },
            groupShown: { group in await prefetch(group.nextToLoad) }
        )
    }

    private func apply(_ outcome: CutRackRailLogic.Outcome) {
        switch outcome {
        case .lift(let id): lifted = id
        case .close: lifted = nil
        case .load(let id), .unload(let id):
            lifted = nil
            railToggle(id)
        }
    }

    /// The tray's toggle, with the plate leaving the rail as it swings in. The rail changes a
    /// moment after the tap, never in the frame where the plate starts to move (a host update
    /// there cost that frame about 30 ms), and only while the load is still in flight.
    private func railToggle(_ id: String) {
        let loading = ownedPlates.first { $0.id == id }.map { !$0.isRacked } ?? false
        toggle(id, finished: { inFlight.remove(id) })
        guard loading else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(40))
            if CutRackTap.pendingSlots[id] != nil { inFlight.insert(id) }
        }
    }

    /// A rail group's next plate gets its lathe faces ready, as a card tile's plate does.
    private func prefetch(_ id: String?) async {
        guard let id, let plate = ownedPlates.first(where: { $0.id == id }) else { return }
        await CutRackWarmUp.prefetchFaces(for: plate)
    }

    @ViewBuilder
    private func standArt(_ id: String) -> some View {
        if let plate = ownedPlates.first(where: { $0.id == id }) {
            RackRailStandArt(request: Self.pictureRequest(plate))
        }
    }

    @ViewBuilder
    private func faceArt(_ id: String) -> some View {
        if let plate = ownedPlates.first(where: { $0.id == id }) {
            RackRailFaceArt(request: Self.pictureRequest(plate))
        }
    }

    /// A rail picture's plate: its tier, weight, engraving and progression rings.
    static func pictureRequest(_ plate: EarnedPlate) -> LathePlateRequest {
        LathePlateRequest(tierID: plate.tierID, weightKg: plate.weightKg, engravingText: plate.engravingText,
                          projection: BarbellPlateRenderProjection(plate: plate))
    }

    // MARK: Scene

    /// The scene follows the screen's first frame: RealityKit sets up while the preload runs, and
    /// the scene's make awaits the preload before it builds the room.
    @ViewBuilder
    private var scene: some View {
        ZStack {
            if showsScene {
                realityScene
            }
            if !assetsReady {
                ProgressView()
                    .tint(DS.Cut.Colors.textPrimary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var realityScene: some View {
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
            barOnly: true,
            prepare: { await startPreload().value },
            onSceneBuilt: { [preload, sceneState, ownedPlates] in
                preload.releaseThumbnails(after: .milliseconds(500))
                CutRackWarmUp.afterSceneBuilt(owned: ownedPlates, in: sceneState)
            }
        )
        .id(sceneRevision)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Your bar in 3D"))
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

    /// One preload per screen, shared by the screen's task and the scene's make.
    @MainActor
    private func startPreload() -> Task<Void, Never> {
        if let task = preload.task, !task.isCancelled { return task }
        // Tray thumbnails that still need rendering wait until the scene is up.
        preload.holdThumbnails()
        let task = Task { @MainActor in await preloadAssets() }
        preload.task = task
        return task
    }

    @MainActor
    private func preloadAssets() async {
        guard !assetsReady else { return }
        await CutRackPreloader.preload(racked: rackedPlates, into: sceneState)
        guard !Task.isCancelled else { return }
        RackOpenTrace.mark("host.ready")
        assetsReady = true
    }

    @MainActor
    private func cacheMaterial(tierID: Int) async {
        await CutRackPreloader.cacheMaterial(tierID: tierID, in: sceneState)
    }

    /// A saved bar change, from the tray, a sheet, the editor or the scene itself. Plates newly on
    /// the bar are lifted or swung in; plates that left it slide off. Plates the scene already
    /// moved (a swipe or a drag) are bar or floor entities already and are left alone.
    private func syncScene(from old: [BarbellRackSceneSyncPlate], to new: [BarbellRackSceneSyncPlate]) {
        notice = nil
        RackOpenTrace.mark("sync")
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
                RackOpenTrace.mark("load.task")
                // Lathe plates never wait for their faces (the lettering arrives mid-flight);
                // legacy plates need their tier's material first.
                if state.plateStyle != .lathe, plate.tierID != 7 {
                    await cacheMaterial(tierID: plate.tierID)
                }
                RackOpenTrace.mark("load.prepared")
                guard !state.isPaused else { return }
                PlateSnapshotService.shared.holdRenders()
                await state.loadPlateOntoBar(plate, rackSlot: slot)
                PlateSnapshotService.shared.releaseRenders()
            }
        }
    }

    /// The editor changed the bar, rack or room: build the scene again with the cached materials.
    /// The new scene has no dropped plates.
    private func rebuildScene() {
        guard assetsReady else { return }
        rain.task?.cancel()
        sceneState.finishTidy()
        playPhase = .idle
        onFloor = []
        let fresh = SceneState()
        fresh.materialCache = sceneState.materialCache
        fresh.plateTextureCache = sceneState.plateTextureCache
        sceneState = fresh
        sceneRevision += 1
    }

    // MARK: Drop them all

    /// Rains the stored plates into the room, variety first and within the scene's caps. Nothing
    /// is saved; a plate dragged onto a sleeve from the pile is a real load (the scene's onRack).
    private func dropAll() {
        guard assetsReady, playPhase == .idle, !sceneState.isPaused else { return }
        let limits = RackPlateRain.limits(for: sceneState.plateStyle)
        let stored = ownedPlates.filter { !$0.isRacked }
        let ids = CutRackRainLogic.selection(ownedPlates.map(CutRackPlateFacts.init), cap: limits.plates,
                                             maxLooks: limits.looks, exclude: Set(sceneState.entityMap.keys))
        let byID = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let plates = ids.compactMap { byID[$0] }
        guard !plates.isEmpty else { return }
        lifted = nil
        onFloor = Set(plates.map(\.id))
        playPhase = .raining
        let state = sceneState
        let gentle = reduceMotion
        rain.task = Task { @MainActor in
            await state.rainPlates(plates, gentle: gentle) { dropped in
                guard !Task.isCancelled, state === sceneState else { return }
                playPhase = .loose
                AccessibilityNotification.Announcement(
                    CutRackRainLogic.announcement(dropped: dropped, stored: stored.count)).post()
            }
        }
    }

    private func tidyUp(animated: Bool = true, announce: Bool = true) {
        rain.task?.cancel()
        rain.task = nil
        sceneState.tidyRainedPlates(exit: animated ? RackTidyStyle.current : nil, reduceMotion: reduceMotion)
        playPhase = .idle
        onFloor = []
        if announce { AccessibilityNotification.Announcement(CutRackRainLogic.tidyAnnouncement).post() }
    }

    // MARK: Tray

    #if DEBUG
    /// Tests: the scene of the most recently shown rack (the throw harness drives it).
    static var testScene: SceneState?
    /// Tests: the tray's toggle of the most recently shown rack (the harness taps through it).
    static var testToggle: ((String) -> Void)?
    /// Tests: the rail of the most recently shown rack (the capture harness lifts and drops).
    static var testRail: CutRackRailTestHooks?
    #endif

    /// - Parameter finished: runs when the tap's save is done (rail: the plate has landed).
    private func toggle(_ id: String, finished: (() -> Void)? = nil) {
        RackOpenTrace.mark("tap")
        guard let plate = ownedPlates.first(where: { $0.id == id }) else { finished?(); return }
        let live = assetsReady && !sceneState.isPaused ? sceneState : nil
        let unit = unit
        CutRackTap.perform(plate, racked: rackedPlates, scene: live) { result in
            RackOpenTrace.mark("tap.saved")
            finished?()
            notice = result
            if result != nil {
                AccessibilityNotification.Announcement(CutRackLogic.hint(
                    CutRackFacts(plates: [], occupiedSlots: 0, unit: unit, notice: result), loaded: 0) ?? ""
                ).post()
            }
        }
    }

    @ViewBuilder
    private func thumbnail(_ id: String) -> some View {
        if let plate = ownedPlates.first(where: { $0.id == id }) {
            CutRackThumbnail(plate: plate)
        }
    }
}

/// What the rack scene's first frame needs, before it is first built: the light probe (started
/// at once, in parallel), legacy plate materials for the bar's tiers (lathe plates do not use
/// them), the bar plates' lathe faces, then the clink and drop sounds. Tray plates are prepared
/// when they are loaded (CutRackHost.syncScene), never up front: an earlier version prepared
/// every owned plate's faces here (128 face image sets for a 90-plate inventory).
enum CutRackPreloader {
    @MainActor
    static func preload(racked: [EarnedPlate], into sceneState: SceneState) async {
        RackOpenTrace.mark("host.preload")
        let lathe = sceneState.plateStyle == .lathe
        Task { @MainActor in
            if lathe { _ = await sharedRackStudioEnvironmentResource() } else { _ = await sharedRackRoomEnvironmentResource() }
        }
        if !lathe {
            for tierID in Set(racked.map(\.tierID)).sorted() where tierID != 7 {
                await cacheMaterial(tierID: tierID, in: sceneState)
            }
        }
        RackOpenTrace.mark("host.materials")
        if lathe {
            await prepareLathePlates(latheFirstFrameRequests(racked))
        }
        RackOpenTrace.mark("host.lathe")
        for tierID in PlateTier.all.map(\.id) {
            let category = PlateAudioCategory.from(tierID: tierID)
            _ = loadAudioResource(named: category.clinkSoundName)
            _ = loadAudioResource(named: category.dropSoundName)
        }
    }

    /// A legacy plate tier's textures and material in the scene's caches.
    @MainActor
    static func cacheMaterial(tierID: Int, in sceneState: SceneState) async {
        guard sceneState.materialCache[tierID] == nil else { return }
        let textures = await loadPlateTexturesAsync(forTierID: tierID)
        sceneState.plateTextureCache[tierID] = textures
        sceneState.materialCache[tierID] = buildMaterial(forTierID: tierID, textures: textures, inRackRoom: true)
    }
}

/// The screen's running preload, kept across body updates, and its hold on thumbnail renders
/// (PlateSnapshotService.holdRenders) while the scene opens.
@MainActor
final class CutRackPreload {
    var task: Task<Void, Never>?
    private var holdsThumbnails = false

    func holdThumbnails() {
        guard !holdsThumbnails else { return }
        holdsThumbnails = true
        PlateSnapshotService.shared.holdRenders()
        // Never hold for long, whatever happens to the scene.
        releaseThumbnails(after: .seconds(5))
    }

    func releaseThumbnails(after delay: Duration? = nil) {
        guard let delay else {
            guard holdsThumbnails else { return }
            holdsThumbnails = false
            PlateSnapshotService.shared.releaseRenders()
            return
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            self?.releaseThumbnails()
        }
    }
}

/// The running "Drop all", kept across body updates so tidying up can stop it.
@MainActor
final class CutRackRainTask {
    var task: Task<Void, Never>?
}

#if DEBUG
/// Tests: drive the rail of the rack on screen.
struct CutRackRailTestHooks {
    var lift: (String?) -> Void
    var drop: () -> Void
    var groupIDs: () -> [String]
}
#endif

/// Identifies the plate whose detail sheet is open.
struct CutRackPlateID: Identifiable, Hashable {
    var id: String
}

/// The legacy rack's save path for one plate, nothing more.
enum CutRackSaving {
    @MainActor
    /// Saves a load into the slot the scene swung the plate to.
    static func load(_ plate: EarnedPlate, slot: Int) -> CutRackNotice? {
        guard !plate.isRacked else { return nil }
        do {
            try BarbellProgressService.shared.rackPlate(plate, at: slot, playsFeedback: false)
            return nil
        } catch BarbellProgressService.RackError.barIsFull {
            return .barFull
        } catch {
            return .loadFailed
        }
    }

    static func toggle(_ plate: EarnedPlate, playsFeedback: Bool = true) -> CutRackNotice? {
        if plate.isRacked {
            BarbellProgressService.shared.removeFromBar(plate: plate)
            return nil
        }
        do {
            try BarbellProgressService.shared.addToBar(plate: plate, replacing: nil, playsFeedback: playsFeedback)
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
        // A plate shown in the tray gets its lathe faces ready, so a tap swings it in lettered.
        .task(id: plate.id) { await CutRackWarmUp.prefetchFaces(for: plate) }
    }
}

/// Work done after the rack scene is up, at low priority, so a tap rarely waits for anything:
/// legacy plate materials for every owned tier, lathe meshes for every owned tier, and the lathe
/// faces of plates the tray shows (prefetchFaces, one at a time, cancelled when the tile goes,
/// and never past LatheFaceCache's bound).
@MainActor
enum CutRackWarmUp {
    /// The rack scene is built and shown; prefetching may start.
    static var sceneIsUp = false
    private static var lastPrefetch: Task<Void, Never>?

    static func afterSceneBuilt(owned: [EarnedPlate], in sceneState: SceneState) {
        sceneIsUp = true
        let tiers = Set(owned.map(\.tierID)).subtracting([7]).sorted()
        Task(priority: .utility) { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            BarbellProgressService.shared.warmRackPath()
            if sceneState.plateStyle == .lathe {
                await prepareLathePlates(tiers.map {
                    LathePlateRequest(tierID: $0, weightKg: 0, engravingText: "", projection: BarbellPlateRenderProjection())
                }, priority: .utility, faces: false)
            } else {
                for tierID in tiers where !sceneState.isPaused {
                    await CutRackPreloader.cacheMaterial(tierID: tierID, in: sceneState)
                }
            }
        }
    }

    /// Prepares one tray plate's two faces (as loaded, and the blank mirror face), after the
    /// scene is up and the tile has stayed a moment. Returns at once for legacy plates.
    static func prefetchFaces(for plate: EarnedPlate) async {
        guard RackPlateStyle.current == .lathe, !plate.isRacked, !plate.isStarterPlate else { return }
        try? await Task.sleep(for: .milliseconds(400))
        while !sceneIsUp {
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(300))
        }
        let previous = lastPrefetch
        let requests = latheFirstFrameRequests([plate]) + latheLaterRequests([plate])
        let task = Task { @MainActor in
            await previous?.value
            // Leave room for the bar's own faces: never evict for a prefetch.
            guard !Task.isCancelled, LatheFaceCache.count + 2 <= LatheFaceCache.limit else { return }
            await prepareLathePlates(requests, priority: .utility)
        }
        lastPrefetch = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }
}

/// A tray tap, in the order that makes it feel immediate: the haptic and pick-up sound first,
/// then the plate starts moving in this frame. Persistence follows the motion: an unload saves
/// after the plate's first frame; a load saves when the plate seats (to the slot it swung to),
/// so the SwiftData change and the screen's re-layout it causes never land while the plate is in
/// flight. Slots of loads still in flight count as taken. A load whose save fails is dropped
/// back to the floor; the scene's resync then finds every plate already where it belongs, so the
/// bar is never rebuilt. The save's notice (bar full, save failed) arrives through `done`.
enum CutRackTap {
    /// How long an unload's save waits, so the plate's first moving frame is drawn before it.
    static let saveDelay: Duration = .milliseconds(20)

    /// Loads in flight and not saved yet: plate ID to bar slot.
    @MainActor private(set) static var pendingSlots: [String: Int] = [:]

    /// The innermost slot neither loaded nor taken by a load in flight.
    @MainActor
    static func freeSlot(racked: [EarnedPlate]) -> Int? {
        let taken = BarbellBarSlots.occupiedSlots(racked).union(pendingSlots.values)
        return BarbellBarSlots.positions.first { !taken.contains($0) }
    }

    @MainActor
    static func perform(
        _ plate: EarnedPlate,
        racked: [EarnedPlate],
        scene: SceneState?,
        feedback: ((Bool) -> Void)? = nil,
        save: ((EarnedPlate) -> CutRackNotice?)? = nil,
        saveToSlot: ((EarnedPlate, Int) -> CutRackNotice?)? = nil,
        done: @escaping (CutRackNotice?) -> Void = { _ in }
    ) {
        let feedback = feedback ?? { BarbellProgressService.shared.playTapFeedback(loading: $0) }
        let save = save ?? { CutRackSaving.toggle($0, playsFeedback: false) }
        let saveToSlot = saveToSlot ?? { CutRackSaving.load($0, slot: $1) }
        // A load still in flight: the plate is already on its way.
        guard pendingSlots[plate.id] == nil else { return }
        guard !plate.isRacked else {
            // Already sliding off from an earlier tap: nothing more to do.
            if let scene, scene.platesBeingUnracked.contains(plate.id) { return }
            feedback(false)
            if let scene { Task { @MainActor in await scene.releaseBarPlateToFloor(plateID: plate.id) } }
            Task { @MainActor in
                try? await Task.sleep(for: saveDelay)
                done(save(plate))
            }
            return
        }
        guard let slot = freeSlot(racked: racked) else {
            done(.barFull)
            return
        }
        feedback(true)
        guard let scene, canStartAtOnce(plate, in: scene) else {
            // No live scene, or a legacy tier whose material is not loaded yet: save now and let
            // the resync swing it in once the material is ready.
            done(saveToSlot(plate, slot))
            return
        }
        PlateSnapshotService.shared.holdRenders()
        guard let load = scene.beginLoadPlateOntoBar(plate, rackSlot: slot) else {
            PlateSnapshotService.shared.releaseRenders()
            done(saveToSlot(plate, slot))
            return
        }
        pendingSlots[plate.id] = slot
        Task { @MainActor in
            let seated = await scene.finishLoadPlateOntoBar(load)
            // Seated, or still on the sleeve (the screen went away mid-swing): keep it.
            let onBar = seated || scene.barMirrorMap[plate.id] === load.mirror
            let notice = onBar ? saveToSlot(plate, slot) : nil
            pendingSlots[plate.id] = nil
            if notice != nil { await scene.releaseBarPlateToFloor(plateID: load.plateID) }
            PlateSnapshotService.shared.releaseRenders()
            done(notice)
        }
    }

    /// Lathe plates always start at once; a legacy plate needs its tier's material in memory.
    @MainActor
    static func canStartAtOnce(_ plate: EarnedPlate, in scene: SceneState) -> Bool {
        scene.plateStyle == .lathe || plate.tierID == 7 || scene.materialCache[plate.tierID] != nil
    }
}

extension CutRackPlateFacts {
    init(_ plate: EarnedPlate) {
        let tier = PlateTier.all.first { $0.id == plate.tierID }
        self.init(
            id: plate.id,
            tierName: tier?.name ?? "Plate",
            engraving: plate.engravingText,
            weightKg: plate.weightKg,
            isLoaded: plate.isRacked,
            rackPosition: plate.rackPosition,
            displayOrder: plate.displayOrder,
            earnedAt: plate.effectiveFirstEarnedAt,
            tierID: plate.tierID,
            progressionTier: plate.currentTier.rawValue,
            liftTypeID: plate.liftTypeID,
            material: tier.map(CutRackPlateFamily.material(for:)) ?? .bumper,
            rarity: tier.map { CutRackPlateFamily.rank($0.rarity) } ?? 0
        )
    }
}

extension CutRackPlateFamily {
    /// The tray section of a tier's plates when they carry no engraving.
    static func material(for tier: PlateTier) -> CutRackPlateFamily {
        switch tier.style {
        case .bumper, .starter: return .bumper
        case .competition: return tier.metallic >= 0.5 ? .metal : .bumper
        case .rawIron, .castIron: return .iron
        case .brass, .polishedSteel, .gold: return .metal
        }
    }

    static func rank(_ rarity: PlateTier.Rarity) -> Int {
        switch rarity {
        case .common: return 0
        case .uncommon: return 1
        case .rare: return 2
        case .epic: return 3
        case .legendary: return 4
        }
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
