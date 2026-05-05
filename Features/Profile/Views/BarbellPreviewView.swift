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


// MARK: - Scene state

private final class BarbellSceneState {
    var root: Entity?
    var rotAngle: Float = -0.42
    var lastTime: TimeInterval = 0
    var lastDt: Float = 1.0 / 60.0
    var spinVelocity: Float = 0.35   // radians/sec; positive = auto-rotate initially
    var appliedTier = -1
    var appliedBar = -1
    var appliedSticker = -1
    var appliedRoomThemeID = ""
    var appliedRackStyleID = ""
    var appliedShowPlateEngravings = true
    var appliedShowcaseSignature = ""
    var emojiTextures: [String: TextureResource] = [:]
    var plateTextures: [Int: PlateTextures] = [:]  // keyed by PlateTier.id
    var competitionFaceTextures: [String: TextureResource] = [:]
    var iblResource: EnvironmentResource?
    var weightDiscCache: [String: ModelEntity] = [:]   // key: "\(tierID)_\(Int(weightKg))"
    var engravingDiscCache: [String: ModelEntity] = [:]  // key: "\(tierID)_\(engravingText)"
}

// MARK: - Display Mode

enum BarbellDisplayMode {
    case editor                              // full editor, own profile
    case showcase(plates: [EarnedPlateInfo]) // compact 240pt, read-only
}

func barbellPreviewSelectionInfo(
    activeTab: Int,
    selectedTier: Int,
    selectedBar: Int,
    selectedSticker: Int
) -> (name: String, rarity: PlateTier.Rarity, earnedBy: String)? {
    switch activeTab {
    case 0:
        guard let tier = barbellPreviewTier(forSelection: selectedTier) else { return nil }
        return (tier.name, tier.rarity, tier.earnedBy)
    case 1:
        guard BarSkin.all.indices.contains(selectedBar) else { return nil }
        let skin = BarSkin.all[selectedBar]
        return (skin.name, skin.rarity, skin.earnedBy)
    case 2:
        guard StickerOption.all.indices.contains(selectedSticker) else { return nil }
        let sticker = StickerOption.all[selectedSticker]
        return (sticker.name, sticker.rarity, sticker.earnedBy)
    default:
        return nil
    }
}

func barbellPreviewTier(forSelection selectedTier: Int) -> PlateTier? {
    if let tier = PlateTier.all.first(where: { $0.id == selectedTier }) {
        return tier
    }
    guard PlateTier.all.indices.contains(selectedTier) else { return nil }
    return PlateTier.all[selectedTier]
}

func barbellShowcaseVisualHalfDepth(for tier: PlateTier) -> Float {
    let profile = PlateVisualDesign.profile(for: tier.style)
    // Face labels, lips, and outer bands sit proud of the base plate. The showcase
    // stack must reserve that depth or adjacent faces z-fight when thick red plates
    // sit next to another plate.
    return profile.thickness * 0.5 + 0.012
}

func barbellShowcaseRightSideOffsets(for plates: [EarnedPlateInfo]) -> [Float] {
    let tiers = plates.prefix(4).compactMap { info in
        PlateTier.all.first(where: { $0.id == info.tierID })
    }
    guard !tiers.isEmpty else { return [] }

    let minimumInnerOffset: Float = 0.34
    let clearance: Float = 0.004
    var offsets: [Float] = []
    var previousHalfDepth: Float = 0

    for tier in tiers {
        let halfDepth = barbellShowcaseVisualHalfDepth(for: tier)
        if offsets.isEmpty {
            offsets.append(minimumInnerOffset)
        } else if let previousOffset = offsets.last {
            offsets.append(previousOffset + previousHalfDepth + halfDepth + clearance)
        }
        previousHalfDepth = halfDepth
    }

    return offsets
}

// MARK: - View

struct BarbellPreviewView: View {
    var mode: BarbellDisplayMode = .editor
    private let selectedRoomThemeID: String
    private let selectedRackStyleID: String
    private let showPlateEngravings: Bool

    @State private var scene = BarbellSceneState()
    @State private var isDragging = false
    @State private var lastTranslationX: CGFloat = 0
    @State private var selectedPlateTip: EarnedPlateInfo? = nil

    @State private var activeTab = 0
    @State private var selectedTier = 0
    @State private var selectedBar = 0
    @State private var selectedSticker = 0
    @State private var addedPairs = 0

    init(
        mode: BarbellDisplayMode = .editor,
        selectedBarID: Int = 0,
        selectedRoomThemeID: String = BarbellCustomizationDefaults.roomThemeID,
        selectedRackStyleID: String = BarbellCustomizationDefaults.rackStyleID,
        showPlateEngravings: Bool = BarbellCustomizationDefaults.showPlateEngravings
    ) {
        self.mode = mode
        self.selectedRoomThemeID = selectedRoomThemeID
        self.selectedRackStyleID = selectedRackStyleID
        self.showPlateEngravings = showPlateEngravings
        _selectedBar = State(initialValue: max(0, min(selectedBarID, BarSkin.all.count - 1)))
    }

    private let tabs = ["Plates", "Bar", "Stickers"]
    private let plateThickness: Float = 0.03
    private let maxExtraPairs = 2

    private var showcasePlates: [EarnedPlateInfo]? {
        if case .showcase(let plates) = mode { return plates }
        return nil
    }

    private var showcaseSignature: String {
        guard let plates = showcasePlates else { return "" }
        return plates
            .map { "\($0.tierID):\($0.weightKg):\($0.engravingText):\($0.earnedByEvent)" }
            .joined(separator: "|")
    }

    var body: some View {
        VStack(spacing: 0) {

            // MARK: 3D scene
            ZStack(alignment: .bottom) {
                Color.black
                    .overlay(roomBackgroundColor)

                TimelineView(.animation) { timeline in
                    RealityView { content in
                        setupLights(in: &content)
                    } update: { content in
                        rebuildIfNeeded(content: &content)

                        let now = timeline.date.timeIntervalSinceReferenceDate
                        let dt = scene.lastTime > 0 ? Float(now - scene.lastTime) : 0
                        scene.lastTime = now
                        scene.lastDt = dt > 0 ? dt : scene.lastDt

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
                                scene.spinVelocity = scene.lastDt > 0 ? (-delta / scene.lastDt) : -delta * 60
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
                            .dsFont(.headline)
                            .foregroundStyle(.white)
                        Text(info.rarity.rawValue)
                            .dsFont(.caption, weight: .bold)
                            .foregroundStyle(info.rarity.color)
                        Text(info.earnedBy)
                            .dsFont(.caption2)
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
                                .dsFont(.subheadline, weight: .bold)
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
                            .dsFont(.subheadline, weight: .bold)
                            .foregroundStyle(DS.Semantic.textPrimary)
                        Text("Max \(2 + maxExtraPairs * 2)")
                            .dsFont(.caption)
                            .foregroundStyle(DS.Semantic.textSecondary)
                    }
                    Spacer()
                    Button {
                        addPlatePair()
                    } label: {
                        Label("Add Plates", systemImage: "plus.circle.fill")
                            .dsFont(.subheadline, weight: .bold)
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
        guard let tier = barbellPreviewTier(forSelection: selectedTier) else { return }
        let sticker = StickerOption.all[selectedSticker]
        let targetX = 0.37 + Float(addedPairs + 1) * plateThickness
        let plateOrientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))

        for sign: Float in [-1, 1] {
            let plate = makePlate(tier: tier, thickness: plateThickness, sticker: sticker, weightKg: 20.0)
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
            color: .white, intensity: 6_200, attenuationRadius: 12
        )
        key.position = SIMD3(0, 2, 2)
        content.add(key)

        let fill = Entity()
        fill.components[PointLightComponent.self] = PointLightComponent(
            color: UIColor(white: 0.94, alpha: 1), intensity: 4_400, attenuationRadius: 10
        )
        fill.position = SIMD3(-1.2, 0.18, 0.95)
        content.add(fill)

        let frontWash = Entity()
        frontWash.components[PointLightComponent.self] = PointLightComponent(
            color: .white, intensity: 3_800, attenuationRadius: 8
        )
        frontWash.position = SIMD3(0.65, 0.85, 1.45)
        content.add(frontWash)
    }

    private func rebuildIfNeeded(content: inout RealityViewCameraContent) {
        guard scene.appliedTier != selectedTier
            || scene.appliedBar != selectedBar
            || scene.appliedSticker != selectedSticker
            || scene.appliedRoomThemeID != selectedRoomThemeID
            || scene.appliedRackStyleID != selectedRackStyleID
            || scene.appliedShowPlateEngravings != showPlateEngravings
            || scene.appliedShowcaseSignature != showcaseSignature
            || scene.root == nil
        else { return }

        scene.root?.removeFromParent()

        let root: Entity
        if let plates = showcasePlates {
            root = makeBarbellShowcase(plates: plates, skin: BarSkin.all[selectedBar])
            scene.spinVelocity = 0.35   // allow auto-spin and drag in showcase
        } else {
            guard let selectedPlateTier = barbellPreviewTier(forSelection: selectedTier) else { return }
            root = makeBarbell(
                tier: selectedPlateTier,
                skin: BarSkin.all[selectedBar],
                sticker: StickerOption.all[selectedSticker]
            )
        }

        // Apply image-based lighting if the HDRI has been loaded
        if let ibl = scene.iblResource {
            let iblEntity = Entity()
            iblEntity.components.set(ImageBasedLightComponent(source: .single(ibl), intensityExponent: 1.55))
            root.addChild(iblEntity)
            root.components.set(ImageBasedLightReceiverComponent(imageBasedLight: iblEntity))
        }

        content.add(root)
        root.orientation = simd_quatf(angle: scene.rotAngle, axis: SIMD3(0, 1, 0))

        scene.root = root
        scene.appliedTier = selectedTier
        scene.appliedBar = selectedBar
        scene.appliedSticker = selectedSticker
        scene.appliedRoomThemeID = selectedRoomThemeID
        scene.appliedRackStyleID = selectedRackStyleID
        scene.appliedShowPlateEngravings = showPlateEngravings
        scene.appliedShowcaseSignature = showcaseSignature
    }

    // MARK: - Barbell construction

    private var roomBackgroundColor: Color {
        switch selectedRoomThemeID {
        case "concrete_room":
            return Color(red: 0.18, green: 0.18, blue: 0.17)
        case "competition_platform":
            return Color(red: 0.03, green: 0.05, blue: 0.08)
        default:
            return Color(red: 0.02, green: 0.02, blue: 0.025)
        }
    }

    private func addRoomAndRack(to root: Entity) {
        let rackMat = rackMaterial()
        for xOffset: Float in [-0.53, 0.53] {
            let upright = ModelEntity(
                mesh: .generateBox(width: 0.018, height: 0.28, depth: 0.018),
                materials: [rackMat]
            )
            upright.position = SIMD3(xOffset, -0.05, -0.035)
            root.addChild(upright)

            let hook = ModelEntity(
                mesh: .generateBox(width: 0.045, height: 0.018, depth: 0.025),
                materials: [rackMat]
            )
            hook.position = SIMD3(xOffset - (xOffset.sign == .minus ? -0.014 : 0.014), 0.02, -0.01)
            root.addChild(hook)
        }
    }

    private func rackMaterial() -> PhysicallyBasedMaterial {
        switch selectedRackStyleID {
        case "brushed_steel":
            return pbrMaterial(color: UIColor(white: 0.70, alpha: 1), metallic: 0.9, roughness: 0.22)
        case "brass_accent_rack":
            return pbrMaterial(color: UIColor(red: 0.78, green: 0.58, blue: 0.24, alpha: 1), metallic: 0.82, roughness: 0.30)
        default:
            return pbrMaterial(color: UIColor(white: 0.055, alpha: 1), metallic: 0.25, roughness: 0.68)
        }
    }

    private func makeBarbell(tier: PlateTier, skin: BarSkin, sticker: StickerOption) -> Entity {
        let root = Entity()
        root.position = SIMD3(0, 0, -0.5)
        root.scale = SIMD3(repeating: 1.8)
        root.components.set(CollisionComponent(shapes: [.generateBox(size: SIMD3(1.2, 0.4, 0.4))]))
        root.components.set(InputTargetComponent())

        let barMat = pbrMaterial(color: skin.barColor, metallic: skin.metallic, roughness: skin.roughness)
        addRoomAndRack(to: root)

        let bar = ModelEntity(mesh: .generateCylinder(height: 1.1, radius: 0.012), materials: [barMat])
        bar.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
        root.addChild(bar)

        // Sleeves fill the plate bore (radius 0.034) so plates rest on them visually.
        // Covers from x=±0.28 to x=±0.46 (all possible plate positions including max addedPairs).
        for xSign: Float in [-1, 1] {
            let sleeve = ModelEntity(mesh: .generateCylinder(height: 0.18, radius: 0.034), materials: [barMat])
            sleeve.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
            sleeve.position = SIMD3(xSign * 0.37, 0, 0)
            root.addChild(sleeve)
        }

        for xOffset: Float in [-0.46, 0.46] {
            let collar = ModelEntity(mesh: .generateCylinder(height: 0.04, radius: 0.036), materials: [barMat])
            collar.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
            collar.position = SIMD3(xOffset, 0, 0)
            root.addChild(collar)
        }

        for xOffset: Float in [-0.37, -0.34, 0.34, 0.37] {
            let plate = makePlate(tier: tier, thickness: plateThickness, sticker: sticker, weightKg: 20.0)
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
        addRoomAndRack(to: root)

        let rightOffsets = barbellShowcaseRightSideOffsets(for: plates)
        let outermostPlateEdge = zip(rightOffsets, plates.prefix(4)).reduce(Float(0.43)) { result, pair in
            guard let tier = PlateTier.all.first(where: { $0.id == pair.1.tierID }) else { return result }
            return max(result, pair.0 + barbellShowcaseVisualHalfDepth(for: tier))
        }
        let collarOffset = max(Float(0.46), outermostPlateEdge + 0.030)
        let barLength = max(Float(1.1), (collarOffset + 0.10) * 2)

        let bar = ModelEntity(mesh: .generateCylinder(height: barLength, radius: 0.012), materials: [barMat])
        bar.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
        root.addChild(bar)

        // Sleeves fill the plate bore so plates rest on them when viewed from the side.
        let sleeveOuter = collarOffset + 0.02
        let sleeveHeight = sleeveOuter - 0.28
        let sleeveCenterAbs = (0.28 + sleeveOuter) / 2
        for xSign: Float in [-1, 1] {
            let sleeve = ModelEntity(mesh: .generateCylinder(height: sleeveHeight, radius: 0.034), materials: [barMat])
            sleeve.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
            sleeve.position = SIMD3(xSign * sleeveCenterAbs, 0, 0)
            root.addChild(sleeve)
        }

        for xOffset in [-collarOffset, collarOffset] {
            let collar = ModelEntity(mesh: .generateCylinder(height: 0.04, radius: 0.036), materials: [barMat])
            collar.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
            collar.position = SIMD3(xOffset, 0, 0)
            root.addChild(collar)
        }

        // Bilateral offsets are depth-aware. Thick tiers, especially red bumper/competition
        // plates with raised face details, need more than the old fixed 0.03m spacing.
        let noSticker = StickerOption(id: 0, name: "None", rarity: .common, earnedBy: "", emoji: nil)

        for (index, info) in plates.prefix(4).enumerated() {
            guard let tier = PlateTier.all.first(where: { $0.id == info.tierID }) else { continue }
            guard rightOffsets.indices.contains(index) else { continue }
            let offset = rightOffsets[index]
            for xOffset in [-offset, offset] {
                let plate = makePlate(
                    tier: tier,
                    thickness: plateThickness,
                    sticker: noSticker,
                    weightKg: info.weightKg,
                    engravingText: showPlateEngravings ? info.engravingText : ""
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
        let plateEntity = makePlateEntity(
            tierID: tier.id,
            textures: scene.plateTextures[tier.id],
            weightKg: weightKg,
            engravingText: engravingText,
            showEngravings: showPlateEngravings,
            options: .visualOnly(role: .bar)
        )
        applyStickerIfNeeded(sticker, to: plateEntity, thickness: PlateVisualDesign.profile(for: tier.style).thickness)
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
    private func makeCompetitionPlate(tier: PlateTier, thickness: Float, sticker: StickerOption, weightKg: Double = 0) -> ModelEntity {
        let radius: Float = 0.18
        let plate = ModelEntity(
            mesh: .generateCylinder(height: thickness, radius: radius),
            materials: [pbrMaterial(color: tier.plateColor, metallic: tier.metallic,
                                    roughness: tier.roughness, clearcoat: tier.clearcoat,
                                    clearcoatRoughness: tier.clearcoatRoughness)]
        )
        plate.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))

        // Branded competition faces on both sides. The artwork is generated in-app so
        // the surface stays original while taking cues from real competition plates.
        for faceSign: Float in [1, -1] {
            let face = makeCompetitionFaceDisc(tier: tier, weightKg: weightKg, thickness: thickness, radius: radius, faceSign: faceSign)
            plate.addChild(face)
        }

        let hub = ModelEntity(
            mesh: .generateCylinder(height: thickness + 0.008, radius: 0.030),
            materials: [chromeMaterial()]
        )
        plate.addChild(hub)

        applyStickerIfNeeded(sticker, to: plate, thickness: thickness)
        return plate
    }

    private func makeCompetitionFaceDisc(
        tier: PlateTier,
        weightKg: Double,
        thickness: Float,
        radius: Float,
        faceSign: Float
    ) -> ModelEntity {
        let key = "\(tier.id)_\(Int(weightKg.rounded()))"
        let texture: TextureResource?
        if let cached = scene.competitionFaceTextures[key] {
            texture = cached
        } else {
            texture = makeCompetitionPlateFaceTexture(tier: tier, weightKg: weightKg)
            if let texture { scene.competitionFaceTextures[key] = texture }
        }

        var material = PhysicallyBasedMaterial()
        if let texture {
            material.baseColor = .init(tint: .white, texture: .init(texture))
        } else {
            material.baseColor = .init(tint: tier.plateColor)
        }
        material.roughness = .init(floatLiteral: 0.62)
        material.clearcoat = .init(floatLiteral: 0.25)
        material.clearcoatRoughness = .init(floatLiteral: 0.18)

        let face = ModelEntity(
            mesh: .generateCylinder(height: 0.004, radius: radius * 0.985),
            materials: [material]
        )
        face.position = SIMD3(0, faceSign * (thickness / 2 + 0.004), 0)
        return face
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
        // Use shared prefix-level cache from BarbellEntityBuilder to avoid duplicate GPU texture
        // uploads. Tier IDs 1=CastIron, 2=Rubber, 3=Brass map to the same source files used by
        // PlateWallView; sharing TextureResource objects halves GPU memory for PBR textures.
        for tierID in [1, 2, 3] where scene.plateTextures[tierID] == nil {
            scene.plateTextures[tierID] = loadPlateTextures(forTierID: tierID)
        }

        // IBL from HDRI
        if scene.iblResource == nil {
            scene.iblResource = try? await EnvironmentResource(named: "IndoorHDRI")
        }

        if [1, 2, 3].contains(selectedTier) || scene.iblResource != nil {
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

    private func makeCompetitionPlateFaceTexture(tier: PlateTier, weightKg: Double) -> TextureResource? {
        let side: CGFloat = 768
        let center = CGPoint(x: side / 2, y: side / 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let bounds = CGRect(x: 0, y: 0, width: side, height: side)
            let plateRect = bounds.insetBy(dx: 22, dy: 22)
            let color = tier.plateColor
            let dark = color.adjustedBrightness(0.62)
            let mid = color.adjustedBrightness(0.92)
            let light = color.adjustedBrightness(1.28)

            cg.setFillColor(dark.cgColor)
            cg.fill(bounds)

            let platePath = UIBezierPath(ovalIn: plateRect)
            cg.saveGState()
            platePath.addClip()
            let colors = [light.cgColor, mid.cgColor, dark.cgColor] as CFArray
            let locations: [CGFloat] = [0.0, 0.58, 1.0]
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
                cg.drawRadialGradient(
                    gradient,
                    startCenter: CGPoint(x: side * 0.34, y: side * 0.28),
                    startRadius: 24,
                    endCenter: center,
                    endRadius: side * 0.55,
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
            }

            cg.setStrokeColor(color.adjustedBrightness(0.50).withAlphaComponent(0.85).cgColor)
            cg.setLineWidth(18)
            cg.strokeEllipse(in: plateRect.insetBy(dx: 16, dy: 16))
            cg.setStrokeColor(color.adjustedBrightness(1.38).withAlphaComponent(0.30).cgColor)
            cg.setLineWidth(8)
            cg.strokeEllipse(in: plateRect.insetBy(dx: 42, dy: 42))
            cg.restoreGState()

            let ringRadii: [CGFloat] = [246, 182, 120]
            for radius in ringRadii {
                cg.setStrokeColor(color.adjustedBrightness(radius == 246 ? 0.72 : 0.58).withAlphaComponent(0.72).cgColor)
                cg.setLineWidth(radius == 246 ? 10 : 7)
                cg.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                cg.setStrokeColor(color.adjustedBrightness(1.28).withAlphaComponent(0.28).cgColor)
                cg.setLineWidth(3)
                cg.strokeEllipse(in: CGRect(x: center.x - radius + 12, y: center.y - radius + 12, width: (radius - 12) * 2, height: (radius - 12) * 2))
            }

            drawMetalHub(in: cg, center: center, radius: 96)

            let brandAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 76, weight: .black),
                .foregroundColor: UIColor.white.withAlphaComponent(0.94),
                .kern: 10.0
            ]
            drawCentered("VOLIA", at: CGPoint(x: center.x, y: center.y - 246), attributes: brandAttrs)

            cg.saveGState()
            cg.translateBy(x: center.x, y: center.y + 246)
            cg.rotate(by: .pi)
            drawCentered("VOLIA", at: .zero, attributes: brandAttrs)
            cg.restoreGState()

            let weightLabel = weightKg.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(weightKg))\nKG"
                : String(format: "%.1f\nKG", weightKg)
            let weightParagraph = NSMutableParagraphStyle()
            weightParagraph.alignment = .center
            weightParagraph.lineSpacing = -4
            let weightAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 58, weight: .black),
                .foregroundColor: UIColor.white.withAlphaComponent(0.92),
                .paragraphStyle: weightParagraph
            ]
            drawMultilineCentered(weightLabel, center: CGPoint(x: center.x - 236, y: center.y + 4), attributes: weightAttrs)

            cg.saveGState()
            cg.translateBy(x: center.x + 236, y: center.y - 4)
            cg.rotate(by: .pi)
            drawMultilineCentered(weightLabel, center: .zero, attributes: weightAttrs)
            cg.restoreGState()
        }

        guard let cgImage = image.cgImage else { return nil }
        return try? TextureResource.generate(from: cgImage, options: .init(semantic: .color))
    }

    private func drawMetalHub(in cg: CGContext, center: CGPoint, radius: CGFloat) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let colors = [
            UIColor(white: 0.98, alpha: 1).cgColor,
            UIColor(white: 0.70, alpha: 1).cgColor,
            UIColor(white: 0.96, alpha: 1).cgColor,
            UIColor(white: 0.48, alpha: 1).cgColor
        ] as CFArray
        let locations: [CGFloat] = [0, 0.36, 0.66, 1]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) {
            cg.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: center.x - 30, y: center.y - 36),
                startRadius: 8,
                endCenter: center,
                endRadius: radius,
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
        cg.setStrokeColor(UIColor(white: 0.20, alpha: 0.42).cgColor)
        cg.setLineWidth(5)
        cg.strokeEllipse(in: rect)
        cg.setFillColor(UIColor(white: 0.06, alpha: 1).cgColor)
        cg.fillEllipse(in: rect.insetBy(dx: radius * 0.63, dy: radius * 0.63))
        cg.setStrokeColor(UIColor.white.withAlphaComponent(0.28).cgColor)
        cg.setLineWidth(2)
        cg.strokeEllipse(in: rect.insetBy(dx: radius * 0.64, dy: radius * 0.64))
    }

    private func drawCentered(_ text: String, at point: CGPoint, attributes: [NSAttributedString.Key: Any]) {
        let string = text as NSString
        let size = string.size(withAttributes: attributes)
        string.draw(
            at: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2),
            withAttributes: attributes
        )
    }

    private func drawMultilineCentered(_ text: String, center: CGPoint, attributes: [NSAttributedString.Key: Any]) {
        let string = text as NSString
        let size = string.boundingRect(
            with: CGSize(width: 150, height: 160),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        ).size
        string.draw(
            with: CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
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
        barbellPreviewSelectionInfo(
            activeTab: activeTab,
            selectedTier: selectedTier,
            selectedBar: selectedBar,
            selectedSticker: selectedSticker
        )
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
                    .dsFont(.caption2, weight: .bold)
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

private extension UIColor {
    func adjustedBrightness(_ multiplier: CGFloat) -> UIColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        if getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) {
            return UIColor(
                hue: hue,
                saturation: saturation,
                brightness: min(max(brightness * multiplier, 0), 1),
                alpha: alpha
            )
        }

        var white: CGFloat = 0
        if getWhite(&white, alpha: &alpha) {
            return UIColor(white: min(max(white * multiplier, 0), 1), alpha: alpha)
        }

        return self
    }
}
