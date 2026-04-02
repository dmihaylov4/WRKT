//
//  BarbellPreviewView.swift
//  WRKT
//
//  Customization preview: plate tiers, bar skins, emoji stickers.
//  All geometry is procedural. Sticker discs use emoji rendered to texture.
//

import SwiftUI
import RealityKit
import UIKit

// MARK: - Data models

struct PlateTier: Identifiable {
    let id: Int
    let name: String
    let rarity: Rarity
    let earnedBy: String
    let plateColor: UIColor
    let metallic: Float
    let roughness: Float
    let clearcoat: Float
    let clearcoatRoughness: Float
    let style: PlateStyle

    enum PlateStyle { case rawIron, castIron, bumper, brass, competition, polishedSteel, gold, starter }

    enum Rarity: String {
        case common = "Common", uncommon = "Uncommon", rare = "Rare"
        case epic = "Epic", legendary = "Legendary"

        var color: Color {
            switch self {
            case .common:    return .gray
            case .uncommon:  return Color(red: 0.2, green: 0.7, blue: 0.3)
            case .rare:      return Color(red: 0.2, green: 0.4, blue: 0.9)
            case .epic:      return Color(red: 0.6, green: 0.2, blue: 0.9)
            case .legendary: return Color(red: 0.9, green: 0.65, blue: 0.1)
            }
        }
    }

    static let all: [PlateTier] = [
        PlateTier(id: 0, name: "Raw Iron", rarity: .common,
                  earnedBy: "Complete your first workout",
                  plateColor: UIColor(red: 0.40, green: 0.18, blue: 0.07, alpha: 1),
                  metallic: 0.12, roughness: 0.97, clearcoat: 0, clearcoatRoughness: 0,
                  style: .rawIron),
        PlateTier(id: 1, name: "Cast Iron", rarity: .common,
                  earnedBy: "Complete 5 workouts",
                  plateColor: UIColor(red: 0.14, green: 0.14, blue: 0.14, alpha: 1),
                  metallic: 0.06, roughness: 0.94, clearcoat: 0, clearcoatRoughness: 0,
                  style: .castIron),
        PlateTier(id: 2, name: "Black Bumper", rarity: .uncommon,
                  earnedBy: "Complete 15 workouts",
                  plateColor: UIColor(red: 0.07, green: 0.07, blue: 0.07, alpha: 1),
                  metallic: 0, roughness: 0.78, clearcoat: 0.3, clearcoatRoughness: 0.25,
                  style: .bumper),
        PlateTier(id: 3, name: "Brass", rarity: .rare,
                  earnedBy: "Complete 25 workouts",
                  plateColor: UIColor(red: 0.75, green: 0.60, blue: 0.25, alpha: 1),
                  metallic: 0.85, roughness: 0.35, clearcoat: 0.2, clearcoatRoughness: 0.15,
                  style: .brass),
        PlateTier(id: 4, name: "Competition", rarity: .rare,
                  earnedBy: "Hit a personal record",
                  plateColor: UIColor(red: 0.82, green: 0.09, blue: 0.09, alpha: 1),
                  metallic: 0, roughness: 0.70, clearcoat: 0.45, clearcoatRoughness: 0.2,
                  style: .competition),
        PlateTier(id: 5, name: "Polished Steel", rarity: .epic,
                  earnedBy: "Complete 50 workouts",
                  plateColor: UIColor(red: 0.72, green: 0.76, blue: 0.80, alpha: 1),
                  metallic: 0.98, roughness: 0.10, clearcoat: 0, clearcoatRoughness: 0,
                  style: .polishedSteel),
        PlateTier(id: 6, name: "Gold", rarity: .legendary,
                  earnedBy: "Complete a 90-day streak",
                  plateColor: UIColor(red: 0.88, green: 0.68, blue: 0.12, alpha: 1),
                  metallic: 1.0, roughness: 0.05, clearcoat: 0.6, clearcoatRoughness: 0.05,
                  style: .gold),
    ]
}

struct BarSkin: Identifiable {
    let id: Int
    let name: String
    let rarity: PlateTier.Rarity
    let earnedBy: String
    let barColor: UIColor
    let metallic: Float
    let roughness: Float

    static let all: [BarSkin] = [
        BarSkin(id: 0, name: "Chrome", rarity: .common, earnedBy: "Default",
                barColor: UIColor(white: 0.85, alpha: 1), metallic: 1.0, roughness: 0.12),
        BarSkin(id: 1, name: "Matte Black", rarity: .uncommon, earnedBy: "10 workouts",
                barColor: UIColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1),
                metallic: 0.15, roughness: 0.92),
        BarSkin(id: 2, name: "Gold", rarity: .epic, earnedBy: "100 workouts",
                barColor: UIColor(red: 0.88, green: 0.68, blue: 0.12, alpha: 1),
                metallic: 1.0, roughness: 0.08),
        BarSkin(id: 3, name: "Cerakote", rarity: .rare, earnedBy: "30-day streak",
                barColor: UIColor(red: 0.20, green: 0.28, blue: 0.17, alpha: 1),
                metallic: 0.25, roughness: 0.80),
    ]
}

struct StickerOption: Identifiable {
    let id: Int
    let name: String
    let rarity: PlateTier.Rarity
    let earnedBy: String
    let emoji: String?  // nil = no sticker

    static let all: [StickerOption] = [
        StickerOption(id: 0, name: "None",      rarity: .common,    earnedBy: "Default",             emoji: nil),
        StickerOption(id: 1, name: "Fire",       rarity: .uncommon,  earnedBy: "5 workouts in a week", emoji: "🔥"),
        StickerOption(id: 2, name: "Lightning",  rarity: .rare,      earnedBy: "Hit a PR",             emoji: "⚡"),
        StickerOption(id: 3, name: "Diamond",    rarity: .epic,      earnedBy: "50 workouts",          emoji: "💎"),
        StickerOption(id: 4, name: "Crown",      rarity: .legendary, earnedBy: "90-day streak",        emoji: "👑"),
        StickerOption(id: 5, name: "Gains",      rarity: .uncommon,  earnedBy: "First strength workout", emoji: "💪"),
    ]
}

// MARK: - Plate textures

private struct PlateTextures {
    var albedo: TextureResource?
    var normal: TextureResource?
    var roughness: TextureResource?
    var metalness: TextureResource?
}

// MARK: - Scene state

private final class BarbellSceneState {
    var root: Entity?
    var rotAngle: Float = 0
    var lastTime: TimeInterval = 0
    var spinVelocity: Float = 0.35   // radians/sec; positive = auto-rotate initially
    var appliedTier = -1
    var appliedBar = -1
    var appliedSticker = -1
    var emojiTextures: [String: TextureResource] = [:]
    var plateTextures: [Int: PlateTextures] = [:]  // keyed by PlateTier.id
    var iblResource: EnvironmentResource?
    var weightDiscCache: [String: ModelEntity] = [:]   // key: "\(tierID)_\(Int(weightKg))"
    var engravingDiscCache: [String: ModelEntity] = [:]  // key: "\(tierID)_\(engravingText)"
}

// MARK: - Display Mode

enum BarbellDisplayMode {
    case editor                              // full editor, own profile
    case showcase(plates: [EarnedPlateInfo]) // compact 240pt, read-only
}

// MARK: - View

struct BarbellPreviewView: View {
    var mode: BarbellDisplayMode = .editor

    @State private var scene = BarbellSceneState()
    @State private var isDragging = false
    @State private var lastTranslationX: CGFloat = 0
    @State private var lastDt: Float = 1.0 / 60.0
    @State private var selectedPlateTip: EarnedPlateInfo? = nil

    @State private var activeTab = 0
    @State private var selectedTier = 0
    @State private var selectedBar = 0
    @State private var selectedSticker = 0
    @State private var addedPairs = 0

    private let tabs = ["Plates", "Bar", "Stickers"]
    private let plateThickness: Float = 0.03
    private let maxExtraPairs = 2

    private var showcasePlates: [EarnedPlateInfo]? {
        if case .showcase(let plates) = mode { return plates }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {

            // MARK: 3D scene
            ZStack(alignment: .bottom) {
                Color.black

                TimelineView(.animation) { timeline in
                    RealityView { content in
                        setupLights(in: &content)
                    } update: { content in
                        rebuildIfNeeded(content: &content)

                        let now = timeline.date.timeIntervalSinceReferenceDate
                        let dt = scene.lastTime > 0 ? Float(now - scene.lastTime) : 0
                        scene.lastTime = now
                        lastDt = dt > 0 ? dt : lastDt

                        if isDragging {
                            // Velocity is updated by drag gesture; no auto-advance
                        } else {
                            // Momentum decay: velocity * 0.92 per frame
                            scene.spinVelocity *= 0.92
                            scene.rotAngle += scene.spinVelocity * dt
                        }
                        scene.root?.orientation = simd_quatf(angle: scene.rotAngle, axis: SIMD3(0, 1, 0))
                    }
                    .gesture(
                        DragGesture()
                            .targetedToAnyEntity()
                            .onChanged { value in
                                isDragging = true
                                let delta = Float(value.translation.width - lastTranslationX) * 0.012
                                scene.spinVelocity = lastDt > 0 ? (-delta / lastDt) : -delta * 60
                                scene.rotAngle -= delta
                                scene.root?.orientation = simd_quatf(angle: scene.rotAngle, axis: SIMD3(0, 1, 0))
                                lastTranslationX = value.translation.width
                            }
                            .onEnded { _ in
                                isDragging = false
                                lastTranslationX = 0
                                // spinVelocity carries forward; decays via 0.92 multiplier above
                            }
                    )
                }

                if let info = currentSelectionInfo() {
                    VStack(spacing: 3) {
                        Text(info.name)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(info.rarity.rawValue)
                            .font(.caption.bold())
                            .foregroundStyle(info.rarity.color)
                        Text(info.earnedBy)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(.bottom, 16)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: showcasePlates != nil ? 240 : 360)

            // MARK: Customization controls
            if showcasePlates == nil {
            VStack(spacing: 0) {

                // Tab row
                HStack(spacing: 0) {
                    ForEach(tabs.indices, id: \.self) { i in
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) { activeTab = i }
                        } label: {
                            Text(tabs[i])
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .foregroundStyle(activeTab == i ? DS.Semantic.brand : DS.Semantic.textSecondary)
                        }
                    }
                }

                Divider()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        if activeTab == 0 {
                            ForEach(PlateTier.all) { tier in
                                OptionCard(
                                    name: tier.name, rarity: tier.rarity,
                                    swatch: Color(tier.plateColor),
                                    isSelected: selectedTier == tier.id
                                ) {
                                    selectedTier = tier.id
                                    addedPairs = 0
                                }
                            }
                        } else if activeTab == 1 {
                            ForEach(BarSkin.all) { skin in
                                OptionCard(
                                    name: skin.name, rarity: skin.rarity,
                                    swatch: Color(skin.barColor),
                                    isSelected: selectedBar == skin.id
                                ) {
                                    selectedBar = skin.id
                                    addedPairs = 0
                                }
                            }
                        } else {
                            ForEach(StickerOption.all) { sticker in
                                OptionCard(
                                    name: sticker.name, rarity: sticker.rarity,
                                    swatch: sticker.emoji != nil
                                        ? Color(red: 0.15, green: 0.15, blue: 0.15)
                                        : Color.white.opacity(0.1),
                                    emoji: sticker.emoji,
                                    isSelected: selectedSticker == sticker.id
                                ) {
                                    selectedSticker = sticker.id
                                    addedPairs = 0
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .frame(height: 104)

                Divider()

                // Add plates
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(2 + addedPairs * 2) plates loaded")
                            .font(.subheadline.bold())
                            .foregroundStyle(DS.Semantic.textPrimary)
                        Text("Max \(2 + maxExtraPairs * 2)")
                            .font(.caption)
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }
                    Spacer()
                    Button {
                        addPlatePair()
                    } label: {
                        Label("Add Plates", systemImage: "plus.circle.fill")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(addedPairs < maxExtraPairs ? DS.Semantic.brand : DS.Semantic.border)
                            .foregroundStyle(addedPairs < maxExtraPairs ? Color.black : DS.Semantic.textSecondary)
                            .clipShape(Capsule())
                    }
                    .disabled(addedPairs >= maxExtraPairs)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .background(DS.Semantic.card)
            } // end if showcasePlates == nil
        }
        .ignoresSafeArea(edges: .top)
        .navigationTitle("Barbell")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await preloadTextures()
        }
    }

    // MARK: - Plate animation

    private func addPlatePair() {
        guard addedPairs < maxExtraPairs, let root = scene.root else { return }
        let tier = PlateTier.all[selectedTier]
        let sticker = StickerOption.all[selectedSticker]
        let targetX = 0.37 + Float(addedPairs + 1) * plateThickness
        let plateOrientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))

        for sign: Float in [-1, 1] {
            let plate = makePlate(tier: tier, thickness: plateThickness, sticker: sticker)
            plate.position = SIMD3(sign * 0.8, 0, 0)
            root.addChild(plate)
            plate.move(
                to: Transform(
                    scale: SIMD3(repeating: 1),
                    rotation: plateOrientation,
                    translation: SIMD3(sign * targetX, 0, 0)
                ),
                relativeTo: root,
                duration: 0.5,
                timingFunction: .easeOut
            )
        }
        addedPairs += 1
    }

    // MARK: - Scene management

    private func setupLights(in content: inout RealityViewCameraContent) {
        let key = Entity()
        key.components[PointLightComponent.self] = PointLightComponent(
            color: .white, intensity: 3000, attenuationRadius: 10
        )
        key.position = SIMD3(0, 2, 2)
        content.add(key)

        let fill = Entity()
        fill.components[PointLightComponent.self] = PointLightComponent(
            color: .white, intensity: 800, attenuationRadius: 8
        )
        fill.position = SIMD3(-2, -1, 1)
        content.add(fill)
    }

    private func rebuildIfNeeded(content: inout RealityViewCameraContent) {
        guard scene.appliedTier != selectedTier
            || scene.appliedBar != selectedBar
            || scene.appliedSticker != selectedSticker
            || scene.root == nil
        else { return }

        scene.root?.removeFromParent()

        let root: Entity
        if let plates = showcasePlates {
            root = makeBarbellShowcase(plates: plates, skin: BarSkin.all[selectedBar])
            scene.spinVelocity = 0
        } else {
            root = makeBarbell(
                tier: PlateTier.all[selectedTier],
                skin: BarSkin.all[selectedBar],
                sticker: StickerOption.all[selectedSticker]
            )
        }

        // Apply image-based lighting if the HDRI has been loaded
        if let ibl = scene.iblResource {
            let iblEntity = Entity()
            iblEntity.components.set(ImageBasedLightComponent(source: .single(ibl), intensityExponent: 0.5))
            root.addChild(iblEntity)
            root.components.set(ImageBasedLightReceiverComponent(imageBasedLight: iblEntity))
        }

        content.add(root)
        root.orientation = simd_quatf(angle: scene.rotAngle, axis: SIMD3(0, 1, 0))

        scene.root = root
        scene.appliedTier = selectedTier
        scene.appliedBar = selectedBar
        scene.appliedSticker = selectedSticker
    }

    // MARK: - Barbell construction

    private func makeBarbell(tier: PlateTier, skin: BarSkin, sticker: StickerOption) -> Entity {
        let root = Entity()
        root.position = SIMD3(0, 0, -0.5)
        root.scale = SIMD3(repeating: 1.8)
        root.components.set(CollisionComponent(shapes: [.generateBox(size: SIMD3(1.2, 0.4, 0.4))]))
        root.components.set(InputTargetComponent())

        let barMat = pbrMaterial(color: skin.barColor, metallic: skin.metallic, roughness: skin.roughness)

        let bar = ModelEntity(mesh: .generateCylinder(height: 1.1, radius: 0.012), materials: [barMat])
        bar.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
        root.addChild(bar)

        for xOffset: Float in [-0.46, 0.46] {
            let collar = ModelEntity(mesh: .generateCylinder(height: 0.04, radius: 0.022), materials: [barMat])
            collar.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
            collar.position = SIMD3(xOffset, 0, 0)
            root.addChild(collar)
        }

        for xOffset: Float in [-0.37, -0.34, 0.34, 0.37] {
            let plate = makePlate(tier: tier, thickness: plateThickness, sticker: sticker)
            plate.position = SIMD3(xOffset, 0, 0)
            root.addChild(plate)
        }

        return root
    }

    // Builds a static barbell for showcase mode using EarnedPlateInfo plate data.
    // Plates are placed at the standard bilateral slot offsets (innermost first).
    // The no-sticker option is used since showcase is read-only.
    private func makeBarbellShowcase(plates: [EarnedPlateInfo], skin: BarSkin) -> Entity {
        let root = Entity()
        root.position = SIMD3(0, 0, -0.5)
        root.scale = SIMD3(repeating: 1.8)
        root.components.set(CollisionComponent(shapes: [.generateBox(size: SIMD3(1.2, 0.4, 0.4))]))
        root.components.set(InputTargetComponent())

        let barMat = pbrMaterial(color: skin.barColor, metallic: skin.metallic, roughness: skin.roughness)

        let bar = ModelEntity(mesh: .generateCylinder(height: 1.1, radius: 0.012), materials: [barMat])
        bar.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
        root.addChild(bar)

        for xOffset: Float in [-0.46, 0.46] {
            let collar = ModelEntity(mesh: .generateCylinder(height: 0.04, radius: 0.022), materials: [barMat])
            collar.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
            collar.position = SIMD3(xOffset, 0, 0)
            root.addChild(collar)
        }

        // Standard bilateral offsets: slot 0=innermost, slot 3=outermost.
        // Each entry maps to a left/right pair of x-offsets.
        let slotOffsets: [[Float]] = [
            [-0.34, 0.34],
            [-0.37, 0.37],
            [-0.40, 0.40],
            [-0.43, 0.43],
        ]
        let noSticker = StickerOption(id: 0, name: "None", rarity: .common, earnedBy: "", emoji: nil)

        for (index, info) in plates.prefix(4).enumerated() {
            guard let tier = PlateTier.all.first(where: { $0.id == info.tierID }) else { continue }
            let offsets = slotOffsets[index]
            for xOffset in offsets {
                let plate = makePlate(
                    tier: tier,
                    thickness: plateThickness,
                    sticker: noSticker,
                    weightKg: info.weightKg,
                    engravingText: info.engravingText
                )
                plate.position = SIMD3(xOffset, 0, 0)
                root.addChild(plate)
            }
        }

        return root
    }

    // MARK: - Per-tier plate construction

    private func makePlate(tier: PlateTier, thickness: Float, sticker: StickerOption,
                           weightKg: Double = 0, engravingText: String = "") -> ModelEntity {
        let plateEntity: ModelEntity
        switch tier.style {
        case .rawIron:  plateEntity = makeRustyIronPlate(tier: tier, thickness: thickness, sticker: sticker)
        case .castIron: plateEntity = makeCastIronPlate(tier: tier, thickness: thickness, sticker: sticker)
        case .bumper:   plateEntity = makeBumperPlate(tier: tier, thickness: thickness, sticker: sticker)
        case .brass:    plateEntity = makeBrassPlate(tier: tier, thickness: thickness, sticker: sticker)
        default:        plateEntity = makeCompetitionPlate(tier: tier, thickness: thickness, sticker: sticker)
        }

        // Attach weight disc (skip starter plates)
        if tier.style != .starter && weightKg > 0 {
            let key = "\(tier.id)_\(Int(weightKg))"
            let weightDisc = scene.weightDiscCache[key] ?? makeWeightDisc(weightKg: weightKg, tierID: tier.id)
            scene.weightDiscCache[key] = weightDisc
            plateEntity.addChild(weightDisc.clone(recursive: false))
        }

        // Attach engraving disc
        if tier.style != .starter && !engravingText.isEmpty {
            let key = "\(tier.id)_\(engravingText)"
            let engravingDisc = scene.engravingDiscCache[key] ?? makeEngravingDisc(text: engravingText, tierID: tier.id)
            scene.engravingDiscCache[key] = engravingDisc
            plateEntity.addChild(engravingDisc.clone(recursive: false))
        }

        return plateEntity
    }

    /// Real PBR texture (Metal041C) over a rust-brown tinted base
    private func makeRustyIronPlate(tier: PlateTier, thickness: Float, sticker: StickerOption) -> ModelEntity {
        let radius: Float = 0.18
        var mat = pbrMaterial(color: tier.plateColor, metallic: tier.metallic, roughness: tier.roughness)
        if let tex = scene.plateTextures[tier.id] {
            if let albedo   = tex.albedo   { mat.baseColor  = .init(tint: .white,              texture: .init(albedo)) }
            if let normal   = tex.normal   { mat.normal     = .init(texture: .init(normal)) }
            if let roughness = tex.roughness { mat.roughness = .init(texture: .init(roughness)) }
            if let metalness = tex.metalness { mat.metallic  = .init(texture: .init(metalness)) }
        }
        let plate = ModelEntity(
            mesh: .generateCylinder(height: thickness, radius: radius),
            materials: [mat]
        )
        plate.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))

        applyStickerIfNeeded(sticker, to: plate, thickness: thickness)
        return plate
    }

    /// Raised outer rim + inner recessed face with sand-cast texture
    private func makeCastIronPlate(tier: PlateTier, thickness: Float, sticker: StickerOption) -> ModelEntity {
        let radius: Float = 0.18

        var outerMat = pbrMaterial(color: tier.plateColor, metallic: tier.metallic, roughness: tier.roughness)
        var innerMat = pbrMaterial(color: UIColor(red: 0.20, green: 0.20, blue: 0.20, alpha: 1),
                                    metallic: 0.04, roughness: 0.96)
        if let tex = scene.plateTextures[tier.id] {
            if let albedo    = tex.albedo    { outerMat.baseColor = .init(tint: .white,                      texture: .init(albedo))
                                               innerMat.baseColor = .init(tint: UIColor(white: 0.6, alpha: 1), texture: .init(albedo)) }
            if let normal    = tex.normal    { outerMat.normal    = .init(texture: .init(normal))
                                               innerMat.normal    = .init(texture: .init(normal)) }
            if let roughness = tex.roughness { outerMat.roughness = .init(texture: .init(roughness))
                                               innerMat.roughness = .init(texture: .init(roughness)) }
            if let metalness = tex.metalness { outerMat.metallic  = .init(texture: .init(metalness))
                                               innerMat.metallic  = .init(texture: .init(metalness)) }
        }
        let plate = ModelEntity(
            mesh: .generateCylinder(height: thickness, radius: radius),
            materials: [outerMat]
        )
        plate.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
        let inner = ModelEntity(
            mesh: .generateCylinder(height: thickness * 0.72, radius: radius * 0.86),
            materials: [innerMat]
        )
        plate.addChild(inner)

        // Raised boss ring around hub
        let boss = ModelEntity(
            mesh: .generateCylinder(height: thickness * 0.82, radius: radius * 0.22),
            materials: [pbrMaterial(color: tier.plateColor, metallic: 0.06, roughness: 0.95)]
        )
        plate.addChild(boss)

        // Chrome hub
        let hub = ModelEntity(
            mesh: .generateCylinder(height: thickness + 0.003, radius: 0.028),
            materials: [chromeMaterial()]
        )
        plate.addChild(hub)

        applyStickerIfNeeded(sticker, to: plate, thickness: thickness)
        return plate
    }

    /// Black bumper with real rubber PBR texture (Rubber003) + gray edge band + chrome hub
    private func makeBumperPlate(tier: PlateTier, thickness: Float, sticker: StickerOption) -> ModelEntity {
        let radius: Float = 0.18
        var mat = pbrMaterial(color: tier.plateColor, metallic: tier.metallic,
                              roughness: tier.roughness, clearcoat: tier.clearcoat,
                              clearcoatRoughness: tier.clearcoatRoughness)
        if let tex = scene.plateTextures[tier.id] {
            if let albedo    = tex.albedo    { mat.baseColor  = .init(tint: .white, texture: .init(albedo)) }
            if let normal    = tex.normal    { mat.normal     = .init(texture: .init(normal)) }
            if let roughness = tex.roughness { mat.roughness  = .init(texture: .init(roughness)) }
        }
        let plate = ModelEntity(
            mesh: .generateCylinder(height: thickness, radius: radius),
            materials: [mat]
        )
        plate.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))

        // Gray outer edge band
        let edgeBand = ModelEntity(
            mesh: .generateCylinder(height: thickness * 0.35, radius: radius + 0.002),
            materials: [pbrMaterial(color: UIColor(white: 0.35, alpha: 1), metallic: 0.1, roughness: 0.88)]
        )
        plate.addChild(edgeBand)

        // Chrome hub
        let hub = ModelEntity(
            mesh: .generateCylinder(height: thickness + 0.003, radius: 0.028),
            materials: [chromeMaterial()]
        )
        plate.addChild(hub)

        applyStickerIfNeeded(sticker, to: plate, thickness: thickness)
        return plate
    }

    /// Brass plate with real PBR texture (Metal048C) + chrome hub
    private func makeBrassPlate(tier: PlateTier, thickness: Float, sticker: StickerOption) -> ModelEntity {
        let radius: Float = 0.18
        var mat = pbrMaterial(color: tier.plateColor, metallic: tier.metallic, roughness: tier.roughness,
                              clearcoat: tier.clearcoat, clearcoatRoughness: tier.clearcoatRoughness)
        if let tex = scene.plateTextures[tier.id] {
            if let albedo    = tex.albedo    { mat.baseColor  = .init(tint: .white, texture: .init(albedo)) }
            if let normal    = tex.normal    { mat.normal     = .init(texture: .init(normal)) }
            if let roughness = tex.roughness { mat.roughness  = .init(texture: .init(roughness)) }
            if let metalness = tex.metalness { mat.metallic   = .init(texture: .init(metalness)) }
        }
        let plate = ModelEntity(
            mesh: .generateCylinder(height: thickness, radius: radius),
            materials: [mat]
        )
        plate.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))

        // Chrome hub
        let hub = ModelEntity(
            mesh: .generateCylinder(height: thickness + 0.003, radius: 0.028),
            materials: [chromeMaterial()]
        )
        plate.addChild(hub)

        applyStickerIfNeeded(sticker, to: plate, thickness: thickness)
        return plate
    }

    /// Competition / polished / gold: chrome face rings + hub
    private func makeCompetitionPlate(tier: PlateTier, thickness: Float, sticker: StickerOption) -> ModelEntity {
        let radius: Float = 0.18
        let plate = ModelEntity(
            mesh: .generateCylinder(height: thickness, radius: radius),
            materials: [pbrMaterial(color: tier.plateColor, metallic: tier.metallic,
                                    roughness: tier.roughness, clearcoat: tier.clearcoat,
                                    clearcoatRoughness: tier.clearcoatRoughness)]
        )
        plate.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))

        // Chrome hub
        let hub = ModelEntity(
            mesh: .generateCylinder(height: thickness + 0.003, radius: 0.028),
            materials: [chromeMaterial()]
        )
        plate.addChild(hub)

        // Chrome face rings on both sides
        for faceSign: Float in [1, -1] {
            let yPos = faceSign * (thickness / 2 + 0.003)
            for ringRadius: Float in [radius * 0.82, radius * 0.42] {
                let ring = ModelEntity(
                    mesh: .generateCylinder(height: 0.004, radius: ringRadius),
                    materials: [chromeMaterial()]
                )
                ring.position = SIMD3(0, yPos, 0)
                plate.addChild(ring)
            }
        }

        applyStickerIfNeeded(sticker, to: plate, thickness: thickness)
        return plate
    }

    // MARK: - Sticker

    private func applyStickerIfNeeded(_ sticker: StickerOption, to plate: ModelEntity, thickness: Float) {
        guard let emoji = sticker.emoji else { return }

        var mat = UnlitMaterial()
        if let texture = scene.emojiTextures[emoji] {
            mat.color = .init(texture: .init(texture))
        } else {
            mat.color = .init(tint: UIColor(white: 0.9, alpha: 1))
        }

        let disc = ModelEntity(
            mesh: .generateCylinder(height: 0.005, radius: 0.036),
            materials: [mat]
        )
        disc.position = SIMD3(0, thickness / 2 + 0.005, 0)
        plate.addChild(disc)
    }

    // MARK: - Texture preloading

    private func preloadTextures() async {
        // Real PBR textures from bundle
        let bundleSets: [(id: Int, prefix: String)] = [
            (0, "RustyIron"),   // Metal041C
            (1, "CastIron"),    // Metal046B
            (2, "Rubber"),      // Rubber003
            (6, "Brass"),       // Metal048C
        ]
        for entry in bundleSets where scene.plateTextures[entry.id] == nil {
            scene.plateTextures[entry.id] = loadBundleTextures(prefix: entry.prefix)
        }

        // IBL from HDRI
        if scene.iblResource == nil {
            scene.iblResource = try? await EnvironmentResource(named: "IndoorHDRI")
        }

        if [0, 1, 2, 6].contains(selectedTier) || scene.iblResource != nil {
            scene.appliedTier = -1
        }

        // Emoji textures
        for option in StickerOption.all {
            guard let emoji = option.emoji, scene.emojiTextures[emoji] == nil else { continue }
            if let texture = makeEmojiTexture(emoji) {
                scene.emojiTextures[emoji] = texture
            }
        }
        scene.appliedSticker = -1
    }

    private func loadBundleTextures(prefix: String) -> PlateTextures {
        func load(_ suffix: String, semantic: TextureResource.Semantic) -> TextureResource? {
            let name = "\(prefix)_\(suffix)"
            guard let url = Bundle.main.url(forResource: name, withExtension: "jpg") else {
                AppLogger.debug("Plate texture URL not found: \(name).jpg", category: AppLogger.ui)
                return nil
            }
            guard let uiImage = UIImage(contentsOfFile: url.path),
                  let sourceCG = uiImage.cgImage else {
                AppLogger.debug("Plate texture decode failed: \(name).jpg", category: AppLogger.ui)
                return nil
            }
            let w = sourceCG.width, h = sourceCG.height
            guard let ctx = CGContext(
                data: nil, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            ctx.draw(sourceCG, in: CGRect(x: 0, y: 0, width: w, height: h))
            guard let rgba = ctx.makeImage() else { return nil }
            guard let tex = try? TextureResource.generate(from: rgba, options: .init(semantic: semantic)) else {
                AppLogger.debug("Plate texture generation failed: \(name).jpg", category: AppLogger.ui)
                return nil
            }
            return tex
        }
        return PlateTextures(
            albedo:    load("Color",     semantic: .color),
            normal:    load("Normal",    semantic: .normal),
            roughness: load("Roughness", semantic: .color),
            metalness: load("Metalness", semantic: .color)
        )
    }

    private func makeEmojiTexture(_ emoji: String) -> TextureResource? {
        let side: CGFloat = 256
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let image = renderer.image { _ in
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 200)]
            let str = emoji as NSString
            let sz = str.size(withAttributes: attrs)
            str.draw(at: CGPoint(x: (side - sz.width) / 2, y: (side - sz.height) / 2),
                     withAttributes: attrs)
        }
        guard let cg = image.cgImage else { return nil }
        return try? TextureResource.generate(from: cg, options: .init(semantic: .color))
    }

    // MARK: - Weight and engraving disc rendering

    /// Renders the weight number onto a thin disc mesh placed at the plate face.
    /// Cache key: "\(tierID)_\(Int(weightKg))" -- reuse across identical plates.
    private func makeWeightDisc(weightKg: Double, tierID: Int) -> ModelEntity {
        let canvas = CGSize(width: 256, height: 256)
        let renderer = UIGraphicsImageRenderer(size: canvas)
        let image = renderer.image { ctx in
            let textColor: UIColor = [0, 1, 2].contains(tierID) ? .white : .black
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 160, weight: .black),
                .foregroundColor: textColor
            ]
            let text = weightKg.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(weightKg))" : String(format: "%.1f", weightKg)
            let size = text.size(withAttributes: attrs)
            let origin = CGPoint(x: (canvas.width - size.width) / 2,
                                 y: (canvas.height - size.height) / 2)
            text.draw(at: origin, withAttributes: attrs)
        }
        guard let cgImage = image.cgImage,
              let texture = try? TextureResource.generate(from: cgImage, options: .init(semantic: .color))
        else { return ModelEntity() }

        var material = UnlitMaterial()
        material.color = .init(texture: .init(texture))
        material.blending = .transparent(opacity: 1.0)

        let disc = ModelEntity(mesh: .generateCylinder(height: 0.002, radius: 0.08),
                               materials: [material])
        // Position on the front face of the plate (z offset slightly proud of plate surface)
        disc.position = SIMD3(0, 0, 0.022)
        return disc
    }

    /// Renders the engraving label onto a second disc placed at 60% radius from center.
    private func makeEngravingDisc(text: String, tierID: Int) -> ModelEntity {
        let canvas = CGSize(width: 256, height: 64)
        let renderer = UIGraphicsImageRenderer(size: canvas)
        let image = renderer.image { ctx in
            let textColor: UIColor = [0, 1, 2].contains(tierID) ? .white : .black
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 28, weight: .light),
                .foregroundColor: textColor,
                .kern: 2.0
            ]
            let upper = text.uppercased()
            let size = upper.size(withAttributes: attrs)
            let origin = CGPoint(x: (canvas.width - size.width) / 2,
                                 y: (canvas.height - size.height) / 2)
            upper.draw(at: origin, withAttributes: attrs)
        }
        guard let cgImage = image.cgImage,
              let texture = try? TextureResource.generate(from: cgImage, options: .init(semantic: .color))
        else { return ModelEntity() }

        var material = UnlitMaterial()
        material.color = .init(texture: .init(texture))
        material.blending = .transparent(opacity: 1.0)

        // Narrow rectangular disc; offset radially so it sits below the weight number
        let disc = ModelEntity(mesh: .generateBox(width: 0.09, height: 0.022, depth: 0.002),
                               materials: [material])
        disc.position = SIMD3(0, -0.055, 0.022)
        return disc
    }

    // MARK: - Materials

    private func pbrMaterial(color: UIColor, metallic: Float, roughness: Float,
                              clearcoat: Float = 0, clearcoatRoughness: Float = 0) -> PhysicallyBasedMaterial {
        var mat = PhysicallyBasedMaterial()
        mat.baseColor = .init(tint: color)
        mat.metallic = .init(floatLiteral: metallic)
        mat.roughness = .init(floatLiteral: roughness)
        mat.clearcoat = .init(floatLiteral: clearcoat)
        mat.clearcoatRoughness = .init(floatLiteral: clearcoatRoughness)
        return mat
    }

    private func chromeMaterial() -> PhysicallyBasedMaterial {
        pbrMaterial(color: UIColor(white: 0.85, alpha: 1), metallic: 1.0, roughness: 0.12)
    }

    // MARK: - Helpers

    private func currentSelectionInfo() -> (name: String, rarity: PlateTier.Rarity, earnedBy: String)? {
        switch activeTab {
        case 0: let t = PlateTier.all[selectedTier]; return (t.name, t.rarity, t.earnedBy)
        case 1: let s = BarSkin.all[selectedBar];    return (s.name, s.rarity, s.earnedBy)
        case 2: let s = StickerOption.all[selectedSticker]; return (s.name, s.rarity, s.earnedBy)
        default: return nil
        }
    }
}

// MARK: - Option card

private struct OptionCard: View {
    let name: String
    let rarity: PlateTier.Rarity
    let swatch: Color
    var emoji: String? = nil
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(swatch)
                        .frame(width: 44, height: 44)
                        .overlay(Circle().strokeBorder(isSelected ? rarity.color : Color.clear, lineWidth: 2.5))
                    if let emoji {
                        Text(emoji).font(.system(size: 24))
                    }
                }
                Text(name)
                    .font(.caption2.bold())
                    .foregroundStyle(isSelected ? .white : DS.Semantic.textSecondary)
                    .lineLimit(1)
                Text(rarity.rawValue)
                    .font(.system(size: 9))
                    .foregroundStyle(rarity.color)
            }
            .frame(width: 64)
            .padding(.vertical, 6).padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 10).fill(isSelected ? DS.Semantic.border : Color.clear))
        }
        .buttonStyle(.plain)
    }
}
