import CoreGraphics
import Foundation
import RealityKit
import Testing
import UIKit
@testable import WRKT

/// The rack open's work budget, counted rather than timed: with 90 earned plates and 4 on the bar,
/// opening prepares the bar's faces only, a second open prepares nothing, and the light probe is
/// built at most once per process. Plus the caches that make it so: disk copies are bit-identical
/// to what was drawn, keys are stable, the directory stays bounded, and cached materials are
/// copy on write.
@MainActor
@Suite(.serialized)
struct RackOpenWorkTests {
    /// Plates whose faces no earlier test can have prepared: every engraving carries this run's tag.
    private static func inventory(count: Int = 90, onBar: Int = 4) -> [EarnedPlate] {
        let tag = UUID().uuidString.prefix(6)
        let tiers = PlateTier.all.map(\.id).filter { $0 != 7 }
        let weights: [Double] = [2.5, 5, 10, 15, 20, 25, 45]
        return (0..<count).map { index in
            EarnedPlate(id: "work-\(tag)-\(index)", tierID: tiers[index % tiers.count],
                        weightKg: weights[(index * 3) % weights.count], engravingText: "T\(tag)\(index)",
                        earnedByEvent: "fixture", isRacked: index < onBar, rackPosition: index < onBar ? index : nil,
                        currentTier: BarbellPlateProgressionTier.allCases[index % 6])
        }
    }

    private static func faceWork() -> Int {
        RackWorkCounters.count(.faceImagesDrawn) + RackWorkCounters.count(.faceImagesReadFromDisk)
    }

    @Test func lathePreloadPreparesTheBarFacesOnly() async {
        let plates = Self.inventory()
        let racked = plates.filter(\.isRacked)
        let state = SceneState()
        state.plateStyle = .lathe

        let faces = Self.faceWork(), uploads = RackWorkCounters.count(.faceTexturesUploaded)
        await CutRackPreloader.preload(racked: racked, into: state)
        #expect(Self.faceWork() - faces == racked.count)
        #expect(RackWorkCounters.count(.faceTexturesUploaded) - uploads == racked.count)
        // Lathe plates take no legacy materials.
        #expect(state.materialCache.isEmpty)

        // A second open of the same bar: nothing to draw, read or upload.
        let again = Self.faceWork(), uploadsAgain = RackWorkCounters.count(.faceTexturesUploaded)
        await CutRackPreloader.preload(racked: racked, into: SceneState())
        #expect(Self.faceWork() == again)
        #expect(RackWorkCounters.count(.faceTexturesUploaded) == uploadsAgain)
    }

    @Test func legacyPreloadLoadsTheBarTiersOnly() async {
        let plates = Self.inventory()
        let racked = plates.filter(\.isRacked)
        let state = SceneState()
        state.plateStyle = .legacy
        let faces = Self.faceWork()
        await CutRackPreloader.preload(racked: racked, into: state)
        #expect(Set(state.materialCache.keys) == Set(racked.map(\.tierID)).subtracting([7]))
        #expect(Self.faceWork() == faces)
    }

    @Test func barOnlySceneRequestsTheBarFacesNotTheTray() {
        let plates = Self.inventory()
        let mode = BarbellRealityMode.rackRoom(rackedPlates: plates.filter(\.isRacked),
                                               floorPlates: plates.filter { !$0.isRacked },
                                               onRack: { _ in }, onUnrack: { _ in })
        #expect(BarbellRealityView.latheFirstFrameRequests(mode: mode, barOnly: true).count == 4)
        #expect(BarbellRealityView.latheLaterRequests(mode: mode, barOnly: true).count == 4)
        #expect(BarbellRealityView.latheLaterRequests(mode: mode, barOnly: true).allSatisfy { $0.engravingText.isEmpty })
        // The wall-storage rack still builds its floor plates up front, as before.
        #expect(BarbellRealityView.latheFirstFrameRequests(mode: mode, barOnly: false).count == 90)
    }

    @Test func studioEnvironmentIsBuiltAtMostOncePerProcess() async {
        let before = RackWorkCounters.count(.studioPanoramasBuilt) + RackWorkCounters.count(.studioPanoramasReadFromDisk)
        async let first = sharedRackStudioEnvironmentResource()
        async let second = sharedRackStudioEnvironmentResource()
        let resources = await [first, second]
        _ = await sharedRackStudioEnvironmentResource()
        let after = RackWorkCounters.count(.studioPanoramasBuilt) + RackWorkCounters.count(.studioPanoramasReadFromDisk)
        #expect(after - before <= 1)
        #expect(resources[0] === resources[1])
    }

    // MARK: Disk cache

    private static func bytes(_ image: CGImage) -> Data? {
        image.dataProvider?.data as Data?
    }

    @Test func faceImagesReadBackBitIdentical() throws {
        let tier = try #require(PlateTier.all.first { $0.id == 14 })
        let spec = latheFaceSpec(tier: tier, weightKg: 20, engravingText: "Disk \(UUID().uuidString.prefix(4))",
                                 projection: BarbellPlateRenderProjection(), showEngravings: true)
        let drawn = try #require(LatheFaceArt.images(for: spec))
        #expect(LatheFaceDiskCache.images(for: spec) == nil)
        LatheFaceDiskCache.store(drawn, for: spec)
        let read = try #require(LatheFaceDiskCache.images(for: spec))
        for (a, b) in [(drawn.color, read.color), (drawn.normal, read.normal), (drawn.roughness, read.roughness)] {
            #expect(Self.bytes(a) == Self.bytes(b))
            #expect(a.colorSpace?.name == b.colorSpace?.name)
            #expect(a.bitmapInfo == b.bitmapInfo)
            #expect(a.width == b.width && a.height == b.height && a.bytesPerRow == b.bytesPerRow)
        }
        try? FileManager.default.removeItem(at: RackAssetDiskCache.fileURL(kind: "face", identity: spec.diskIdentity))
    }

    @Test func studioPanoramaReadsBackBitIdentical() throws {
        let identity = "test-\(UUID().uuidString)"
        let decoded = try #require(RackStudioEnvironment.loadPanorama(diskCache: false))
        RackStudioPanoramaDiskCache.store(decoded, identity: identity)
        let read = try #require(RackStudioPanoramaDiskCache.image(identity: identity))
        #expect(Self.bytes(decoded) == Self.bytes(read))
        #expect(decoded.colorSpace?.name == read.colorSpace?.name)
        #expect(decoded.bitmapInfo == read.bitmapInfo)
        #expect(decoded.width == read.width && decoded.height == read.height)
        try? FileManager.default.removeItem(at: RackStudioPanoramaDiskCache.url(identity: identity))
    }

    @Test func faceKeysAreStableAndDistinct() throws {
        let tier = try #require(PlateTier.all.first { $0.id == 6 })
        func spec(_ engraving: String) -> LatheFaceSpec {
            latheFaceSpec(tier: tier, weightKg: 25, engravingText: engraving,
                          projection: BarbellPlateRenderProjection(), showEngravings: true)
        }
        #expect(spec("Bench 100").diskIdentity == spec("Bench 100").diskIdentity)
        #expect(spec("Bench 100").diskIdentity != spec("Bench 105").diskIdentity)
        #expect(RackAssetDiskCache.fileURL(kind: "face", identity: "a") == RackAssetDiskCache.fileURL(kind: "face", identity: "a"))
        #expect(RackAssetDiskCache.fileURL(kind: "face", identity: "a").path.contains("/Caches/rack_assets/"))
        #expect(RackAssetDiskCache.buildStamp != "unknown")
    }

    @Test func pruneKeepsTheNewestFilesWithinTheBound() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("rack-prune-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for index in 0..<5 {
            let url = folder.appendingPathComponent("f\(index).bin")
            try Data(count: 1000).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(1000 + index))], ofItemAtPath: url.path)
        }
        RackAssetDiskCache.prune(in: folder, maximumBytes: 2500)
        let left = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        #expect(left == ["f3.bin", "f4.bin"])
    }

    @Test func otherBuildsFilesAreRetired() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("rack-builds-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["aaaa1111-face-x.bin", "bbbb2222-face-y.bin", "aaaa1111-studio-z.bin"] {
            try Data(count: 10).write(to: folder.appendingPathComponent(name))
        }
        RackAssetDiskCache.removeOtherBuilds(in: folder, keeping: "aaaa1111")
        let left = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        #expect(left == ["aaaa1111-face-x.bin", "aaaa1111-studio-z.bin"])
        #expect(RackAssetDiskCache.fileURL(kind: "face", identity: "a").lastPathComponent.hasPrefix(RackAssetDiskCache.buildTag + "-face-"))
    }
}
