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

    @Test func barOnlyFramingIsUnchangedUpToTheCalibratedShapeAndCloserOnTallBands() {
        // At and below 0.81 the original calibration holds.
        for aspect: Float in [0.5, 0.75, 0.81] {
            #expect(abs(barbellBarOnlyCameraPosition(aspect: aspect).z - (1.79 - 1.75 * aspect)) < 0.0001)
        }
        // Taller bands still move the camera back, but less, so the bar keeps its width.
        let tall = barbellBarOnlyCameraPosition(aspect: 1.2).z
        #expect(tall > 1.79 - 1.75 * 1.2)
        #expect(tall < barbellBarOnlyCameraPosition(aspect: 1.0).z)
        #expect(barbellBarOnlyCameraPosition(aspect: .nan) == barbellBarOnlyCameraPosition(aspect: 0.75))
    }

    @Test func fallTimeGrowsWithHeight() {
        #expect(RackPlateRain.fallTime(fromY: 1.7) > RackPlateRain.fallTime(fromY: 0.5))
        #expect(RackPlateRain.fallTime(fromY: 1.7) < 0.8)
    }

    // MARK: Settling

    @Test func tiltIsMeasuredFromLyingFlatOnEitherFace() {
        #expect(RackPlatePlay.tiltDegrees(simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))) < 0.01)
        #expect(abs(RackPlatePlay.tiltDegrees(simd_quatf(angle: .pi, axis: SIMD3(1, 0, 0)))) < 0.01)
        #expect(abs(RackPlatePlay.tiltDegrees(simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))) - 90) < 0.01)
        #expect(abs(RackPlatePlay.tiltDegrees(simd_quatf(angle: .pi / 6, axis: SIMD3(1, 0, 0))) - 30) < 0.01)
        // Spinning about its own axis does not tilt it.
        #expect(RackPlatePlay.tiltDegrees(simd_quatf(angle: 1.3, axis: SIMD3(0, 1, 0))) < 0.01)
    }

    /// Steps a still plate in a pose until it is not moving any more, collecting the verdicts.
    private func settle(tilt: Float, height: Float, frames: Int = 600) -> [BarbellFloorSettleState.Verdict] {
        var state = BarbellFloorSettleState(delay: RackPlatePlay.settleDelay)
        var verdicts: [BarbellFloorSettleState.Verdict] = []
        for _ in 0..<frames {
            let verdict = state.advance(deltaTime: 1.0 / 60, linearSpeed: 0.005, angularSpeed: 0.01, tiltDegrees: tilt, height: height)
            verdicts.append(verdict)
            if verdict == .resting { break }
        }
        return verdicts
    }

    @Test func aPlateLyingFlatSleepsAfterAMomentOfStillness() {
        let verdicts = settle(tilt: 8, height: 0.03)
        #expect(verdicts.last == .resting)
        #expect(!verdicts.contains(.nudge))
        // Not before the delay plus the stillness.
        #expect(Double(verdicts.count) / 60 >= RackPlatePlay.settleDelay + BarbellFloorSettleState.stillFor - 0.02)
        // Flat on the pile is stable too.
        #expect(settle(tilt: 15, height: 0.2).contains(.nudge) == false)
    }

    @Test func aPlateOnItsEdgeOrLeaningIsTippedOverBeforeItMaySleep() {
        for tilt: Float in [40, 60, 89] {
            let verdicts = settle(tilt: tilt, height: 0.22)
            #expect(verdicts.filter { $0 == .nudge }.count == BarbellFloorSettleState.maxNudges, "tilt \(tilt)")
            // A lean it keeps after the nudges is accepted: nothing stays awake for ever.
            #expect(verdicts.last == .resting)
            #expect(Double(verdicts.count) / 60 < RackPlatePlay.settleDelay + BarbellFloorSettleState.giveUpAfter)
        }
    }

    @Test func aPlateProppedUpOnTheBarOrAStandIsPushedOff() {
        // Flat, but its centre is at bar height.
        #expect(settle(tilt: 5, height: 0.55).first(where: { $0 != .moving }) == .nudge)
        #expect(!BarbellFloorSettleState.isStablePose(tiltDegrees: 5, height: 0.55))
        #expect(BarbellFloorSettleState.isStablePose(tiltDegrees: 20, height: 0.1))
    }

    @Test func aPlateThatNeverStopsIsAcceptedAtTheTimeLimit() {
        var state = BarbellFloorSettleState(delay: 0.5)
        var frames = 0
        while state.advance(deltaTime: 1.0 / 60, linearSpeed: 0.2, angularSpeed: 1, tiltDegrees: 80, height: 0.3) != .resting {
            frames += 1
            #expect(frames < 60 * 10)
            if frames >= 60 * 10 { break }
        }
        #expect(abs(Double(frames) / 60 - (0.5 + BarbellFloorSettleState.giveUpAfter)) < 0.05)
    }

    @Test func tippingOverTurnsTheFaceTowardTheNearerVerticalAndAwayFromTheBar() {
        for (angle, axis) in [(Float(1.2), SIMD3<Float>(1, 0, 0)), (-1.4, SIMD3(0, 0, 1)), (2.0, SIMD3(1, 0, 0)), (.pi / 2, SIMD3(0, 0, 1))] {
            let orientation = simd_quatf(angle: angle, axis: axis)
            let normal = orientation.act(SIMD3<Float>(0, 1, 0))
            let push = RackPlatePlay.tipOver(orientation: orientation, position: SIMD3(0.5, 0.2, 0.3))
            // The face normal starts turning toward straight up (or straight down if it faces down).
            let change = simd_cross(push.angular, normal)
            #expect(change.y * (normal.y >= 0 ? 1 : -1) > 0, "angle \(angle) axis \(axis)")
            #expect(push.linear.y > 0)
            #expect(push.linear.z > 0, "away from the bar")
            #expect(push.linear.x < 0, "in from the right side")
        }
        // Out on open floor in the middle: no sideways slide.
        let open = RackPlatePlay.tipOver(orientation: simd_quatf(angle: 1, axis: SIMD3(1, 0, 0)), position: SIMD3(0, 0.2, 0.6))
        #expect(open.linear.x == 0 && open.linear.z == 0)
    }

    // MARK: Collider

    @Test func theColliderIsARoundDiscAsThickAsThePlate() {
        let radius: Float = 0.22, thickness: Float = 0.044
        let points = plateDiscColliderPoints(radius: radius, thickness: thickness)
        #expect(points.count == plateDiscColliderSides * 2)
        for p in points {
            #expect(abs(abs(p.y) - thickness / 2) < 1e-5)
            let r = simd_length(SIMD2(p.x, p.z))
            // Corners just outside the rim, flat sides touching it: never the 31 cm slab corner.
            #expect(r >= radius && r <= radius * 1.03)
        }
        // A flat side's midpoint lies on the rim.
        let a = points[0], b = points[2]
        #expect(abs(simd_length(SIMD2((a.x + b.x) / 2, (a.z + b.z) / 2)) - radius) < 1e-4)
    }

    @Test @MainActor func everyPlateStyleGetsTheDiscColliderWithSweptCollision() throws {
        for style in [RackPlateStyle.lathe, .legacy] {
            for tierID in [22, 0, 6] {
                let plate = makePlateEntity(tierID: tierID, weightKg: 20, plateStyle: style)
                let collision = try #require(plate.components[CollisionComponent.self])
                #expect(collision.shapes.count == 1)
                let body = try #require(plate.components[PhysicsBodyComponent.self])
                #expect(body.isContinuousCollisionDetectionEnabled)
                let profile = PlateVisualDesign.profile(for: PlateTier.all.first { $0.id == tierID }!.style)
                let bounds = collision.shapes[0].bounds
                // Thin along the plate's axis (the slab was 10 cm), plate-sized across.
                #expect(bounds.extents.y < profile.thickness + 0.02, "tier \(tierID) \(style): \(bounds.extents)")
                #expect(abs(bounds.extents.x - 2 * profile.outerRadius) < 0.03)
                #expect(body.angularDamping == plateAngularDamping && body.linearDamping == plateLinearDamping)
            }
        }
    }

    // MARK: Tidy up

    private func positions(_ count: Int) -> [(id: String, position: SIMD3<Float>)] {
        (0..<count).map { i in
            (id: "p\(i)", position: SIMD3((RackPlateRain.hash(i, 1) - 0.5) * 1.1, 0.03, 0.1 + RackPlateRain.hash(i, 2) * 0.6))
        }
    }

    @Test func trayAndSinkTakeTheNearestPlateFirstAndWheelTheOutermost() {
        let plates = positions(16)
        for style in [RackTidyStyle.tray, .sink] {
            let plan = RackPlateRain.tidyPlan(plates, style: style, reduceMotion: false)
            let zs = plan.map { step in plates.first { $0.id == step.id }!.position.z }
            #expect(zs == zs.sorted(by: >), "\(style)")
        }
        let wheel = RackPlateRain.tidyPlan(plates, style: .wheel, reduceMotion: false)
        let xs = wheel.map { step in abs(plates.first { $0.id == step.id }!.position.x) }
        #expect(xs == xs.sorted(by: >))
        // Every plate exactly once.
        #expect(Set(wheel.map(\.id)) == Set(plates.map(\.id)) && wheel.count == plates.count)
    }

    @Test func theWholeTidyFitsTheBudgetWithAnEvenStagger() {
        for style in RackTidyStyle.allCases {
            for count in [1, 2, 5, 16, 24, 40] {
                let plan = RackPlateRain.tidyPlan(positions(count), style: style, reduceMotion: false)
                let end = plan.map { $0.delay + $0.duration }.max() ?? 0
                #expect(end <= RackPlateRain.tidyBudget + 1e-9, "\(style) \(count): \(end)")
                #expect(plan.first?.delay == 0)
                for (a, b) in zip(plan, plan.dropFirst()) {
                    #expect(b.delay - a.delay <= RackPlateRain.tidyMaxStagger + 1e-9)
                    #expect(b.delay > a.delay)
                }
            }
        }
        // Few plates leave about 40 ms apart.
        let five = RackPlateRain.tidyPlan(positions(5), style: .tray, reduceMotion: false)
        #expect(abs(five[1].delay - 0.04) < 1e-9)
    }

    @Test func underReduceMotionEveryPlateFadesAtOnce() {
        for style in RackTidyStyle.allCases {
            let plan = RackPlateRain.tidyPlan(positions(16), style: style, reduceMotion: true)
            #expect(plan.allSatisfy { $0.delay == 0 && $0.duration == 0.25 })
        }
    }

    @Test func tidyExitsLeaveTheFrame() {
        let start = Transform(scale: .one, rotation: simd_quatf(angle: 0.3, axis: SIMD3(1, 0, 0)), translation: SIMD3(0.3, 0.03, 0.5))
        let tray = RackPlateRain.tidyKeyframes(.tray, from: start)
        #expect(tray.count == 2)
        #expect(tray[0].translation.y > start.translation.y, "it lifts first")
        #expect(tray[1].translation.z > 1.5 && tray[1].scale.x < 0.5, "toward the camera and the tray, shrinking")
        let wheel = RackPlateRain.tidyKeyframes(.wheel, from: start)
        #expect(wheel.count == 1 && wheel[0].translation.x > 1.2, "off the nearer (right) side")
        let left = RackPlateRain.tidyKeyframes(.wheel, from: Transform(translation: SIMD3(-0.1, 0.03, 0.5)))
        #expect(left[0].translation.x < -1.2)
        let sink = RackPlateRain.tidyKeyframes(.sink, from: start)
        #expect(sink[0].translation.y < start.translation.y && sink[0].scale.x < 1)
    }

    @Test func theTidyStyleOverrideIsDebugOnly() {
        #expect(RackTidyStyle.resolve(isDebugBuild: false, argument: "sink", environment: ["VOLIA_RACK_TIDY": "wheel"]) == .tray)
        #expect(RackTidyStyle.resolve(isDebugBuild: true, argument: "sink", environment: ["VOLIA_RACK_TIDY": "wheel"]) == .sink)
        #expect(RackTidyStyle.resolve(isDebugBuild: true, argument: nil, environment: ["VOLIA_RACK_TIDY": "wheel"]) == .wheel)
        #expect(RackTidyStyle.resolve(isDebugBuild: true, argument: "spin", environment: [:]) == .tray)
        #expect(RackTidyStyle.standard == .tray)
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
        // They lie flat or nearly flat on the floor or each other, low, and off the bar and stands.
        #expect(rest.aboveBarHeight == 0, "\(rest)")
        #expect(rest.onEdge == 0, "\(rest)")
        #expect(rest.onRig == 0, "\(rest)")
        #expect(rest.flat >= chosen.count * 3 / 4, "\(rest)")
        #expect(rest.minY > -0.03, "\(rest)")
        print("rain rest \(state.plateStyle): \(rest)")
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

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_RACK_RAIN"] == "1"))
    func tidyPlaysAnExitAndADropMidTidyClearsIt() async throws {
        let plates = Self.inventory()
        let state = SceneState()
        let window = try await Self.showScene(state: state, racked: [], floor: plates)
        defer { Self.close(window) }

        #expect(await state.rainPlates(Array(plates.prefix(8)), gentle: false) == 8)
        _ = try await Self.waitForSleep(state, ids: state.rainedPlateIDs, timeout: 15)
        let first = state.rainedPlateIDs.compactMap { state.entityMap[$0] }
        #expect(state.tidyRainedPlates(exit: .tray) == 8)
        // Out of the bookkeeping and out of reach at once, still on screen for the exit.
        #expect(state.rainedPlateIDs.isEmpty && state.loosePlateIDs.isEmpty)
        #expect(state.leavingPlates.count == 8)
        #expect(first.allSatisfy { $0.parent != nil && $0.components[CollisionComponent.self] == nil
                                   && $0.components[PhysicsBodyComponent.self] == nil })
        #expect(state.tidyTask != nil)
        try await Task.sleep(for: .seconds(RackPlateRain.tidyBudget + 0.3))
        #expect(state.leavingPlates.isEmpty)
        #expect(first.allSatisfy { $0.parent == nil })

        // A drop while plates are still leaving: they go at once and the new ones fall.
        #expect(await state.rainPlates(Array(plates.prefix(8)), gentle: false) == 8)
        _ = try await Self.waitForSleep(state, ids: state.rainedPlateIDs, timeout: 15)
        let second = state.rainedPlateIDs.compactMap { state.entityMap[$0] }
        #expect(state.tidyRainedPlates(exit: .sink) == 8)
        try await Task.sleep(for: .milliseconds(100))
        let again = await state.rainPlates(Array(plates.dropFirst(8).prefix(4)), gentle: false)
        #expect(again == 4)
        #expect(state.leavingPlates.isEmpty && state.tidyTask == nil)
        #expect(second.allSatisfy { $0.parent == nil })
        #expect(state.rainedPlateIDs.count == 4)
        // Reduce Motion: a fade, all at once, and gone within its length.
        _ = try await Self.waitForSleep(state, ids: state.rainedPlateIDs, timeout: 15)
        #expect(state.tidyRainedPlates(exit: .wheel, reduceMotion: true) == 4)
        try await Task.sleep(for: .milliseconds(450))
        #expect(state.leavingPlates.isEmpty)
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
            var awake = ""
            if env["VOLIA_RACK_RAIN_DIAG"] == "1" {
                try await Task.sleep(for: .seconds(2.5))
                for id in state.rainedPlateIDs {
                    guard let e = state.entityMap[id], e.components[PhysicsBodyComponent.self]?.mode == .dynamic else { continue }
                    let m = e.components[PhysicsMotionComponent.self] ?? PhysicsMotionComponent()
                    let p = e.position(relativeTo: state.sceneRoot)
                    awake += String(format: "    %@ lin=%.3f ang=%.3f tilt=%.0f y=%.3f nudges=%d still=%.2f\n", id, simd_length(m.linearVelocity),
                                    simd_length(m.angularVelocity), RackPlatePlay.tiltDegrees(e.orientation(relativeTo: state.sceneRoot)), p.y,
                                    state.floorSettles[id]?.nudges ?? -1, state.floorSettles[id]?.still ?? -1)
                }
            }
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
                             memBefore, memAfter, memAfter - memBefore, entities, rest.description) + awake
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
        try await Task.sleep(for: .seconds(Double(env["VOLIA_CAPTURE_MID"] ?? "") ?? 0.9))
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

    /// TEST_RUNNER_VOLIA_RACK_TIDY_CAPTURE=tray|wheel|sink|fade: drops the cap into the full rack
    /// screen, lets it settle, then writes tidy-<style>.burst (an outside script screenshots back to
    /// back) and tidies up slowed down by TEST_RUNNER_VOLIA_TIDY_SLOW (default 10), so each
    /// screenshot is a frame of the real exit about every 50 ms.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_RACK_TIDY_CAPTURE"] != nil))
    func captureTidy() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let raw = env["VOLIA_RACK_TIDY_CAPTURE"] ?? "tray"
        let fade = raw == "fade"
        let style = RackTidyStyle(rawValue: raw) ?? .tray
        let slow = Double(env["VOLIA_TIDY_SLOW"] ?? "") ?? 10
        let plates = Self.inventory(racked: [0, 1, 2])
        let state = SceneState()
        let window = Self.window(Self.rackScreen(plates: plates, state: state, playPhase: .loose))
        defer { Self.close(window) }
        try await Task.sleep(for: .seconds(Double(env["VOLIA_CAPTURE_WAIT"] ?? "") ?? 12))
        let limits = RackPlateRain.limits(for: state.plateStyle)
        _ = await state.rainPlates(Self.order(plates, cap: limits.plates, looks: limits.looks), gentle: false)
        _ = try await Self.waitForSleep(state, ids: state.rainedPlateIDs, timeout: 20)
        try await Task.sleep(for: .seconds(1))
        try Data().write(to: root.appendingPathComponent("tidy-\(raw).burst"))
        try await Task.sleep(for: .seconds(1.5))
        state.tidyRainedPlates(exit: style, reduceMotion: fade, timeScale: slow)
        try await Task.sleep(for: .seconds(RackPlateRain.tidyBudget * slow + 2))
    }

    static func rackScreen(plates: [EarnedPlate], state: SceneState, playPhase: CutRackPlayPhase) -> AnyView {
        let facts = plates.map(CutRackPlateFacts.init)
        let model = CutRackLogic.model(CutRackFacts(plates: facts, occupiedSlots: plates.filter(\.isRacked).count, unit: .kg,
                                                    notice: nil, playPhase: playPhase),
                                       locale: Locale(identifier: "en_US"))
        return AnyView(CutRackView(
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
        ))
    }

    // MARK: Helpers

    struct Rest: CustomStringConvertible {
        var outOfRoom = 0
        var outOfFrame = 0
        var minY: Float = .greatestFiniteMagnitude
        var maxY: Float = -.greatestFiniteMagnitude
        var aboveBarHeight = 0
        /// Each resting plate's tilt from lying flat, in degrees (0 flat, 90 on its edge).
        var tilts: [Float] = []
        /// Plates resting with their centre at or above 0.25 m within 0.30 m of the bar's depth:
        /// propped on the bar, the stands or the pile against them.
        var onRig = 0
        var flat: Int { tilts.filter { $0 < 20 }.count }
        var leaning: Int { tilts.filter { $0 >= 20 && $0 < 60 }.count }
        var onEdge: Int { tilts.filter { $0 >= 60 }.count }
        var medianTilt: Float { tilts.isEmpty ? 0 : tilts.sorted()[tilts.count / 2] }
        var description: String {
            String(format: "outOfRoom=%d outOfFrame=%d y=[%.3f, %.3f] restingAbove0.45=%d tilt: flat<20=%d leaning20-60=%d edge>=60=%d median=%.0f max=%.0f onRig=%d",
                   outOfRoom, outOfFrame, minY, maxY, aboveBarHeight, flat, leaning, onEdge, medianTilt, tilts.max() ?? 0, onRig)
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
            rest.tilts.append(RackPlatePlay.tiltDegrees(entity.orientation(relativeTo: state.sceneRoot)))
            if p.y >= 0.25 && abs(p.z - 0.12) < 0.30 { rest.onRig += 1 }
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
