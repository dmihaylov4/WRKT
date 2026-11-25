import CoreGraphics
import Foundation
import Metal
import RealityKit
import Testing
import UIKit
@testable import WRKT

/// Renders every tier's lathe plate face on in the studio light (offscreen, RealityRenderer) and
/// compares the face's colour with the thumbnail colour (the tier's plateColor, which
/// PlateFaceView paints). VOLIA_COLOUR_AUDIT=1 runs it (TEST_RUNNER_ prefix from xcodebuild);
/// VOLIA_CAPTURE_DIR receives colour-audit.tsv and one PNG per tier.
@MainActor
@Suite(.serialized)
struct LatheColourAuditTests {
    struct Sample {
        let tierID: Int
        let name: String
        let reference: (h: Double, s: Double, v: Double)
        let rendered: (h: Double, s: Double, v: Double)
        var hueGap: Double {
            let d = abs(reference.h - rendered.h).truncatingRemainder(dividingBy: 360)
            return min(d, 360 - d)
        }
        /// Saturation or value low enough that hue means little (greys, steel, black).
        var isNeutral: Bool { reference.s < 0.25 || reference.v < 0.15 }
        var flags: [String] {
            var out: [String] = []
            if !isNeutral && hueGap > 10 { out.append("hue") }
            if rendered.v > reference.v + 0.15 && rendered.s < reference.s - 0.2 { out.append("paler") }
            if !isNeutral && rendered.s < reference.s - 0.3 { out.append("washed") }
            return out
        }
    }

    static func hsv(_ r: Double, _ g: Double, _ b: Double) -> (h: Double, s: Double, v: Double) {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        var h = 0.0
        if d > 1e-6 {
            if mx == r { h = 60 * ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { h = 60 * ((b - r) / d + 2) }
            else { h = 60 * ((r - g) / d + 4) }
        }
        if h < 0 { h += 360 }
        return (h, mx > 0 ? d / mx : 0, mx)
    }

    static func render(tierID: Int, environment: EnvironmentResource, device: MTLDevice, side: Int = 256) async -> CGImage? {
        guard let renderer = try? RealityRenderer() else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: side, height: side, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        let root = Entity()
        let plate = makePlateEntity(tierID: tierID, weightKg: 20, options: .visualOnly(), plateStyle: .lathe)
        // Plate axis (local y) toward the camera.
        plate.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0))
        root.addChild(plate)
        let key = Entity()
        key.components.set(SpotLightComponent(color: .white, intensity: RackRoomLightingPreset.studio.keyIntensity,
                                              innerAngleInDegrees: 16, outerAngleInDegrees: 74, attenuationRadius: 10))
        key.look(at: .zero, from: SIMD3(0, 3.2, 3.2), relativeTo: nil)
        root.addChild(key)
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 30
        camera.camera.near = 0.05
        camera.camera.far = 20
        camera.position = SIMD3(0, 0, 1)
        root.addChild(camera)
        renderer.entities.append(root)
        renderer.activeCamera = camera
        renderer.lighting.resource = environment
        renderer.lighting.intensityExponent = RackRoomLightingPreset.studio.imageBasedLightIntensityExponent
        renderer.cameraSettings.colorBackground = .color(CGColor(gray: 0, alpha: 1))
        let drawn: Bool = await withCheckedContinuation { continuation in
            do {
                let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
                try renderer.updateAndRender(deltaTime: 0, cameraOutput: output, onComplete: { _ in continuation.resume(returning: true) })
            } catch {
                continuation.resume(returning: false)
            }
        }
        guard drawn else { return nil }
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        texture.getBytes(&bytes, bytesPerRow: side * 4, from: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData), let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Median colour of the face ring between the hub and the lip (lettering is a small share).
    static func faceMedian(_ image: CGImage) -> (h: Double, s: Double, v: Double)? {
        let side = image.width
        guard let data = image.dataProvider?.data as Data? else { return nil }
        let bytes = [UInt8](data)
        let pixelsPerMetre = Double(side) / 2 / (1.0 * tan(15.0 * .pi / 180))
        var r: [Double] = [], g: [Double] = [], b: [Double] = []
        for y in 0..<side {
            for x in 0..<side {
                let dx = Double(x) + 0.5 - Double(side) / 2, dy = Double(y) + 0.5 - Double(side) / 2
                let radius = (dx * dx + dy * dy).squareRoot() / pixelsPerMetre
                guard radius > 0.085, radius < 0.16 else { continue }
                let i = (y * side + x) * 4
                b.append(Double(bytes[i]) / 255); g.append(Double(bytes[i + 1]) / 255); r.append(Double(bytes[i + 2]) / 255)
            }
        }
        func median(_ v: [Double]) -> Double { v.sorted()[v.count / 2] }
        guard !r.isEmpty else { return nil }
        return hsv(median(r), median(g), median(b))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOLIA_COLOUR_AUDIT"] == "1"))
    func everyTierMatchesItsThumbnail() async throws {
        let environment = try #require(await sharedRackStudioEnvironmentResource())
        let device = try #require(MTLCreateSystemDefaultDevice())
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["VOLIA_CAPTURE_DIR"] ?? "/private/tmp/volia-colour-audit")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var lines = ["tier\tname\tref_h\tref_s\tref_v\tlathe_h\tlathe_s\tlathe_v\thue_gap\tflags"]
        var flagged: [String] = []
        for tier in PlateTier.all where tier.id != 7 {
            let image = try #require(await Self.render(tierID: tier.id, environment: environment, device: device))
            try #require(UIImage(cgImage: image).pngData()).write(to: directory.appendingPathComponent("tier-\(tier.id).png"))
            let rendered = try #require(Self.faceMedian(image))
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            tier.plateColor.getRed(&r, green: &g, blue: &b, alpha: &a)
            let sample = Sample(tierID: tier.id, name: tier.name, reference: Self.hsv(Double(r), Double(g), Double(b)), rendered: rendered)
            lines.append(String(format: "%d\t%@\t%.0f\t%.2f\t%.2f\t%.0f\t%.2f\t%.2f\t%.0f\t%@", tier.id, tier.name,
                                sample.reference.h, sample.reference.s, sample.reference.v,
                                rendered.h, rendered.s, rendered.v, sample.hueGap, sample.flags.joined(separator: ",")))
            if !sample.flags.isEmpty { flagged.append("\(tier.id) \(tier.name): \(sample.flags)") }
        }
        try lines.joined(separator: "\n").appending("\n").write(to: directory.appendingPathComponent("colour-audit.tsv"),
                                                               atomically: true, encoding: .utf8)
        #expect(flagged.isEmpty, "\(flagged)")
    }
}
