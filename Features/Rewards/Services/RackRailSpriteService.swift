import CryptoKit
import Observation
import RealityKit
import SwiftUI
import UIKit

/// The rack rail's plate pictures, rendered with the rack scene's own plates and cached on disk:
/// one "stand" picture per plate look (the plate standing on the floor, face toward the viewer,
/// leaning back a little and turned a little so its rim and thickness show, lettered as in the
/// scene) and one larger face-on picture for the plate lifted out of the row. The plates the rack
/// room draws this launch (RackPlateStyle.current). Also renders the lathe thumbnails for
/// PlateSnapshotService (renderThumbnail).
///
/// Lettered faces are built for each picture alone (makeLatheSnapshotPlate): they never enter the
/// scene's LatheFaceCache, and their textures are released with the picture's plate. Pictures are
/// rendered at the size they are shown, decoded off the main thread and kept in a cost-bounded
/// memory cache.
///
/// Renders go through PlateSnapshotService's queue, so they never start while a rack scene opens
/// or a plate swings in (holdRenders). Stand pictures render in batches with one offscreen ARView
/// per batch; a batch checks for a hold before each picture and again right before its snapshot,
/// and a held picture is put back and the view torn down, so a render never runs into a swing.
@MainActor
@Observable
final class RackRailSpriteService {
    static let shared = RackRailSpriteService()

    /// Bumped whenever a new picture is in memory. Rail views do not observe it (every picture
    /// view would re-evaluate for every new picture); each observes its own key's slot.
    @ObservationIgnored private(set) var revision = 0
    @ObservationIgnored private var slots: [String: RackRailSpriteSlot] = [:]

    /// The observable change count of one picture.
    func slot(for key: String) -> RackRailSpriteSlot {
        if let slot = slots[key] { return slot }
        let slot = RackRailSpriteSlot()
        slots[key] = slot
        return slot
    }

    /// Stand pictures share one framing so a plate's real diameter maps to the same scale (a
    /// 0.15 m iron plate stands lower than a 0.22 m bumper) and every plate's lowest point sits on
    /// the picture's bottom edge.
    enum StandFrame {
        /// The world square the picture shows, in metres.
        static let world: Float = 0.5
        /// Points of the offscreen view (rendered at the screen's scale): the largest size the
        /// row shows a plate at.
        static let side: CGFloat = 128
        /// The plate leans back against the row and turns a little to its left, so the top and
        /// right of the rim show.
        static let leanDegrees: Float = 14
        static let turnDegrees: Float = 22
    }

    static let liftedSide: CGFloat = 200
    /// Bump when the framing or lighting changes, so old pictures are not reused.
    static let version = "s2"

    @ObservationIgnored private let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        // About 50 stand pictures at 3x (590 KB each), fewer with a lifted face among them.
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()
    @ObservationIgnored private var missing: [(key: String, request: LathePlateRequest)] = []
    @ObservationIgnored private var batch: Task<Void, Never>?
    @ObservationIgnored private var reading: Set<String> = []
    @ObservationIgnored private var liftedRenders: [String: Task<UIImage?, Never>] = [:]

    private init() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("rack_rail_sprites", isDirectory: true)
    }

    // MARK: Keys

    static func key(_ request: LathePlateRequest, pose: String, style: RackPlateStyle) -> String {
        var input = Data("\(version)|\(pose)|\(style.rawValue)|\(request.tierID)|\(request.weightKg.bitPattern)|\(request.projection.tierRingCount)|".utf8)
        input.append(contentsOf: request.engravingText.utf8)
        return pose + "_" + SHA256.hash(data: input).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    static func standKey(_ request: LathePlateRequest) -> String {
        key(request, pose: "stand", style: RackPlateStyle.current)
    }

    // MARK: Stand pictures

    func memoryStand(_ request: LathePlateRequest) -> UIImage? {
        memory.object(forKey: Self.standKey(request) as NSString)
    }

    /// The stand picture with the row's floor darkening baked in (RackRailFlatArt.shaded), so the
    /// row composites one plain image per plate over the live scene instead of a gradient masked
    /// by the picture, which Core Animation redrew offscreen every frame.
    func shadedStand(_ request: LathePlateRequest) -> UIImage? {
        let key = "shaded_" + Self.standKey(request)
        if let shaded = memory.object(forKey: key as NSString) { return shaded }
        guard let stand = memoryStand(request), let shaded = RackRailFlatArt.shaded(stand) else { return nil }
        let pixels = (shaded.cgImage?.width ?? 100) * (shaded.cgImage?.height ?? 100)
        memory.setObject(shaded, forKey: key as NSString, cost: pixels * 4)
        return shaded
    }

    /// Asks for a stand picture: read from disk, or rendered in the background. A later revision
    /// brings it.
    func requestStand(_ request: LathePlateRequest) {
        let key = Self.standKey(request)
        guard memory.object(forKey: key as NSString) == nil else { return }
        load(key: key) { [weak self] in self?.queue(key, request) }
    }

    /// Reads a picture from disk off the main thread, or calls `missing`.
    private func load(key: String, missing: @escaping @MainActor () -> Void) {
        guard !reading.contains(key) else { return }
        reading.insert(key)
        let url = directory.appendingPathComponent(key + ".png")
        Task { @MainActor in
            let decoded = await Self.decode(url, priority: .utility)
            reading.remove(key)
            if let decoded {
                store(decoded, key: key, write: false)
            } else {
                missing()
            }
        }
    }

    private static func decode(_ url: URL, priority: TaskPriority) async -> UIImage? {
        await Task.detached(priority: priority) { () -> PlateSnapshotImageBox? in
            guard let data = try? Data(contentsOf: url), let image = UIImage(data: data, scale: 3) else { return nil }
            return PlateSnapshotImageBox(image: image.preparingForDisplay() ?? image)
        }.value?.image
    }

    private func queue(_ key: String, _ request: LathePlateRequest) {
        guard !missing.contains(where: { $0.key == key }) else { return }
        missing.append((key, request))
        guard batch == nil else { return }
        batch = Task { @MainActor in
            // Let the row ask for every plate it shows first, so one batch covers them.
            try? await Task.sleep(for: .milliseconds(50))
            while !missing.isEmpty {
                _ = await PlateSnapshotService.shared.renderQueued {
                    await RackRailSpriteService.shared.renderStandBatch()
                    return nil
                }
            }
            batch = nil
        }
    }

    /// Renders queued stand pictures with one offscreen view until done or a hold starts.
    private func renderStandBatch() async {
        let style = RackPlateStyle.current
        guard let stage = await RackRailStage(side: StandFrame.side, style: style) else {
            missing.removeAll()
            return
        }
        defer { stage.tearDown() }
        stage.frame(world: StandFrame.world, centerY: StandFrame.world / 2 - 0.01, pitchDegrees: 6)
        while let next = missing.first, !PlateSnapshotService.shared.isHeld {
            guard let tier = PlateTier.all.first(where: { $0.id == next.request.tierID }),
                  let plate = await Self.plateEntity(tier: tier, style: style, request: next.request) else {
                missing.removeFirst()
                continue
            }
            let radius = PlateVisualDesign.profile(for: tier.style).outerRadius
            let lean = StandFrame.leanDegrees * .pi / 180
            let faceOn = simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0))
            let leanBack = simd_quatf(angle: -lean, axis: SIMD3(1, 0, 0))
            let turn = simd_quatf(angle: -StandFrame.turnDegrees * .pi / 180, axis: SIMD3(0, 1, 0))
            // Standing on the floor: the lowest point of the rim at y = 0.
            plate.transform = Transform(scale: .one, rotation: turn * leanBack * faceOn,
                                        translation: [0, radius * cos(lean), 0])
            guard let image = await stage.snapshot(plate) else {
                // A hold started while the plate settled: put it back for after the swing.
                break
            }
            missing.removeFirst()
            store(image, key: next.key, write: true)
            RackWorkCounters.add(.railSpritesRendered)
        }
    }

    // MARK: Lifted face

    func memoryLifted(_ request: LathePlateRequest) -> UIImage? {
        memory.object(forKey: Self.key(request, pose: "lifted", style: RackPlateStyle.current) as NSString)
    }

    /// The plate's lettered face, face on: from memory, disk, or rendered (after any hold).
    func lifted(_ request: LathePlateRequest) async -> UIImage? {
        let style = RackPlateStyle.current
        let key = Self.key(request, pose: "lifted", style: style)
        if let image = memory.object(forKey: key as NSString) { return image }
        if let running = liftedRenders[key] { return await running.value }
        let url = directory.appendingPathComponent(key + ".png")
        let task = Task { @MainActor () -> UIImage? in
            if let image = await Self.decode(url, priority: .userInitiated) {
                store(image, key: key, write: false)
                return image
            }
            guard let tier = PlateTier.all.first(where: { $0.id == request.tierID }) else { return nil }
            for _ in 0..<3 {
                let image = await PlateSnapshotService.shared.renderQueued {
                    guard let stage = await RackRailStage(side: Self.liftedSide, style: style),
                          let plate = await Self.plateEntity(tier: tier, style: style, request: request) else { return nil }
                    defer { stage.tearDown() }
                    stage.frame(world: 0.47, centerY: 0, pitchDegrees: 0)
                    plate.transform = Transform(scale: .one, rotation: simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0)),
                                                translation: .zero)
                    return await stage.snapshot(plate)
                }
                if let image {
                    store(image, key: key, write: true)
                    RackWorkCounters.add(.railSpritesRendered)
                    return image
                }
                // Held mid-render: try again after the swing.
            }
            return nil
        }
        liftedRenders[key] = task
        let image = await task.value
        liftedRenders[key] = nil
        return image
    }

    // MARK: Thumbnail

    /// The world square a thumbnail shows: the lifted picture's framing, so a 0.45 m bumper
    /// fills the thumbnail's circle as the legacy thumbnails' wide lens did.
    static let thumbnailWorld: Float = 0.47

    /// A lathe plate face on, lettered, for PlateSnapshotService's thumbnails. Not queued:
    /// PlateSnapshotService calls it from inside its own render queue. Nil when a hold started
    /// while the plate settled (the caller shows the drawn stand-in and renders another time).
    static func renderThumbnail(tierID: Int, weightKg: Double, engravingText: String, side: CGFloat) async -> UIImage? {
        guard let tier = PlateTier.all.first(where: { $0.id == tierID }) else { return nil }
        let request = LathePlateRequest(tierID: tierID, weightKg: weightKg, engravingText: engravingText,
                                        projection: BarbellPlateRenderProjection())
        guard let stage = await RackRailStage(side: side, style: .lathe) else { return nil }
        defer { stage.tearDown() }
        guard !Task.isCancelled, let plate = await plateEntity(tier: tier, style: .lathe, request: request) else { return nil }
        stage.frame(world: thumbnailWorld, centerY: 0, pitchDegrees: 0)
        plate.transform = Transform(scale: .one, rotation: simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0)),
                                    translation: .zero)
        return await stage.snapshot(plate)
    }

    // MARK: Shared

    /// The lettered plate as the rack scene draws it, axis along y, no physics, no shared face cache.
    private static func plateEntity(tier: PlateTier, style: RackPlateStyle, request: LathePlateRequest) async -> Entity? {
        let holder = Entity()
        if style == .lathe {
            guard let plate = await makeLatheSnapshotPlate(tier: tier, weightKg: request.weightKg,
                                                           engravingText: request.engravingText,
                                                           projection: request.projection) else { return nil }
            holder.addChild(plate)
            return holder
        }
        let textures = await loadPlateTexturesAsync(forTierID: tier.id)
        guard !Task.isCancelled else { return nil }
        let material = buildMaterial(forTierID: tier.id, textures: textures)
        holder.addChild(makePlateEntity(tierID: tier.id, textures: textures, material: material,
                                        weightKg: request.weightKg, engravingText: request.engravingText,
                                        renderProjection: request.projection, options: .visualOnly()))
        return holder
    }

    private func store(_ image: UIImage, key: String, write: Bool) {
        let pixels = (image.cgImage?.width ?? 100) * (image.cgImage?.height ?? 100)
        memory.setObject(image, forKey: key as NSString, cost: pixels * 4)
        revision += 1
        slots[key]?.version += 1
        guard write, let data = image.pngData() else { return }
        let url = directory.appendingPathComponent(key + ".png")
        Task.detached(priority: .utility) { try? data.write(to: url, options: .atomic) }
    }

    #if DEBUG
    /// Tests: puts a stand picture in memory as a finished render would.
    func storeForTesting(_ image: UIImage, request: LathePlateRequest) {
        store(image, key: Self.standKey(request), write: false)
    }

    /// Tests: nothing queued or rendering.
    var isIdleForTesting: Bool { missing.isEmpty && batch == nil }

    /// Tests: forget every picture in memory and on disk.
    func removeAllForTesting() {
        memory.removeAllObjects()
        for slot in slots.values { slot.version += 1 }
        for file in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: file)
        }
        revision += 1
    }

    /// Tests: renders the stand pictures now and waits for them.
    func renderStandsForTesting(_ requests: [LathePlateRequest]) async -> [UIImage?] {
        for request in requests { requestStand(request) }
        for _ in 0..<900 {
            if requests.allSatisfy({ memoryStand($0) != nil }) { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return requests.map { memoryStand($0) }
    }
    #endif
}

/// The rail's art flattened into plain images, so nothing in the row needs an offscreen pass when
/// Core Animation composites it over the live 3D scene every frame: the floor darkening baked into
/// each plate picture, and the contact shadow (two blurred ellipses) rendered once per plate size.
@MainActor
enum RackRailFlatArt {
    /// The plate darkening toward the floor as the room does: clear down to 45 % of its height,
    /// then to black at 32 % at its feet.
    static let shadeStops: [Gradient.Stop] = [.init(color: .clear, location: 0.45), .init(color: .black.opacity(0.32), location: 1)]
    static var floorShade: LinearGradient {
        LinearGradient(stops: shadeStops, startPoint: .top, endPoint: .bottom)
    }

    /// `image` with floorShade drawn over it where it is opaque (the same as the gradient masked by
    /// the picture, composited over it).
    nonisolated static func shaded(_ image: UIImage) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        let rect = CGRect(origin: .zero, size: image.size)
        // The gradient where the picture is (destination in: gradient times the picture's alpha),
        // then that over the picture.
        let overlay = UIGraphicsImageRenderer(size: image.size, format: format).image { context in
            let colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.32).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0.45, 1]) {
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: rect.height),
                                                     options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
            image.draw(in: rect, blendMode: .destinationIn, alpha: 1)
        }
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: rect)
            overlay.draw(in: rect)
        }
    }

    private static var shadows: [String: UIImage] = [:]
    /// Room around the shadow for its blur, in points.
    static let shadowMargin: CGFloat = 32

    /// The contact shadow for a plate `side` points wide, as one image with `shadowMargin` around
    /// it, rendered once by SwiftUI itself so its blur is exactly the live one's.
    static func contactShadow(side: CGFloat, scale: CGFloat) -> UIImage? {
        let key = "\(side)@\(scale)"
        if let cached = shadows[key] { return cached }
        let renderer = ImageRenderer(content: RackRailContactShadow(side: side).padding(shadowMargin))
        renderer.scale = scale
        guard let image = renderer.uiImage else { return nil }
        if shadows.count > 8 { shadows.removeAll() }
        shadows[key] = image
        return image
    }
}

/// Where a plate meets the floor: a soft pool spreading past both sides of the plate and a tight
/// dark core under its rim, so it stands on the floor instead of floating over it.
struct RackRailContactShadow: View {
    let side: CGFloat

    var body: some View {
        ZStack {
            Ellipse().fill(Color.black.opacity(0.7))
                .frame(width: side * 1.2, height: side * 0.22)
                .blur(radius: 10)
            Ellipse().fill(Color.black.opacity(0.9))
                .frame(width: side * 0.7, height: side * 0.07)
                .blur(radius: 2.5)
                .offset(y: -side * 0.02)
        }
        .frame(width: side)
    }
}

/// One picture's change count, observed by the views that show it.
@MainActor
@Observable
final class RackRailSpriteSlot {
    var version = 0
}

/// One offscreen ARView lit like the rack room (neutral white from above, darker toward the
/// floor), for a batch of plate pictures.
@MainActor
private final class RackRailStage {
    let view: ARView
    let anchor = AnchorEntity(world: .zero)
    let camera = PerspectiveCamera()
    private var current: Entity?

    init?(side: CGFloat, style: RackPlateStyle) async {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) else { return nil }
        view = ARView(frame: CGRect(x: -side - 10, y: -side - 10, width: side, height: side),
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

        // The room's overhead light: from above and a little in front.
        let key = DirectionalLight()
        key.light.intensity = style == .lathe ? 2200 : 2600
        key.look(at: .zero, from: [-0.3, 1.6, 0.7], relativeTo: nil)
        anchor.addChild(key)
        // A weak rim from behind, so black rubber keeps its edge against the dark floor.
        let rim = DirectionalLight()
        rim.light.intensity = style == .lathe ? 900 : 1200
        rim.look(at: .zero, from: [0.5, 1.2, -1.2], relativeTo: nil)
        anchor.addChild(rim)

        let environment = style == .lathe ? await sharedRackStudioEnvironmentResource() : await sharedIndoorEnvironmentResource()
        if let environment {
            let light = Entity()
            light.components.set(ImageBasedLightComponent(
                source: .single(environment),
                intensityExponent: style == .lathe ? RackRoomLightingPreset.current(for: .lathe).imageBasedLightIntensityExponent + 0.4 : 8
            ))
            anchor.addChild(light)
            anchor.components.set(ImageBasedLightReceiverComponent(imageBasedLight: light))
        }
    }

    /// A narrow lens from a little above, so the plates in the row share one perspective.
    func frame(world: Float, centerY: Float, pitchDegrees: Float) {
        let distance: Float = 4
        camera.camera.fieldOfViewInDegrees = 2 * atan(world / 2 / distance) * 180 / .pi
        let target = SIMD3<Float>(0, centerY, 0)
        let pitch = pitchDegrees * .pi / 180
        camera.look(at: target, from: target + SIMD3(0, sin(pitch), cos(pitch)) * distance, relativeTo: nil)
    }

    /// Nil when a hold started while the plate settled: the caller puts the picture back.
    func snapshot(_ plate: Entity) async -> UIImage? {
        current?.removeFromParent()
        anchor.addChild(plate)
        current = plate
        // A few frames for the materials and the light to settle.
        try? await Task.sleep(for: .milliseconds(120))
        guard !PlateSnapshotService.shared.isHeld else {
            plate.removeFromParent()
            current = nil
            return nil
        }
        return await view.snapshot(timeout: .seconds(5))
    }

    func tearDown() {
        current?.removeFromParent()
        view.scene.anchors.removeAll()
        view.removeFromSuperview()
    }
}

// MARK: - Views

/// A plate standing in the row: the rendered picture, or until it is ready a drawn stand-in in
/// the plate's own finish colour with the same size and lean.
struct RackRailStandArt: View {
    let request: LathePlateRequest

    var body: some View {
        let _ = RackWorkCounters.debugTick(.railPictureBodies)
        let service = RackRailSpriteService.shared
        _ = service.slot(for: RackRailSpriteService.standKey(request)).version
        let image = service.shadedStand(request)
        return ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .transition(.opacity)
            } else {
                // Until the picture is ready: the drawn stand-in, darkened toward the floor live.
                RackRailDrawnStand(tierID: request.tierID)
                    .overlay {
                        RackRailFlatArt.floorShade
                            .mask { RackRailDrawnStand(tierID: request.tierID) }
                    }
            }
        }
        .animation(.easeOut(duration: 0.25), value: image != nil)
        .task(id: RackRailSpriteService.standKey(request)) { service.requestStand(request) }
    }
}

/// The drawn stand-in: a disc in the finish colour with its bore, leaning like the picture.
@MainActor
struct RackRailDrawnStand: View {
    let tierID: Int

    var body: some View {
        let tier = PlateTier.all.first { $0.id == tierID }
        let finish = tier.map(LatheFinish.body(for:))
        let color = Color(uiColor: finish?.color ?? .darkGray)
        let radius = CGFloat(tier.map { PlateVisualDesign.profile(for: $0.style).outerRadius } ?? 0.22)
        let scale = radius * 2 / CGFloat(RackRailSpriteService.StandFrame.world)
        GeometryReader { proxy in
            let height = proxy.size.height * scale * 0.97
            let width = height * 0.93
            ZStack {
                Ellipse().fill(color.opacity(0.55)).offset(x: width * 0.06)
                Ellipse().fill(LinearGradient(colors: [color, color.opacity(finish?.isMetal == true ? 0.6 : 0.82)],
                                              startPoint: .top, endPoint: .bottom))
                Ellipse().strokeBorder(Color.black.opacity(0.25), lineWidth: width * 0.05).padding(width * 0.1)
                Ellipse().fill(Color.black.opacity(0.7)).frame(width: width * 0.14, height: height * 0.14)
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
        _image = State(initialValue: RackRailSpriteService.shared.memoryLifted(request))
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().interpolation(.high).scaledToFit()
            } else if let stand = RackRailSpriteService.shared.memoryStand(request) {
                Image(uiImage: stand).resizable().interpolation(.high).scaledToFit()
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
        .task(id: RackRailSpriteService.key(request, pose: "lifted", style: RackPlateStyle.current)) {
            if image == nil { image = await RackRailSpriteService.shared.lifted(request) }
        }
    }
}

extension ARView {
    /// ARView.snapshot, or nil when its callback has not come within `timeout` (a view that is
    /// not drawing), so a caller in the plate render queue never waits forever.
    @MainActor
    func snapshot(timeout: Duration) async -> UIImage? {
        let box = SnapshotWait()
        return await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            box.continuation = continuation
            snapshot(saveToHDR: false) { image in
                let result = image.map(PlateSnapshotImageBox.init(image:))
                Task { @MainActor in box.finish(result?.image) }
            }
            box.timer = Task { @MainActor in
                try? await Task.sleep(for: timeout)
                box.finish(nil)
            }
        }
    }
}

@MainActor
private final class SnapshotWait {
    var continuation: CheckedContinuation<UIImage?, Never>?
    var timer: Task<Void, Never>?

    func finish(_ image: UIImage?) {
        guard let continuation else { return }
        self.continuation = nil
        timer?.cancel()
        continuation.resume(returning: image)
    }
}
