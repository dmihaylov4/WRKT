// Features/Rewards/Views/LathePlateBuilder.swift
//
// The rack room's lathe plates: one ModelEntity per plate, one revolved mesh shared by every plate
// of the same family and size, three material slots (body, hub, face). Lettering, the progression
// accent ring and the engraving are painted into the face slot's textures (colour plus a normal
// map for raised or stamped letters) instead of the legacy plate's decal entities.
//
// Everything here is built once per process: meshes per profile, shared surface textures, one
// face texture pair per distinct face (tier, weight label, engraving, accent). prepareLathePlates
// draws the face images off the main thread before the scene's first frame; a plate that arrives
// later (a new award) builds its face on first use.
//
// Only the rack room scene (BarbellRealityView, through SceneState.plateStyle) builds these. The
// profile preview, spinning plate and snapshot thumbnails keep the legacy plate and its materials.

import os
import RealityKit
import UIKit

// MARK: - Finishes

/// How a lathe plate surface is made, which picks its shared detail texture.
nonisolated enum LatheSurface: Hashable, Sendable {
    /// Turned metal: fine concentric machining in the normal and roughness.
    case machined
    /// Sand cast iron: a pitted normal.
    case cast
    /// Rubber or powder coat: smooth.
    case smooth
}

/// One slot's physically based values. Metals are metallic 1 with their colour as the reflection
/// tint; rubber and powder coat are metallic 0 with a saturated colour.
struct LatheFinish: Equatable {
    var color: UIColor
    var metallic: Float
    var roughness: Float
    var clearcoat: Float = 0
    var clearcoatRoughness: Float = 0
    var surface: LatheSurface
    /// Dielectric reflectance scale (RealityKit's default 0.5 is F0 0.04). Metals ignore it.
    var specular: Float = 0.5

    static let rubberRoughness: Float = 0.85
    static let rubberSpecular: Float = 0.15

    /// Debug tuning from VOLIA_RACK_LIGHT: rubberSpec, rubberRough.
    static func rubberOverride(_ name: String) -> Float? {
        #if DEBUG
        return rackRoomLightingOverrides(ProcessInfo.processInfo.environment["VOLIA_RACK_LIGHT"])[name]
        #else
        return nil
        #endif
    }

    var isMetal: Bool { metallic >= 0.5 }

    /// The machined steel of a bumper or competition hub insert.
    static let steelInsert = LatheFinish(color: UIColor(white: 0.80, alpha: 1), metallic: 1, roughness: 0.26, surface: .machined)

    static func family(for tier: PlateTier) -> LathePlateFamily {
        switch tier.style {
        case .bumper, .starter: return .bumper
        case .competition: return tier.metallic >= 0.5 ? .machined : .competition
        case .castIron: return .castIron
        case .rawIron, .brass, .polishedSteel, .gold: return .machined
        }
    }

    /// Rim, lip and outer wall.
    static func body(for tier: PlateTier) -> LatheFinish {
        switch tier.id {
        // Neutral metals: the metals' reflectance in sRGB, nudged brighter so they read on a phone.
        case 5: return metal(white: 0.90, roughness: 0.11)                                   // Polished Steel: chrome
        case 26: return metal(UIColor(white: 0.42, alpha: 1), roughness: 0.12)               // Dark Chrome
        // Coloured metals take their thumbnail's hue and depth, the way anodised or tinted metal
        // gets colour: a saturated base (a metal's reflection takes its base colour) and enough
        // roughness that the colour, not a mirror image of the white studio, fills the face. Pale
        // tints (Rose Gold was 1.0, 0.66, 0.70) mirrored the studio and read pastel.
        case 6: return tinted(tier, roughness: 0.20)                                          // Gold
        case 31: return tinted(tier, roughness: 0.22)                                         // Forge S1
        case 11: return tinted(tier, roughness: 0.18)                                         // Royal Gold
        case 3: return tinted(tier, roughness: 0.26)                                          // Brass
        case 13: return tinted(tier, roughness: 0.26)                                         // Copper
        case 28: return tinted(tier, roughness: 0.32)                                         // Iron Crown: bronze
        case 8: return anodised(tier)                                                         // Rose Gold: anodised magenta
        case 9: return anodised(tier)                                                         // Emerald: anodised green
        case 12: return anodised(tier)                                                        // Diamond: anodised ice blue
        case 0:                                                                                // Rusty Iron: forged, rust brown
            var finish = tinted(tier, roughness: 0.44)
            finish.surface = .cast
            return finish
        default: break
        }
        switch tier.style {
        case .castIron:
            return LatheFinish(color: UIColor(white: 0.58, alpha: 1), metallic: 1, roughness: 0.52, surface: .cast)
        case .competition where tier.metallic < 0.5:
            // Powder coat: saturated colour under a light clearcoat.
            return LatheFinish(color: PlateDisplaySurface.faceColor(for: tier), metallic: 0, roughness: 0.44,
                               clearcoat: 0.35, clearcoatRoughness: 0.22, surface: .smooth)
        case .bumper, .starter:
            // Matte rubber with a weak sheen. At the default reflectance, faces seen edge on (as
            // every face on the bar is) picked up a white Fresnel sheen from the bright studio
            // and turned pale and bright: red read pink, magenta pastel.
            return LatheFinish(color: rubberColor(for: tier), metallic: 0, roughness: rubberOverride("rubberRough") ?? rubberRoughness,
                               surface: .smooth, specular: rubberOverride("rubberSpec") ?? rubberSpecular)
        default:
            return metal(PlateDisplaySurface.faceColor(for: tier), roughness: 0.18)
        }
    }

    /// Bore and hub: steel inserts in rubber and powder coat plates, a slightly rougher turned boss
    /// of the same metal on metal plates.
    static func hub(for tier: PlateTier) -> LatheFinish {
        let body = body(for: tier)
        guard body.isMetal else { return steelInsert }
        var hub = body
        hub.roughness = min(0.6, body.roughness + 0.08)
        if hub.surface == .cast { hub.surface = .machined }
        return hub
    }

    /// A coloured metal from the tier's thumbnail colour: same hue and saturation, value at least
    /// 0.62 so dark tiers (bronze, rust) still reflect.
    static func tinted(_ tier: PlateTier, roughness: Float) -> LatheFinish {
        let hsb = tier.plateColor.barbellHSB
        let color = UIColor(hue: renderedHue(hsb.hue), saturation: hsb.saturation, brightness: max(0.62, hsb.brightness), alpha: 1)
        return LatheFinish(color: color, metallic: 1, roughness: roughness, surface: .machined)
    }

    /// Anodised colour: deeper and more saturated than the thumbnail's flat colour and a satin
    /// finish, because a bright tint on metal mirrors the white studio and reads pastel (the
    /// owner's 75-workout Rose Gold read pale pink).
    static func anodised(_ tier: PlateTier) -> LatheFinish {
        let hsb = tier.plateColor.barbellHSB
        let color = UIColor(hue: renderedHue(hsb.hue), saturation: min(1, hsb.saturation + 0.2),
                            brightness: min(0.78, max(0.62, hsb.brightness)), alpha: 1)
        return LatheFinish(color: color, metallic: 1, roughness: 0.38, surface: .machined)
    }

    private static func metal(white: CGFloat, roughness: Float) -> LatheFinish {
        metal(UIColor(white: white, alpha: 1), roughness: roughness)
    }

    private static func metal(_ color: UIColor, roughness: Float) -> LatheFinish {
        LatheFinish(color: color, metallic: 1, roughness: roughness, surface: .machined)
    }

    /// Bumper rubber: the readable face colour, black bumpers a true deep black-grey.
    /// The thumbnail's colour (the legacy readable boost pushed every bumper to full brightness
    /// and saturation, which the tone mapper bent: green turned yellow, teal pale). Black
    /// bumpers a true deep black-grey.
    private static func rubberColor(for tier: PlateTier) -> UIColor {
        let hsb = tier.plateColor.barbellHSB
        if hsb.brightness < 0.12 { return UIColor(white: 0.075, alpha: 1) }
        return UIColor(hue: renderedHue(hsb.hue), saturation: hsb.saturation, brightness: hsb.brightness, alpha: 1)
    }

    /// The renderer's tone mapping bends saturated greens toward yellow (a green bumper at hue
    /// 140 rendered at 118, emerald 153 at 135, measured by LatheColourAuditTests). Greens start a
    /// little bluer so they land on their thumbnail's hue. Other hues land within a few degrees.
    static func renderedHue(_ hue: CGFloat) -> CGFloat {
        let degrees = hue * 360
        guard degrees > 95, degrees < 170 else { return hue }
        // Full shift through the greens, fading out toward yellow-green and cyan.
        let weight = min(1, min(degrees - 95, 170 - degrees) / 25)
        return (degrees + 20 * weight) / 360
    }
}

// MARK: - Face art

/// Everything the face texture shows, as plain values so the images can be drawn off the main
/// thread. Equal specs share one texture pair.
nonisolated struct LatheFaceSpec: Hashable, Sendable {
    var family: LathePlateFamily
    /// Face colour, sRGB 0 to 1.
    var base: SIMD3<Float>
    var letter: SIMD3<Float>
    /// Progression rings: cut into the face as fine grooves in the plate's own colour (the owner
    /// found painted accent colours, yellow on gold tiers, did not fit). The tier's accent colour
    /// is no longer used, so specs differ only by ring count.
    var accentRings: Int
    var weightLabel: String
    var engraving: String
    /// Raised (rubber, cast) or stamped (machined metal) lettering.
    var raised: Bool
    /// Roughness of the face and of the letters (raised cast letters are worn smooth, stamped
    /// letters are rough at the bottom).
    var roughness: Float
    var letterRoughness: Float
    var surface: LatheSurface
    var outerRadius: Float
    /// The recessed face ring the lettering must stay inside, as radii in metres.
    var faceInnerRadius: Float
    var faceOuterRadius: Float
}

private extension UIColor {
    var latheRGB: SIMD3<Float> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        if !getRed(&r, green: &g, blue: &b, alpha: &a) {
            var w: CGFloat = 0
            getWhite(&w, alpha: &a)
            r = w; g = w; b = w
        }
        return SIMD3(Float(r), Float(g), Float(b))
    }
}

@MainActor
func latheFaceSpec(tier: PlateTier, weightKg: Double, engravingText: String,
                   projection: BarbellPlateRenderProjection, showEngravings: Bool) -> LatheFaceSpec {
    let family = LatheFinish.family(for: tier)
    let finish = LatheFinish.body(for: tier)
    let profile = latheProfile(for: tier)
    let face = LatheGeometry.faceRing(profile)
    let base = finish.color.latheRGB
    let letter: SIMD3<Float>
    let raised: Bool
    var roughness = finish.roughness
    var letterRoughness = finish.roughness
    if finish.isMetal {
        if finish.surface == .cast {
            // Cast lettering stands proud and its tops are worn bright and smooth.
            raised = true
            letter = simd_min(base * 1.3, SIMD3(repeating: 1))
            letterRoughness = max(0.22, finish.roughness - 0.24)
        } else {
            // Stamped into the metal and darkened, like a filled engraving. The turned face is a
            // little less polished than the rim, so it spreads the studio instead of mirroring
            // one dark corner of it.
            raised = false
            letter = base * 0.42
            roughness = min(0.4, finish.roughness + 0.10)
            letterRoughness = 0.6
        }
    } else {
        raised = true
        let luminance = 0.2126 * base.x + 0.7152 * base.y + 0.0722 * base.z
        letter = luminance > 0.55 ? SIMD3(repeating: 0.10) : SIMD3(repeating: 0.96)
        letterRoughness = max(0.35, finish.roughness - 0.2)
    }
    let label: String
    if showEngravings, weightKg > 0, tier.id != 7 {
        label = (weightKg.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(weightKg))" : String(format: "%.1f", weightKg)) + " KG"
    } else {
        label = ""
    }
    return LatheFaceSpec(
        family: family, base: base, letter: letter,
        accentRings: tier.id == 7 ? 0 : projection.tierRingCount,
        weightLabel: label,
        engraving: showEngravings && tier.id != 7 ? normalizedRimEngravingText(engravingText) : "",
        raised: raised, roughness: roughness, letterRoughness: letterRoughness,
        surface: finish.surface, outerRadius: profile.outerRadius,
        faceInnerRadius: face.inner, faceOuterRadius: face.outer
    )
}

extension LatheGeometry {
    /// Inner and outer radius of the flat face-slot ring.
    nonisolated static func faceRing(_ profile: LatheProfile) -> (inner: Float, outer: Float) {
        var inner = Float.greatestFiniteMagnitude, outer: Float = 0
        for (i, slot) in profile.edgeSlots.enumerated() where slot == LatheSlot.face {
            inner = min(inner, profile.corners[i].r, profile.corners[i + 1].r)
            outer = max(outer, profile.corners[i].r, profile.corners[i + 1].r)
        }
        return inner < outer ? (inner, outer) : (0, profile.outerRadius)
    }
}

/// Face images: sRGB colour and a tangent-space normal map, `side` pixels square, covering the
/// whole plate disc (the planar face UVs span the outer radius).
nonisolated enum LatheFaceArt {
    static let side = 512

    struct Images: @unchecked Sendable {
        let color: CGImage
        let normal: CGImage
        /// Roughness in the red channel (linear).
        let roughness: CGImage
    }

    static func images(for spec: LatheFaceSpec) -> Images? {
        let n = side
        let size = CGSize(width: n, height: n)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        // Lettering and accent rings as two white-on-clear masks.
        let letters = UIGraphicsImageRenderer(size: size, format: format).image { _ in drawLettering(spec, side: CGFloat(n)) }
        let paint = UIGraphicsImageRenderer(size: size, format: format).image { ctx in drawAccentRings(spec, side: CGFloat(n), in: ctx.cgContext) }
        guard let letterMask = alpha(of: letters.cgImage, side: n), let paintMask = alpha(of: paint.cgImage, side: n) else { return nil }

        var color = [UInt8](repeating: 255, count: n * n * 4)
        var height = [Float](repeating: 0, count: n * n)
        var rough = [UInt8](repeating: 255, count: n * n * 4)
        let centre = Float(n) / 2
        let metresPerPixel = 2 * spec.outerRadius / Float(n)
        for y in 0..<n {
            for x in 0..<n {
                let i = y * n + x
                let dx = Float(x) + 0.5 - centre, dy = Float(y) + 0.5 - centre
                let rMetres = (dx * dx + dy * dy).squareRoot() * metresPerPixel
                let m = letterMask[i], p = paintMask[i]
                var c = spec.base
                // A groove reads a shade darker than the face around it.
                c = c * (1 - 0.12 * p)
                c = c + (spec.letter - c) * m
                color[i * 4] = UInt8(max(0, min(255, c.x * 255)))
                color[i * 4 + 1] = UInt8(max(0, min(255, c.y * 255)))
                color[i * 4 + 2] = UInt8(max(0, min(255, c.z * 255)))
                let r = UInt8(max(0, min(255, (spec.roughness + (spec.letterRoughness - spec.roughness) * m) * 255)))
                rough[i * 4] = r; rough[i * 4 + 1] = r; rough[i * 4 + 2] = r
                // Height in pixels: letters 1.2 px proud or stamped in, plus the surface detail.
                var h = (spec.raised ? 1.2 : -1.2) * m - 0.8 * p
                switch spec.surface {
                case .machined:
                    // Fine turned rings, about 1.6 mm apart.
                    h += 0.05 * sin(rMetres / 0.0016 * 2 * .pi)
                case .cast:
                    h += 0.7 * castNoise(x: x, y: y, period: n)
                case .smooth:
                    break
                }
                height[i] = h
            }
        }
        guard let colorImage = rgbaImage(color, side: n, space: CGColorSpace(name: CGColorSpace.sRGB)),
              let normalImage = normalMap(height: height, width: n, height: n, strength: 1.0),
              let roughImage = rgbaImage(rough, side: n, space: CGColorSpaceCreateDeviceRGB()) else { return nil }
        return Images(color: colorImage, normal: normalImage, roughness: roughImage)
    }

    private static func font(_ name: String, size: CGFloat, weight: UIFont.Weight) -> UIFont {
        UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    private static func drawLettering(_ spec: LatheFaceSpec, side: CGFloat) {
        let pixelsPerMetre = side / CGFloat(2 * spec.outerRadius)
        let inner = CGFloat(spec.faceInnerRadius) * pixelsPerMetre
        let outer = CGFloat(spec.faceOuterRadius) * pixelsPerMetre
        let band = outer - inner
        let centre = CGPoint(x: side / 2, y: side / 2)
        let textRadius = inner + band * 0.62
        let brandSize = band * 0.30
        let brand: [NSAttributedString.Key: Any] = [
            .font: font("BarlowSemiCondensed-Black", size: brandSize, weight: .black),
            .foregroundColor: UIColor.white, .kern: brandSize * 0.18
        ]
        drawArc("VOLIA", centre: centre, radius: textRadius, centreAngle: -.pi / 2, attributes: brand, top: true)
        let bottom = spec.engraving.isEmpty ? "VOLIA" : spec.engraving
        let bottomSize = spec.engraving.isEmpty ? brandSize : min(brandSize * 0.8, band * 0.24)
        var bottomAttributes = brand
        bottomAttributes[.font] = font("BarlowSemiCondensed-Bold", size: bottomSize, weight: .bold)
        bottomAttributes[.kern] = bottomSize * 0.10
        drawArc(bottom, centre: centre, radius: textRadius, centreAngle: .pi / 2, attributes: bottomAttributes, top: false)
        guard !spec.weightLabel.isEmpty else { return }
        let weightSize = band * 0.26
        let weight: [NSAttributedString.Key: Any] = [
            .font: font("BarlowSemiCondensed-Black", size: weightSize, weight: .black),
            .foregroundColor: UIColor.white
        ]
        drawArc(spec.weightLabel, centre: centre, radius: textRadius, centreAngle: 0, attributes: weight, top: true)
        drawArc(spec.weightLabel, centre: centre, radius: textRadius, centreAngle: .pi, attributes: weight, top: true)
    }

    private static func drawAccentRings(_ spec: LatheFaceSpec, side: CGFloat, in context: CGContext) {
        guard spec.accentRings > 0 else { return }
        let pixelsPerMetre = side / CGFloat(2 * spec.outerRadius)
        let outer = CGFloat(spec.faceOuterRadius) * pixelsPerMetre
        let centre = CGPoint(x: side / 2, y: side / 2)
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(max(2, side * 0.006))
        for index in 0..<min(spec.accentRings, 3) {
            let radius = outer - side * (0.012 + 0.016 * CGFloat(index))
            context.strokeEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
        }
    }

    /// Letters on an arc, centred on `centreAngle` (0 is right, positive clockwise in image space).
    /// Top arcs read left to right with letters standing outward; bottom arcs read left to right
    /// with letters standing inward, so both read upright.
    private static func drawArc(_ text: String, centre: CGPoint, radius: CGFloat, centreAngle: CGFloat,
                                attributes: [NSAttributedString.Key: Any], top: Bool) {
        guard let context = UIGraphicsGetCurrentContext(), !text.isEmpty else { return }
        let characters = text.map(String.init)
        let advances = characters.map { ($0 as NSString).size(withAttributes: attributes).width }
        let kern = attributes[.kern] as? CGFloat ?? 0
        let total = advances.reduce(0, +) + kern * CGFloat(max(0, characters.count - 1))
        let direction: CGFloat = top ? 1 : -1
        var angle = centreAngle - direction * (total / 2) / radius
        for (i, character) in characters.enumerated() {
            let half = advances[i] / 2
            let a = angle + direction * half / radius
            let point = CGPoint(x: centre.x + cos(a) * radius, y: centre.y + sin(a) * radius)
            context.saveGState()
            context.translateBy(x: point.x, y: point.y)
            context.rotate(by: top ? a + .pi / 2 : a - .pi / 2)
            let size = (character as NSString).size(withAttributes: attributes)
            (character as NSString).draw(at: CGPoint(x: -size.width / 2, y: -size.height / 2), withAttributes: attributes)
            context.restoreGState()
            angle += direction * (advances[i] + kern) / radius
        }
    }

    private static func alpha(of image: CGImage?, side n: Int) -> [Float]? {
        guard let image else { return nil }
        var bytes = [UInt8](repeating: 0, count: n * n)
        let ok = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: n, height: n))
            return true
        }
        return ok ? bytes.map { Float($0) / 255 } : nil
    }

    /// Smooth tileable value noise in -1...1 (pitting of a sand cast surface).
    static func castNoise(x: Int, y: Int, period: Int) -> Float {
        func hash(_ i: Int, _ j: Int) -> Float {
            var h = UInt32(truncatingIfNeeded: (i & 1023) &* 73_856_093 ^ (j & 1023) &* 19_349_663)
            h = (h ^ (h >> 13)) &* 1_274_126_177
            return Float(h & 0xFFFF) / 32_767.5 - 1
        }
        func octave(_ cell: Int) -> Float {
            let cells = max(1, period / cell)
            let fx = Float(x) / Float(cell), fy = Float(y) / Float(cell)
            let x0 = Int(fx), y0 = Int(fy)
            let tx = fx - Float(x0), ty = fy - Float(y0)
            let sx = tx * tx * (3 - 2 * tx), sy = ty * ty * (3 - 2 * ty)
            let a = hash(x0 % cells, y0 % cells), b = hash((x0 + 1) % cells, y0 % cells)
            let c = hash(x0 % cells, (y0 + 1) % cells), d = hash((x0 + 1) % cells, (y0 + 1) % cells)
            return (a + (b - a) * sx) + ((c + (d - c) * sx) - (a + (b - a) * sx)) * sy
        }
        return 0.55 * octave(4) + 0.30 * octave(8) + 0.15 * octave(16)
    }

    static func rgbaImage(_ bytes: [UInt8], side n: Int, space: CGColorSpace?) -> CGImage? {
        guard let space, let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Tangent-space normals from a height field (heights in pixels), wrapping at the edges.
    /// Image rows run down while texture v runs up, so the row slope enters with its sign flipped.
    static func normalMap(height: [Float], width w: Int, height h: Int, strength: Float) -> CGImage? {
        var out = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let dx = (height[y * w + (x + 1) % w] - height[y * w + (x - 1 + w) % w]) * 0.5 * strength
                let dy = (height[((y - 1 + h) % h) * w + x] - height[((y + 1) % h) * w + x]) * 0.5 * strength
                let n = simd_normalize(SIMD3<Float>(-dx, -dy, 1))
                let i = (y * w + x) * 4
                out[i] = UInt8(max(0, min(255, (n.x * 0.5 + 0.5) * 255)))
                out[i + 1] = UInt8(max(0, min(255, (n.y * 0.5 + 0.5) * 255)))
                out[i + 2] = UInt8(max(0, min(255, (n.z * 0.5 + 0.5) * 255)))
            }
        }
        guard let provider = CGDataProvider(data: Data(out) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// The shared detail for lathe-UV slots (body and hub): u around the axis, v along the profile.
    /// Machined: fine turned grooves along v. Cast: pitting noise, tiled by the material's UV scale.
    static func surfaceNormal(_ surface: LatheSurface) -> CGImage? {
        switch surface {
        case .machined:
            // 8 x 1024: about 0.9 mm of profile per row on a 22 cm plate; grooves every 3 rows.
            let w = 8, h = 1024
            var height = [Float](repeating: 0, count: w * h)
            for y in 0..<h {
                let groove = 0.10 * sin(Float(y) / 3 * 2 * .pi) + 0.05 * sin(Float(y) / 11 * 2 * .pi)
                for x in 0..<w { height[y * w + x] = groove }
            }
            return normalMap(height: height, width: w, height: h, strength: 1)
        case .cast:
            let n = 256
            var height = [Float](repeating: 0, count: n * n)
            for y in 0..<n { for x in 0..<n { height[y * n + x] = 1.1 * castNoise(x: x, y: y, period: n) } }
            return normalMap(height: height, width: n, height: n, strength: 1)
        case .smooth:
            return nil
        }
    }
}

// MARK: - Caches and resources

@MainActor private var _latheMeshCache: [LatheProfile.Key: MeshResource] = [:]
@MainActor private var _latheSurfaceNormalCache: [String: TextureResource] = [:]
@MainActor private var _latheFaceTextureCache: [LatheFaceSpec: (color: TextureResource, normal: TextureResource, roughness: TextureResource)] = [:]
@MainActor private var _latheSlotMaterialCache: [Int: (body: PhysicallyBasedMaterial, hub: PhysicallyBasedMaterial)] = [:]
@MainActor private var _latheFaceMaterialCache: [LatheFaceSpec: PhysicallyBasedMaterial] = [:]

@MainActor
func latheProfile(for tier: PlateTier) -> LatheProfile {
    let visual = PlateVisualDesign.profile(for: tier.style)
    return LatheProfile.make(family: LatheFinish.family(for: tier), outerRadius: visual.outerRadius,
                             thickness: visual.thickness, boreRadius: visual.boreRadius)
}

/// One mesh per profile key, shared by every plate of that family and size.
@MainActor
func cachedLatheMesh(for profile: LatheProfile) -> MeshResource? {
    if let cached = _latheMeshCache[profile.key] { return cached }
    guard let mesh = makeLatheMesh(LatheMeshData.revolve(profile), name: "LathePlate_\(profile.family.rawValue)") else { return nil }
    _latheMeshCache[profile.key] = mesh
    return mesh
}

@MainActor
func makeLatheMesh(_ data: LatheMeshData, name: String) -> MeshResource? {
    var descriptor = MeshDescriptor(name: name)
    descriptor.positions = MeshBuffers.Positions(data.positions)
    descriptor.normals = MeshBuffers.Normals(data.normals)
    descriptor.tangents = MeshBuffers.Tangents(data.tangents)
    descriptor.bitangents = MeshBuffers.Tangents(data.bitangents)
    descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(data.uvs)
    descriptor.primitives = .triangles(data.indices)
    descriptor.materials = .perFace(data.triangleSlots)
    return try? MeshResource.generate(from: [descriptor])
}

/// Repeat addressing, trilinear filtering and anisotropy for every lathe texture.
private func latheTexture(_ resource: TextureResource) -> MaterialParameters.Texture {
    var sampler = MaterialParameters.Texture.Sampler()
    sampler.modify { descriptor in
        descriptor.sAddressMode = .repeat
        descriptor.tAddressMode = .repeat
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.mipFilter = .linear
        descriptor.maxAnisotropy = 8
    }
    return MaterialParameters.Texture(resource, sampler: sampler)
}

@MainActor
private func surfaceNormalTexture(_ surface: LatheSurface) -> TextureResource? {
    let key = "\(surface)"
    if let cached = _latheSurfaceNormalCache[key] { return cached }
    guard let image = LatheFaceArt.surfaceNormal(surface),
          let texture = try? TextureResource(image: image, options: .init(semantic: .normal)) else { return nil }
    _latheSurfaceNormalCache[key] = texture
    return texture
}

@MainActor
private func latheMaterial(_ finish: LatheFinish, detail: Bool) -> PhysicallyBasedMaterial {
    var material = PhysicallyBasedMaterial()
    material.baseColor = .init(tint: finish.color)
    material.metallic = .init(floatLiteral: finish.metallic)
    material.roughness = .init(floatLiteral: finish.roughness)
    material.clearcoat = .init(floatLiteral: finish.clearcoat)
    material.clearcoatRoughness = .init(floatLiteral: finish.clearcoatRoughness)
    // A closed mesh: back faces are never seen.
    material.faceCulling = .back
    if !finish.isMetal {
        material.specular = .init(floatLiteral: finish.specular)
    }
    if detail, let normal = surfaceNormalTexture(finish.surface) {
        material.normal = .init(texture: latheTexture(normal))
        if finish.surface == .cast {
            // The 256 px pitting tile, repeated around and along the plate (about 3 mm cells).
            material.textureCoordinateTransform = .init(scale: SIMD2(48, 12))
        }
    }
    return material
}

@MainActor
private func latheSlotMaterials(for tier: PlateTier) -> (body: PhysicallyBasedMaterial, hub: PhysicallyBasedMaterial) {
    if let cached = _latheSlotMaterialCache[tier.id] { return cached }
    let result = (latheMaterial(LatheFinish.body(for: tier), detail: true), latheMaterial(LatheFinish.hub(for: tier), detail: true))
    _latheSlotMaterialCache[tier.id] = result
    return result
}

@MainActor
private func latheFaceMaterial(for spec: LatheFaceSpec, tier: PlateTier) -> PhysicallyBasedMaterial {
    if let cached = _latheFaceMaterialCache[spec] { return cached }
    var material = latheMaterial(LatheFinish.body(for: tier), detail: false)
    if let textures = latheFaceTextures(for: spec) {
        material.baseColor = .init(tint: .white, texture: latheTexture(textures.color))
        material.normal = .init(texture: latheTexture(textures.normal))
        material.roughness = .init(scale: 1, texture: latheTexture(textures.roughness))
    }
    _latheFaceMaterialCache[spec] = material
    return material
}

@MainActor
private func latheFaceTextures(for spec: LatheFaceSpec, images: LatheFaceArt.Images? = nil) -> (color: TextureResource, normal: TextureResource, roughness: TextureResource)? {
    if let cached = _latheFaceTextureCache[spec] { return cached }
    guard let images = images ?? countedFaceImages(for: spec),
          let color = try? TextureResource(image: images.color, options: .init(semantic: .color)),
          let normal = try? TextureResource(image: images.normal, options: .init(semantic: .normal)),
          let roughness = try? TextureResource(image: images.roughness, options: .init(semantic: .raw)) else { return nil }
    RackWorkCounters.add(.faceTexturesUploaded)
    _latheFaceTextureCache[spec] = (color, normal, roughness)
    return (color, normal, roughness)
}

/// LatheFaceArt.images, counted.
nonisolated func countedFaceImages(for spec: LatheFaceSpec) -> LatheFaceArt.Images? {
    RackWorkCounters.add(.faceImagesDrawn)
    return LatheFaceArt.images(for: spec)
}

/// A plate the scene is about to show, for prepareLathePlates.
struct LathePlateRequest {
    let tierID: Int
    let weightKg: Double
    let engravingText: String
    let projection: BarbellPlateRenderProjection
    var showEngravings = true
}

/// Builds meshes, shared textures and every face the requests need before the scene is built:
/// face images are drawn off the main thread, then uploaded. Later calls with the same plates
/// return at once. Cancelling leaves whatever finished cached.
@MainActor
func prepareLathePlates(_ requests: [LathePlateRequest]) async {
    let interval = barbellSignposter.beginInterval("PrepareLathePlates", id: barbellSignposter.makeSignpostID())
    defer { barbellSignposter.endInterval("PrepareLathePlates", interval) }
    var pending: [LatheFaceSpec] = []
    for request in requests {
        guard let tier = PlateTier.all.first(where: { $0.id == request.tierID }) else { continue }
        _ = cachedLatheMesh(for: latheProfile(for: tier))
        _ = latheSlotMaterials(for: tier)
        let spec = latheFaceSpec(tier: tier, weightKg: request.weightKg, engravingText: request.engravingText,
                                 projection: request.projection, showEngravings: request.showEngravings)
        if _latheFaceTextureCache[spec] == nil, !pending.contains(spec) { pending.append(spec) }
    }
    guard !pending.isEmpty else { return }
    RackOpenTrace.mark("lathe.draw")
    let drawn = await Task.detached(priority: .userInitiated) { () -> [(LatheFaceSpec, LatheFaceArt.Images)] in
        pending.compactMap { spec in countedFaceImages(for: spec).map { (spec, $0) } }
    }.value
    RackOpenTrace.mark("lathe.drawn")
    for (spec, images) in drawn {
        _ = latheFaceTextures(for: spec, images: images)
    }
    RackOpenTrace.mark("lathe.uploaded")
}

/// The faces a scene shows in its first frame: each plate as built, with its engraving (bar
/// plates and their mirrors alike). See latheLaterRequests for the rest.
@MainActor
func latheFirstFrameRequests(_ plates: [EarnedPlate]) -> [LathePlateRequest] {
    plates.filter { !$0.isStarterPlate }.map {
        LathePlateRequest(tierID: $0.tierID, weightKg: $0.weightKg, engravingText: $0.engravingText,
                          projection: BarbellPlateRenderProjection(plate: $0))
    }
}

/// The faces the same plates need later: mirrors rebuilt after a load or a drag back onto the bar
/// carry no engraving.
@MainActor
func latheLaterRequests(_ plates: [EarnedPlate]) -> [LathePlateRequest] {
    plates.filter { !$0.isStarterPlate }.map {
        LathePlateRequest(tierID: $0.tierID, weightKg: $0.weightKg, engravingText: "",
                          projection: BarbellPlateRenderProjection(plate: $0))
    }
}

/// The lathe plate's visual: one ModelEntity, the shared mesh, body, hub and face materials, turned
/// so its axis lies along the bar (the legacy plate's orientation). makePlateEntity adds the same
/// collision, physics, audio and metadata components as for a legacy plate.
@MainActor
func makeLathePlateVisual(tier: PlateTier, weightKg: Double, engravingText: String, showEngravings: Bool,
                          projection: BarbellPlateRenderProjection) -> ModelEntity? {
    let profile = latheProfile(for: tier)
    guard let mesh = cachedLatheMesh(for: profile) else { return nil }
    let slots = latheSlotMaterials(for: tier)
    let spec = latheFaceSpec(tier: tier, weightKg: weightKg, engravingText: engravingText,
                             projection: projection, showEngravings: showEngravings)
    let face = latheFaceMaterial(for: spec, tier: tier)
    let entity = ModelEntity(mesh: mesh, materials: [slots.body, slots.hub, face])
    entity.name = "lathePlate"
    entity.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
    return entity
}
