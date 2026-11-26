//
//  HomeHexPortalHost.swift
//  WRKT
//
//  Feeds the hex portal from what the rack already reads (the plates on the bar and the bar's
//  config) and runs it: the still's cache and refresh, the press, the cover with the live rack
//  screen, the fly-through and the hand-off to the live scene, and the way back. The rack screen
//  in the cover is the same CutRackHost the Me tab opens, with CutRackPortalHooks set; leaving
//  tears it down exactly as closing the Me sheet does.
//

import Combine
import RealityKit
import SwiftData
import SwiftUI
import UIKit

// MARK: - Coordinator

/// The portal's state, shared by the window and the cover. Each view reads only the values it
/// draws, so the fly-through never invalidates Home. Home itself does not move: a scale on Home
/// (tried as scaleEffect and as a visual effect) changed its safe area inset on every frame and
/// laid Home out per frame; the veil darkens it instead.
@Observable
@MainActor
final class HomeHexPortalCoordinator {
    static let openDuration: TimeInterval = 0.68
    static let closeDuration: TimeInterval = 0.5
    /// Ease in and out like a camera move (the mock's curve).
    static let openCurve = Animation.timingCurve(0.55, 0.05, 0.25, 1, duration: openDuration)
    static let closeCurve = Animation.timingCurve(0.3, 0.8, 0.25, 1, duration: closeDuration)
    /// The live scene is trusted after this many scene updates past its build.
    static let liveFramesBeforeHandOff = 3

    private(set) var phase = HomeHexPortalPhase()
    var isPresented = false
    private(set) var progress: CGFloat = 0
    private(set) var veilShown = false
    /// The cell's light tube (it fades as the cell's edge leaves the screen).
    private(set) var tubeShown = true
    private(set) var coverOpacity: Double = 1
    private(set) var stillOpacity: Double = 1
    private(set) var fullShown = false
    private(set) var controlsOpacity: Double = 0
    private(set) var restImage: UIImage?
    private(set) var restKey: String?
    private(set) var fullImage: UIImage?
    private(set) var stillSceneSize: CGSize = .zero
    private(set) var sourceFrame: CGRect = .zero
    private(set) var zoomScene: CGRect = .zero
    private(set) var focusWindowToken = 0
    /// The live rack screen is in the cover. It is mounted when the zoom ends, never during it:
    /// creating the RealityView and building the room take 150 to 320 ms of the main thread on
    /// the simulator, which would freeze the zoom; behind the full-screen still it is invisible.
    private(set) var roomMounted = false
    /// The live rack's scene band (measured in the cover, else estimated from the screen).
    private(set) var band: CGRect = .zero

    @ObservationIgnored var latestSourceFrame: CGRect = .zero
    @ObservationIgnored var isScrolling = false
    @ObservationIgnored var homeVisible = false
    @ObservationIgnored var workoutStartedAt: Date?
    @ObservationIgnored var facts: HomeHexStillFacts?
    @ObservationIgnored var racked: [EarnedPlate] = []
    @ObservationIgnored private var reduceMotion = false
    @ObservationIgnored private var liveScene: SceneState?
    @ObservationIgnored private var liveSubscription: (any Cancellable)?
    @ObservationIgnored private var keyAtOpen: String?
    @ObservationIgnored private var zoomStarted = false
    @ObservationIgnored private var pressEnd: Task<Void, Never>?
    @ObservationIgnored private var fullLoad: Task<Void, Never>?
    @ObservationIgnored private var prewarm: Task<Void, Never>?
    @ObservationIgnored private var handOffFallback: Task<Void, Never>?
    @ObservationIgnored private var screen: CGSize = .zero

    #if DEBUG
    /// The transition's timeline (name, time) for the timing harness.
    @ObservationIgnored var timeline: [(String, CFTimeInterval)] = []
    /// Tests: called when the cover's zoom starts, with the zoom's inputs.
    @ObservationIgnored var onZoomStart: (() -> Void)?
    /// Tests: the capture harness sets every value itself (scrub) instead of animating.
    @ObservationIgnored var scrubMode = false

    /// Tests: one frame of the transition, held still for a screenshot.
    func scrub(progress: CGFloat, still: Double, controls: Double, veil: Bool, tube: Bool = true, cover: Double = 1,
               full: Bool = true) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            self.progress = progress
            stillOpacity = still
            controlsOpacity = controls
            veilShown = veil
            tubeShown = tube
            coverOpacity = cover
            fullShown = full
        }
    }

    /// Tests: the scene the cover shows, once built.
    var liveSceneForTesting: SceneState? { liveScene }
    #endif

    private func mark(_ name: String) {
        #if DEBUG
        timeline.append((name, CACurrentMediaTime()))
        #endif
    }

    var currentKey: String? { facts.map(HomeHexPortalLogic.stillKey) }

    var workoutStarting: Bool {
        workoutStartedAt.map { Date().timeIntervalSince($0) < 6 } ?? false
    }

    // MARK: Band

    /// The band from disk, or estimated from the key window, once per screen size.
    func resolveBand() {
        guard let window = Self.keyWindow() else { return }
        let size = window.bounds.size
        guard size != screen || band == .zero else { return }
        screen = size
        let insets = window.safeAreaInsets
        band = RackRoomStillService.shared.measuredBand(screen: size)
            ?? HomeHexGeometry.estimatedScene(safeSize: CGSize(width: size.width - insets.left - insets.right,
                                                               height: size.height - insets.top - insets.bottom))
    }

    static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
    }

    // MARK: Still

    func setRest(_ image: UIImage, key: String, sceneSize: CGSize) {
        guard restKey != key else { return }
        withAnimation(restImage == nil ? nil : .easeInOut(duration: 0.3)) {
            restImage = image
            restKey = key
            stillSceneSize = sceneSize
        }
    }

    // MARK: Press

    func pressChanged(_ pressed: Bool) {
        if pressed {
            pressEnd?.cancel()
            guard phase.stage == .idle else { return }
            phase.handle(.touchDown)
            mark("touchDown")
            Haptics.light()
            prepare()
        } else {
            // The button's action may follow the release; only a release without a tap cancels.
            pressEnd = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(80))
                guard let self, !Task.isCancelled, self.phase.stage == .pressed else { return }
                self.phase.handle(.touchCancelled)
            }
        }
    }

    /// From the first touch: the full-resolution still decodes and the room's assets load (light
    /// probe, the bar plates' faces), so the scene's own preload finds them ready.
    private func prepare() {
        if fullImage == nil, fullLoad == nil, let key = restKey {
            fullLoad = Task { @MainActor [weak self] in
                let image = await RackRoomStillService.shared.loadFull(key)
                guard let self, self.restKey == key, self.phase.stage != .idle else { return }
                self.fullImage = image
                self.mark("fullStill")
                if self.zoomStarted { withAnimation(.easeIn(duration: 0.18)) { self.fullShown = true } }
            }
        }
        if prewarm == nil {
            let racked = racked
            prewarm = Task(priority: .userInitiated) { @MainActor [weak self] in
                await HomeHexPortalPrewarm.run(racked: racked)
                self?.mark("prewarmed")
            }
        }
    }

    // MARK: Open

    func open(reduceMotion: Bool) {
        guard phase.stage == .idle || phase.stage == .pressed else { return }
        mark("tap")
        if phase.stage == .idle { Haptics.light() }
        self.reduceMotion = reduceMotion
        prepare()
        resolveBand()
        phase.handle(.tap)
        keyAtOpen = currentKey
        sourceFrame = latestSourceFrame
        zoomScene = band
        zoomStarted = false
        roomMounted = false
        progress = 0
        veilShown = false
        tubeShown = true
        fullShown = false
        stillOpacity = 1
        controlsOpacity = 0
        coverOpacity = reduceMotion ? 0 : 1
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { isPresented = true }
    }

    /// The cover's first appearance: the zoom starts on the next run loop turn, aimed at the band
    /// measured on the last open (or estimated before the first).
    func coverAppeared() {
        Task { @MainActor [weak self] in self?.startZoom() }
    }

    private func startZoom() {
        guard phase.stage == .opening, !zoomStarted else { return }
        zoomStarted = true
        mark("zoomStart")
        #if DEBUG
        onZoomStart?()
        if scrubMode { return }
        #endif
        handOffFallback = Task { @MainActor [weak self] in
            // A scene that never reports its frames still hands off, a little late.
            try? await Task.sleep(for: .seconds(6))
            guard let self, !Task.isCancelled, !self.phase.liveReady else { return }
            self.apply(.liveFrame)
        }
        if reduceMotion {
            progress = 1
            veilShown = true
            withAnimation(.easeOut(duration: 0.25)) {
                coverOpacity = 1
            } completion: { [weak self] in
                self?.apply(.zoomEnded)
            }
            return
        }
        if fullImage != nil { withAnimation(.easeIn(duration: 0.18)) { fullShown = true } }
        withAnimation(Self.openCurve) {
            progress = 1
        } completion: { [weak self] in
            self?.apply(.zoomEnded)
        }
        withAnimation(.easeIn(duration: 0.42).delay(0.12)) {
            veilShown = true
        }
        withAnimation(.easeIn(duration: 0.25).delay(0.42)) {
            tubeShown = false
        }
    }

    // MARK: Live scene

    func sceneFrameChanged(_ rect: CGRect) {
        guard rect.width > 0, rect.height > 0, phase.stage != .idle else { return }
        if let window = Self.keyWindow() {
            RackRoomStillService.shared.recordBand(rect, screen: window.bounds.size)
        }
        // Measured once the room is mounted, after the zoom: it only differs from the band the zoom
        // used on the very first open (an estimate), and then the still moves onto it before the
        // hand-off.
        if zoomScene != rect, phase.stillShown { zoomScene = rect }
        if band != rect { band = rect }
    }

    func sceneBuilt(_ state: SceneState) {
        liveScene = state
        mark("sceneBuilt")
        guard let scene = state.sceneRoot.scene else {
            apply(.liveFrame)
            return
        }
        var updates = 0
        liveSubscription = scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            MainActor.assumeIsolated {
                updates += 1
                guard updates == Self.liveFramesBeforeHandOff, let self else { return }
                self.liveSubscription?.cancel()
                self.liveSubscription = nil
                self.apply(.liveFrame)
            }
        }
    }

    // MARK: Close

    func close() {
        guard phase.stage == .opening || phase.stage == .open else { return }
        mark("back")
        let wasOpen = phase.stage == .open && phase.controlsShown
        Task { @MainActor [weak self] in
            guard let self else { return }
            if wasOpen { await self.refreshStillFromLiveScene() }
            self.apply(.back)
            if self.roomMounted {
                // The controls fade first (the still is already over the scene: the same picture),
                // then the live room is let go before the cell shrinks, so the way back composites
                // images only and the room is torn down exactly as closing the Me sheet does.
                try? await Task.sleep(for: .milliseconds(130))
                self.roomMounted = false
                self.mark("roomUnmounted")
            }
            self.playClose()
        }
    }

    /// The bar changed during the visit: the live scene's frame, as it is now, becomes the still
    /// (the cell lands on the room as it was left). Otherwise the still stays; a stale still is
    /// re-rendered in the background after the close.
    private func refreshStillFromLiveScene() async {
        guard let state = liveScene, let key = currentKey, let facts else { return }
        let floor = state.entityMap.values.filter { $0.components[PlateRoleComponent.self]?.role == .floor }.count
        let moving = CutRackTap.pendingSlots.count + state.platesBeingUnracked.count
        guard HomeHexPortalLogic.capturesLiveFrameOnClose(keyAtOpen: keyAtOpen, keyAtClose: key, floorPlates: floor,
                                                         platesMoving: moving,
                                                         stillCached: RackRoomStillService.shared.hasStill(key)) else { return }
        guard let image = await RackRoomStillService.shared.captureLive(state, sceneSize: zoomScene.size,
                                                                        roomTheme: facts.roomTheme) else { return }
        mark("liveCaptured")
        fullImage = image
        fullShown = true
        // The window's small copy now (the cell lands on it); the files follow in the background.
        let size = zoomScene.size
        guard let rest = await RackRoomStillService.shared.makeRest(image, sceneSize: size) else { return }
        pendingRest = (rest, key, size)
        Task { @MainActor in await RackRoomStillService.shared.write(image, rest: rest, key: key) }
    }

    @ObservationIgnored private var pendingRest: (UIImage, String, CGSize)?

    private func playClose() {
        #if DEBUG
        if scrubMode { return }
        #endif
        let finish: () -> Void = { [weak self] in self?.apply(.closeEnded) }
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.25)) { coverOpacity = 0 } completion: { finish() }
            return
        }
        withAnimation(Self.closeCurve) {
            progress = 0
        } completion: {
            finish()
        }
        withAnimation(.easeOut(duration: 0.3)) {
            veilShown = false
        }
        withAnimation(.easeOut(duration: 0.2)) {
            tubeShown = true
        }
    }

    #if DEBUG
    /// Tests: ends a scrubbed close the way the animation's completion would.
    func finishScrubbedClose() { apply(.closeEnded) }
    /// Tests: ends a scrubbed zoom the way the animation's completion would.
    func finishScrubbedZoom() { apply(.zoomEnded) }
    #endif

    // MARK: Phases

    private func apply(_ event: HomeHexPortalPhase.Event) {
        let before = phase
        phase.handle(event)
        mark("\(event)")
        if event == .zoomEnded, phase.stage == .open, !roomMounted {
            roomMounted = true
            mark("roomMounted")
        }
        #if DEBUG
        if scrubMode {
            if event == .closeEnded, before.stage == .closing { finishClose() }
            return
        }
        #endif
        if before.stillShown != phase.stillShown {
            mark(phase.stillShown ? "stillIn" : "handOff")
            withAnimation(phase.stillShown ? .easeOut(duration: 0.12) : .easeInOut(duration: 0.18)) {
                stillOpacity = phase.stillShown ? 1 : 0
            }
        }
        if before.controlsShown != phase.controlsShown {
            if phase.controlsShown {
                handOffFallback?.cancel()
                // After the still has gone, so the controls arrive on the live room.
                withAnimation(.easeOut(duration: 0.22).delay(before.stillShown ? 0.16 : 0)) {
                    controlsOpacity = 1
                } completion: { [weak self] in
                    guard self?.phase.controlsShown == true else { return }
                    self?.mark("controlsIn")
                    UIAccessibility.post(notification: .screenChanged, argument: nil)
                }
            } else {
                withAnimation(.easeOut(duration: 0.12)) { controlsOpacity = 0 }
            }
        }
        if event == .closeEnded, before.stage == .closing {
            finishClose()
        }
    }

    private func finishClose() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        // UIKit still slides the cover down when it is let go, and the cover's coordinates jump to
        // the slide's end, so a cell it still drew came down from the top onto the window. The
        // window shows the same picture from this frame on: the cover draws nothing on its way out.
        withTransaction(transaction) {
            coverOpacity = 0
            isPresented = false
        }
        handOffFallback?.cancel()
        liveSubscription?.cancel()
        liveSubscription = nil
        liveScene = nil
        fullLoad?.cancel()
        fullLoad = nil
        prewarm = nil
        if let (image, key, size) = pendingRest {
            pendingRest = nil
            restImage = image
            restKey = key
            stillSceneSize = size
        }
        fullImage = nil
        fullShown = false
        veilShown = false
        tubeShown = true
        focusWindowToken += 1
        mark("closed")
    }
}

// MARK: - Prewarm

/// The room's shared assets, loaded from the window's touch-down: the light probe (built once per
/// process) and, with lathe plates, the bar plates' meshes and faces (LatheFaceCache). The rack
/// host's own preload then finds them ready. Per-scene work (legacy materials) is left to it.
enum HomeHexPortalPrewarm {
    @MainActor
    static func run(racked: [EarnedPlate]) async {
        if RackPlateStyle.current == .lathe {
            async let probe: EnvironmentResource? = sharedRackStudioEnvironmentResource()
            await prepareLathePlates(latheFirstFrameRequests(racked))
            _ = await probe
        } else {
            _ = await sharedRackRoomEnvironmentResource()
        }
    }
}

// MARK: - Host

/// The window in the field's cut corner and the cover it opens. Shown only when the flag is on
/// and the field is not a workout in progress (CutTrainHost decides with HomeHexPortalLogic).
struct HomeHexPortalHost: View {
    let coordinator: HomeHexPortalCoordinator
    /// A workout is running or starting: no still is rendered.
    let workoutBusy: Bool

    @Query(filter: #Predicate<EarnedPlate> { $0.isRacked == true && $0.earnedByEvent != "starter" })
    private var rackedPlates: [EarnedPlate]
    @Query(filter: #Predicate<BarbellConfig> { $0.id == "global" })
    private var configs: [BarbellConfig]
    @AppStorage("weight_unit") private var weightUnitRaw: String = WeightUnit.kg.rawValue
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var unit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .kg }

    private var facts: HomeHexStillFacts {
        let config = configs.first
        return HomeHexStillFacts(
            plates: rackedPlates.map {
                HomeHexStillPlate(id: $0.id, tierID: $0.tierID, weightKg: $0.weightKg, engraving: $0.engravingText,
                                  rackPosition: $0.rackPosition, progressionTier: $0.currentTier.rawValue,
                                  liftTypeID: $0.liftTypeID)
            },
            barSkin: config?.barSkinIndex ?? 0,
            rackStyle: config?.effectiveSelectedRackStyleID ?? "matte_black",
            roomTheme: config?.effectiveSelectedRoomThemeID ?? "dark_gym",
            wallText: config?.roomName,
            plateStyle: RackPlateStyle.current.rawValue,
            sceneSize: coordinator.band.size,
            displayScale: displayScale
        )
    }

    var body: some View {
        let facts = facts
        let key = HomeHexPortalLogic.stillKey(facts)
        HomeHexWindowView(
            model: HomeHexPortalWindowModel(isShown: true,
                                            accessibilityValue: HomeHexPortalLogic.accessibilityValue(
                                                loadedKg: rackedPlates.map(\.weightKg), unit: unit)),
            image: coordinator.restImage,
            imageKey: coordinator.restKey,
            sceneSize: coordinator.stillSceneSize,
            isHidden: coordinator.phase.stage != .idle && coordinator.phase.stage != .pressed,
            focusToken: coordinator.focusWindowToken,
            pressChanged: { coordinator.pressChanged($0) },
            open: { coordinator.open(reduceMotion: reduceMotion) }
        )
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { coordinator.latestSourceFrame = $0 }
        .onAppear {
            coordinator.homeVisible = true
            coordinator.resolveBand()
        }
        .onDisappear { coordinator.homeVisible = false }
        .onChange(of: facts, initial: true) { _, new in
            coordinator.facts = new
            coordinator.racked = rackedPlates
        }
        .task(id: key) { await keepStill(key: key, facts: facts) }
        .fullScreenCover(isPresented: Binding(get: { coordinator.isPresented }, set: { coordinator.isPresented = $0 })) {
            HomeHexPortalOverlay(coordinator: coordinator) {
                CutRackHost()
                    .environment(\.cutRackPortal, CutRackPortalHooks(
                        back: { coordinator.close() },
                        sceneFrame: { coordinator.sceneFrameChanged($0) },
                        sceneBuilt: { coordinator.sceneBuilt($0) }
                    ))
            }
            .presentationBackground(.clear)
        }
    }

    /// Shows the cached still for the key, or renders one when Home is idle (HomeHexPortalLogic
    /// .stillAction). A stale still stays on screen until the new one is ready.
    private func keepStill(key: String, facts: HomeHexStillFacts) async {
        guard facts.sceneSize.width > 0 else { return }
        let service = RackRoomStillService.shared
        if service.hasStill(key), let image = await service.loadRest(key) {
            coordinator.setRest(image, key: key, sceneSize: facts.sceneSize)
            return
        }
        // Never on Home's first frames: let the screen settle first.
        try? await Task.sleep(for: .seconds(1.5))
        var failures = 0
        while !Task.isCancelled, failures < 3 {
            let action = HomeHexPortalLogic.stillAction(
                cachedKey: service.hasStill(key) ? key : nil, currentKey: key,
                homeVisible: coordinator.homeVisible, scrolling: coordinator.isScrolling,
                workoutBusy: workoutBusy || coordinator.workoutStarting,
                portalIdle: coordinator.phase.stage == .idle,
                roomDrawnBefore: service.roomHasBeenDrawn)
            switch action {
            case .show:
                if let image = await service.loadRest(key) { coordinator.setRest(image, key: key, sceneSize: facts.sceneSize) }
                return
            case .wait:
                try? await Task.sleep(for: .seconds(1))
            case .render:
                let request = RackRoomStillService.RoomRequest(
                    racked: rackedPlates, barSkin: facts.barSkin, rackStyle: facts.rackStyle,
                    roomTheme: facts.roomTheme, wallText: facts.wallText, sceneSize: facts.sceneSize)
                let image = await service.render(request, key: key) {
                    // Checked again when the render queue reaches it.
                    coordinator.homeVisible && !coordinator.isScrolling && !coordinator.workoutStarting
                        && coordinator.phase.stage == .idle
                }
                if let image {
                    coordinator.setRest(image, key: key, sceneSize: facts.sceneSize)
                    return
                }
                failures += 1
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}
