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
import OSLog
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

    static let inset = EdgeInsets(top: 30, leading: 28, bottom: 30, trailing: 28)
    /// The top of the year's digits, in points from the top of the face. The year is the
    /// face's centre of gravity, a little above the middle; the words sit under it and leave
    /// a calm margin at the bottom.
    static let yearTop: CGFloat = 150

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The mark keeps its corner, clear of the cut one, without pushing the text down.
            VMarkShape()
                .fill(Self.deepInk)
                .frame(width: 74, height: 46)
                .frame(maxWidth: .infinity, alignment: .topTrailing)
            VStack(alignment: .leading, spacing: 0) {
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
                .padding(.top, 14)
                Text(content.objectLine)
                    .font(DS.Typography.custom(size: 18, weight: .bold, relativeTo: .body))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(Self.fineInk)
                    .padding(.top, 16)
            }
            .padding(.top, Self.yearTop - Self.inset.top)
        }
        .padding(Self.inset)
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

/// Float planes allocated once and reused, so building the maps does not churn through large
/// temporary arrays. Freed when the pool goes.
private final class CutYearAwardPlanes {
    let count: Int
    private let planes: [UnsafeMutablePointer<Float>]

    init(count: Int, planes number: Int) {
        self.count = count
        planes = (0..<number).map { _ in
            let plane = UnsafeMutablePointer<Float>.allocate(capacity: count)
            plane.initialize(repeating: 0, count: count)
            return plane
        }
    }

    subscript(index: Int) -> UnsafeMutablePointer<Float> { planes[index] }

    deinit { planes.forEach { $0.deallocate() } }
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

    enum Style {
        /// The deep cut (the year and the mark): walls this many pixels wide, steeper than 45
        /// degrees so the lip and the wall separate, then a flat floor.
        static let deepSteps = 7
        static let deepSlope: Float = 1.5
        /// The words: narrow enough that the cut is a V.
        static let fineSteps = 4
        static let fineSlope: Float = 1.2
        /// How far into the floor the corner darkening reaches, in pixels.
        static let occlusionSteps = 6

        static let faceRoughness: Float = 0.17
        /// The cut walls are left polished by the cutter: the bright lip.
        static let wallRoughness: Float = 0.08
        /// The floor is bead blasted: a fine matte stipple against the brushed face.
        static let floorRoughness: Float = 0.5
        static let fineRoughness: Float = 0.36

        static let floorDarkening: Float = 0.3
        static let wallDarkening: Float = 0.04
        static let fineDarkening: Float = 0.5
        /// Darkening of the floor where it meets the walls.
        static let occlusion: Float = 0.35
        /// The shadow the upper wall casts on the floor: the light comes from above and a
        /// little to the left, so the shadow falls down and a little right.
        static let shadow: Float = 0.5
        static let shadowOffset = (x: 2, y: 13)

        /// Height of the brush grain, in pixels of depth. Small: the grain is felt in the light,
        /// not seen as lines.
        static let grainDepth: Float = 0.035
        /// Height of the bead blast stipple on the floor.
        static let blastDepth: Float = 0.22
    }

    /// Turns the mask into the face's maps. Pure CPU work, vectorised with Accelerate, in a
    /// fixed set of reused planes: about 60 MB at the peak instead of a new array per step.
    nonisolated static func maps(mask: CGImage) -> CutYearAwardFaceMaps? {
        let w = mask.width, h = mask.height, n = w * h
        guard w > 8, h > 8 else { return nil }
        let p = CutYearAwardPlanes(count: n, planes: 7)
        let deep = p[0], fine = p[1], height = p[2], current = p[3], a = p[4], b = p[5], floor = p[6]
        let length = vDSP_Length(n)

        guard split(mask, red: deep, green: fine, width: w, height: h) else { return nil }

        // Height: 0 on the face, negative into the cut. Each erosion adds one pixel of depth:
        // the sum is a distance into the shape, capped at the wall width.
        func accumulate(_ plane: UnsafeMutablePointer<Float>, steps: Int, slope: Float) {
            current.update(from: plane, count: n)
            var s = slope
            vDSP_vsma(current, 1, &s, height, 1, height, 1, length)
            for step in 0..<steps {
                erode(current, into: a, scratch: b, step: step, width: w, height: h)
                current.update(from: a, count: n)
                vDSP_vsma(current, 1, &s, height, 1, height, 1, length)
            }
        }
        accumulate(deep, steps: Style.deepSteps, slope: Style.deepSlope)
        // What is left after the walls is the deep cut's floor.
        floor.update(from: current, count: n)
        accumulate(fine, steps: Style.fineSteps, slope: Style.fineSlope)
        vDSP_vneg(height, 1, height, 1, length)
        // A light smoothing: enough to hide the erosion steps, not enough to round the lip.
        convolve(height, into: a, kernel: [0, 1, 0, 1, 4, 1, 0, 1, 0].map { $0 / 8 }, width: w, height: h)
        height.update(from: a, count: n)

        // Brush grain on the face, bead blast on the floor.
        addSurface(to: height, deep: deep, fine: fine, floor: floor, width: w, height: h)

        // Roughness and tint first, while the planes they need are still there.
        guard let roughness = roughnessImage(deep: deep, fine: fine, floor: floor, into: a, cut: b,
                                             width: w, height: h),
              let tint = tintImage(deep: deep, fine: fine, floor: floor, into: a, scratch: b, current: current,
                                   width: w, height: h),
              let normal = normalImage(height: height, planes: (deep, fine, a, b), width: w, height: h) else {
            return nil
        }
        return CutYearAwardFaceMaps(normal: normal, roughness: roughness, tint: tint)
    }

    // MARK: Steps

    private static let blur: [Float] = [1, 2, 1, 2, 4, 2, 1, 2, 1].map { $0 / 16 }

    /// The mask's red and green channels as floats in 0...1.
    private static func split(_ mask: CGImage, red: UnsafeMutablePointer<Float>, green: UnsafeMutablePointer<Float>,
                              width w: Int, height h: Int) -> Bool {
        let rgba = UnsafeMutablePointer<UInt8>.allocate(capacity: w * h * 4)
        let channel = UnsafeMutablePointer<UInt8>.allocate(capacity: w * h)
        defer { rgba.deallocate(); channel.deallocate() }
        guard let context = CGContext(data: rgba, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
        context.draw(mask, in: CGRect(x: 0, y: 0, width: w, height: h))
        var source = vImage_Buffer(data: rgba, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: w * 4)
        var bytes = vImage_Buffer(data: channel, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: w)
        for (index, plane) in [(0, red), (1, green)] {
            var floats = buffer(plane, width: w, height: h)
            vImageExtractChannel_ARGB8888(&source, &bytes, index, vImage_Flags(kvImageNoFlags))
            vImageConvert_Planar8toPlanarF(&bytes, &floats, 1, 0, vImage_Flags(kvImageNoFlags))
        }
        return true
    }

    /// One erosion step. Alternating square and cross keeps the walls even on diagonals.
    private static func erode(_ source: UnsafeMutablePointer<Float>, into dest: UnsafeMutablePointer<Float>,
                              scratch: UnsafeMutablePointer<Float>, step: Int, width w: Int, height h: Int) {
        var input = buffer(source, width: w, height: h)
        var output = buffer(dest, width: w, height: h)
        let flags = vImage_Flags(kvImageEdgeExtend)
        if step.isMultiple(of: 2) {
            vImageMin_PlanarF(&input, &output, nil, 0, 0, 3, 3, flags)
        } else {
            var other = buffer(scratch, width: w, height: h)
            vImageMin_PlanarF(&input, &output, nil, 0, 0, 1, 3, flags)
            vImageMin_PlanarF(&input, &other, nil, 0, 0, 3, 1, flags)
            vDSP_vmin(dest, 1, scratch, 1, dest, 1, vDSP_Length(w * h))
        }
    }

    private static func convolve(_ source: UnsafeMutablePointer<Float>, into dest: UnsafeMutablePointer<Float>,
                                 kernel: [Float], width w: Int, height h: Int) {
        var input = buffer(source, width: w, height: h)
        var output = buffer(dest, width: w, height: h)
        vImageConvolve_PlanarF(&input, &output, nil, 0, 0, kernel, 3, 3, 0, vImage_Flags(kvImageEdgeExtend))
    }

    private static func buffer(_ plane: UnsafeMutablePointer<Float>, width w: Int, height h: Int) -> vImage_Buffer {
        vImage_Buffer(data: plane, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: w * 4)
    }

    /// Adds the brush grain to the face and the bead blast to the deep floor, a row at a time.
    /// Seeded, so every award gets the same metal.
    private static func addSurface(to height: UnsafeMutablePointer<Float>, deep: UnsafeMutablePointer<Float>,
                                   fine: UnsafeMutablePointer<Float>, floor: UnsafeMutablePointer<Float>,
                                   width w: Int, height h: Int) {
        var seed: UInt64 = 0x5EED_2026
        func next() -> Float {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float(seed >> 40) / Float(1 << 24)
        }
        // A small tile of soft noise for the blast, repeated across the floor.
        let tileSize = 64
        var tile = [Float](repeating: 0, count: tileSize * tileSize)
        for i in tile.indices { tile[i] = next() - 0.5 }
        var soft = tile
        for y in 0..<tileSize {
            for x in 0..<tileSize {
                var sum: Float = 0
                for dy in -1...1 {
                    for dx in -1...1 {
                        sum += tile[((y + dy + tileSize) % tileSize) * tileSize + (x + dx + tileSize) % tileSize]
                    }
                }
                soft[y * tileSize + x] = sum / 9 * Style.blastDepth * 3
            }
        }
        let row = UnsafeMutablePointer<Float>.allocate(capacity: w)
        let face = UnsafeMutablePointer<Float>.allocate(capacity: w)
        defer { row.deallocate(); face.deallocate() }
        let count = vDSP_Length(w)
        var one: Float = 1, minusOne: Float = -1, zero: Float = 0
        for y in 0..<h {
            let offset = y * w
            // Grain: one height per row plus a few longer streaks.
            var value = (next() - 0.5) * Style.grainDepth
            vDSP_vfill(&value, row, 1, count)
            for _ in 0..<3 {
                let start = Int(next() * Float(w))
                let span = min(w - start, Int(Float(w) * (0.2 + next() * 0.8)))
                guard span > 0 else { continue }
                var streak = (next() - 0.5) * Style.grainDepth * 1.6
                vDSP_vsadd(row + start, 1, &streak, row + start, 1, vDSP_Length(span))
            }
            // Only on the face: 1 - (deep + fine), clipped.
            vDSP_vadd(deep + offset, 1, fine + offset, 1, face, 1, count)
            vDSP_vclip(face, 1, &zero, &one, face, 1, count)
            vDSP_vsmsa(face, 1, &minusOne, &one, face, 1, count)
            vDSP_vma(row, 1, face, 1, height + offset, 1, height + offset, 1, count)
            // Blast: the tile's row, repeated, only on the floor.
            soft.withUnsafeBufferPointer { source in
                guard let base = source.baseAddress else { return }
                let tileRow = base + (y % tileSize) * tileSize
                var x = 0
                while x < w {
                    let span = min(tileSize, w - x)
                    (row + x).update(from: tileRow, count: span)
                    x += span
                }
            }
            vDSP_vma(row, 1, floor + offset, 1, height + offset, 1, height + offset, 1, count)
        }
    }

    /// Satin brushed face, polished walls, a matte blasted floor, frosted words.
    private static func roughnessImage(deep: UnsafeMutablePointer<Float>, fine: UnsafeMutablePointer<Float>,
                                       floor: UnsafeMutablePointer<Float>, into out: UnsafeMutablePointer<Float>,
                                       cut: UnsafeMutablePointer<Float>, width w: Int, height h: Int) -> CGImage? {
        let n = vDSP_Length(w * h)
        var zero: Float = 0, one: Float = 1
        vDSP_vadd(deep, 1, fine, 1, cut, 1, n)
        vDSP_vclip(cut, 1, &zero, &one, cut, 1, n)
        var wallStep = Style.wallRoughness - Style.faceRoughness, face = Style.faceRoughness
        vDSP_vsmsa(cut, 1, &wallStep, &face, out, 1, n)
        var floorStep = Style.floorRoughness - Style.wallRoughness
        vDSP_vsma(floor, 1, &floorStep, out, 1, out, 1, n)
        var fineStep = Style.fineRoughness - Style.wallRoughness
        vDSP_vsma(fine, 1, &fineStep, out, 1, out, 1, n)
        vDSP_vclip(out, 1, &zero, &one, out, 1, n)
        return grayImage(out, width: w, height: h)
    }

    /// How much of the room each point reflects: less in the cut, less again in the floor's
    /// corners and under the upper wall's shadow.
    private static func tintImage(deep: UnsafeMutablePointer<Float>, fine: UnsafeMutablePointer<Float>,
                                  floor: UnsafeMutablePointer<Float>, into out: UnsafeMutablePointer<Float>,
                                  scratch: UnsafeMutablePointer<Float>, current: UnsafeMutablePointer<Float>,
                                  width w: Int, height h: Int) -> CGImage? {
        let count = w * h, n = vDSP_Length(count)
        var one: Float = 1, minusOne: Float = -1, zero: Float = 0
        vDSP_vfill(&one, out, 1, n)
        var wall = -Style.wallDarkening
        vDSP_vsma(deep, 1, &wall, out, 1, out, 1, n)
        var floorDark = -(Style.floorDarkening - Style.wallDarkening)
        vDSP_vsma(floor, 1, &floorDark, out, 1, out, 1, n)
        var fineDark = -Style.fineDarkening
        vDSP_vsma(fine, 1, &fineDark, out, 1, out, 1, n)

        // The upper wall and the floor under it are in shadow: the light comes from above.
        // A point is shaded when the point up and a little to the left of it is still inside
        // the cut, short of the shift: the shadow covers the upper wall and falls a few pixels
        // onto the floor below it.
        let blurred = UnsafeMutablePointer<Float>.allocate(capacity: count)
        defer { blurred.deallocate() }
        vDSP_vclr(scratch, 1, n)
        let (dx, dy) = Style.shadowOffset
        for y in dy..<h {
            (scratch + y * w + dx).update(from: deep + (y - dy) * w, count: w - dx)
        }
        // Shadow = deep * (1 - shifted deep).
        vDSP_vsmsa(scratch, 1, &minusOne, &one, scratch, 1, n)
        vDSP_vmul(scratch, 1, deep, 1, scratch, 1, n)
        convolve(scratch, into: blurred, kernel: blur, width: w, height: h)
        convolve(blurred, into: scratch, kernel: blur, width: w, height: h)
        var shadow = -Style.shadow
        vDSP_vsma(scratch, 1, &shadow, out, 1, out, 1, n)

        // Corner darkening: how far into the floor a point is, from further erosions of it.
        vDSP_vclr(scratch, 1, n)
        current.update(from: floor, count: count)
        for step in 0..<Style.occlusionSteps {
            erode(current, into: blurred, scratch: deep, step: step, width: w, height: h)
            current.update(from: blurred, count: count)
            vDSP_vadd(scratch, 1, current, 1, scratch, 1, n)
        }
        // scratch is now 0 at the floor's edge rising to occlusionSteps inside it.
        var inverse = -1 / Float(Style.occlusionSteps)
        vDSP_vsmsa(scratch, 1, &inverse, &one, scratch, 1, n)
        vDSP_vmul(scratch, 1, floor, 1, scratch, 1, n)
        var occlusion = -Style.occlusion
        vDSP_vsma(scratch, 1, &occlusion, out, 1, out, 1, n)
        vDSP_vclip(out, 1, &zero, &one, out, 1, n)
        return grayImage(out, width: w, height: h)
    }

    /// Unit normals from the height's slope, as an RGBA8 image. Image rows run down, the
    /// texture's v runs up.
    private static func normalImage(height: UnsafeMutablePointer<Float>,
                                    planes: (UnsafeMutablePointer<Float>, UnsafeMutablePointer<Float>,
                                             UnsafeMutablePointer<Float>, UnsafeMutablePointer<Float>),
                                    width w: Int, height h: Int) -> CGImage? {
        let (nx, ny, nz, length) = planes
        let count = w * h, n = vDSP_Length(count)
        convolve(height, into: nx, kernel: [-1, 0, 1, -2, 0, 2, -1, 0, 1].map { $0 / 8 }, width: w, height: h)
        convolve(height, into: ny, kernel: [-1, -2, -1, 0, 0, 0, 1, 2, 1].map { $0 / 8 }, width: w, height: h)
        var one: Float = 1, nCount = Int32(count)
        vDSP_vsq(nx, 1, length, 1, n)
        vDSP_vma(ny, 1, ny, 1, length, 1, length, 1, n)
        vDSP_vsadd(length, 1, &one, length, 1, n)
        vvsqrtf(length, length, &nCount)
        vDSP_vdiv(length, 1, nx, 1, nx, 1, n)
        vDSP_vneg(nx, 1, nx, 1, n)
        vDSP_vdiv(length, 1, ny, 1, ny, 1, n)
        vDSP_svdiv(&one, length, 1, nz, 1, n)

        let planes8 = (0..<4).map { _ in UnsafeMutablePointer<UInt8>.allocate(capacity: count) }
        defer { planes8.forEach { $0.deallocate() } }
        var buffers = planes8.map {
            vImage_Buffer(data: $0, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: w)
        }
        for (index, plane) in [nx, ny, nz].enumerated() {
            var floats = buffer(plane, width: w, height: h)
            vImageConvert_PlanarFtoPlanar8(&floats, &buffers[index], 1, -1, vImage_Flags(kvImageNoFlags))
        }
        planes8[3].initialize(repeating: 255, count: count)
        let pixels = UnsafeMutablePointer<UInt8>.allocate(capacity: count * 4)
        var output = vImage_Buffer(data: pixels, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: w * 4)
        // Memory order follows the argument order: red, green, blue, then the opaque alpha.
        vImageConvert_Planar8toARGB8888(&buffers[0], &buffers[1], &buffers[2], &buffers[3], &output,
                                        vImage_Flags(kvImageNoFlags))
        return image(owning: pixels, width: w, height: h, components: 4)
    }

    /// A 0...1 plane as an 8 bit grey image at half size: roughness and tint change slowly.
    private static func grayImage(_ plane: UnsafeMutablePointer<Float>, width w: Int, height h: Int) -> CGImage? {
        let full = UnsafeMutablePointer<UInt8>.allocate(capacity: w * h)
        defer { full.deallocate() }
        var floats = buffer(plane, width: w, height: h)
        var bytes = vImage_Buffer(data: full, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: w)
        vImageConvert_PlanarFtoPlanar8(&floats, &bytes, 1, 0, vImage_Flags(kvImageNoFlags))
        let outWidth = w / 2, outHeight = h / 2
        let half = UnsafeMutablePointer<UInt8>.allocate(capacity: outWidth * outHeight)
        var output = vImage_Buffer(data: half, height: vImagePixelCount(outHeight), width: vImagePixelCount(outWidth),
                                   rowBytes: outWidth)
        vImageScale_Planar8(&bytes, &output, nil, vImage_Flags(kvImageHighQualityResampling))
        return image(owning: half, width: outWidth, height: outHeight, components: 1)
    }

    /// Wraps pixels in an image without copying them; the image frees them.
    private static func image(owning pixels: UnsafeMutablePointer<UInt8>, width: Int, height: Int,
                              components: Int) -> CGImage? {
        let space = components == 1 ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB()
        let info: CGImageAlphaInfo = components == 1 ? .none : .noneSkipLast
        let size = width * height * components
        let data = Data(bytesNoCopy: pixels, count: size, deallocator: .custom { pointer, _ in pointer.deallocate() })
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8 * components,
                       bytesPerRow: width * components, space: space, bitmapInfo: CGBitmapInfo(rawValue: info.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

// MARK: - Studio

/// The room the steel reflects: a soft lit room rather than a black void, a round light
/// overhead, a tall strip either side of the viewer, side and floor light for the chamfers,
/// so the face is clean bright steel with one band of light that sweeps as it turns and the
/// edges always catch something. Generated as a small HDR panorama.
enum CutYearAwardStudio {
    /// Soft lights need little resolution; the polished chamfers still show clean edges.
    static let width = 512

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
        Light(azimuth: -70, elevation: 48, width: 40, height: 26, radiance: 1.3, feather: 14),
        // The band on the face: a tall strip a little to the viewer's left, where the resting
        // pose looks, so the band crosses the face at rest and sweeps off as it turns.
        Light(azimuth: -14, elevation: 8, width: 8, height: 80, radiance: 3.0, feather: 9),
        // A weaker strip on the right, so turning the other way finds light too.
        Light(azimuth: 30, elevation: 12, width: 14, height: 70, radiance: 1.6, feather: 10),
        // Side lights for the side chamfers: a rim that keeps the silhouette off the black.
        Light(azimuth: -95, elevation: 25, width: 40, height: 90, radiance: 1.5, feather: 18),
        Light(azimuth: 95, elevation: 20, width: 34, height: 80, radiance: 1.3, feather: 18),
        // Behind the object, for the side walls when the turn shows them.
        Light(azimuth: 180, elevation: 10, width: 140, height: 40, radiance: 0.6, feather: 30),
        // Light off the floor, so the bottom edge reads as metal.
        Light(azimuth: 0, elevation: -40, width: 360, height: 50, radiance: 0.45, feather: 30),
        // The ground right under the object: the bottom chamfer looks almost straight down, so
        // without this it drops to near black and the bottom edge merges with the background.
        Light(azimuth: 0, elevation: -80, width: 360, height: 24, radiance: 0.45, feather: 20),
        // Broad fill behind the viewer: the face never drops to dark grey, so the cut words
        // always read darker than the steel round them.
        Light(azimuth: 0, elevation: 6, width: 120, height: 60, radiance: 0.55, feather: 40),
    ]

    /// The overhead light: a round soft box round the zenith, which a rectangle in azimuth
    /// and elevation cannot describe. The top chamfer and a face tipped back catch it.
    static let overheadRadius: Float = 38
    static let overheadRadiance: Float = 2.4
    static let overheadFeather: Float = 18

    /// Every light is a product of an azimuth profile and an elevation profile, so the image
    /// is built a row at a time with vector adds rather than a loop over every pixel.
    nonisolated static func panorama() -> CGImage? {
        let w = width, h = width / 2
        let columns: [[Float]] = lights.map { light in
            (0..<w).map { column in
                // RealityKit's panorama runs right to left seen from inside, so mirror.
                var azimuth = 360 - ((Float(column) + 0.5) / Float(w)) * 360
                if azimuth > 180 { azimuth -= 360 }
                var distance = abs(azimuth - light.azimuth)
                if distance > 180 { distance = 360 - distance }
                return edge(distance, half: light.width / 2, feather: light.feather)
            }
        }
        let pixels = UnsafeMutablePointer<Float>.allocate(capacity: w * h * 4)
        let row = UnsafeMutablePointer<Float>.allocate(capacity: w)
        defer { row.deallocate() }
        let count = vDSP_Length(w)
        var alpha: Float = 1, cool: Float = 1.02, one: Float = 1
        for y in 0..<h {
            let elevation = (0.5 - (Float(y) + 0.5) / Float(h)) * 180
            // A dim room, a touch lighter above than below.
            var base: Float = elevation > 0 ? 0.06 + 0.04 * elevation / 90 : 0.035
            base += overheadRadiance * edge(90 - elevation, half: overheadRadius, feather: overheadFeather)
            vDSP_vfill(&base, row, 1, count)
            for (index, light) in lights.enumerated() {
                var weight = light.radiance * edge(abs(elevation - light.elevation), half: light.height / 2,
                                                   feather: light.feather)
                guard weight > 0 else { continue }
                columns[index].withUnsafeBufferPointer { profile in
                    vDSP_vsma(profile.baseAddress!, 1, &weight, row, 1, row, 1, count)
                }
            }
            // Interleave as RGBA, a hair cool, as daylight on steel.
            let out = pixels + y * w * 4
            vDSP_vsmul(row, 1, &one, out, 4, count)
            vDSP_vsmul(row, 1, &one, out + 1, 4, count)
            vDSP_vsmul(row, 1, &cool, out + 2, 4, count)
            vDSP_vfill(&alpha, out + 3, 4, count)
        }
        // The image owns the pixels and frees them.
        let size = w * h * 16
        let data = Data(bytesNoCopy: pixels, count: size, deallocator: .custom { pointer, _ in pointer.deallocate() })
        guard let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB),
              let provider = CGDataProvider(data: data as CFData) else { return nil }
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue
        return CGImage(width: w, height: h, bitsPerComponent: 32, bitsPerPixel: 128, bytesPerRow: w * 16,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: info), provider: provider, decode: nil,
                       shouldInterpolate: true, intent: .defaultIntent)
    }

    /// A soft edged step: 1 inside `half`, 0 past `half + feather / 2`, smooth between.
    private static func edge(_ distance: Float, half: Float, feather: Float) -> Float {
        let t = min(max((half + feather / 2 - distance) / feather, 0), 1)
        return t * t * (3 - 2 * t)
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

    /// Steel's own colour: a clean, slightly cool grey. Bright enough to read as polished steel,
    /// short of chrome's near white.
    static let steel = UIColor(red: 0.80, green: 0.81, blue: 0.83, alpha: 1)

    #if DEBUG
    private static let log = Logger(subsystem: "com.dmihaylov.trak", category: "YearAward")
    #endif

    @MainActor
    static func build(content: CutYearAwardContent) async throws -> Scene {
        #if DEBUG
        // Tests the fallback to the SwiftUI plaque.
        if ProcessInfo.processInfo.arguments.contains("-CutYearAwardFailBuild") { throw BuildError.layout }
        let clock = ContinuousClock(), start = clock.now
        func mark(_ stage: String) {
            log.info("Year award build: \(stage, privacy: .public) at \(clock.now - start, privacy: .public), \(CutYearAwardMemory.summary, privacy: .public)")
        }
        #else
        func mark(_ stage: String) {}
        #endif
        mark("start")
        guard let mask = CutYearAwardFaceMapBuilder.mask(for: content) else { throw BuildError.layout }
        mark("layout")
        async let mapsTask = Task.detached(priority: .userInitiated) {
            CutYearAwardFaceMapBuilder.maps(mask: mask)
        }.value
        async let panoramaTask = Task.detached(priority: .userInitiated) {
            CutYearAwardStudio.panorama()
        }.value
        guard let maps = await mapsTask, let panorama = await panoramaTask else { throw BuildError.maps }
        mark("maps and studio")

        // The studio's prefiltering is the slowest step: run the uploads alongside it.
        async let environmentTask = EnvironmentResource(equirectangular: panorama, withName: "CutYearAwardStudio")
        async let normalTask = TextureResource(image: maps.normal, withName: nil,
                                               options: .init(semantic: .normal, mipmapsMode: .allocateAndGenerateAll))
        async let roughnessTask = TextureResource(image: maps.roughness, withName: nil,
                                                  options: .init(semantic: .scalar, mipmapsMode: .allocateAndGenerateAll))
        async let tintTask = TextureResource(image: maps.tint, withName: nil,
                                             options: .init(semantic: .color, mipmapsMode: .allocateAndGenerateAll))
        let (environment, normal, roughness, tint) = try await (environmentTask, normalTask, roughnessTask, tintTask)
        mark("environment and textures")

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
        mark("mesh")
        return Scene(object: object, environment: environment)
    }

    enum BuildError: Error {
        case layout
        case maps
    }
}

#if DEBUG
/// Debug: the app's memory footprint now and at its highest so far, for the build log.
enum CutYearAwardMemory {
    static var summary: String {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return "footprint unknown" }
        let mb = { (bytes: UInt64) in String(format: "%.0f MB", Double(bytes) / 1_048_576) }
        return "footprint \(mb(info.phys_footprint)), peak \(mb(UInt64(info.ledger_phys_footprint_peak)))"
    }
}
#endif
