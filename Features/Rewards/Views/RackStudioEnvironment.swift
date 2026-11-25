// Features/Rewards/Views/RackStudioEnvironment.swift
//
// The lathe plates' light probe: a photographic studio with large soft boxes and a dark surround,
// which is what polished metal needs to reflect. Loaded once per process from a Radiance .hdr in
// the app bundle, decoded off the main thread and handed to RealityKit as an equirectangular
// panorama (RealityKit prefilters it). If anything fails the scene keeps the procedural room
// (RackRoomEnvironment).
//
// Why not EnvironmentResource(named:): that initialiser only finds environments Xcode compiled
// from a `<Name>.skybox` folder (realitytool writes `<Name>.realityenv`). A plain .exr or .hdr in
// Resources is copied as is and the lookup throws resourceNotFound, which is why IndoorHDRI.exr
// has never loaded. Wrapping it in IndoorHDRI.skybox/ would fix that lookup, but the compiled
// environment for a 1k map is about 5.3 MB (measured with realitytool), against 1.6 MB for the
// .hdr loaded here.
//
// Asset: "Studio Small 09" by Sergej Majboroda, Poly Haven, 1k Radiance HDR.
// https://polyhaven.com/a/studio_small_09
// https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/1k/studio_small_09_1k.hdr
// Licence: CC0 1.0 (public domain), https://polyhaven.com/license

import CoreGraphics
import Foundation
import os
import RealityKit
import simd

nonisolated enum RackStudioEnvironment {
    static let resourceName = "RackStudio_studio_small_09_1k"
    static let resourceExtension = "hdr"

    /// Clamp for the brightest texels: the bare bulbs in the photo reach several hundred, which
    /// prefiltering turns into sparkle on rough metal. The soft boxes sit around 10 to 40.
    static let radianceClamp: Float = 48

    /// Turn of the studio about the vertical, baked into the panorama's columns (see
    /// panorama(_:clamp:yawDegrees:)). 0 is the orientation every capture was tuned in: plate
    /// faces on the bar then match a plate lying on the floor within about 5 % (rack-mixed
    /// capture), and the room stays as it was. 120 gives a richer gold on the floor but a darker
    /// floor. In debug builds VOLIA_RACK_LIGHT's studioBake overrides it, studioClamp the clamp.
    ///
    /// Why baked: the first prototype turned the light entity instead (90 degrees). The simulator
    /// ignores that transform (captures with and without it are identical), so every capture was
    /// tuned unturned, while the phone appears to apply it: there the soft boxes swung round to
    /// face the plates on the bar, which then read far brighter and paler than plates on the floor.
    static let bakedYawDegrees: Float = 0

    struct Radiance: Sendable {
        let width: Int
        let height: Int
        /// Linear RGB, row major from the top.
        let rgb: [Float]
    }

    /// Decodes a Radiance RGBE file (new style run length encoding or flat), as written by Poly Haven.
    static func decode(_ data: Data) -> Radiance? {
        let bytes = [UInt8](data)
        // Header: lines up to a blank line, then "-Y <h> +X <w>".
        var index = 0
        func line() -> String? {
            guard index < bytes.count else { return nil }
            let start = index
            while index < bytes.count, bytes[index] != 0x0A { index += 1 }
            let text = String(decoding: bytes[start..<index], as: UTF8.self)
            index += 1
            return text
        }
        guard let magic = line(), magic.hasPrefix("#?") else { return nil }
        var format = ""
        while let header = line(), !header.isEmpty {
            if header.hasPrefix("FORMAT=") { format = String(header.dropFirst(7)) }
        }
        guard format.isEmpty || format == "32-bit_rle_rgbe", let size = line() else { return nil }
        let parts = size.split(separator: " ")
        guard parts.count == 4, parts[0] == "-Y", parts[2] == "+X",
              let height = Int(parts[1]), let width = Int(parts[3]), width > 0, height > 0 else { return nil }

        var rgbe = [UInt8](repeating: 0, count: width * height * 4)
        var scan = [UInt8](repeating: 0, count: width * 4)
        for y in 0..<height {
            guard index + 4 <= bytes.count else { return nil }
            if width >= 8, width < 32768, bytes[index] == 2, bytes[index + 1] == 2, bytes[index + 2] & 0x80 == 0 {
                index += 4
                for channel in 0..<4 {
                    var x = 0
                    while x < width {
                        guard index < bytes.count else { return nil }
                        var count = Int(bytes[index]); index += 1
                        if count > 128 {
                            count -= 128
                            guard index < bytes.count, x + count <= width else { return nil }
                            let value = bytes[index]; index += 1
                            for k in 0..<count { scan[(x + k) * 4 + channel] = value }
                        } else {
                            guard count > 0, index + count <= bytes.count, x + count <= width else { return nil }
                            for k in 0..<count { scan[(x + k) * 4 + channel] = bytes[index + k] }
                            index += count
                        }
                        x += count
                    }
                }
            } else {
                // Flat pixels.
                guard index + width * 4 <= bytes.count else { return nil }
                for k in 0..<(width * 4) { scan[k] = bytes[index + k] }
                index += width * 4
            }
            for k in 0..<(width * 4) { rgbe[y * width * 4 + k] = scan[k] }
        }
        var rgb = [Float](repeating: 0, count: width * height * 3)
        for p in 0..<(width * height) {
            let e = rgbe[p * 4 + 3]
            guard e != 0 else { continue }
            let scale = ldexpf(1, Int32(e) - 136)
            rgb[p * 3] = Float(rgbe[p * 4]) * scale
            rgb[p * 3 + 1] = Float(rgbe[p * 4 + 1]) * scale
            rgb[p * 3 + 2] = Float(rgbe[p * 4 + 2]) * scale
        }
        return Radiance(width: width, height: height, rgb: rgb)
    }

    /// A linear float RGBA panorama for EnvironmentResource(equirectangular:), clamped.
    /// `yawDegrees` turns the studio by shifting columns, so the turn is in the pixels themselves
    /// and does not depend on how a renderer treats the light entity's transform.
    ///
    /// `symmetric` averages the studio with its mirror image about the camera's view axis, so the
    /// left and right sleeves (whose plate faces look opposite ways) are lit as mirror images. The
    /// photo has one big soft box off to a side; unmirrored, one sleeve's plates read lighter.
    /// Columns run right to left seen from inside (see RackRoomEnvironment.panorama), with column
    /// 0 behind the viewer and the middle column ahead, so the mirror is a horizontal flip.
    static func panorama(_ radiance: Radiance, clamp: Float = radianceClamp, yawDegrees: Float = 0,
                         symmetric: Bool = true) -> CGImage? {
        let w = radiance.width, h = radiance.height
        let balance = whiteBalance(radiance, clamp: clamp)
        let shift = ((Int((yawDegrees / 360 * Float(w)).rounded()) % w) + w) % w
        var pixels = [Float](repeating: 1, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let p = y * w + x, source = y * w + (x + shift) % w
                let mirror = y * w + (w - 1 - x + shift) % w
                for c in 0..<3 {
                    let direct = min(clamp, radiance.rgb[source * 3 + c] * balance[c])
                    let mirrored = min(clamp, radiance.rgb[mirror * 3 + c] * balance[c])
                    pixels[p * 4 + c] = symmetric ? (direct + mirrored) / 2 : direct
                }
            }
        }
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        guard let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB),
              let provider = CGDataProvider(data: data as CFData) else { return nil }
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue
        return CGImage(width: w, height: h, bitsPerComponent: 32, bitsPerPixel: 128, bytesPerRow: w * 16,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: info), provider: provider, decode: nil,
                       shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Channel gains that make the studio's average light neutral grey. The photo is a little
    /// warm, which tinted pale rooms brown and shifted every plate colour; neutral light keeps the
    /// plates' own colours.
    static func whiteBalance(_ radiance: Radiance, clamp: Float = radianceClamp) -> SIMD3<Float> {
        var sum = SIMD3<Float>(repeating: 0)
        for p in 0..<(radiance.width * radiance.height) {
            sum += simd_min(SIMD3(radiance.rgb[p * 3], radiance.rgb[p * 3 + 1], radiance.rgb[p * 3 + 2]), SIMD3(repeating: clamp))
        }
        guard sum.x > 0, sum.y > 0, sum.z > 0 else { return SIMD3(repeating: 1) }
        let grey = (sum.x + sum.y + sum.z) / 3
        return SIMD3(grey / sum.x, grey / sum.y, grey / sum.z)
    }

    /// The bundled file's panorama, or nil when it is missing or unreadable.
    static func loadPanorama(bundle: Bundle = .main) -> CGImage? {
        guard let url = bundle.url(forResource: resourceName, withExtension: resourceExtension),
              let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let radiance = decode(data) else { return nil }
        var clamp = radianceClamp, yaw = bakedYawDegrees
        #if DEBUG
        let overrides = rackRoomLightingOverrides(ProcessInfo.processInfo.environment["VOLIA_RACK_LIGHT"])
        if let value = overrides["studioClamp"] { clamp = value }
        if let value = overrides["studioBake"] { yaw = value }
        let symmetric = overrides["studioMirror"].map { $0 != 0 } ?? true
        #else
        let symmetric = true
        #endif
        return panorama(radiance, clamp: clamp, yawDegrees: yaw, symmetric: symmetric)
    }
}

// One studio environment per process. Concurrent first callers await the same load.
@MainActor private var _rackStudioEnvironmentTask: Task<EnvironmentResource?, Never>?

@MainActor
func sharedRackStudioEnvironmentResource() async -> EnvironmentResource? {
    if let task = _rackStudioEnvironmentTask { return await task.value }
    let task = Task { @MainActor () -> EnvironmentResource? in
        let interval = barbellSignposter.beginInterval("RackStudioEnvironment", id: barbellSignposter.makeSignpostID())
        defer { barbellSignposter.endInterval("RackStudioEnvironment", interval) }
        guard let panorama = await Task.detached(priority: .userInitiated, operation: {
            RackStudioEnvironment.loadPanorama()
        }).value else { return nil }
        return try? await EnvironmentResource(equirectangular: panorama, withName: "RackStudioEnvironment")
    }
    _rackStudioEnvironmentTask = task
    return await task.value
}
