import Foundation
import RealityKit
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// Fixture-only captures of the Cut rack. The plates are in-memory EarnedPlate values that are
/// never inserted into a SwiftData container; nothing reads the account or calls a service. The
/// scene slot holds the real bar-only BarbellRealityView built from those fixtures.
/// TEST_RUNNER_VOLIA_CAPTURE_RACK=1, TEST_RUNNER_VOLIA_CAPTURE_DIR=<directory>.
/// TEST_RUNNER_VOLIA_CAPTURE_HOLD=<seconds> keeps each window up after writing <name>.ready so an
/// outside screenshot (simctl io screenshot) can record the Metal layer, which drawHierarchy skips.
/// TEST_RUNNER_VOLIA_CAPTURE_STATE=<name>[,<name>...] runs only those fixtures.
/// TEST_RUNNER_VOLIA_CAPTURE_ROOM=<room theme id> builds the rack scene in that room (default dark_gym).
/// Each rack fixture also writes <name>.stats.txt: the scene's entity, model and material slot counts.
@MainActor
@Suite(.serialized)
struct CutRackCaptureTests {
    nonisolated static let names = [
        "rack-default", "rack-ax5", "rack-ax5-bottom", "rack-empty", "rack-full-lb", "rack-owner", "detail", "detail-ax5", "collection", "collection-ax5",
        "scene-legacy", "scene-moment", "scene-welcome", "zoom-stack", "zoom-chrome", "zoom-owner", "rack-mixed", "rack-owner25", "rack-owner-reds", "zoom-left", "zoom-right", "rack-owner-floor", "rack-letters", "rack-rose-floor", "rack-floor-metal"
    ]
    nonisolated static var selectedNames: [String] {
        guard let value = ProcessInfo.processInfo.environment["VOLIA_CAPTURE_STATE"] else { return names }
        let selected = value.split(separator: ",").map(String.init)
        precondition(selected.allSatisfy(names.contains), "Unknown capture fixture")
        return selected
    }
    private var root: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_DIR"] ?? "/private/tmp/volia-cut-rack")
    }
    private var hold: Double { Double(ProcessInfo.processInfo.environment["VOLIA_CAPTURE_HOLD"] ?? "") ?? 0 }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_RACK"] == "1"), arguments: selectedNames)
    func render(_ name: String) async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let previous = scene.windows.first { $0.isKeyWindow }
        previous?.isHidden = true
        let window = UIWindow(windowScene: scene)
        let content = fixture(name.hasPrefix("zoom") ? Self.zoomSource(name) : name).environment(\.dynamicTypeSize, name.contains("-ax5") ? .accessibility5 : .large)
        window.rootViewController = UIHostingController(rootView: Group {
            if name.hasPrefix("rack") || name.hasPrefix("scene") || name.hasPrefix("zoom") { content }
            else { Color.black.sheet(isPresented: .constant(true)) { content } }
        }.preferredColorScheme(.dark))
        window.overrideUserInterfaceStyle = .dark
        window.windowLevel = .alert + 1
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.isHidden = false
            previous?.makeKey()
        }
        try await Task.sleep(for: .seconds(3))
        if name.hasPrefix("zoom") {
            zoomIn(name)
            try await Task.sleep(for: .seconds(1.5))
        }
        if name == "rack-mixed" || name == "rack-owner-floor" || name == "rack-letters" || name == "rack-rose-floor"
            || name == "rack-floor-metal" {
            layMixedFloorPlates(name == "rack-mixed" ? Self.mixedPlates : name == "rack-letters" ? Self.letterPlates
                                : name == "rack-rose-floor" ? Self.roseFloorPlates : name == "rack-floor-metal" ? Self.floorMetalPlates
                                : [Self.ownerRedPlates[1]])
            try await Task.sleep(for: .seconds(1.5))
        }
        if name.hasSuffix("-bottom"), let scroll = verticalScroll(in: window) {
            let bottom = scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height
            scroll.setContentOffset(CGPoint(x: 0, y: max(-scroll.adjustedContentInset.top, bottom)), animated: false)
            try await Task.sleep(for: .seconds(1))
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try #require(image.pngData()).write(to: root.appendingPathComponent(name + ".png"))
        if name.hasPrefix("rack") || name.hasPrefix("scene") || name.hasPrefix("zoom"), let sceneRoot = CutRackFixtureScene.lastSceneState?.sceneRoot {
            try CutRackFixtureScene.stats(sceneRoot).write(to: root.appendingPathComponent(name + ".stats.txt"),
                                                           atomically: true, encoding: .utf8)
        }
        if name.hasPrefix("zoom") {
            // Layout during the snapshot re-frames the bar: move in again for the outside screenshot.
            zoomIn(name)
            try await Task.sleep(for: .seconds(1.5))
        }
        if hold > 0 {
            try Data().write(to: root.appendingPathComponent(name + ".ready"))
            try await Task.sleep(for: .seconds(hold))
        }
    }

    /// A close three-quarter look at the right-hand stack: the camera proxy (the scene root) moves
    /// the room so the stack sits in front of the fixed camera.
    /// The same plates as on the bar, lying flat on the floor in front of it (the way a dropped
    /// plate comes to rest), built exactly as the scene builds them.
    private func layMixedFloorPlates(_ plates: [EarnedPlate]) {
        guard let state = CutRackFixtureScene.lastSceneState else { return }
        for (index, plate) in plates.enumerated() {
            let entity = makePlateEntity(tierID: plate.tierID, weightKg: plate.weightKg, role: .floor,
                                         options: .visualOnly(), plateStyle: state.plateStyle)
            entity.name = "mixed-floor-\(index)"
            let thickness = PlateVisualDesign.profile(for: PlateTier.all.first { $0.id == plate.tierID }!.style).thickness
            entity.orientation = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
            let x = plates.count == 1 ? Float(0.30) : plates.count == 4 ? (Float(index) - 1.5) * 0.42 : Float(index - 1) * 0.50
            entity.position = SIMD3(x, thickness / 2 + 0.003, 0.50)
            entity.components.set(GroundingShadowComponent(castsShadow: true))
            state.sceneRoot.addChild(entity)
        }
    }

    private func zoomIn(_ name: String) {
        guard let root = CutRackFixtureScene.lastSceneState?.sceneRoot else { return }
        // zoom-left and zoom-right: straight in front of each sleeve, unturned, so the two stacks are
        // seen as mirror images.
        let sleeve: Float? = name == "zoom-left" ? -0.68 : name == "zoom-right" ? 0.68 : nil
        let target = SIMD3<Float>(sleeve ?? (name == "zoom-stack" ? 0.70 : 0.62), 0.60, 0.12)
        let turn = sleeve != nil ? simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
            : simd_quatf(angle: -0.62, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: 0.12, axis: SIMD3(1, 0, 0))
        // Put the stack where the bar's centre was framed, turned, then bring it toward the camera.
        let barCentre = SIMD3<Float>(0, 0.60, 0.12)
        let framed = CutRackFixtureScene.framedRootPosition ?? root.position
        CutRackFixtureScene.framedRootPosition = framed
        let forward = Float(Double(ProcessInfo.processInfo.environment["VOLIA_CAPTURE_ZOOM"] ?? "") ?? (name == "zoom-stack" ? 0.55 : 0.75))
        root.orientation = turn
        root.position = framed + barCentre - turn.act(target) + SIMD3(0, 0, forward)
    }

    private func verticalScroll(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView, scroll.contentSize.height > scroll.bounds.height + 1,
           scroll.bounds.height > 120 { return scroll }
        for child in view.subviews { if let found = verticalScroll(in: child) { return found } }
        return nil
    }

    // MARK: Fixtures

    private static let day = Date(timeIntervalSince1970: 1_790_000_000)

    private static func plate(_ id: String, tier: Int, kg: Double, slot: Int? = nil, engraving: String = "",
                              order: Int) -> EarnedPlate {
        let plate = EarnedPlate(id: "fixture-\(id)", tierID: tier, weightKg: kg, engravingText: engraving,
                                earnedAt: day.addingTimeInterval(Double(order) * 86_400), earnedByEvent: "fixture",
                                isRacked: slot != nil, rackPosition: slot, liftTypeID: nil, currentTier: .steel,
                                workoutsUsedCount: 14, prCount: 2)
        plate.displayOrder = order
        return plate
    }

    private static let plates: [EarnedPlate] = [
        plate("lime", tier: 22, kg: 20, slot: 0, order: 8),
        plate("blue", tier: 15, kg: 20, slot: 1, order: 7),
        plate("chrome", tier: 26, kg: 35, slot: 2, engraving: "Bench 100", order: 6),
        plate("circuit", tier: 25, kg: 20, order: 5),
        plate("red", tier: 14, kg: 20, order: 4),
        plate("gold", tier: 6, kg: 45, order: 3),
        plate("black", tier: 2, kg: 5, order: 2),
        plate("comp", tier: 4, kg: 2.5, order: 1)
    ]

    /// The owner's own bar when the lighting looked worst on the phone: a grey cast iron 25 kg
    /// inside a bronze-looking raw iron 15 kg, on the lime VOLIA bar.
    private static let ownerPlates: [EarnedPlate] = [
        plate("castiron", tier: 1, kg: 25, slot: 0, order: 2),
        plate("rawiron", tier: 0, kg: 15, slot: 1, order: 1)
    ]

    /// The zoom fixtures reuse a rack fixture's plates and then move the camera in.
    private static func zoomSource(_ name: String) -> String {
        switch name {
        case "zoom-stack": return "rack-full-lb"
        case "zoom-owner": return "rack-owner"
        case "zoom-left", "zoom-right": return "rack-owner-reds"
        default: return "rack-chrome"
        }
    }

    /// Owner's report: a red 20 kg and a magenta 25 kg bumper look fine on the floor, "super lit up"
    /// on the bar. Plus a gold plate for the metal.
    static let mixedPlates: [EarnedPlate] = [
        plate("red", tier: 14, kg: 20, slot: 0, order: 3),
        plate("pink", tier: 18, kg: 25, slot: 1, order: 2),
        plate("gold", tier: 6, kg: 20, slot: 2, order: 1)
    ]

    /// The owner's 25 kg plate (earned at 75 workouts: tier 8, its thumbnail deep magenta) inside a
    /// red 20 kg bumper, and the same plate with three red bumpers.
    static let owner25Plates: [EarnedPlate] = [
        plate("rose", tier: 8, kg: 25, slot: 0, engraving: "75 Workouts", order: 2),
        plate("red1", tier: 14, kg: 20, slot: 1, order: 1)
    ]
    static let ownerRedPlates: [EarnedPlate] = [
        plate("rose", tier: 8, kg: 25, slot: 0, engraving: "75 Workouts", order: 4),
        plate("red1", tier: 14, kg: 20, slot: 1, order: 3),
        plate("red2", tier: 14, kg: 20, slot: 2, order: 2),
        plate("red3", tier: 14, kg: 20, slot: 3, order: 1)
    ]

    /// One of each lettering finish, on the bar and on the floor: a red bumper, the Rose Gold
    /// tinted metal, gold, and cast iron.
    static let letterPlates: [EarnedPlate] = [
        plate("castiron", tier: 1, kg: 25, slot: 0, order: 4),
        plate("gold", tier: 6, kg: 20, slot: 1, order: 3),
        plate("rose", tier: 8, kg: 25, slot: 2, engraving: "75 Workouts", order: 2),
        plate("red1", tier: 14, kg: 20, slot: 3, order: 1)
    ]

    /// The owner's screen: an empty bar and the Rose Gold 25 kg lying on the floor.
    static let roseFloorPlates: [EarnedPlate] = [plate("rose", tier: 8, kg: 25, engraving: "75 Workouts", order: 1)]
    /// Reflection check: chrome and gold lying flat on the floor, facing the ceiling and the wall.
    static let floorMetalPlates: [EarnedPlate] = [
        plate("steel", tier: 5, kg: 25, order: 2),
        plate("gold", tier: 6, kg: 20, order: 1)
    ]

    private static let chromePlates: [EarnedPlate] = [
        plate("steel", tier: 5, kg: 25, slot: 0, engraving: "Bench 100", order: 1)
    ]

    private static let fullPlates: [EarnedPlate] = [
        plate("lime", tier: 22, kg: 20, slot: 0, order: 8),
        plate("blue", tier: 15, kg: 20, slot: 1, order: 7),
        plate("chrome", tier: 26, kg: 35, slot: 2, order: 6),
        plate("gold", tier: 6, kg: 45, slot: 3, order: 5),
        plate("red", tier: 14, kg: 20, order: 4)
    ]

    private func fixture(_ name: String) -> AnyView {
        if name.hasPrefix("scene") { return AnyView(SharedSceneFixture(name: name, plates: Self.plates)) }
        let locale = Locale(identifier: "en_US")
        let unit: WeightUnit = name.hasSuffix("-lb") ? .lb : .kg
        let source: [EarnedPlate] = name == "rack-empty" ? [] : name == "rack-full-lb" ? Self.fullPlates
            : name == "rack-owner" ? Self.ownerPlates : name == "rack-chrome" ? Self.chromePlates
            : name == "rack-mixed" ? Self.mixedPlates : name == "rack-owner25" ? Self.owner25Plates
            : name == "rack-owner-reds" || name == "rack-owner-floor" ? Self.ownerRedPlates
            : name == "rack-letters" ? Self.letterPlates : name == "rack-rose-floor" ? Self.roseFloorPlates
            : name == "rack-floor-metal" ? Self.floorMetalPlates : Self.plates
        let facts = source.map(CutRackPlateFacts.init)
        let thumbnail: (String) -> AnyView = { id in
            guard let plate = source.first(where: { $0.id == id }) else { return AnyView(EmptyView()) }
            return AnyView(PlateFaceView(tierID: plate.tierID, progressionTier: plate.currentTier,
                                         liftTypeID: plate.liftTypeID, weightKg: plate.weightKg))
        }
        if name.hasPrefix("rack") {
            let model = CutRackLogic.model(CutRackFacts(
                plates: facts,
                occupiedSlots: facts.filter(\.isLoaded).count,
                unit: unit,
                notice: name == "rack-full-lb" ? .barFull : nil
            ), locale: locale)
            // rack-empty passes an old starter row still racked at slot 3: the scene must not show it.
            let racked = name == "rack-empty" ? [EarnedPlate.makeStarter(position: 3)] : source.filter(\.isRacked)
            return AnyView(CutRackView(
                model: model,
                actions: CutRackActions(back: {}, edit: {}, showAll: {}, toggle: { _ in }, details: { _ in }),
                scene: { CutRackFixtureScene(racked: racked, barSkinID: name == "rack-owner" ? 4 : 0) },
                thumbnail: thumbnail
            ))
        }
        if name.hasPrefix("detail") {
            let plate = Self.plates[2]
            let model = CutRackPlateDetailLogic.model(CutRackPlateDetailFacts(
                plate: CutRackPlateFacts(plate), source: "Push Day", progressionTier: "Steel",
                workoutsUsed: plate.workoutsUsedCount, prCount: plate.prCount, barIsFull: false, unit: .kg
            ), locale: locale)
            return AnyView(CutRackPlateDetailView(model: model, toggle: {}, close: {}) { thumbnail(plate.id) })
        }
        return AnyView(CutRackCollectionView(
            model: CutRackCollectionLogic.model(plates: facts, unit: .kg, locale: locale),
            open: { _ in }, close: {}, thumbnail: thumbnail
        ))
    }
}

/// The other callers of the same scene: the legacy wall-storage rack, the finish screen moment
/// (no storage, earned plates hanging above the floor) and the welcome spin.
private struct SharedSceneFixture: View {
    let name: String
    let plates: [EarnedPlate]
    @State private var sceneState: SceneState = {
        let state = SceneState()
        for tierID in PlateTier.all.map(\.id) where tierID != 7 {
            state.plateTextureCache[tierID] = loadPlateTextures(forTierID: tierID)
            state.materialCache[tierID] = buildMaterial(forTierID: tierID, textures: state.plateTextureCache[tierID], inRackRoom: true)
        }
        return state
    }()

    var body: some View {
        Group {
            switch name {
            case "scene-welcome":
                VStack {
                    Spacer()
                    BarbellRealityView(
                        mode: .welcome(plates: plates.prefix(3).map {
                            EarnedPlateInfo(tierID: $0.tierID, weightKg: $0.weightKg, engravingText: "", earnedByEvent: "fixture")
                        }),
                        sceneState: sceneState
                    )
                    .frame(height: 300)
                    .padding(.horizontal, 8)
                    Spacer()
                }
                .background(Color.black)
            default:
                BarbellRealityView(
                    mode: .rackRoom(rackedPlates: plates.filter(\.isRacked),
                                    floorPlates: name == "scene-moment" ? Array(plates.filter { !$0.isRacked }.prefix(2))
                                                                         : plates.filter { !$0.isRacked },
                                    onRack: { _ in }, onUnrack: { _ in }),
                    sceneState: sceneState,
                    roomThemeID: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_ROOM"] ?? "dark_gym",
                    allowsInteraction: false,
                    showsStorage: name == "scene-legacy"
                )
            }
        }
        .onAppear { CutRackFixtureScene.lastSceneState = sceneState }
    }
}

/// The real bar-only scene, built from fixture plates with the legacy preload done up front.
private struct CutRackFixtureScene: View {
    let racked: [EarnedPlate]
    var barSkinID = 0
    @MainActor static var lastSceneState: SceneState? {
        didSet { framedRootPosition = nil }
    }
    /// The bar-only framing before a zoom fixture moved the camera in.
    @MainActor static var framedRootPosition: SIMD3<Float>?
    @State private var sceneState: SceneState = {
        let state = SceneState()
        for tierID in PlateTier.all.map(\.id) where tierID != 7 {
            state.plateTextureCache[tierID] = loadPlateTextures(forTierID: tierID)
            state.materialCache[tierID] = buildMaterial(forTierID: tierID, textures: state.plateTextureCache[tierID], inRackRoom: true)
        }
        return state
    }()

    var body: some View {
        BarbellRealityView(
            mode: .rackRoom(rackedPlates: racked, floorPlates: [], onRack: { _ in }, onUnrack: { _ in }),
            sceneState: sceneState,
            barSkinID: barSkinID,
            roomThemeID: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_ROOM"] ?? "dark_gym",
            allowsInteraction: false,
            barOnly: true
        )
        .onAppear { Self.lastSceneState = sceneState }
    }

    /// Enabled entities, model entities, material slots (about one draw each), lights, and which
    /// parts carry a grounding shadow or receive the image based light.
    @MainActor static func stats(_ root: Entity) -> String {
        var entities = 0, models = 0, slots = 0, points = 0, spots = 0, directional = 0, grounding = 0
        var shadowedLights = 0, iblReceivers = 0, iblSources = 0
        func visit(_ entity: Entity) {
            guard entity.isEnabled else { return }
            entities += 1
            if let model = entity.components[ModelComponent.self] {
                models += 1
                slots += model.materials.count
            }
            if entity.components[PointLightComponent.self] != nil { points += 1 }
            if entity.components[SpotLightComponent.self] != nil { spots += 1 }
            if entity.components[DirectionalLightComponent.self] != nil { directional += 1 }
            if entity.components[SpotLightComponent.Shadow.self] != nil
                || entity.components[DirectionalLightComponent.Shadow.self] != nil { shadowedLights += 1 }
            if entity.components[GroundingShadowComponent.self]?.castsShadow == true { grounding += 1 }
            if entity.components[ImageBasedLightReceiverComponent.self] != nil { iblReceivers += 1 }
            if entity.components[ImageBasedLightComponent.self] != nil { iblSources += 1 }
            entity.children.forEach(visit)
        }
        visit(root)
        return """
        entities=\(entities) models=\(models) materialSlots=\(slots)
        pointLights=\(points) spotLights=\(spots) directionalLights=\(directional) shadowedLights=\(shadowedLights)
        groundingShadowCasters=\(grounding) iblSources=\(iblSources) iblReceivers=\(iblReceivers)

        """
    }
}
