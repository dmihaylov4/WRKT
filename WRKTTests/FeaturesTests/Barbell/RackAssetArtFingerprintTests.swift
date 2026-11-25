import CoreGraphics
import CryptoKit
import Foundation
import Testing
@testable import WRKT

/// The safety net for RackAssetDiskCache's version. Cached faces, floors and the studio panorama
/// are kept across app updates as long as `RackAssetDiskCache.version` stays the same, so a change
/// to what they draw must come with a version bump, or users keep the old look from their cache.
///
/// This draws a fixed set of reference faces (one per plate family, with and without lettering),
/// both floor styles and the studio panorama with the shipped settings, shrinks each to 32 by 32
/// and keeps 5 bits a channel (so the test does not depend on the last bit of antialiasing), and
/// compares a digest of all of it with the one recorded for the current version.
///
/// When it fails: if the drawing was meant to change, bump `RackAssetDiskCache.version` and record
/// the digest the failure prints next to it below. If it was not meant to change, the change has
/// moved pixels it should not have.
@MainActor
@Suite struct RackAssetArtFingerprintTests {
    /// The digest each version's art was recorded with (iOS 27 simulator).
    static let recorded: [String: String] = [
        "rack-assets-v4": "df8f15fac764fd037e25f99c4d7f69ae1552bcc289852ef52f7bd2b420725664"
    ]

    @Test func theCachedArtMatchesTheRecordedVersion() throws {
        let digest = try Self.digest()
        let expected = Self.recorded[RackAssetDiskCache.version]
        #expect(expected == digest, """
            The rack's cached art changed. Bump RackAssetDiskCache.version if it was meant to, and record
            "\(RackAssetDiskCache.version)": "\(digest)" (or the new version) in RackAssetArtFingerprintTests.recorded.
            """)
    }

    static func digest() throws -> String {
        var hasher = SHA256()
        for image in try referenceImages() {
            hasher.update(data: fingerprint(image))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func referenceImages() throws -> [CGImage] {
        var images: [CGImage] = []
        // Faces: a bumper, a competition plate, cast iron, a machined metal and an engraved one.
        for (tierID, kg, engraving) in [(14, 20.0, ""), (10, 25.0, ""), (1, 20.0, ""), (6, 45.0, ""), (14, 20.0, "Bench 100")] {
            let tier = try #require(PlateTier.all.first { $0.id == tierID })
            let spec = latheFaceSpec(tier: tier, weightKg: kg, engravingText: engraving,
                                     projection: BarbellPlateRenderProjection(), showEngravings: true)
            let face = try #require(LatheFaceArt.images(for: spec))
            images += [face.color, face.normal, face.roughness]
        }
        for style in RackFloorStyle.allCases {
            let floor = try #require(RackRoomFloorArt.images(style, diskCache: false))
            images += [floor.color, floor.normal]
        }
        // The studio panorama as Release builds it (no overrides; the mood's honeycomb painted in).
        let url = try #require(Bundle.main.url(forResource: RackStudioEnvironment.resourceName,
                                               withExtension: RackStudioEnvironment.resourceExtension))
        let radiance = try #require(RackStudioEnvironment.decode(try Data(contentsOf: url)))
        images.append(try #require(RackStudioEnvironment.panorama(radiance, clamp: RackStudioEnvironment.radianceClamp,
                                                                  yawDegrees: RackStudioEnvironment.bakedYawDegrees,
                                                                  symmetric: true, hex: RackHexPlacement.defaultPlacement)))
        return images
    }

    /// 32 by 32 sRGB pixels, 5 bits a channel.
    static func fingerprint(_ image: CGImage) -> Data {
        let side = 32
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        return Data(bytes.map { $0 >> 3 })
    }
}
