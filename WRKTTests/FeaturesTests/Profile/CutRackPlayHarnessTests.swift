import Foundation
import RealityKit
import SwiftUI
import Testing
import UIKit
@testable import WRKT

/// Scripted play with a loose plate in the real bar-only rack scene, with real RealityKit physics.
/// Fixture plates only (never inserted into a store, nothing saved). The outer plate is dropped to
/// the floor the way the tray drops it, then picked up through the same SceneState calls the drag
/// gesture makes (beginHold, updateHold every frame, endHold, the release decision, releaseLoose),
/// carried to several places and let go. Asserts it stays loose and inside the room everywhere but
/// a sleeve drop zone, and that the room goes back to sleep.
/// TEST_RUNNER_VOLIA_RACK_PLAY=1. TEST_RUNNER_VOLIA_RACK_PLATES=legacy|lathe picks the plate style.
/// TEST_RUNNER_VOLIA_CAPTURE_DIR + TEST_RUNNER_VOLIA_CAPTURE_HOLD=<seconds> write <step>.ready and
/// hold so an outside simctl screenshot can record the Metal layer.
@MainActor
@Suite(.serialized)
struct CutRackPlayHarnessTests {
    private var root: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_DIR"] ?? "/private/tmp/volia-rack-play")
    }
    private var hold: Double { Double(ProcessInfo.processInfo.environment["VOLIA_CAPTURE_HOLD"] ?? "") ?? 0 }

    private static func plate(_ id: String, tier: Int, kg: Double, slot: Int?) -> EarnedPlate {
        EarnedPlate(id: "play-\(id)", tierID: tier, weightKg: kg, engravingText: "",
                    earnedAt: Date(timeIntervalSince1970: 1_790_000_000), earnedByEvent: "fixture",
                    isRacked: slot != nil, rackPosition: slot, liftTypeID: nil, currentTier: .steel,
                    workoutsUsedCount: 1, prCount: 0)
    }

    private static let racked = [plate("lime", tier: 22, kg: 20, slot: 0), plate("gold", tier: 6, kg: 45, slot: 1)]

    /// Where a scripted release ends, in the scene root's space, and what it must do.
    private struct Release {
        var name: String
        var target: SIMD3<Float>
        var fling: CGSize = .zero
        var barHasFreeSlot = true
        var expected: RackPlateRelease
    }

    private struct Bounds {
        var maxAbsX: Float = 0
        var minY: Float = .greatestFiniteMagnitude
        var maxY: Float = -.greatestFiniteMagnitude
        var minZ: Float = .greatestFiniteMagnitude
        var maxZ: Float = -.greatestFiniteMagnitude
        mutating func add(_ p: SIMD3<Float>) {
            maxAbsX = max(maxAbsX, abs(p.x)); minY = min(minY, p.y); maxY = max(maxY, p.y)
            minZ = min(minZ, p.z); maxZ = max(maxZ, p.z)
        }
        var text: String {
            String(format: "|x|<=%.3f y=[%.3f, %.3f] z=[%.3f, %.3f]", maxAbsX, minY, maxY, minZ, maxZ)
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_RACK_PLAY"] == "1"))
    func playWithALoosePlate() async throws {
        let windowScene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let previous = windowScene.windows.first { $0.isKeyWindow }
        previous?.isHidden = true
        let window = UIWindow(windowScene: windowScene)
        let state = SceneState()
        if state.plateStyle == .legacy {
            for tierID in Set(Self.racked.map(\.tierID)) {
                state.plateTextureCache[tierID] = loadPlateTextures(forTierID: tierID)
                state.materialCache[tierID] = buildMaterial(forTierID: tierID, textures: state.plateTextureCache[tierID], inRackRoom: true)
            }
        }
        window.rootViewController = UIHostingController(rootView: VStack(spacing: 0) {
            Color.black.frame(height: 120)
            BarbellRealityView(
                mode: .rackRoom(rackedPlates: Self.racked, floorPlates: [], onRack: { _ in }, onUnrack: { _ in }),
                sceneState: state,
                barOnly: true
            )
            .frame(height: 420)
            Spacer()
        }.background(Color.black).preferredColorScheme(.dark))
        window.windowLevel = .alert + 1
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.isHidden = false
            previous?.makeKey()
        }
        var log = "style=\(state.plateStyle)\n"
        defer { try? log.write(to: root.appendingPathComponent("play-\(state.plateStyle).txt"), atomically: true, encoding: .utf8) }

        try await Task.sleep(for: .seconds(4))
        let id = "play-gold"
        let plate = try #require(state.entityMap[id])
        #expect(plate.components[PlateRoleComponent.self]?.role == .bar)

        // Drop the outer plate the way the tray does, and let it come to rest.
        #expect(await state.releaseBarPlateToFloor(plateID: id))
        var bounds = Bounds()
        try await watch(plate, in: state, seconds: 4, bounds: &bounds)
        log += "dropped: \(v(plate, state)) \(bounds.text) mode=\(mode(plate))\n"
        #expect(plate.components[PlateRoleComponent.self]?.role == .floor)
        #expect(plate.position(relativeTo: state.sceneRoot).y < 0.40)
        #expect(state.loosePlateIDs.contains(id))
        let dropped = plate.position(relativeTo: state.sceneRoot)
        #expect(abs(dropped.x) <= RackPlatePlay.frameMaxAbsX + 0.04 && dropped.z <= RackPlatePlay.frameMaxZ + 0.04,
                "the dropped plate came to rest out of frame: \(dropped)")
        try await shot("play-0-dropped")

        let bar = state.barAnchor.position
        let releases: [Release] = [
            Release(name: "floor-middle", target: SIMD3(0, 0.15, 0), expected: .loose),
            // At bar height over the middle of the bar: the old rule loaded this.
            Release(name: "bar-height-middle", target: SIMD3(0.05, bar.y, 0), expected: .loose),
            // Well above the bar: the old rule loaded anything up to 50 cm above it.
            Release(name: "above-bar", target: SIMD3(0.30, bar.y + 0.35, 0), expected: .loose),
            Release(name: "under-right-sleeve", target: SIMD3(0.62, 0.30, 0), expected: .loose),
            Release(name: "left-floor", target: SIMD3(-0.50, 0.20, 0), expected: .loose),
            // A toss up and to the side: it flies, comes down and stays loose.
            Release(name: "toss", target: SIMD3(0.20, 0.45, 0), fling: CGSize(width: 900, height: -1400), expected: .loose),
            // At the right sleeve end with a full bar: no zone, stays loose.
            Release(name: "right-sleeve-full-bar", target: SIMD3(0.62, bar.y, 0), barHasFreeSlot: false, expected: .loose),
            // A fast flick through the zone is a throw.
            Release(name: "flick-through-sleeve", target: SIMD3(0.62, bar.y, 0), fling: CGSize(width: 0, height: -1600), expected: .loose),
            // Held still at either sleeve end: the deliberate load.
            Release(name: "left-sleeve", target: SIMD3(-0.62, bar.y, 0), expected: .rack),
            Release(name: "right-sleeve", target: SIMD3(0.62, bar.y, 0), expected: .rack)
        ]

        for (index, release) in releases.enumerated() {
            let entity = try #require(state.entityMap[id])
            if entity.components[PlateRoleComponent.self]?.role == .bar {
                // Put it back on the floor after a rack, as the tray would.
                #expect(await state.releaseBarPlateToFloor(plateID: id))
                var settle = Bounds()
                try await watch(entity, in: state, seconds: 4, bounds: &settle)
            }
            #expect(state.transition(to: .draggingPlate(entity, plateID: id, originRole: .floor)))
            state.beginHold(entity: entity, plateID: id, barSlot: release.barHasFreeSlot ? 1 : nil)
            let start = entity.position
            let goal = SIMD3(release.target.x, release.target.y, start.z)
            let translation = CGSize(width: CGFloat((goal.x - start.x) / RackPlatePlay.dragScale),
                                     height: CGFloat(-(goal.y - start.y) / RackPlatePlay.dragScale))
            // A finger moving there over 0.6 s, then held still for 0.5 s (or let go at once for a flick).
            let steps = 36
            for step in 1...steps {
                let t = CGFloat(step) / CGFloat(steps)
                state.updateHold(translation: CGSize(width: translation.width * t, height: translation.height * t), maxAbsX: 0.64)
                try await Task.sleep(for: .milliseconds(16))
            }
            if release.fling == .zero { try await Task.sleep(for: .milliseconds(500)) }
            let heldAt = entity.position(relativeTo: state.sceneRoot)
            let cueShown = state.slotHighlights.contains { $0.isEnabled }
            if release.expected == .rack { try await shot("play-\(index + 1)-\(release.name)-held") }
            #expect(state.transition(to: .idle))
            let held = state.endHold()
            let decision = RackPlatePlay.releaseDecision(RackPlateReleaseFacts(
                origin: .loosePlate, didDrag: true, sleeveSide: held?.sleeveSide,
                barHasFreeSlot: held?.barSlot != nil,
                releaseSpeed: hypot(release.fling.width, release.fling.height),
                hoveredStorageSlot: nil, originStorageSlot: nil))
            log += "\(release.name): heldAt=\(String(format: "(%.3f, %.3f, %.3f)", heldAt.x, heldAt.y, heldAt.z)) sleeve=\(held?.sleeveSide.map { "\($0)" } ?? "nil") cue=\(cueShown) -> \(decision)"
            #expect(decision == release.expected, "\(release.name): \(decision)")
            #expect(cueShown == (held?.sleeveSide != nil), "\(release.name): cue \(cueShown)")
            switch decision {
            case .rack:
                state.freezeForSnap(entity)
                let loaded = try #require(Self.racked.first { $0.id == id })
                #expect(await state.loadPlateOntoBar(loaded, rackSlot: 1))
                #expect(entity.components[PlateRoleComponent.self]?.role == .bar)
                log += " racked\n"
            default:
                state.releaseLoose(entity: entity, plateID: id, fingerVelocity: release.fling, maxAbsX: 0.64)
                var flight = Bounds()
                try await watch(entity, in: state, seconds: 4.5, bounds: &flight)
                let rest = entity.position(relativeTo: state.sceneRoot)
                log += " rest=\(String(format: "(%.3f, %.3f, %.3f)", rest.x, rest.y, rest.z)) flight \(flight.text) mode=\(mode(entity))\n"
                #expect(entity.components[PlateRoleComponent.self]?.role == .floor, "\(release.name) left the floor role")
                #expect(entity.parent !== state.barAnchor, "\(release.name) went onto the bar")
                // Inside the room the whole time, and back on the floor at the end.
                #expect(flight.maxAbsX <= 0.80, "\(release.name) \(flight.text)")
                // A 3 cm disc landing at 5 m/s from a flick can sink a couple of centimetres into the
                // floor for one physics step before the contact pushes it out (the 10 cm slab hid this).
                #expect(flight.minY >= -0.035 && flight.maxY <= 1.90, "\(release.name) \(flight.text)")
                #expect(flight.minZ >= -0.15 && flight.maxZ <= 0.90, "\(release.name) \(flight.text)")
                // On the floor (lying, or standing on its rim against a rail) and in full view.
                #expect(rest.y < 0.40, "\(release.name) did not come to rest on the floor: \(rest)")
                #expect(abs(rest.x) <= RackPlatePlay.frameMaxAbsX + 0.04 && rest.z <= RackPlatePlay.frameMaxZ + 0.04,
                        "\(release.name) came to rest out of frame: \(rest)")
                #expect(mode(entity) == "kinematic", "\(release.name) never went to sleep")
                #expect(state.floorSettles.isEmpty)
                try await shot("play-\(index + 1)-\(release.name)")
            }
        }
    }

    private func watch(_ entity: Entity, in state: SceneState, seconds: Double, bounds: inout Bounds) async throws {
        let frames = Int(seconds / 0.016)
        for _ in 0..<frames {
            bounds.add(entity.position(relativeTo: state.sceneRoot))
            try await Task.sleep(for: .milliseconds(16))
        }
    }

    private func mode(_ entity: Entity) -> String {
        switch entity.components[PhysicsBodyComponent.self]?.mode {
        case .some(.dynamic): return "dynamic"
        case .some(.kinematic): return "kinematic"
        case .some(.static): return "static"
        default: return "none"
        }
    }

    private func v(_ entity: Entity, _ state: SceneState) -> String {
        let p = entity.position(relativeTo: state.sceneRoot)
        return String(format: "(%.3f, %.3f, %.3f)", p.x, p.y, p.z)
    }

    private func shot(_ name: String) async throws {
        guard hold > 0 else { return }
        try Data().write(to: root.appendingPathComponent(name + ".ready"))
        try await Task.sleep(for: .seconds(hold))
    }
}
