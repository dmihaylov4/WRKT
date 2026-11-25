import CryptoKit
import Observation
import RealityKit
import SwiftUI
import UIKit

/// The rack rail's plate pictures, rendered with the rack scene's own plates and cached on disk:
/// one "edge" sprite per plate tier (the plate standing on the rail, turned a little toward the
/// camera, face blank because lettering would not read at that size and angle) and one "face"
/// picture per distinct face for the plate lifted out of the rail (face on, lettered, as in the
/// scene). Lathe plates in debug builds, legacy plates otherwise (RackPlateStyle.current).
///
/// Renders go through PlateSnapshotService's queue, so they never run while a rack scene opens or
/// a plate swings in (holdRenders). Edge sprites render in batches with one offscreen ARView per
/// batch; a batch stops between sprites as soon as a hold starts and the rest queue again.
/// Disk reads and PNG decoding run off the main thread.
@MainActor
@Observable
final class RackRailSpriteService {
    static let shared = RackRailSpriteService()

    /// Bumped whenever a new picture is in memory, so rail views look again.
    private(set) var revision = 0

    /// Edge sprites are framed so every plate stands on the image's bottom edge and its real
    /// diameter maps to the same scale: a 0.15 m iron plate is shorter than a 0.22 m bumper.
    enum EdgeFrame {
        /// The world height and width the sprite shows, in metres.
        static let worldHeight: Float = 0.47
        static let worldWidth: Float = 0.21
        /// Points of the offscreen view (rendered at the screen's scale).
        static let size = CGSize(width: 52, height: 116)
        /// How far the plate's axis is turned from pointing across the rail toward the camera.
        static let turnDegrees: Float = 18
    }

    static let faceSize = CGSize(width: 220, height: 220)
    /// Bump when the framing or lighting changes, so old pictures are not reused.
    static let version = "r2"

    @ObservationIgnored private let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()
    @ObservationIgnored private var missingEdges: [Int] = []
    @ObservationIgnored private var edgeBatch: Task<Void, Never>?
    @ObservationIgnored private var reading: Set<String> = []
    @ObservationIgnored private var faceRenders: [String: Task<UIImage?, Never>] = [:]

    private init() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("rack_rail_sprites", isDirectory: true)
    }

    // MARK: Keys

    static func edgeKey(tierID: Int, style: RackPlateStyle) -> String {
        "edge_\(version)_\(style.rawValue)_\(tierID)"
    }

    static func faceKey(_ request: LathePlateRequest, style: RackPlateStyle) -> String {
        var input = Data("\(version)|\(style.rawValue)|\(request.tierID)|\(request.weightKg.bitPattern)|\(request.projection.tierRingCount)|".utf8)
        input.append(contentsOf: request.engravingText.utf8)
        return "face_" + SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Edge sprites

    /// The tier's edge sprite if it is in memory; otherwise nil, and it is read from disk or
    /// rendered in the background (a later revision brings it).
    func edge(tierID: Int) -> UIImage? {
        let key = Self.edgeKey(tierID: tierID, style: RackPlateStyle.current)
        if let image = memory.object(forKey: key as NSString) { return image }
        load(key: key) { [weak self] in self?.queueEdge(tierID) }
        return nil
    }

    func memoryEdge(tierID: Int) -> UIImage? {
        memory.object(forKey: Self.edgeKey(tierID: tierID, style: RackPlateStyle.current) as NSString)
    }

    /// Reads a picture from disk off the main thread, or calls `missing`.
    private func load(key: String, missing: @escaping @MainActor () -> Void) {
        guard !reading.contains(key) else { return }
        reading.insert(key)
        let url = directory.appendingPathComponent(key + ".png")
        Task { @MainActor in
            let decoded = await Task.detached(priority: .utility) { () -> PlateSnapshotImageBox? in
                guard let data = try? Data(contentsOf: url), let image = UIImage(data: data, scale: 3) else { return nil }
                return PlateSnapshotImageBox(image: image.preparingForDisplay() ?? image)
            }.value
            reading.remove(key)
            if let image = decoded?.image {
                store(image, key: key, write: false)
            } else {
                missing()
            }
        }
    }

    private func queueEdge(_ tierID: Int) {
        guard !missingEdges.contains(tierID) else { return }
        missingEdges.append(tierID)
        guard edgeBatch == nil else { return }
        edgeBatch = Task { @MainActor in
            // Let the rail ask for every tier it shows first, so one batch covers them.
            try? await Task.sleep(for: .milliseconds(50))
            while !missingEdges.isEmpty {
                _ = await PlateSnapshotService.shared.renderQueued {
                    await RackRailSpriteService.shared.renderEdgeBatch()
                    return nil
                }
            }
            edgeBatch = nil
        }
    }

    /// Renders queued edge sprites with one offscreen view until done or a hold starts.
    private func renderEdgeBatch() async {
        let style = RackPlateStyle.current
        guard let stage = await RackRailStage(size: EdgeFrame.size, style: style) else {
            missingEdges.removeAll()
            return
        }
        defer { stage.tearDown() }
        stage.frameEdge()
        while let tierID = missingEdges.first, !PlateSnapshotService.shared.isHeld {
            missingEdges.removeFirst()
            guard let tier = PlateTier.all.first(where: { $0.id == tierID }),
                  let plate = await Self.plateEntity(tier: tier, style: style, face: nil) else { continue }
            let half = PlateVisualDesign.profile(for: tier.style).outerRadius
            // Standing on the rail: the plate's lowest point at y = 0; axis across the rail,
            // turned toward the camera so the front face shows as a narrow ellipse.
            let across = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
            let turn = simd_quatf(angle: -EdgeFrame.turnDegrees * .pi / 180, axis: SIMD3(0, 1, 0))
            plate.transform = Transform(scale: .one, rotation: turn * across, translation: [0, half, 0])
            if let image = await stage.snapshot(plate) {
                store(image, key: Self.edgeKey(tierID: tierID, style: style), write: true)
                RackWorkCounters.add(.railSpritesRendered)
            }
        }
    }

    // MARK: Face pictures

    func memoryFace(_ request: LathePlateRequest) -> UIImage? {
        memory.object(forKey: Self.faceKey(request, style: RackPlateStyle.current) as NSString)
    }

    /// The plate's lettered face, face on: from memory, disk, or rendered (after any hold).
    func face(_ request: LathePlateRequest) async -> UIImage? {
        let style = RackPlateStyle.current
        let key = Self.faceKey(request, style: style)
        if let image = memory.object(forKey: key as NSString) { return image }
        if let running = faceRenders[key] { return await running.value }
        let url = directory.appendingPathComponent(key + ".png")
        let task = Task { @MainActor () -> UIImage? in
            let decoded = await Task.detached(priority: .userInitiated) { () -> PlateSnapshotImageBox? in
                guard let data = try? Data(contentsOf: url), let image = UIImage(data: data, scale: 3) else { return nil }
                return PlateSnapshotImageBox(image: image.preparingForDisplay() ?? image)
            }.value
            if let image = decoded?.image {
                store(image, key: key, write: false)
                return image
            }
            guard let tier = PlateTier.all.first(where: { $0.id == request.tierID }) else { return nil }
            let image = await PlateSnapshotService.shared.renderQueued {
                if style == .lathe { await prepareLathePlates([request]) }
                guard let stage = await RackRailStage(size: Self.faceSize, style: style),
                      let plate = await Self.plateEntity(tier: tier, style: style, face: request) else { return nil }
                defer { stage.tearDown() }
                stage.frameFace()
                // Axis toward the camera, lettered face forward.
                plate.transform = Transform(scale: .one, rotation: simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0)), translation: .zero)
                return await stage.snapshot(plate)
            }
            if let image {
                store(image, key: key, write: true)
                RackWorkCounters.add(.railSpritesRendered)
            }
            return image
        }
        faceRenders[key] = task
        let image = await task.value
        faceRenders[key] = nil
        return image
    }

    // MARK: Shared

    /// The plate as the rack scene builds it, axis along y, no physics. `face` nil: blank face.
    private static func plateEntity(tier: PlateTier, style: RackPlateStyle, face: LathePlateRequest?) async -> Entity? {
        if style == .lathe {
            if let face {
                return makeLathePlateVisual(tier: tier, weightKg: face.weightKg, engravingText: face.engravingText,
                                            showEngravings: true, projection: face.projection)
                    .map { plate in
                        // makeLathePlateVisual turns the axis along x; bring it back to y.
                        plate.orientation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
                        let holder = Entity()
                        holder.addChild(plate)
                        return holder
                    }
            }
            return makeLathePlateBlankVisual(tier: tier)
        }
        let textures = await loadPlateTexturesAsync(forTierID: tier.id)
        guard !Task.isCancelled else { return nil }
        let material = buildMaterial(forTierID: tier.id, textures: textures)
        let plate = makePlateEntity(tierID: tier.id, textures: textures, material: material,
                                    weightKg: face?.weightKg ?? 0, engravingText: face?.engravingText ?? "",
                                    showEngravings: face != nil,
                                    renderProjection: face?.projection ?? BarbellPlateRenderProjection(),
                                    options: .visualOnly())
        let holder = Entity()
        holder.addChild(plate)
        return holder
    }

    private func store(_ image: UIImage, key: String, write: Bool) {
        let pixels = (image.cgImage?.width ?? 100) * (image.cgImage?.height ?? 100)
        memory.setObject(image, forKey: key as NSString, cost: pixels * 4)
        revision += 1
        guard write, let data = image.pngData() else { return }
        let url = directory.appendingPathComponent(key + ".png")
        Task.detached(priority: .utility) { try? data.write(to: url, options: .atomic) }
    }

    #if DEBUG
    /// Tests: forget every picture in memory and on disk.
    func removeAllForTesting() {
        memory.removeAllObjects()
        for file in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: file)
        }
        revision += 1
    }

    /// Tests: renders the tiers' edge sprites now and waits for them.
    func renderEdgesForTesting(_ tierIDs: [Int]) async -> [Int: UIImage] {
        for tierID in tierIDs { _ = edge(tierID: tierID) }
        for _ in 0..<600 {
            if tierIDs.allSatisfy({ memoryEdge(tierID: $0) != nil }) { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return Dictionary(uniqueKeysWithValues: tierIDs.compactMap { id in memoryEdge(tierID: id).map { (id, $0) } })
    }
    #endif
}

/// One offscreen ARView lit like the rack room, for a batch of plate pictures.
@MainActor
private final class RackRailStage {
    let view: ARView
    let anchor = AnchorEntity(world: .zero)
    let camera = PerspectiveCamera()
    private var current: Entity?

    init?(size: CGSize, style: RackPlateStyle) async {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) else { return nil }
        view = ARView(frame: CGRect(x: -size.width - 10, y: -size.height - 10, width: size.width, height: size.height),
                      cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(.clear)
        view.backgroundColor = .clear
        view.isOpaque = false
        view.renderOptions.insert(.disableMotionBlur)
        view.renderOptions.insert(.disableDepthOfField)
        view.renderOptions.insert(.disableCameraGrain)
        window.addSubview(view)
        view.scene.addAnchor(anchor)
        let cameraAnchor = AnchorEntity(world: .zero)
        cameraAnchor.addChild(camera)
        view.scene.addAnchor(cameraAnchor)

        // A key light from the upper left front, as the room's key falls on the bar.
        let key = DirectionalLight()
        key.light.intensity = style == .lathe ? 1800 : 2400
        key.look(at: .zero, from: [-0.6, 1.2, 1.0], relativeTo: nil)
        anchor.addChild(key)
        // A rim light from behind and above, so black rubber keeps an edge against the dark rail.
        let rim = DirectionalLight()
        rim.light.intensity = style == .lathe ? 1400 : 1800
        rim.look(at: .zero, from: [0.4, 1.4, -1.2], relativeTo: nil)
        anchor.addChild(rim)

        let environment = style == .lathe ? await sharedRackStudioEnvironmentResource() : await sharedIndoorEnvironmentResource()
        if let environment {
            let light = Entity()
            light.components.set(ImageBasedLightComponent(
                source: .single(environment),
                intensityExponent: style == .lathe ? RackRoomLightingPreset.current(for: .lathe).imageBasedLightIntensityExponent + 0.6 : 8
            ))
            anchor.addChild(light)
            anchor.components.set(ImageBasedLightReceiverComponent(imageBasedLight: light))
        }
    }

    /// A narrow lens from a little above, so the plates on the rail line up without perspective
    /// and the top of each rim shows.
    func frameEdge() {
        let frame = RackRailSpriteService.EdgeFrame.self
        let distance: Float = 4
        camera.camera.fieldOfViewInDegrees = 2 * atan(frame.worldHeight / 2 / distance) * 180 / .pi
        let target = SIMD3<Float>(0, frame.worldHeight / 2 - 0.004, 0)
        let pitch: Float = 5 * .pi / 180
        camera.look(at: target, from: target + SIMD3(0, sin(pitch), cos(pitch)) * distance, relativeTo: nil)
    }

    func frameFace() {
        let distance: Float = 4
        camera.camera.fieldOfViewInDegrees = 2 * atan(0.47 / 2 / distance) * 180 / .pi
        camera.look(at: .zero, from: [0, 0, distance], relativeTo: nil)
    }

    func snapshot(_ plate: Entity) async -> UIImage? {
        current?.removeFromParent()
        anchor.addChild(plate)
        current = plate
        // A few frames for the materials and the light to settle.
        try? await Task.sleep(for: .milliseconds(120))
        return await withCheckedContinuation { continuation in
            view.snapshot(saveToHDR: false) { image in continuation.resume(returning: image) }
        }
    }

    func tearDown() {
        current?.removeFromParent()
        view.scene.anchors.removeAll()
        view.removeFromSuperview()
    }
}

// MARK: - Views

/// One plate of a rail group standing on edge: the rendered sprite, or until it is ready a drawn
/// stand-in in the plate's own finish colour.
struct RackRailEdgeArt: View {
    let tierID: Int

    var body: some View {
        let service = RackRailSpriteService.shared
        _ = service.revision
        return Group {
            if let image = service.memoryEdge(tierID: tierID) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .transition(.opacity)
            } else {
                RackRailDrawnEdge(tierID: tierID)
            }
        }
        .animation(.easeOut(duration: 0.25), value: service.memoryEdge(tierID: tierID) != nil)
        .task(id: tierID) { _ = service.edge(tierID: tierID) }
    }
}

/// The drawn stand-in: the plate standing on the rail, its face a narrow ellipse in the finish
/// colour over a darker tread, with the bore. Proportioned like the sprite.
@MainActor
struct RackRailDrawnEdge: View {
    let tierID: Int

    var body: some View {
        let tier = PlateTier.all.first { $0.id == tierID }
        let finish = tier.map(LatheFinish.body(for:))
        let color = Color(uiColor: finish?.color ?? .darkGray)
        let radius = CGFloat(tier.map { PlateVisualDesign.profile(for: $0.style).outerRadius } ?? 0.22)
        let scale = radius / CGFloat(RackRailSpriteService.EdgeFrame.worldHeight)
        GeometryReader { proxy in
            let height = proxy.size.height * scale * 2
            let width = height * 0.4
            ZStack {
                Ellipse().fill(color.opacity(0.55)).offset(x: -width * 0.22)
                Ellipse().fill(LinearGradient(colors: [color, color.opacity(finish?.isMetal == true ? 0.55 : 0.8)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                Ellipse().fill(Color.black.opacity(0.7)).frame(width: width * 0.16, height: height * 0.16)
            }
            .frame(width: width, height: height)
            .position(x: proxy.size.width / 2, y: proxy.size.height - height / 2)
        }
    }
}

/// The lifted plate's face: the rendered face, or a plain disc in its colour until it is ready.
struct RackRailFaceArt: View {
    let request: LathePlateRequest
    @State private var image: UIImage?

    init(request: LathePlateRequest) {
        self.request = request
        _image = State(initialValue: RackRailSpriteService.shared.memoryFace(request))
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().interpolation(.high).scaledToFit()
            } else {
                let tier = PlateTier.all.first { $0.id == request.tierID }
                let color = Color(uiColor: tier.map { LatheFinish.body(for: $0).color } ?? .darkGray)
                ZStack {
                    Circle().fill(color)
                    Circle().strokeBorder(Color.black.opacity(0.25), lineWidth: 6).padding(10)
                    Circle().fill(Color.black.opacity(0.7)).frame(width: 18, height: 18)
                }
                .padding(4)
            }
        }
        .animation(.easeOut(duration: 0.2), value: image != nil)
        .task(id: RackRailSpriteService.faceKey(request, style: RackPlateStyle.current)) {
            if image == nil { image = await RackRailSpriteService.shared.face(request) }
        }
    }
}
