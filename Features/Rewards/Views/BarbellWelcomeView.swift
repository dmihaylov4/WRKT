// Features/Rewards/Views/BarbellWelcomeView.swift
import SwiftUI
import SwiftData
import SceneKit
import UIKit

// MARK: - Texture cache (UIImage, same source files as BarbellPreviewView)

private enum PlateUITextureCache {
    private static var cache: [Int: UIImage] = [:]

    static func image(for tierID: Int) -> UIImage? {
        if let cached = cache[tierID] { return cached }
        let prefix: String
        switch tierID {
        case 0: prefix = "RustyIron"
        case 1: prefix = "CastIron"
        case 2: prefix = "Rubber"
        case 3: prefix = "Brass"
        case 6: prefix = "Brass"
        default: return nil
        }
        guard let url = Bundle.main.url(forResource: "\(prefix)_Color", withExtension: "jpg"),
              let img = UIImage(contentsOfFile: url.path) else { return nil }
        cache[tierID] = img
        return img
    }
}

// MARK: - Shared scene-kit light constants
//
// All SCNScene instances in this file use identical lights so the barbell
// and plate thumbnails render under the same conditions.

private enum WelcomeLights {
    static let keyIntensity: CGFloat  = 80
    static let keyPosition            = SCNVector3(0.5, 1.5, 1.5)
    static let fillIntensity: CGFloat = 30
    static let fillPosition           = SCNVector3(-1.5, -0.5, 0.8)
    static let ambientIntensity: CGFloat = 20
}

private func addWelcomeLights(to scene: SCNScene) {
    let keyNode = SCNNode()
    keyNode.light = {
        let l = SCNLight()
        l.type = .omni
        l.intensity = WelcomeLights.keyIntensity
        l.color = UIColor.white
        return l
    }()
    keyNode.position = WelcomeLights.keyPosition
    scene.rootNode.addChildNode(keyNode)

    let fillNode = SCNNode()
    fillNode.light = {
        let l = SCNLight()
        l.type = .omni
        l.intensity = WelcomeLights.fillIntensity
        l.color = UIColor(white: 0.85, alpha: 1)
        return l
    }()
    fillNode.position = WelcomeLights.fillPosition
    scene.rootNode.addChildNode(fillNode)

    let ambNode = SCNNode()
    ambNode.light = {
        let l = SCNLight()
        l.type = .ambient
        l.intensity = WelcomeLights.ambientIntensity
        l.color = UIColor(white: 0.8, alpha: 1)
        return l
    }()
    scene.rootNode.addChildNode(ambNode)
}

// MARK: - SCNView wrapper
//
// UIViewRepresentable is needed to set backgroundColor = .clear and
// isOpaque = false — SwiftUI's SceneView does not expose these.

private struct PlateSceneView: UIViewRepresentable {
    let scnView: SCNView

    func makeUIView(context: Context) -> SCNView {
        scnView.frame = CGRect(x: 0, y: 0, width: 68, height: 68)
        scnView.backgroundColor = .black
        scnView.isOpaque = true
        scnView.antialiasingMode = .multisampling4X
        scnView.allowsCameraControl = false
        scnView.rendersContinuously = true
        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}

// MARK: - SceneKit plate scene builder
//
// Builds the same physical structure as BarbellPreviewView's makePlate():
// main cylinder + chrome hub + style-specific geometry (inner face, edge band,
// chrome rings). Uses the same PBR values from PlateTier.all and the same
// texture images from the bundle.
//
// SceneKit is used instead of RealityKit because RealityKit's envProbeTable
// and envProbeDiffuseArray are process-wide Metal singletons: two simultaneous
// RealityView instances corrupt each other's Metal state and crash. SCNView
// uses per-instance Metal state and coexists safely with the barbell's
// RealityView.

private func buildPlateScene(tierID: Int) -> (scene: SCNScene, spinRoot: SCNNode) {
    let scene = SCNScene()
    scene.background.contents = UIColor.black

    // Camera positioned to fill ~85% of the 68×68 cell
    let camNode = SCNNode()
    camNode.camera = {
        let c = SCNCamera()
        c.fieldOfView = 60
        c.zNear = 0.01
        return c
    }()
    camNode.position = SCNVector3(0, 0, 0.38)
    scene.rootNode.addChildNode(camNode)

    addWelcomeLights(to: scene)

    // Spin root: rotating this around Y gives the coin-spin effect
    let spinRoot = SCNNode()
    scene.rootNode.addChildNode(spinRoot)

    // Plate inner node: cylinder axis is Y by default; rotate 90° around X
    // so the flat cap faces the camera (toward +Z)
    let plateInner = buildSCNPlate(tierID: tierID)
    plateInner.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
    spinRoot.addChildNode(plateInner)

    return (scene, spinRoot)
}

private func buildSCNPlate(tierID: Int) -> SCNNode {
    guard let tier = PlateTier.all.first(where: { $0.id == tierID }) else { return SCNNode() }

    let thickness: CGFloat = 0.04
    let radius: CGFloat = 0.18
    let root = SCNNode()

    let chrome = pbrSCNMaterial(color: UIColor(white: 0.85, alpha: 1), metallic: 1.0, roughness: 0.12)

    // Main disc — set all 3 slots explicitly: [tube, front cap, back cap]
    let mainCyl = SCNCylinder(radius: radius, height: thickness)
    let plateMat = pbrSCNMaterial(
        color: tier.plateColor,
        texture: PlateUITextureCache.image(for: tierID),
        metallic: tier.metallic,
        roughness: tier.roughness
    )
    mainCyl.materials = [plateMat, plateMat, plateMat]
    root.addChildNode(SCNNode(geometry: mainCyl))

    // Chrome hub — all tiers
    let hubCyl = SCNCylinder(radius: 0.028, height: thickness + 0.003)
    hubCyl.materials = [chrome, chrome, chrome]
    root.addChildNode(SCNNode(geometry: hubCyl))

    // Style-specific geometry (mirrors BarbellPreviewView)
    switch tier.style {
    case .castIron:
        let innerMat = pbrSCNMaterial(
            color: UIColor(red: 0.20, green: 0.20, blue: 0.20, alpha: 1),
            texture: PlateUITextureCache.image(for: tierID),
            metallic: 0.06, roughness: 0.96
        )
        let innerCyl = SCNCylinder(radius: radius * 0.86, height: thickness * 0.72)
        innerCyl.materials = [innerMat, innerMat, innerMat]
        root.addChildNode(SCNNode(geometry: innerCyl))

        let bossMat = pbrSCNMaterial(color: tier.plateColor, metallic: 0.06, roughness: 0.95)
        let bossCyl = SCNCylinder(radius: radius * 0.22, height: thickness * 0.82)
        bossCyl.materials = [bossMat, bossMat, bossMat]
        root.addChildNode(SCNNode(geometry: bossCyl))

    case .bumper:
        let bandMat = pbrSCNMaterial(color: UIColor(white: 0.35, alpha: 1), metallic: 0.1, roughness: 0.88)
        let bandCyl = SCNCylinder(radius: radius + 0.002, height: thickness * 0.35)
        bandCyl.materials = [bandMat, bandMat, bandMat]
        root.addChildNode(SCNNode(geometry: bandCyl))

    case .competition, .polishedSteel, .gold:
        for faceSign: Float in [1, -1] {
            let yPos = faceSign * Float(thickness / 2 + 0.003)
            for ringR in [radius * 0.82, radius * 0.42] {
                let ringCyl = SCNCylinder(radius: ringR, height: 0.004)
                ringCyl.materials = [chrome, chrome, chrome]
                let ringNode = SCNNode(geometry: ringCyl)
                ringNode.position = SCNVector3(0, yPos, 0)
                root.addChildNode(ringNode)
            }
        }

    default:
        break
    }

    return root
}

private func pbrSCNMaterial(color: UIColor, texture: UIImage? = nil,
                             metallic: Float, roughness: Float) -> SCNMaterial {
    let m = SCNMaterial()
    m.lightingModel = .physicallyBased
    m.diffuse.contents = texture ?? color
    m.metalness.contents = NSNumber(value: metallic)
    m.roughness.contents = NSNumber(value: roughness)
    return m
}

/// Builds a full barbell scene for the welcome screen hero.
/// Returns the scene and its spin root (rotate spinRoot.eulerAngles.y for spin).
///
/// Coordinate system: bar runs along X. Camera looks toward +Z.
/// Plates: innermost pair at ±0.34, outer pair at ±0.37 (matches showcase slots 0-1).
private func buildWelcomeBarbellScene(plates: [EarnedPlateInfo]) -> (scene: SCNScene, spinRoot: SCNNode) {
    let scene = SCNScene()
    scene.background.contents = UIColor.black

    // Camera — pulled back to frame the full ~1.1-unit wide barbell
    let camNode = SCNNode()
    camNode.camera = {
        let c = SCNCamera()
        c.fieldOfView = 38
        c.zNear = 0.01
        return c
    }()
    camNode.position = SCNVector3(0, 0.08, 1.6)
    scene.rootNode.addChildNode(camNode)

    addWelcomeLights(to: scene)

    let spinRoot = SCNNode()
    scene.rootNode.addChildNode(spinRoot)

    // Bar — SCNCylinder axis is Y; rotate 90° around Z to lay along X
    let chromeMat = pbrSCNMaterial(
        color: UIColor(white: 0.85, alpha: 1), metallic: 1.0, roughness: 0.12
    )
    let barCyl = SCNCylinder(radius: 0.012, height: 1.1)
    barCyl.materials = [chromeMat, chromeMat, chromeMat]
    let barNode = SCNNode(geometry: barCyl)
    barNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
    spinRoot.addChildNode(barNode)

    // Collars at ±0.475
    for xSign: Float in [-1, 1] {
        let collarCyl = SCNCylinder(radius: 0.022, height: 0.04)
        collarCyl.materials = [chromeMat, chromeMat, chromeMat]
        let collarNode = SCNNode(geometry: collarCyl)
        collarNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
        collarNode.position = SCNVector3(xSign * 0.475, 0, 0)
        spinRoot.addChildNode(collarNode)
    }

    // Plates — bilateral pairs, innermost first
    let slotOffsets: [[Float]] = [
        [-0.34, 0.34],
        [-0.37, 0.37],
        [-0.40, 0.40],
        [-0.43, 0.43],
    ]
    for (index, info) in plates.prefix(4).enumerated() {
        let offsets = slotOffsets[index]
        for xOffset in offsets {
            let plateInner = buildSCNPlate(tierID: info.tierID)
            // buildSCNPlate cylinder axis is Y, already rotated 90° around X so face is +Z.
            // Move the plate to its X slot on the bar.
            let plateNode = SCNNode()
            plateNode.addChildNode(plateInner)
            plateNode.position = SCNVector3(xOffset, 0, 0)
            spinRoot.addChildNode(plateNode)
        }
    }

    return (scene, spinRoot)
}

// MARK: - Plate state
//
// A plain class — held by @State so it survives re-renders, but never written
// to @State itself. All per-frame physics mutations stay on class properties,
// which SwiftUI does not observe. This eliminates "modifying state during view
// update" warnings: there are no @State writes in the hot path.

private final class PlateState {
    let scnView = SCNView()
    var spinRoot: SCNNode? = nil
    var rotY: Double = Double.random(in: 0...360)
    var velocity: Double = Double.random(in: 20...55) * (Bool.random() ? 1 : -1)
    var isDragging: Bool = false
    var lastTranslationX: CGFloat = 0
}

// MARK: - Spinnable plate cell

private struct SpinnablePlateCell: View {
    let plate: EarnedPlate
    @State private var s = PlateState()   // 's' to keep captures short

    var body: some View {
        VStack(spacing: 4) {
            PlateSceneView(scnView: s.scnView)
                .frame(width: 68, height: 68)
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { value in
                            s.isDragging = true
                            let delta = Double(value.translation.width - s.lastTranslationX)
                            s.velocity = delta * 90
                            s.rotY += delta * 1.8
                            s.lastTranslationX = value.translation.width
                            s.spinRoot?.eulerAngles.y = Float(s.rotY * .pi / 180)
                        }
                        .onEnded { _ in
                            s.isDragging = false
                            s.lastTranslationX = 0
                        }
                )
                // Build scene and run physics on main actor.
                // Mutations go to PlateState (class) and SCNNode directly —
                // zero @State writes per frame.
                .task { @MainActor in
                    let (scene, spin) = buildPlateScene(tierID: plate.tierID)
                    s.scnView.scene = scene
                    s.spinRoot = spin
                    s.spinRoot?.eulerAngles.y = Float(s.rotY * .pi / 180)

                    var lastTime = Date().timeIntervalSinceReferenceDate
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(16))
                        let now = Date().timeIntervalSinceReferenceDate
                        let dt = min(now - lastTime, 0.05)
                        lastTime = now
                        guard !s.isDragging else { continue }
                        s.velocity *= pow(0.97, dt * 60)   // ~3% per 60Hz frame
                        s.rotY += s.velocity * dt
                        s.spinRoot?.eulerAngles.y = Float(s.rotY * .pi / 180)
                    }
                }

            Text(plate.engravingText)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(1)
        }
    }
}

// MARK: - Main view

struct BarbellWelcomeView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var ownedPlates: [EarnedPlate]
    @State private var showPlateWall = false

    private var earnedPlates: [EarnedPlate] {
        ownedPlates.filter { $0.earnedByEvent != "starter" }
    }

    private var showcasePlateInfos: [EarnedPlateInfo] {
        earnedPlates
            .sorted { $0.tierID > $1.tierID }
            .prefix(4)
            .map { EarnedPlateInfo(tierID: $0.tierID, weightKg: $0.weightKg, engravingText: $0.engravingText, earnedByEvent: $0.earnedByEvent) }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                BarbellPreviewView(mode: .showcase(plates: showcasePlateInfos))
                    .allowsHitTesting(true)

                VStack(spacing: 8) {
                    Text("Your workouts have paid off.")
                        .font(.title.weight(.bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text("\(earnedPlates.count) plates earned")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 24)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 12) {
                    ForEach(earnedPlates) { plate in
                        SpinnablePlateCell(plate: plate)
                    }
                }
                .padding(.horizontal, 24)

                Spacer()

                Button {
                    showPlateWall = true
                } label: {
                    Text("Build Your Rack")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .background(DS.Semantic.brand)
                .foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .fullScreenCover(isPresented: $showPlateWall) {
            PlateWallView()
                .onDisappear { dismiss() }
        }
    }
}
