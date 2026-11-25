// Features/Rewards/Views/RackAssetDiskCache.swift
//
// On-disk copies of the rack scene's generated images, so a later launch reads them back instead
// of drawing them again: the lathe plates' face images (colour, normal, roughness) and the studio
// environment's processed panorama. Files live in Caches/rack_assets only (the system may purge
// them; nothing here is user data), hold the exact pixel bytes the generators produced (no image
// codec, so a read-back texture is bit-identical to a drawn one) and are bounded by size.
//
// Invalidation: every file name starts with a tag made from RackAssetDiskCache.version, and
// the first write of a process deletes files with any other tag. Files survive app updates that
// leave the drawing alone (they used to carry the build's stamp too, so every update redrew every
// face and the panorama). Bump `version` whenever what the face art, the floor or the studio
// panorama draws changes; RackAssetArtFingerprintTests fails when the drawn pixels change while
// `version` stays the same, so a forgotten bump is caught before it ships.

import CoreGraphics
import CryptoKit
import Foundation
import os
import simd

nonisolated enum RackAssetDiskCache {
    /// Bump when the drawn face art or the processed studio panorama changes.
    static let version = "rack-assets-v4"

    /// Upper bound for the directory; the oldest files go first.
    static let maximumBytes = 32 * 1024 * 1024

    static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("rack_assets", isDirectory: true)
    }

    /// Eight hex digits naming this version in every file name.
    static let versionTag: String = hex(SHA256.hash(data: Data(version.utf8))).prefix(8).description

    static func fileURL(kind: String, identity: String) -> URL {
        let digest = hex(SHA256.hash(data: Data("\(version)|\(kind)|\(identity)".utf8)))
        return directory.appendingPathComponent("\(versionTag)-\(kind)-\(digest).bin")
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    private static let retiredOtherVersions = OSAllocatedUnfairLock(initialState: false)

    /// Deletes files another version wrote (and files from builds that still tagged their files
    /// with the build). Once per process, on the first write.
    static func removeOtherVersions(in folder: URL = directory, keeping tag: String = versionTag) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        for file in files where !file.lastPathComponent.hasPrefix(tag + "-") {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// The file's bytes, LZFSE-decompressed.
    static func read(_ url: URL) -> Data? {
        guard let stored = try? Data(contentsOf: url, options: .mappedIfSafe),
              let data = try? (stored as NSData).decompressed(using: .lzfse) as Data else { return nil }
        // Mark it used, so pruning keeps it over older files.
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return data
    }

    /// Writes the bytes LZFSE-compressed, then prunes the directory.
    static func write(_ data: Data, to url: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let stored = try? (data as NSData).compressed(using: .lzfse) as Data,
              (try? stored.write(to: url, options: .atomic)) != nil else { return }
        let first = retiredOtherVersions.withLock { done in
            defer { done = true }
            return !done
        }
        if first { removeOtherVersions() }
        prune()
    }

    /// Deletes the least recently used files until the directory fits in `maximumBytes`.
    static func prune(in folder: URL = directory, maximumBytes: Int = maximumBytes) {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else { return }
        var entries = files.compactMap { url -> (url: URL, size: Int, date: Date)? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }
        var total = entries.reduce(0) { $0 + $1.size }
        guard total > maximumBytes else { return }
        entries.sort { $0.date < $1.date }
        for entry in entries where total > maximumBytes {
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
        }
    }
}

// MARK: - Lathe faces

extension LatheFaceSpec {
    /// Every field, spelled out with exact float bits, so equal specs give equal keys across
    /// launches (Hashable's hash is seeded per process).
    nonisolated var diskIdentity: String {
        func bits(_ v: Float) -> String { String(v.bitPattern, radix: 16) }
        func bits(_ v: SIMD3<Float>) -> String { "\(bits(v.x)),\(bits(v.y)),\(bits(v.z))" }
        return [
            family.rawValue, bits(base), bits(letter), "\(accentRings)", weightLabel, engraving,
            "\(raised)", bits(roughness), bits(letterRoughness), "\(surface)", bits(outerRadius),
            bits(faceInnerRadius), bits(faceOuterRadius), "\(LatheFaceArt.side)"
        ].joined(separator: "|")
    }
}

nonisolated enum LatheFaceDiskCache {
    private static let kind = "face"

    /// The cached images for this spec, or nil.
    static func images(for spec: LatheFaceSpec) -> LatheFaceArt.Images? {
        let n = LatheFaceArt.side, plane = n * n * 4
        guard let data = RackAssetDiskCache.read(RackAssetDiskCache.fileURL(kind: kind, identity: spec.diskIdentity)),
              data.count == plane * 3 else { return nil }
        let bytes = [UInt8](data)
        guard let color = LatheFaceArt.rgbaImage(Array(bytes[0..<plane]), side: n, space: CGColorSpace(name: CGColorSpace.sRGB)),
              let normal = LatheFaceArt.rgbaImage(Array(bytes[plane..<(2 * plane)]), side: n, space: CGColorSpaceCreateDeviceRGB()),
              let rough = LatheFaceArt.rgbaImage(Array(bytes[(2 * plane)...]), side: n, space: CGColorSpaceCreateDeviceRGB()) else { return nil }
        return LatheFaceArt.Images(color: color, normal: normal, roughness: rough)
    }

    /// Stores the three images' pixel bytes. Skipped if any image is not the expected layout.
    static func store(_ images: LatheFaceArt.Images, for spec: LatheFaceSpec) {
        let n = LatheFaceArt.side
        var data = Data(capacity: n * n * 4 * 3)
        for image in [images.color, images.normal, images.roughness] {
            guard image.width == n, image.height == n, image.bitsPerPixel == 32, image.bytesPerRow == n * 4,
                  let bytes = image.dataProvider?.data as Data?, bytes.count == n * n * 4 else { return }
            data.append(bytes)
        }
        RackAssetDiskCache.write(data, to: RackAssetDiskCache.fileURL(kind: kind, identity: spec.diskIdentity))
    }
}

// MARK: - Studio panorama

/// Carries a finished, immutable panorama into a background store.
nonisolated struct RackStudioPanoramaBox: @unchecked Sendable {
    let image: CGImage
}

nonisolated enum RackStudioPanoramaDiskCache {
    private static let kind = "studio"

    /// Width, height and every setting the processed panorama depends on.
    static func identity(sourceBytes: Int, clamp: Float, yawDegrees: Float, symmetric: Bool, hex: RackHexPlacement? = nil) -> String {
        "\(RackStudioEnvironment.resourceName)|\(sourceBytes)|\(String(clamp.bitPattern, radix: 16))|\(String(yawDegrees.bitPattern, radix: 16))|\(symmetric)|\(hex.map { "\($0)@\(String(RackHexFixture.signHeight.bitPattern, radix: 16))" } ?? "none")"
    }

    static func url(identity: String) -> URL {
        RackAssetDiskCache.fileURL(kind: kind, identity: identity)
    }

    /// The cached panorama, rebuilt with the same layout RackStudioEnvironment.panorama uses.
    static func image(identity: String) -> CGImage? {
        guard let data = RackAssetDiskCache.read(RackAssetDiskCache.fileURL(kind: kind, identity: identity)),
              data.count > 8 else { return nil }
        let width = Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: Int32.self) })
        let height = Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: Int32.self) })
        let pixels = data.subdata(in: 8..<data.count)
        guard width > 0, height > 0, pixels.count == width * height * 16,
              let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB),
              let provider = CGDataProvider(data: pixels as CFData) else { return nil }
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue
        return CGImage(width: width, height: height, bitsPerComponent: 32, bitsPerPixel: 128, bytesPerRow: width * 16,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: info), provider: provider, decode: nil,
                       shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Stores a panorama made by RackStudioEnvironment.panorama (float RGBA, 16 bytes a pixel).
    static func store(_ image: CGImage, identity: String) {
        guard image.bitsPerPixel == 128, image.bytesPerRow == image.width * 16,
              let pixels = image.dataProvider?.data as Data?, pixels.count == image.width * image.height * 16 else { return }
        var data = Data(capacity: pixels.count + 8)
        withUnsafeBytes(of: Int32(image.width)) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: Int32(image.height)) { data.append(contentsOf: $0) }
        data.append(pixels)
        RackAssetDiskCache.write(data, to: RackAssetDiskCache.fileURL(kind: kind, identity: identity))
    }
}
