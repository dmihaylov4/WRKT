import Testing
import UIKit
@testable import WRKT

@Suite("PlateSnapshotService cache key and disk I/O")
struct PlateSnapshotServiceTests {

    @Test("cacheKey is stable for same inputs")
    @MainActor
    func cacheKeyStable() {
        let k1 = PlateSnapshotService.cacheKey(tierID: 5, weightKg: 35, engravingText: "Volume Champion", style: .legacy)
        let k2 = PlateSnapshotService.cacheKey(tierID: 5, weightKg: 35, engravingText: "Volume Champion", style: .legacy)
        #expect(k1 == k2)
        // The legacy thumbnails keep the key they had before the lathe plates, so they are reused.
        #expect(k1 == "v3_e475445974e3ad2950faba3a936863e858675b794c9dd8d9fb638abb8bde7c27")
    }

    @Test("lathe thumbnails never share a key with legacy ones")
    @MainActor
    func cacheKeyVariesByPlateStyle() {
        let legacy = PlateSnapshotService.cacheKey(tierID: 5, weightKg: 35, engravingText: "Volume Champion", style: .legacy)
        let lathe = PlateSnapshotService.cacheKey(tierID: 5, weightKg: 35, engravingText: "Volume Champion", style: .lathe)
        #expect(lathe == "l1_e475445974e3ad2950faba3a936863e858675b794c9dd8d9fb638abb8bde7c27")
        #expect(lathe != legacy)
        // The key a launch uses is its plate style's.
        #expect(PlateSnapshotService.cacheKey(tierID: 5, weightKg: 35, engravingText: "Volume Champion")
                == PlateSnapshotService.cacheKey(tierID: 5, weightKg: 35, engravingText: "Volume Champion", style: RackPlateStyle.current))
    }

    @Test("cacheKey differs when tierID changes")
    @MainActor
    func cacheKeyVariesByTier() {
        let k1 = PlateSnapshotService.cacheKey(tierID: 5, weightKg: 35, engravingText: "Champion")
        let k2 = PlateSnapshotService.cacheKey(tierID: 6, weightKg: 35, engravingText: "Champion")
        #expect(k1 != k2)
    }

    @Test("cacheKey differs when engravingText changes")
    @MainActor
    func cacheKeyVariesByEngraving() {
        let k1 = PlateSnapshotService.cacheKey(tierID: 5, weightKg: 35, engravingText: "Alpha")
        let k2 = PlateSnapshotService.cacheKey(tierID: 5, weightKg: 35, engravingText: "Beta")
        #expect(k1 != k2)
    }

    @Test("writing and reading a UIImage round-trips correctly")
    @MainActor
    func diskRoundTrip() async throws {
        let service = PlateSnapshotService.shared
        let key = "test_roundtrip_\(UUID().uuidString)"

        let image = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        await service.writeToDisk(image: image, key: key)

        let loaded = service.loadFromDisk(key: key)
        #expect(loaded != nil)

        try? FileManager.default.removeItem(at: service.cacheURL(for: key))
    }

    @Test("cachedImage returns nil for unknown key")
    @MainActor
    func cachedImageMiss() {
        let service = PlateSnapshotService.shared
        let result = service.cachedImage(tierID: 9999, weightKg: 0, engravingText: "MISSING")
        #expect(result == nil)
    }
    @Test("different rendering weights do not alias after decimal truncation")
    @MainActor
    func cacheKeyPreservesWeightPrecision() {
        #expect(PlateSnapshotService.cacheKey(tierID: 5, weightKg: 35.01, engravingText: "A") !=
                PlateSnapshotService.cacheKey(tierID: 5, weightKg: 35.02, engravingText: "A"))
    }

    @Test("legacy cleanup preserves current keys, subdirectories, symlinks and outside files")
    @MainActor
    func legacyCleanupIsScoped() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = root.appendingPathComponent("plate_snapshots")
        let nested = cache.appendingPathComponent("nested")
        try manager.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let outside = root.appendingPathComponent("outside.png")
        let child = nested.appendingPathComponent("old.png")
        let legacy = cache.appendingPathComponent("v2_p5_350_1234.png")
        let current = cache.appendingPathComponent(PlateSnapshotService.cacheKey(
            tierID: 5, weightKg: 35, engravingText: "A", style: .legacy) + ".png")
        let lathe = cache.appendingPathComponent(PlateSnapshotService.cacheKey(
            tierID: 5, weightKg: 35, engravingText: "A", style: .lathe) + ".png")
        for url in [outside, child, legacy, current, lathe] { try Data([42]).write(to: url) }
        let link = cache.appendingPathComponent("link.png")
        try manager.createSymbolicLink(at: link, withDestinationURL: outside)
        try PlateSnapshotService.removeLegacyCacheFiles(in: cache)
        #expect(!manager.fileExists(atPath: legacy.path))
        for url in [outside, child, current, lathe] { #expect(try Data(contentsOf: url) == Data([42])) }
        #expect(try link.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
        #expect(manager.fileExists(atPath: cache.appendingPathComponent(".v3-cleanup-complete").path))
    }

    @Test("successful legacy cleanup is performed only once")
    @MainActor
    func legacyCleanupRunsOnce() throws {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: directory) }
        try PlateSnapshotService.removeLegacyCacheFiles(in: directory)
        let later = directory.appendingPathComponent("later.png")
        try Data([1]).write(to: later)
        try PlateSnapshotService.removeLegacyCacheFiles(in: directory)
        #expect(try Data(contentsOf: later) == Data([1]))
    }

}
