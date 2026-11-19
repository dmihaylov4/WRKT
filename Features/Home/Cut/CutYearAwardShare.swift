//
//  CutYearAwardShare.swift
//  WRKT
//
//  The award's shared picture: a landscape plate in the same steel, light and engraving as the
//  object on screen, composed for the frames a post's picture is shown in. Rendered once by a
//  RealityRenderer of its own, at the picture's size, which is released with everything it
//  allocated as soon as the picture exists. The shape, the frames and the style live in
//  CutYearAwardModel.swift (`CutYearAwardShare`).
//

import Metal
import OSLog
import RealityKit
import SwiftUI
import UIKit

// MARK: - Engraving

/// What is cut into the shared plate, in the mask's inks, one point to the plate's millimetre.
/// The year leads on the left, the headline and the quiet line under it, the mark in the far
/// corner: all inside the area every post frame keeps.
struct CutYearAwardShareLayout: View {
    let content: CutYearAwardContent

    var body: some View {
        let insets = CutYearAwardShare.contentInsets
        ZStack(alignment: .topLeading) {
            VMarkShape()
                .fill(CutYearAwardObjectLayout.deepInk)
                .frame(width: 70, height: 44)
                .frame(maxWidth: .infinity, alignment: .topTrailing)
            VStack(alignment: .leading, spacing: 0) {
                Text(content.yearText)
                    .font(DS.Cut.Typography.condensed(size: 124, monospacedDigits: true))
                    .tracking(1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.vertical, Self.tightening(size: 124, lineHeight: 0.84))
                    .foregroundStyle(CutYearAwardObjectLayout.deepInk)
                VStack(alignment: .leading, spacing: Self.lineGap(size: 28, lineHeight: 1.0)) {
                    ForEach(Array(content.headlineLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(DS.Cut.Typography.condensed(size: 28, relativeTo: .title2))
                            .textCase(.uppercase)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
                .foregroundStyle(CutYearAwardObjectLayout.fineInk)
                .padding(.top, 12)
                Text(content.objectLine)
                    .font(DS.Typography.custom(size: 18, weight: .bold, relativeTo: .body))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(CutYearAwardObjectLayout.fineInk)
                    .padding(.top, 12)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .padding(.horizontal, insets.horizontal)
        .padding(.vertical, insets.vertical)
        .frame(width: CGFloat(CutYearAwardShare.slab.width * 1000), height: CGFloat(CutYearAwardShare.slab.height * 1000),
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

// MARK: - Picture

@MainActor
enum CutYearAwardSharePicture {
    /// Pixels across the plate's maps: about 2.3 per millimetre, the picture's own density in
    /// the face style.
    static let mapWidth = 1400

    #if DEBUG
    private static let log = Logger(subsystem: "com.dmihaylov.trak", category: "YearAward")
    #endif

    /// The shared picture, or nil if it could not be drawn. The studio comes from the on-screen
    /// object, so its prefiltered light is not built twice.
    static func render(content: CutYearAwardContent, environment: EnvironmentResource, device: MTLDevice,
                       style: CutYearAwardShare.Style) async -> UIImage? {
        #if DEBUG
        let clock = ContinuousClock(), start = clock.now
        func mark(_ step: String, main: Duration? = nil) {
            let onMain = main.map { ", main thread \($0)" } ?? ""
            log.info("Year award share: \(step, privacy: .public) at \(clock.now - start, privacy: .public)\(onMain, privacy: .public), \(CutYearAwardMemory.summary, privacy: .public)")
        }
        #else
        func mark(_ step: String, main: Duration? = nil) {}
        #endif
        defer { CutYearAwardPages.relieve() }
        guard let slab = try? await CutYearAwardObjectBuilder.buildSlab(CutYearAwardShare.slab,
                                                                       layout: CutYearAwardShareLayout(content: content),
                                                                       mapWidth: mapWidth) else { return nil }
        mark("plate")
        let width = Int(CutYearAwardShare.pixelSize.width), height = Int(CutYearAwardShare.pixelSize.height)
        #if DEBUG
        let setupStart = clock.now
        #endif
        guard let renderer = try? RealityRenderer(),
              let texture = outputTexture(device: device, width: width, height: height) else { return nil }
        let root = Entity(), pivot = Entity(), camera = PerspectiveCamera()
        pivot.addChild(slab)
        root.addChild(pivot)
        pivot.orientation = CutYearAwardStage.orientation(for: CutYearAwardShare.pose)
        camera.camera.fieldOfViewInDegrees = CutYearAwardSlab.fieldOfView
        camera.camera.near = 0.05
        camera.camera.far = 20
        let distance = CutYearAwardSlab.cameraDistance(viewHeight: CutYearAwardShare.visibleHeight(style) * 1000)
        camera.position = SIMD3(0, 0, distance + CutYearAwardSlab.thickness / 2)
        root.addChild(camera)
        renderer.entities.append(root)
        renderer.activeCamera = camera
        renderer.lighting.resource = environment
        renderer.lighting.intensityExponent = 0
        renderer.cameraSettings.colorBackground = .color(CGColor(gray: 0, alpha: 0))
        // The screen's format and multisampling, so the screen's compiled pipelines are reused.
        renderer.cameraSettings.antialiasing = .multisample4X
        let drawn: Bool = await withCheckedContinuation { continuation in
            do {
                let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
                try renderer.updateAndRender(deltaTime: 0, cameraOutput: output, onComplete: { _ in
                    continuation.resume(returning: true)
                })
            } catch {
                continuation.resume(returning: false)
            }
            #if DEBUG
            mark("encoded", main: clock.now - setupStart)
            #endif
        }
        mark("drawn")
        guard drawn, let rendered = image(from: texture, width: width, height: height, opaque: style == .face) else {
            return nil
        }
        let picture = style == .face ? rendered : onWall(rendered, width: width, height: height)
        mark("picture")
        return picture.map { UIImage(cgImage: $0, scale: 3, orientation: .up) }
    }

    private static func outputTexture(device: MTLDevice, width: Int, height: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: CutYearAwardStage.pixelFormat,
                                                                  width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        return device.makeTexture(descriptor: descriptor)
    }

    /// The texture's pixels in one buffer the image then owns: no further copies.
    private static func image(from texture: MTLTexture, width: Int, height: Int, opaque: Bool) -> CGImage? {
        let count = width * height * 4
        guard let pixels = CutYearAwardPages.allocate(UInt8.self, count: count) else { return nil }
        texture.getBytes(pixels, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        let data = Data(bytesNoCopy: pixels, count: count, deallocator: .custom { pointer, size in
            munmap(pointer, max(1, size))
        })
        let alpha: CGImageAlphaInfo = opaque ? .noneSkipFirst : .premultipliedFirst
        guard let provider = CGDataProvider(data: data as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: alpha.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// The object style's ground: a dark studio wall, lit from above and a little left like the
    /// steel, never black.
    private static func onWall(_ plate: CGImage, width: Int, height: Int) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                                        | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let wall = [CGColor(srgbRed: 0.20, green: 0.21, blue: 0.225, alpha: 1),
                    CGColor(srgbRed: 0.11, green: 0.115, blue: 0.125, alpha: 1)] as CFArray
        let glow = [CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10),
                    CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0)] as CFArray
        // Core Graphics' y runs up: the light is at the top.
        if let gradient = CGGradient(colorsSpace: space, colors: wall, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: bounds.height), end: .zero, options: [])
        }
        if let gradient = CGGradient(colorsSpace: space, colors: glow, locations: [0, 1]) {
            let centre = CGPoint(x: bounds.width * 0.42, y: bounds.height * 0.8)
            context.drawRadialGradient(gradient, startCenter: centre, startRadius: 0, endCenter: centre,
                                       endRadius: bounds.width * 0.7, options: [])
        }
        context.draw(plate, in: bounds)
        return context.makeImage()
    }
}
