//
//  CutYearAwardObject.swift
//  WRKT
//
//  The year award as a real object: a thick steel slab with the plaque's cut corner, a 45
//  degree diamond cut chamfer round the face, a brushed face and the year, the mark and the
//  words cut into it. Everything is generated in code: the mesh, the engraving's normal,
//  roughness and tint maps (from the text laid out by SwiftUI), and a soft studio to reflect.
//  CutYearAwardObjectView.swift renders it; the shape and the pose maths live in
//  CutYearAwardModel.swift.
//

import Accelerate
import RealityKit
import SwiftUI
import UIKit

// MARK: - Engraving layout

/// What is cut into the face, laid out in the plaque's points. Drawn as a mask, not shown:
/// red is the deep cut (the year and the mark), green the fine cut (the words).
struct CutYearAwardObjectLayout: View {
    let content: CutYearAwardContent

    static let deepInk = Color(red: 1, green: 0, blue: 0)
    static let fineInk = Color(red: 0, green: 1, blue: 0)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                VMarkShape()
                    .fill(Self.deepInk)
                    .frame(width: 74, height: 46)
            }
            Spacer(minLength: 0)
            Text(content.yearText)
                .font(DS.Cut.Typography.condensed(size: 118, monospacedDigits: true))
                .tracking(1)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.vertical, Self.tightening(size: 118, lineHeight: 0.84))
                .foregroundStyle(Self.deepInk)
            VStack(alignment: .leading, spacing: Self.lineGap(size: 28, lineHeight: 1.0)) {
                ForEach(Array(content.headlineLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(DS.Cut.Typography.condensed(size: 28, relativeTo: .title2))
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .foregroundStyle(Self.fineInk)
            .padding(.top, 12)
            Text(content.objectLine)
                .font(DS.Typography.custom(size: 18, weight: .bold, relativeTo: .body))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .foregroundStyle(Self.fineInk)
                .padding(.top, 18)
        }
        .padding(EdgeInsets(top: 30, leading: 28, bottom: 30, trailing: 28))
        .frame(width: CGFloat(CutYearAwardSlab.width * 1000), height: CGFloat(CutYearAwardSlab.height * 1000),
               alignment: .topLeading)
        .dynamicTypeSize(.large)
        .environment(\.colorScheme, .dark)
    }

    private static func tightening(size: CGFloat, lineHeight: CGFloat) -> CGFloat {
        min(0, (lineHeight - DS.Cut.Typography.naturalLineHeight) * size / 2)
    }

    private static func lineGap(size: CGFloat, lineHeight: CGFloat) -> CGFloat {
        (lineHeight - DS.Cut.Typography.naturalLineHeight) * size
    }
}

// MARK: - Maps

/// The face's maps, as images ready to upload.
struct CutYearAwardFaceMaps: @unchecked Sendable {
    let normal: CGImage
    let roughness: CGImage
    let tint: CGImage
}

enum CutYearAwardFaceMapBuilder {
    /// Pixels across the face. About 3.2 px per point: the face is drawn at most 318 pt wide,
    /// so this matches a 3x screen without wasting memory (6 MB for the normal map).
    static let width = 1024

    /// Lays the engraving out with SwiftUI, so the object uses the app's fonts and the mark.
    @MainActor
    static func mask(for content: CutYearAwardContent) -> CGImage? {
        let renderer = ImageRenderer(content: CutYearAwardObjectLayout(content: content).background(Color.black))
        renderer.scale = CGFloat(width) / CGFloat(CutYearAwardSlab.width * 1000)
        renderer.isOpaque = true
        return renderer.cgImage
    }

    /// Engraving profile, in pixels: the deep cut has 45 degree walls this wide and then a flat
    /// floor; the fine cut is narrow enough that it is a V.
    static let deepSteps = 7
    static let fineSteps = 4

    /// Turns the mask into the face's maps. Pure CPU work, vectorised with Accelerate.
    nonisolated static func maps(mask: CGImage) -> CutYearAwardFaceMaps? {
        let w = mask.width, h = mask.height, n = w * h
        guard w > 8, h > 8 else { return nil }

        // The mask as RGBA bytes, then its red and green channels as floats in 0...1.
        var rgba = [UInt8](repeating: 0, count: n * 4)
        let drawn: Bool = rgba.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.draw(mask, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        let deep = channel(rgba, index: 0, width: w, height: h)
        let fine = channel(rgba, index: 1, width: w, height: h)

        let (deepDepth, deepFloor) = depth(deep, steps: deepSteps, width: w, height: h)
        let (fineDepth, fineFloor) = depth(fine, steps: fineSteps, width: w, height: h)

        // Height: 0 on the face, negative into the cut, one unit per pixel inward (45 degrees).
        var height = [Float](repeating: 0, count: n)
        height = vDSP.multiply(-1, vDSP.add(deepDepth, fineDepth))
        height = convolve(height, width: w, height: h,
                          kernel: [1, 2, 1, 2, 4, 2, 1, 2, 1].map { Float($0) / 16 })

        // Brushing: fine horizontal grain on the face only, not inside the cuts.
        let cut = vDSP.clip(vDSP.add(deep, fine), to: 0...1)
        let face = vDSP.subtract([Float](repeating: 1, count: n), cut)
        let grain = brushGrain(width: w, height: h)
        let faceGrain = vDSP.multiply(grain, face)
        height = vDSP.add(height, faceGrain)

        // Normals from the height's slope. Image rows run down, the texture's v runs up.
        let sobelX: [Float] = [-1, 0, 1, -2, 0, 2, -1, 0, 1].map { $0 / 8 }
        let sobelY: [Float] = [-1, -2, -1, 0, 0, 0, 1, 2, 1].map { $0 / 8 }
        let dx = convolve(height, width: w, height: h, kernel: sobelX)
        let dy = convolve(height, width: w, height: h, kernel: sobelY)
        var nx = vDSP.multiply(-1, dx)
        var ny = dy
        var length = [Float](repeating: 1, count: n)
        length = vDSP.add(length, vDSP.add(vDSP.square(nx), vDSP.square(ny)))
        length = vForce.sqrt(length)
        nx = vDSP.divide(nx, length)
        ny = vDSP.divide(ny, length)
        let nz = vDSP.divide(1, length)

        // Roughness: satin brushed face, polished cut walls, a matte floor in the deep cut.
        let floor = vDSP.add(deepFloor, fineFloor)
        let wall = vDSP.subtract(cut, floor)
        var roughness = vDSP.multiply(Style.faceRoughness, face)
        roughness = vDSP.add(roughness, vDSP.multiply(Style.wallRoughness, wall))
        roughness = vDSP.add(roughness, vDSP.multiply(Style.floorRoughness, floor))
        roughness = vDSP.add(roughness, vDSP.multiply(Style.grainRoughness, faceGrain))
        // The words: frosted over their whole width, not only on a floor.
        roughness = vDSP.add(vDSP.multiply(vDSP.subtract([Float](repeating: 1, count: n), fine), roughness),
                             vDSP.multiply(Style.fineRoughness, fine))
        roughness = vDSP.clip(roughness, to: 0...1)

        // Tint: the cut reflects less of the room than the face around it.
        var tint = [Float](repeating: 1, count: n)
        tint = vDSP.subtract(tint, vDSP.multiply(Style.floorDarkening, floor))
        tint = vDSP.subtract(tint, vDSP.multiply(Style.wallDarkening, wall))
        tint = vDSP.subtract(tint, vDSP.multiply(Style.fineDarkening, fine))

        guard let normalImage = rgbImage(nx, ny, nz, width: w, height: h),
              let roughnessImage = grayImage(roughness, width: w, height: h, scale: 0.5),
              let tintImage = grayImage(tint, width: w, height: h, scale: 0.5) else { return nil }
        return CutYearAwardFaceMaps(normal: normalImage, roughness: roughnessImage, tint: tintImage)
    }

    enum Style {
        static let faceRoughness: Float = 0.17
        static let wallRoughness: Float = 0.12
        static let floorRoughness: Float = 0.55
        static let grainRoughness: Float = 0.5
        static let floorDarkening: Float = 0.34
        static let wallDarkening: Float = 0.06
        /// The words are frosted as well as cut, so they read even when the walls catch no light.
        static let fineDarkening: Float = 0.38
        static let fineRoughness: Float = 0.42
        /// Height of the brush grain, in pixels of depth. Small: the grain is felt in the light,
        /// not seen as lines.
        static let grainDepth: Float = 0.035
    }

    // MARK: Helpers

    private static func channel(_ rgba: [UInt8], index: Int, width: Int, height: Int) -> [Float] {
        var bytes = [UInt8](repeating: 0, count: width * height)
        rgba.withUnsafeBufferPointer { source in
            bytes.withUnsafeMutableBufferPointer { dest in
                for i in 0..<(width * height) { dest[i] = source[i * 4 + index] }
            }
        }
        return vDSP.divide(vDSP.integerToFloatingPoint(bytes, floatingPointType: Float.self), 255)
    }

    /// Approximate distance into the shape, capped at `steps` pixels: the sum of the shape
    /// eroded once, twice, and so on. Alternating square and cross erosions keep the walls
    /// even on diagonals. Also returns the last erosion: the flat floor past the walls.
    private static func depth(_ plane: [Float], steps: Int, width: Int, height: Int) -> ([Float], [Float]) {
        var sum = plane
        var current = plane
        for step in 0..<steps {
            if step.isMultiple(of: 2) {
                current = minimum(current, width: width, height: height, kernelWidth: 3, kernelHeight: 3)
            } else {
                let across = minimum(current, width: width, height: height, kernelWidth: 3, kernelHeight: 1)
                let down = minimum(current, width: width, height: height, kernelWidth: 1, kernelHeight: 3)
                current = vDSP.minimum(across, down)
            }
            sum = vDSP.add(sum, current)
        }
        return (sum, current)
    }

    private static func minimum(_ plane: [Float], width: Int, height: Int, kernelWidth: Int, kernelHeight: Int) -> [Float] {
        var result = [Float](repeating: 0, count: plane.count)
        var source = plane
        source.withUnsafeMutableBytes { src in
            result.withUnsafeMutableBytes { dst in
                var input = vImage_Buffer(data: src.baseAddress, height: vImagePixelCount(height),
                                          width: vImagePixelCount(width), rowBytes: width * 4)
                var output = vImage_Buffer(data: dst.baseAddress, height: vImagePixelCount(height),
                                           width: vImagePixelCount(width), rowBytes: width * 4)
                _ = vImageMin_PlanarF(&input, &output, nil, 0, 0, vImagePixelCount(kernelHeight),
                                      vImagePixelCount(kernelWidth), vImage_Flags(kvImageEdgeExtend))
            }
        }
        return result
    }

    private static func convolve(_ plane: [Float], width: Int, height: Int, kernel: [Float]) -> [Float] {
        var result = [Float](repeating: 0, count: plane.count)
        var source = plane
        source.withUnsafeMutableBytes { src in
            result.withUnsafeMutableBytes { dst in
                var input = vImage_Buffer(data: src.baseAddress, height: vImagePixelCount(height),
                                          width: vImagePixelCount(width), rowBytes: width * 4)
                var output = vImage_Buffer(data: dst.baseAddress, height: vImagePixelCount(height),
                                           width: vImagePixelCount(width), rowBytes: width * 4)
                _ = vImageConvolve_PlanarF(&input, &output, nil, 0, 0, kernel, 3, 3, 0,
                                           vImage_Flags(kvImageEdgeExtend))
            }
        }
        return result
    }

    /// Horizontal brush grain: every row gets its own small height, with a few longer streaks
    /// on top. Seeded, so every award gets the same metal.
    private static func brushGrain(width: Int, height: Int) -> [Float] {
        var seed: UInt64 = 0x5EED_2026
        func next() -> Float {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float(seed >> 40) / Float(1 << 24)
        }
        var grain = [Float](repeating: 0, count: width * height)
        let depth = Style.grainDepth
        grain.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            for row in 0..<height {
                let rowBase = base + row * width
                var value = (next() - 0.5) * depth
                vDSP_vfill(&value, rowBase, 1, vDSP_Length(width))
                for _ in 0..<3 {
                    let start = Int(next() * Float(width))
                    let length = min(width - start, Int(Float(width) * (0.2 + next() * 0.8)))
                    guard length > 0 else { continue }
                    var streak = (next() - 0.5) * depth * 1.6
                    vDSP_vsadd(rowBase + start, 1, &streak, rowBase + start, 1, vDSP_Length(length))
                }
            }
        }
        return grain
    }

    /// Unit normals in -1...1 as an RGBA8 image.
    private static func rgbImage(_ x: [Float], _ y: [Float], _ z: [Float], width: Int, height: Int) -> CGImage? {
        func bytes(_ plane: [Float]) -> [UInt8] {
            let scaled = vDSP.add(127.5, vDSP.multiply(127.5, plane))
            return vDSP.floatingPointToInteger(vDSP.clip(scaled, to: 0...255), integerType: UInt8.self,
                                               rounding: .towardNearestInteger)
        }
        let r = bytes(x), g = bytes(y), b = bytes(z)
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        pixels.withUnsafeMutableBufferPointer { dest in
            for i in 0..<(width * height) {
                dest[i * 4] = r[i]
                dest[i * 4 + 1] = g[i]
                dest[i * 4 + 2] = b[i]
            }
        }
        return image(pixels, width: width, height: height, components: 4)
    }

    /// A 0...1 plane as an 8 bit grey image, optionally scaled down.
    private static func grayImage(_ plane: [Float], width: Int, height: Int, scale: Double) -> CGImage? {
        var bytes = vDSP.floatingPointToInteger(vDSP.clip(vDSP.multiply(255, plane), to: 0...255),
                                                integerType: UInt8.self, rounding: .towardNearestInteger)
        let outWidth = max(1, Int(Double(width) * scale)), outHeight = max(1, Int(Double(height) * scale))
        guard outWidth != width else { return image(bytes, width: width, height: height, components: 1) }
        var scaled = [UInt8](repeating: 0, count: outWidth * outHeight)
        bytes.withUnsafeMutableBytes { src in
            scaled.withUnsafeMutableBytes { dst in
                var input = vImage_Buffer(data: src.baseAddress, height: vImagePixelCount(height),
                                          width: vImagePixelCount(width), rowBytes: width)
                var output = vImage_Buffer(data: dst.baseAddress, height: vImagePixelCount(outHeight),
                                           width: vImagePixelCount(outWidth), rowBytes: outWidth)
                _ = vImageScale_Planar8(&input, &output, nil, vImage_Flags(kvImageHighQualityResampling))
            }
        }
        return image(scaled, width: outWidth, height: outHeight, components: 1)
    }

    private static func image(_ bytes: [UInt8], width: Int, height: Int, components: Int) -> CGImage? {
        let space = components == 1 ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB()
        let info: CGImageAlphaInfo = components == 1 ? .none : .noneSkipLast
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8 * components,
                       bytesPerRow: width * components, space: space, bitmapInfo: CGBitmapInfo(rawValue: info.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

// MARK: - Studio

/// The room the steel reflects: near black, a broad soft light overhead, a tall strip either
/// side of the viewer and a faint fill, so the brushed face shows one calm band of light that
/// sweeps as it turns. Generated as a small HDR panorama.
enum CutYearAwardStudio {
    static let width = 1024

    struct Light {
        /// Centre, in degrees: azimuth round from the viewer (0 is behind the viewer, where the
        /// face looks), positive to the viewer's right; elevation up from the horizon.
        var azimuth: Float
        var elevation: Float
        var width: Float
        var height: Float
        var radiance: Float
        var feather: Float = 6
    }

    static let lights: [Light] = [
        // Up and to the left, for the cut corner's chamfer.
        Light(azimuth: -70, elevation: 48, width: 40, height: 26, radiance: 1.2, feather: 14),
        // The band on the face: a tall strip a little to the viewer's left, where the resting
        // pose looks, so the band crosses the face at rest and sweeps off as it turns.
        Light(azimuth: -14, elevation: 8, width: 8, height: 80, radiance: 3.2, feather: 9),
        // A weaker strip on the right, so turning the other way finds light too.
        Light(azimuth: 30, elevation: 12, width: 14, height: 70, radiance: 1.6, feather: 10),
        // Side lights for the side chamfers and the edge.
        Light(azimuth: -95, elevation: 30, width: 34, height: 76, radiance: 1.4, feather: 16),
        Light(azimuth: 100, elevation: 10, width: 12, height: 50, radiance: 1.0, feather: 8),
        // A faint bounce from the floor, so the bottom edge reads as metal, not a black line.
        Light(azimuth: 0, elevation: -40, width: 360, height: 40, radiance: 0.10, feather: 30),
        // Soft fill behind the viewer, so the face is never black.
        Light(azimuth: 0, elevation: 4, width: 90, height: 40, radiance: 0.20, feather: 30),
    ]

    /// The overhead light: a round soft box round the zenith, which a rectangle in azimuth
    /// and elevation cannot describe. The top chamfer and a face tipped back catch it.
    static let overheadRadius: Float = 38
    static let overheadRadiance: Float = 2.2
    static let overheadFeather: Float = 18

    nonisolated static func panorama() -> CGImage? {
        let w = width, h = width / 2
        var pixels = [Float](repeating: 0, count: w * h * 4)
        pixels.withUnsafeMutableBufferPointer { buffer in
            for row in 0..<h {
                let elevation = (0.5 - (Float(row) + 0.5) / Float(h)) * 180
                // Ambient: a dark room a touch lighter above than below.
                let ambient: Float = elevation > 0 ? 0.025 + 0.02 * elevation / 90 : 0.012
                for column in 0..<w {
                    // The centre of the image looks down -Z, away from the viewer: azimuth 180.
                    // RealityKit's panorama runs right to left seen from inside, so mirror.
                    var azimuth = 360 - ((Float(column) + 0.5) / Float(w)) * 360
                    if azimuth > 180 { azimuth -= 360 }
                    let fromZenith = 90 - elevation
                    let t = min(max((overheadRadius + overheadFeather / 2 - fromZenith) / overheadFeather, 0), 1)
                    var value = ambient + overheadRadiance * t * t * (3 - 2 * t)
                    for light in lights {
                        value += light.radiance * coverage(light, azimuth: azimuth, elevation: elevation)
                    }
                    // A hair cool, as daylight on steel.
                    let index = (row * w + column) * 4
                    buffer[index] = value
                    buffer[index + 1] = value
                    buffer[index + 2] = value * 1.02
                    buffer[index + 3] = 1
                }
            }
        }
        guard let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) else { return nil }
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue
        return pixels.withUnsafeMutableBytes { raw in
            CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 32, bytesPerRow: w * 16,
                      space: space, bitmapInfo: info)?.makeImage()
        }
    }

    /// How much of a soft edged rectangular light covers a direction, 0...1.
    private static func coverage(_ light: Light, azimuth: Float, elevation: Float) -> Float {
        var da = abs(azimuth - light.azimuth)
        if da > 180 { da = 360 - da }
        let de = abs(elevation - light.elevation)
        func edge(_ distance: Float, _ half: Float) -> Float {
            let t = (half + light.feather / 2 - distance) / light.feather
            let c = min(max(t, 0), 1)
            return c * c * (3 - 2 * c)
        }
        return edge(da, light.width / 2) * edge(de, light.height / 2)
    }
}

// MARK: - Mesh

enum CutYearAwardSlabMesh {
    enum Part: UInt32 {
        case face = 0
        case edge = 1
        case back = 2
    }

    /// The slab with flat shaded facets: the face, a 45 degree chamfer round it, the side
    /// walls, a small back chamfer and the back. The face carries planar UVs over the whole
    /// outline (matching the maps) and tangents along x, so the brushing runs across.
    @MainActor
    static func make() throws -> MeshResource {
        let outline = CutYearAwardSlab.outline
        let front = CutYearAwardSlab.inset(outline, by: CutYearAwardSlab.frontChamfer)
        let back = CutYearAwardSlab.inset(outline, by: CutYearAwardSlab.backChamfer)
        let t = CutYearAwardSlab.thickness / 2
        let zFace = t, zFrontEdge = t - CutYearAwardSlab.frontChamfer
        let zBackEdge = -t + CutYearAwardSlab.backChamfer, zBack = -t

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var tangents: [SIMD3<Float>] = []
        var bitangents: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var parts: [UInt32] = []

        let w = CutYearAwardSlab.width, h = CutYearAwardSlab.height
        func faceUV(_ p: SIMD2<Float>) -> SIMD2<Float> { SIMD2(p.x / w + 0.5, p.y / h + 0.5) }

        func addPolygon(_ points: [SIMD2<Float>], z: Float, normal: SIMD3<Float>, part: Part) {
            let start = UInt32(positions.count)
            for p in points {
                positions.append(SIMD3(p.x, p.y, z))
                normals.append(normal)
                uvs.append(faceUV(p))
                tangents.append(SIMD3(normal.z >= 0 ? 1 : -1, 0, 0))
                bitangents.append(SIMD3(0, 1, 0))
            }
            for i in 1..<(points.count - 1) {
                let tri: [UInt32] = normal.z >= 0
                    ? [start, start + UInt32(i), start + UInt32(i + 1)]
                    : [start, start + UInt32(i + 1), start + UInt32(i)]
                indices += tri
                parts.append(part.rawValue)
            }
        }

        /// The face as a fine grid so its normals can carry the crown smoothly. Grid points past
        /// the cut corner are pulled down onto the cut, which keeps the outline exact.
        func addFace(_ polygon: [SIMD2<Float>], z: Float) {
            let minX = polygon.map(\.x).min() ?? 0, maxX = polygon.map(\.x).max() ?? 0
            let minY = polygon.map(\.y).min() ?? 0, maxY = polygon.map(\.y).max() ?? 0
            // The cut runs from polygon[4] (on the leading side) to polygon[3] (on the top).
            let cutStart = polygon[4], cutEnd = polygon[3]
            let columns = 24, rows = 36
            let start = UInt32(positions.count)
            for row in 0...rows {
                for column in 0...columns {
                    var p = SIMD2(minX + (maxX - minX) * Float(column) / Float(columns),
                                  minY + (maxY - minY) * Float(row) / Float(rows))
                    if p.x < cutEnd.x {
                        let t = (p.x - cutStart.x) / (cutEnd.x - cutStart.x)
                        p.y = min(p.y, cutStart.y + (cutEnd.y - cutStart.y) * t)
                    }
                    positions.append(SIMD3(p.x, p.y, z))
                    let normal = CutYearAwardSlab.crownNormal(at: p)
                    normals.append(normal)
                    uvs.append(faceUV(p))
                    let tangent = simd_normalize(SIMD3<Float>(normal.z, 0, -normal.x))
                    tangents.append(tangent)
                    bitangents.append(simd_cross(normal, tangent))
                }
            }
            let stride = UInt32(columns + 1)
            for row in 0..<UInt32(rows) {
                for column in 0..<UInt32(columns) {
                    let a = start + row * stride + column, b = a + 1, c = a + stride + 1, d = a + stride
                    indices += [a, b, c, a, c, d]
                    parts += [Part.face.rawValue, Part.face.rawValue]
                }
            }
        }

        /// One quad per edge between two rings, the first ring nearer the viewer.
        func addBand(_ near: [SIMD2<Float>], _ nearZ: Float, _ far: [SIMD2<Float>], _ farZ: Float, part: Part) {
            let count = near.count
            for i in 0..<count {
                let j = (i + 1) % count
                let a = SIMD3(near[i].x, near[i].y, nearZ), b = SIMD3(near[j].x, near[j].y, nearZ)
                let c = SIMD3(far[j].x, far[j].y, farZ), d = SIMD3(far[i].x, far[i].y, farZ)
                // Counterclockwise outline, far ring behind: (d - a) x (b - a) points outward.
                let normal = simd_normalize(simd_cross(d - a, b - a))
                let along = simd_normalize(b - a)
                let start = UInt32(positions.count)
                let length = simd_length(b - a)
                for (point, uv) in [(a, SIMD2<Float>(0, 1)), (b, SIMD2(length, 1)), (c, SIMD2(length, 0)), (d, SIMD2(0, 0))] {
                    positions.append(point)
                    normals.append(normal)
                    uvs.append(uv)
                    tangents.append(along)
                    bitangents.append(simd_cross(normal, along))
                }
                // Counterclockwise seen from outside, so RealityKit does not cull it.
                indices += [start, start + 3, start + 2, start, start + 2, start + 1]
                parts += [part.rawValue, part.rawValue]
            }
        }

        addFace(front, z: zFace)
        addBand(front, zFace, outline, zFrontEdge, part: .edge)
        addBand(outline, zFrontEdge, outline, zBackEdge, part: .edge)
        addBand(outline, zBackEdge, back, zBack, part: .back)
        addPolygon(back, z: zBack, normal: SIMD3(0, 0, -1), part: .back)

        var descriptor = MeshDescriptor(name: "CutYearAwardSlab")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.tangents = MeshBuffers.Tangents(tangents)
        descriptor.bitangents = MeshBuffers.Tangents(bitangents)
        descriptor.primitives = .triangles(indices)
        descriptor.materials = .perFace(parts)
        return try MeshResource.generate(from: [descriptor])
    }
}

// MARK: - Scene

/// Builds the award object and its studio. The slow parts (the maps and the panorama) run off
/// the main actor; uploading them to RealityKit happens on it.
enum CutYearAwardObjectBuilder {
    struct Scene {
        let object: ModelEntity
        let environment: EnvironmentResource
    }

    /// Steel's own colour: a cool, slightly dark grey, so it reads as steel and not chrome.
    static let steel = UIColor(red: 0.74, green: 0.75, blue: 0.77, alpha: 1)

    @MainActor
    static func build(content: CutYearAwardContent) async throws -> Scene {
        guard let mask = CutYearAwardFaceMapBuilder.mask(for: content) else { throw BuildError.layout }
        async let mapsTask = Task.detached(priority: .userInitiated) {
            CutYearAwardFaceMapBuilder.maps(mask: mask)
        }.value
        async let panoramaTask = Task.detached(priority: .userInitiated) {
            CutYearAwardStudio.panorama()
        }.value
        guard let maps = await mapsTask, let panorama = await panoramaTask else { throw BuildError.maps }

        let environment = try await EnvironmentResource(equirectangular: panorama, withName: "CutYearAwardStudio")
        let normal = try await TextureResource(image: maps.normal, withName: nil,
                                               options: .init(semantic: .normal, mipmapsMode: .allocateAndGenerateAll))
        let roughness = try await TextureResource(image: maps.roughness, withName: nil,
                                                  options: .init(semantic: .scalar, mipmapsMode: .allocateAndGenerateAll))
        let tint = try await TextureResource(image: maps.tint, withName: nil,
                                             options: .init(semantic: .color, mipmapsMode: .allocateAndGenerateAll))

        var face = PhysicallyBasedMaterial()
        face.baseColor = .init(tint: steel, texture: .init(tint))
        face.metallic = 1.0
        face.roughness = .init(scale: 1, texture: .init(roughness))
        face.normal = .init(texture: .init(normal))
        face.anisotropyLevel = 0.4
        face.anisotropyAngle = 0.0

        // Diamond cut: the chamfer and the sides are polished bright.
        var edge = PhysicallyBasedMaterial()
        edge.baseColor = .init(tint: steel)
        edge.metallic = 1.0
        edge.roughness = 0.12

        var back = PhysicallyBasedMaterial()
        back.baseColor = .init(tint: steel)
        back.metallic = 1.0
        back.roughness = 0.42

        let mesh = try CutYearAwardSlabMesh.make()
        let object = ModelEntity(mesh: mesh, materials: [face, edge, back])
        return Scene(object: object, environment: environment)
    }

    enum BuildError: Error {
        case layout
        case maps
    }
}
