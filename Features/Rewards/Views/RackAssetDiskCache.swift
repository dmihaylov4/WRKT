// Features/Rewards/Views/RackAssetDiskCache.swift
//
// On-disk copies of the rack scene's generated images, so a later launch reads them back instead
// of drawing them again: the lathe plates' face images (colour, normal, roughness) and the studio
// environment's processed panorama. Files live in Caches/rack_assets only (the system may purge
// them; nothing here is user data), hold the exact pixel bytes the generators produced (no image
// codec, so a read-back texture is bit-identical to a drawn one) and are bounded by size.
//
// Invalidation: every key starts with RackAssetDiskCache.version and the build stamp of the binary
// that drew it. Bump `version` whenever what the face art or the studio panorama draws changes
// (lettering, colours, rings, normal strength, clamp, white balance...). The build stamp also
// retires every file after each new install (the first write of a process deletes other builds'
// files), so a forgotten bump costs at most one stale look within one build.

import CoreGraphics
import CryptoKit
import Foundation
import os
import simd

nonisolated enum RackAssetDiskCache {
    /// Bump when the drawn face art or the processed studio panorama changes.
    static let version = "rack-assets-v1"

    /// Upper bound for the directory; the oldest files go first.
    static let maximumBytes = 32 * 1024 * 1024

    static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("rack_assets", isDirectory: true)
    }

    /// Size and modification date of the image that holds this code (the debug dylib in Debug
    /// builds, the app binary in Release): changes with every build.
    static let buildStamp: String = {
        var info = Dl_info()
        guard dladdr(#dsohandle, &info) != 0, let path = info.dli_fname,
              let attributes = try? FileManager.default.attributesOfItem(atPath: String(cString: path)) else { return "unknown" }
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let date = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(size)-\(Int64(date * 1000))"
    }()

    /// Eight hex digits naming this version and build in every file name.
    static let buildTag: String = hex(SHA256.hash(data: Data("\(version)|\(buildStamp)".utf8))).prefix(8).description

    static func fileURL(kind: String, identity: String) -> URL {
        let digest = hex(SHA256.hash(data: Data("\(version)|\(buildStamp)|\(kind)|\(identity)".utf8)))
        return directory.appendingPathComponent("\(buildTag)-\(kind)-\(digest).bin")
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    private static let retiredOtherBuilds = OSAllocatedUnfairLock(initialState: false)

    /// Deletes files another version or build wrote. Once per process, on the first write.
    static func removeOtherBuilds(in folder: URL = directory, keeping tag: String = buildTag) {
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
        let first = retiredOtherBuilds.withLock { done in
            defer { done = true }
            return !done
        }
        if first { removeOtherBuilds() }
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
    static func identity(sourceBytes: Int, clamp: Float, yawDegrees: Float, symmetric: Bool) -> String {
        "\(RackStudioEnvironment.resourceName)|\(sourceBytes)|\(String(clamp.bitPattern, radix: 16))|\(String(yawDegrees.bitPattern, radix: 16))|\(symmetric)"
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
