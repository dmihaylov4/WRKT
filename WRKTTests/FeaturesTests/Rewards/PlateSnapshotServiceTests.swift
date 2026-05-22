import Testing
import UIKit
@testable import WRKT

@Suite("PlateSnapshotService cache key and disk I/O")
struct PlateSnapshotServiceTests {

    @Test("cacheKey is stable for same inputs")
    func cacheKeyStable() {
        let k1 = PlateSnapshotService.cacheKey(tierID: 5, weightKg: 35, engravingText: "Volume Champion")
        let k2 = PlateSnapshotService.cacheKey(tierID: 5, weightKg: 35, engravingText: "Volume Champion")
        #expect(k1 == k2)
    }

    @Test("cacheKey differs when tierID changes")
    func cacheKeyVariesByTier() {
        let k1 = PlateSnapshotService.cacheKey(tierID: 5, weightKg: 35, engravingText: "Champion")
        let k2 = PlateSnapshotService.cacheKey(tierID: 6, weightKg: 35, engravingText: "Champion")
        #expect(k1 != k2)
    }

    @Test("cacheKey differs when engravingText changes")
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
}
