import Combine
import Darwin
import Foundation
import QuartzCore
import RealityKit
import SwiftUI
import Testing
import UIKit
import UserNotifications
@testable import WRKT

/// The rain's pure rules: caps, spread, feedback rate limit. No scene.
@Suite struct RackPlateRainRuleTests {
    @Test func legacyPlatesGetALowerCapThanLathePlates() {
        let lathe = RackPlateRain.limits(for: .lathe), legacy = RackPlateRain.limits(for: .legacy)
        #expect(legacy.plates < lathe.plates)
        #expect(legacy.looks <= lathe.looks)
        #expect(lathe.plates > 0 && legacy.plates > 0)
    }

    @Test func plateSpawnInsideTheVisibleFloorInFrontOfTheBar() {
        for index in 0..<200 {
            for gentle in [false, true] {
                let pose = RackPlateRain.pose(index: index, gentle: gentle)
                #expect(abs(pose.position.x) <= RackPlatePlay.frameMaxAbsX)
                #expect(pose.position.z >= 0.25 && pose.position.z <= RackPlatePlay.frameMaxZ)
                // Below the room's recovery ceiling, so nothing is clamped as it spawns.
                #expect(pose.position.y > 0 && pose.position.y < 1.80)
                if gentle {
                    #expect(pose.linearVelocity == .zero && pose.angularVelocity == .zero)
                }
            }
        }
    }

    @Test func spawnsSpreadAcrossTheWidth() {
        let xs = (0..<10).map { RackPlateRain.pose(index: $0, gentle: false).position.x }
        #expect(xs.filter { $0 < 0 }.count >= 3 && xs.filter { $0 > 0 }.count >= 3)
        // Consecutive plates never fall in the same place.
        for i in 1..<10 { #expect(abs(xs[i] - xs[i - 1]) > 0.1) }
    }

    @Test func aStreamOfLandingsIsRateLimited() {
        var limiter = RackPlateRain.FeedbackLimiter()
        // 90 plates landing 70 ms apart.
        let results = (0..<90).map { limiter.admit(at: Double($0) * 0.07 + 0.5) }
        let sounds = results.filter(\.sound).count
        let haptics = results.filter(\.haptic).count
        #expect(results[0].sound && results[0].haptic)
        #expect(sounds <= 45 && sounds >= 20)
        #expect(haptics == RackPlateRain.FeedbackLimiter.maxHaptics)
        #expect(!results[1].sound)
    }

    @Test func fallTimeGrowsWithHeight() {
        #expect(RackPlateRain.fallTime(fromY: 1.7) > RackPlateRain.fallTime(fromY: 0.5))
        #expect(RackPlateRain.fallTime(fromY: 1.7) < 0.8)
    }
}

/// Drop all in the real bar-only rack scene with real physics. Fixture plates only (never inserted
/// into a store, nothing saved).
/// TEST_RUNNER_VOLIA_RACK_RAIN=1 runs the checks: plates share meshes and materials, stay inside
/// the room, go to sleep, and tidying up removes exactly the rained plates and nothing on the bar.
/// TEST_RUNNER_VOLIA_RACK_RAIN_MEASURE=30,60,90 also measures frame time, main-thread stalls,
/// memory and settle time per count, with every distinct face (TEST_RUNNER_VOLIA_RACK_RAIN_LOOKS
/// caps the looks); TEST_RUNNER_VOLIA_CAPTURE_DIR receives rain-<style>.txt.
/// TEST_RUNNER_VOLIA_RACK_RAIN_CAPTURE=1 shows the whole rack view and writes rain-mid and
/// rain-settled .ready files (with TEST_RUNNER_VOLIA_CAPTURE_HOLD) for simctl screenshots.
/// TEST_RUNNER_VOLIA_RACK_PLATES=legacy|lathe picks the plate style.
@MainActor
@Suite(.serialized)
struct CutRackRainHarnessTests {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    private var root: URL { URL(fileURLWithPath: env["VOLIA_CAPTURE_DIR"] ?? "/private/tmp/volia-rack-rain") }
    private var hold: Double { Double(env["VOLIA_CAPTURE_HOLD"] ?? "") ?? 0 }

    /// The realistic inventory's plates, none loaded, as unsaved values: 90 plates, 35 looks.
    static func inventory(racked: [Int] = []) -> [EarnedPlate] {
        var made: [EarnedPlate] = []
        let day = Date(timeIntervalSince1970: 1_780_000_000)
        for spec in CutRackRealisticInventory.specs {
            for _ in 0..<spec.count {
                let index = made.count
                let slot = racked.firstIndex(of: index)
                made.append(EarnedPlate(id: "rain-\(index)", tierID: spec.tier, weightKg: spec.kg, engravingText: spec.engraving,
                                        earnedAt: day.addingTimeInterval(Double(index) * 86_400), earnedByEvent: "fixture-\(index)",
                                        isRacked: slot != nil, rackPosition: slot, liftTypeID: spec.lift,
                                        currentTier: spec.progression))
            }
        }
        return made
    }

    static func order(_ plates: [EarnedPlate], cap: Int, looks: Int) -> [EarnedPlate] {
        let ids = CutRackRainLogic.selection(plates.map(CutRackPlateFacts.init), cap: cap, maxLooks: looks)
        return ids.compactMap { id in plates.first { $0.id == id } }
    }

    // MARK: Behaviour

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_RACK_RAIN"] == "1"))
    func rainSharesStaysInSleepsAndTidiesAway() async throws {
        let plates = Self.inventory(racked: [0, 1])
        let racked = plates.filter(\.isRacked)
        let state = SceneState()
        let limits = RackPlateRain.limits(for: state.plateStyle)
        let window = try await Self.showScene(state: state, racked: racked, floor: plates.filter { !$0.isRacked })
        defer { Self.close(window) }

        let chosen = Self.order(plates, cap: limits.plates, looks: limits.looks)
        #expect(chosen.count == limits.plates)
        #expect(Set(chosen.map { CutRackLogic.look(CutRackPlateFacts($0)) }).count <= limits.looks)
        let barBefore = state.entityMap.filter { $0.value.components[PlateRoleComponent.self]?.role == .bar }.keys.sorted()

        let dropped = await state.rainPlates(chosen + racked, gentle: false)
        #expect(dropped == chosen.count, "loaded plates are never rained")
        #expect(state.rainedPlateIDs.count == chosen.count)

        // Identical plates share their mesh and every material.
        let rained = state.rainedPlateIDs.compactMap { state.entityMap[$0] }
        var byLook: [CutRackPlateLook: [ModelEntity]] = [:]
        for entity in rained {
            guard let plate = plates.first(where: { $0.id == entity.name }) else { continue }
            if let model = entity as? ModelEntity { byLook[CutRackLogic.look(CutRackPlateFacts(plate)), default: []].append(model) }
        }
        for (_, copies) in byLook where copies.count > 1 {
            let first = try #require(copies[0].model)
            for copy in copies.dropFirst() {
                let model = try #require(copy.model)
                #expect(model.mesh === first.mesh, "copies share one mesh")
                if state.plateStyle == .lathe {
                    #expect(model.materials.count == first.materials.count)
                    for (a, b) in zip(model.materials, first.materials) {
                        #expect((a as? PhysicallyBasedMaterial)?.baseColor.texture?.resource
                                === (b as? PhysicallyBasedMaterial)?.baseColor.texture?.resource,
                                "copies share face textures")
                    }
                }
            }
        }

        let settle = try await Self.waitForSleep(state, ids: state.rainedPlateIDs, timeout: 20)
        #expect(settle != nil, "the pile went to sleep")
        let rest = Self.restReport(state, ids: state.rainedPlateIDs)
        #expect(rest.outOfRoom == 0, "\(rest)")
        #expect(rest.outOfFrame <= 1, "\(rest)")
        // A few plates may lean on the pile; most lie on the floor, below the bar.
        #expect(rest.aboveBarHeight <= limits.plates / 4, "\(rest)")
        #expect(rest.minY > -0.03, "\(rest)")
        // The bar and its plates did not move.
        let barAfter = state.entityMap.filter { $0.value.components[PlateRoleComponent.self]?.role == .bar }.keys.sorted()
        #expect(barAfter == barBefore, "bar \(barBefore) -> \(barAfter)")
        #expect(state.floorSettles.isEmpty)

        let removed = state.tidyRainedPlates()
        #expect(removed == chosen.count)
        #expect(state.rainedPlateIDs.isEmpty)
        #expect(state.loosePlateIDs.isDisjoint(with: Set(chosen.map(\.id))))
        #expect(chosen.allSatisfy { state.entityMap[$0.id] == nil })
        #expect(state.entityMap.filter { $0.value.components[PlateRoleComponent.self]?.role == .bar }.keys.sorted() == barBefore)
        // Fixture plates are values only: nothing saved, nothing racked.
        #expect(plates.filter(\.isRacked).map(\.id) == racked.map(\.id))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_RACK_RAIN"] == "1"))
    func tidyingUpMidRainStopsTheStream() async throws {
        let plates = Self.inventory()
        let state = SceneState()
        let window = try await Self.showScene(state: state, racked: [], floor: plates)
        defer { Self.close(window) }
        let task = Task { @MainActor in await state.rainPlates(Array(plates.prefix(30)), gentle: false) }
        try await Task.sleep(for: .milliseconds(500))
        task.cancel()
        let dropped = await task.value
        #expect(dropped > 0 && dropped < 30)
        #expect(state.tidyRainedPlates() == dropped)
        #expect(state.rainedPlateIDs.isEmpty)
        // Gentle placement (Reduce Motion) lands too, and sleeps.
        let gentle = await state.rainPlates(Array(plates.prefix(12)), gentle: true)
        #expect(gentle == 12)
        #expect(try await Self.waitForSleep(state, ids: state.rainedPlateIDs, timeout: 15) != nil)
        #expect(Self.restReport(state, ids: state.rainedPlateIDs).outOfRoom == 0)
        state.tidyRainedPlates()
    }

    // MARK: Measurement

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_RACK_RAIN_MEASURE"] != nil))
    func measure() async throws {
        let counts = (env["VOLIA_RACK_RAIN_MEASURE"] ?? "30,60,90").split(separator: ",").compactMap { Int($0) }
        let looks = Int(env["VOLIA_RACK_RAIN_LOOKS"] ?? "") ?? 1000
        let plates = Self.inventory()
        var report = "style=\(RackPlateStyle.current.rawValue) looks<=\(looks)\n"
        for count in counts {
            let state = SceneState()
            let window = try await Self.showScene(state: state, racked: [], floor: plates)
            let chosen = Self.order(plates, cap: count, looks: looks)
            let faces = Set(chosen.map { CutRackLogic.look(CutRackPlateFacts($0)) }).count
            let memBefore = Self.footprintMB()
            var deltas: [Double] = []
            let subscription = state.sceneRoot.scene?.subscribe(to: SceneEvents.Update.self) { event in
                deltas.append(event.deltaTime)
            }
            let stalls = MainThreadStallMonitor()
            stalls.start()
            let start = CACurrentMediaTime()
            let dropped = await state.rainPlates(chosen, gentle: false)
            let spawnEnd = CACurrentMediaTime() - start
            let settled = try await Self.waitForSleep(state, ids: state.rainedPlateIDs, timeout: 25)
            let settledAt = settled.map { $0 - start }
            try await Task.sleep(for: .seconds(1))
            stalls.stop()
            subscription?.cancel()
            let memAfter = Self.footprintMB()
            let rest = Self.restReport(state, ids: state.rainedPlateIDs)
            var entities = 0
            func visit(_ e: Entity) { entities += 1; e.children.forEach(visit) }
            visit(state.sceneRoot)
            let sorted = deltas.sorted()
            func pct(_ p: Double) -> Double { sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))] * 1000 }
            report += String(format: "\n[%d plates, %d faces] dropped=%d spawn=%.2fs asleep=%@ frames=%d p50=%.1fms p95=%.1fms max=%.1fms over33=%d longestMainStall=%.1fms stallsOver50=%d memory %.0f->%.0f MB (+%.0f) entities=%d\n  rest: %@\n",
                             count, faces, dropped, spawnEnd, settledAt.map { String(format: "%.1fs", $0) } ?? "never",
                             sorted.count, pct(0.5), pct(0.95), (sorted.last ?? 0) * 1000, sorted.filter { $0 > 0.034 }.count,
                             stalls.longest * 1000, stalls.gaps.filter { $0.length > 0.05 }.count,
                             memBefore, memAfter, memAfter - memBefore, entities, rest.description)
            state.tidyRainedPlates()
            Self.close(window)
            try await Task.sleep(for: .seconds(1))
        }
        print(report)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try report.write(to: root.appendingPathComponent("rain-\(RackPlateStyle.current.rawValue)-\(looks).txt"), atomically: true, encoding: .utf8)
    }

    // MARK: Capture

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_RACK_RAIN_CAPTURE"] == "1"))
    func captureRain() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.provisional])
        let plates = Self.inventory(racked: [0, 1, 2])
        let state = SceneState()
        let facts = plates.map(CutRackPlateFacts.init)
        let model = CutRackLogic.model(CutRackFacts(plates: facts, occupiedSlots: 3, unit: .kg, notice: nil, playPhase: .loose),
                                       locale: Locale(identifier: "en_US"))
        let view = CutRackView(
            model: model,
            actions: CutRackActions(back: {}, edit: {}, showAll: {}, toggle: { _ in }, details: { _ in }),
            scene: {
                BarbellRealityView(mode: .rackRoom(rackedPlates: plates.filter(\.isRacked), floorPlates: plates.filter { !$0.isRacked },
                                                   onRack: { _ in }, onUnrack: { _ in }),
                                   sceneState: state, barOnly: true)
            },
            thumbnail: { id in
                if let plate = plates.first(where: { $0.id == id }) {
                    PlateFaceView(tierID: plate.tierID, progressionTier: plate.currentTier, liftTypeID: plate.liftTypeID, weightKg: plate.weightKg)
                }
            }
        )
        let window = Self.window(AnyView(view))
        defer { Self.close(window) }
        try await Task.sleep(for: .seconds(Double(env["VOLIA_CAPTURE_WAIT"] ?? "") ?? 12))
        let limits = RackPlateRain.limits(for: state.plateStyle)
        let chosen = Self.order(plates, cap: limits.plates, looks: limits.looks)
        let rain = Task { @MainActor in await state.rainPlates(chosen, gentle: false) }
        try await Task.sleep(for: .seconds(1.6))
        if hold > 0 {
            // The stream mid-fall: pause physics updates are not possible from here, so the
            // screenshot is taken as soon as possible after the marker.
            try Data().write(to: root.appendingPathComponent("rain-\(state.plateStyle.rawValue)-mid.ready"))
            try await Task.sleep(for: .seconds(hold))
        }
        _ = await rain.value
        _ = try await Self.waitForSleep(state, ids: state.rainedPlateIDs, timeout: 20)
        if hold > 0 {
            try Data().write(to: root.appendingPathComponent("rain-\(state.plateStyle.rawValue)-settled.ready"))
            try await Task.sleep(for: .seconds(hold))
        }
    }

    // MARK: Helpers

    struct Rest: CustomStringConvertible {
        var outOfRoom = 0
        var outOfFrame = 0
        var minY: Float = .greatestFiniteMagnitude
        var maxY: Float = -.greatestFiniteMagnitude
        var aboveBarHeight = 0
        var description: String {
            String(format: "outOfRoom=%d outOfFrame=%d y=[%.3f, %.3f] restingAbove0.45=%d", outOfRoom, outOfFrame, minY, maxY, aboveBarHeight)
        }
    }

    static func restReport(_ state: SceneState, ids: [String]) -> Rest {
        var rest = Rest()
        for id in ids {
            guard let entity = state.entityMap[id], entity.components[PlateRoleComponent.self]?.role == .floor else { continue }
            let p = entity.position(relativeTo: state.sceneRoot)
            if abs(p.x) > 0.85 || p.z > 1.15 || p.z < -0.15 || p.y < -0.05 || p.y > 1.95 { rest.outOfRoom += 1 }
            if abs(p.x) > RackPlatePlay.frameMaxAbsX + 0.06 || p.z > RackPlatePlay.frameMaxZ + 0.06 { rest.outOfFrame += 1 }
            rest.minY = min(rest.minY, p.y)
            rest.maxY = max(rest.maxY, p.y)
            if p.y > 0.45 { rest.aboveBarHeight += 1 }
        }
        return rest
    }

    /// When every one of `ids` lying on the floor is asleep (kinematic), or nil after the timeout.
    static func waitForSleep(_ state: SceneState, ids: [String], timeout: Double) async throws -> CFTimeInterval? {
        let start = CACurrentMediaTime()
        while CACurrentMediaTime() - start < timeout {
            let awake = ids.contains { id in
                guard let entity = state.entityMap[id], entity.components[PlateRoleComponent.self]?.role == .floor else { return false }
                return entity.components[PhysicsBodyComponent.self]?.mode == .dynamic
            }
            if !awake { return CACurrentMediaTime() }
            try await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    /// The bar-only scene in a band the shape of the new rack screen's (402 x 500 points).
    static func showScene(state: SceneState, racked: [EarnedPlate], floor: [EarnedPlate]) async throws -> UIWindow {
        if state.plateStyle == .legacy {
            for tierID in Set(racked.map(\.tierID)) {
                state.plateTextureCache[tierID] = loadPlateTextures(forTierID: tierID)
                state.materialCache[tierID] = buildMaterial(forTierID: tierID, textures: state.plateTextureCache[tierID], inRackRoom: true)
            }
        }
        let window = Self.window(AnyView(VStack(spacing: 0) {
            Color.black.frame(height: 150)
            BarbellRealityView(mode: .rackRoom(rackedPlates: racked, floorPlates: floor, onRack: { _ in }, onUnrack: { _ in }),
                               sceneState: state, barOnly: true)
                .frame(height: 500)
            Spacer()
        }.background(Color.black)))
        try await Task.sleep(for: .seconds(6))
        return window
    }

    static func window(_ view: AnyView) -> UIWindow {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first!
        scene.windows.first { $0.isKeyWindow }?.isHidden = true
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: view.preferredColorScheme(.dark))
        window.overrideUserInterfaceStyle = .dark
        window.windowLevel = .alert + 1
        window.makeKeyAndVisible()
        return window
    }

    static func close(_ window: UIWindow) {
        window.isHidden = true
        window.rootViewController = nil
    }
}
