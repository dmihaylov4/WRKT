import Foundation
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
@MainActor
@Suite(.serialized)
struct CutRackCaptureTests {
    nonisolated static let names = [
        "rack-default", "rack-ax5", "rack-ax5-bottom", "rack-empty", "rack-full-lb", "detail", "detail-ax5", "collection", "collection-ax5"
    ]
    nonisolated static var selectedNames: [String] {
        guard let name = ProcessInfo.processInfo.environment["VOLIA_CAPTURE_STATE"] else { return names }
        precondition(names.contains(name), "Unknown capture fixture")
        return [name]
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
        let content = fixture(name).environment(\.dynamicTypeSize, name.contains("-ax5") ? .accessibility5 : .large)
        window.rootViewController = UIHostingController(rootView: Group {
            if name.hasPrefix("rack") { content }
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
        if hold > 0 {
            try Data().write(to: root.appendingPathComponent(name + ".ready"))
            try await Task.sleep(for: .seconds(hold))
        }
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

    private static let fullPlates: [EarnedPlate] = [
        plate("lime", tier: 22, kg: 20, slot: 0, order: 8),
        plate("blue", tier: 15, kg: 20, slot: 1, order: 7),
        plate("chrome", tier: 26, kg: 35, slot: 2, order: 6),
        plate("gold", tier: 6, kg: 45, slot: 3, order: 5),
        plate("red", tier: 14, kg: 20, order: 4)
    ]

    private func fixture(_ name: String) -> AnyView {
        let locale = Locale(identifier: "en_US")
        let unit: WeightUnit = name.hasSuffix("-lb") ? .lb : .kg
        let source: [EarnedPlate] = name == "rack-empty" ? [] : name == "rack-full-lb" ? Self.fullPlates : Self.plates
        let facts = source.map(CutRackPlateFacts.init)
        let thumbnail: (String) -> AnyView = { id in
            guard let plate = source.first(where: { $0.id == id }) else { return AnyView(EmptyView()) }
            return AnyView(PlateFaceView(tierID: plate.tierID, progressionTier: plate.currentTier,
                                         liftTypeID: plate.liftTypeID, weightKg: plate.weightKg))
        }
        if name.hasPrefix("rack") {
            let model = CutRackLogic.model(CutRackFacts(
                plates: facts,
                occupiedSlots: name == "rack-empty" ? 1 : facts.filter(\.isLoaded).count,
                unit: unit,
                notice: name == "rack-full-lb" ? .barFull : nil
            ), locale: locale)
            let racked = name == "rack-empty" ? [EarnedPlate.makeStarter(position: 3)] : source.filter(\.isRacked)
            return AnyView(CutRackView(
                model: model,
                actions: CutRackActions(back: {}, edit: {}, showAll: {}, toggle: { _ in }, details: { _ in }),
                scene: { CutRackFixtureScene(racked: racked) },
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

/// The real bar-only scene, built from fixture plates with the legacy preload done up front.
private struct CutRackFixtureScene: View {
    let racked: [EarnedPlate]
    @State private var sceneState: SceneState = {
        let state = SceneState()
        for tierID in PlateTier.all.map(\.id) where tierID != 7 {
            state.plateTextureCache[tierID] = loadPlateTextures(forTierID: tierID)
            state.materialCache[tierID] = buildMaterial(forTierID: tierID, textures: state.plateTextureCache[tierID])
        }
        return state
    }()

    var body: some View {
        BarbellRealityView(
            mode: .rackRoom(rackedPlates: racked, floorPlates: [], onRack: { _ in }, onUnrack: { _ in }),
            sceneState: sceneState,
            allowsInteraction: false,
            barOnly: true
        )
    }
}
