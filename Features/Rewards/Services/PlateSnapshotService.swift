import UIKit
import RealityKit
import Foundation
import CryptoKit

/// Plate thumbnails rendered once per plate look with RealityKit, then read from Caches. The
/// plates are the ones the rack room draws this launch (RackPlateStyle.current): legacy plates
/// under "v3_" keys, lathe plates under "l1_" keys, so a launch never shows a thumbnail of the
/// other style and both sets stay valid when a tester switches the new design off and on.
/// Renders run one at a time (each one is an offscreen ARView on the main thread) and wait while
/// a rack scene is opening (holdRenders), so a tray of uncached plates never competes with the
/// scene's first frame. Disk reads and PNG decoding run off the main thread; decoded images are
/// kept in a cost-bounded memory cache.
@MainActor
final class PlateSnapshotService {
    static let shared = PlateSnapshotService()

    private let memoryCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        // About 20 full-size (900 px) decoded thumbnails.
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    private init() {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? Self.removeLegacyCacheFiles(in: cacheDirectory)
    }

    // MARK: - Cache Directory

    private var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("plate_snapshots", isDirectory: true)
    }

    func cacheURL(for key: String) -> URL {
        cacheDirectory.appendingPathComponent("\(key).png")
    }

    // MARK: - Cache Key

    static func cacheKey(tierID: Int, weightKg: Double, engravingText: String,
                         style: RackPlateStyle = RackPlateStyle.current) -> String {
        var input = Data("\(tierID)|\(weightKg.bitPattern)|".utf8)
        input.append(contentsOf: engravingText.utf8)
        let digest = SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
        return keyPrefix(style) + digest
    }

    /// "v3_" is the legacy thumbnails' key since before the lathe plates, so they are reused.
    static func keyPrefix(_ style: RackPlateStyle) -> String {
        switch style {
        case .legacy: "v3_"
        case .lathe: "l1_"
        }
    }

    static func removeLegacyCacheFiles(in directory: URL) throws {
        let manager = FileManager.default
        let marker = directory.appendingPathComponent(".v3-cleanup-complete")
        guard !manager.fileExists(atPath: marker.path) else { return }
        let entries = try manager.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        for entry in entries {
            let values = try entry.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            guard entry.lastPathComponent.range(of: "^(v3|l1)_[0-9a-f]{64}\\.png$",
                                                 options: .regularExpression) == nil else { continue }
            try manager.removeItem(at: entry)
        }
        try Data().write(to: marker, options: .atomic)
    }

    // MARK: - Read

    func cachedImage(tierID: Int, weightKg: Double, engravingText: String) -> UIImage? {
        let key = Self.cacheKey(tierID: tierID, weightKg: weightKg, engravingText: engravingText)
        if let mem = memoryImage(key: key) { return mem }
        return loadFromDisk(key: key)
    }

    /// The decoded image if it is in memory; never touches the disk.
    func memoryImage(tierID: Int, weightKg: Double, engravingText: String) -> UIImage? {
        memoryImage(key: Self.cacheKey(tierID: tierID, weightKg: weightKg, engravingText: engravingText))
    }

    /// cachedImage with the file read and the PNG decode off the main thread.
    func cachedImageAsync(tierID: Int, weightKg: Double, engravingText: String) async -> UIImage? {
        let key = Self.cacheKey(tierID: tierID, weightKg: weightKg, engravingText: engravingText)
        if let mem = memoryImage(key: key) { return mem }
        let url = cacheURL(for: key)
        let decoded = await Task.detached(priority: .userInitiated) { () -> PlateSnapshotImageBox? in
            guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return nil }
            return PlateSnapshotImageBox(image: image.preparingForDisplay() ?? image)
        }.value
        guard let image = decoded?.image else { return nil }
        storeInMemory(image, key: key)
        return image
    }

    func loadFromDisk(key: String) -> UIImage? {
        let url = cacheURL(for: key)
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else { return nil }
        storeInMemory(image, key: key)
        return image
    }

    private func memoryImage(key: String) -> UIImage? {
        memoryCache.object(forKey: key as NSString)
    }

    private func storeInMemory(_ image: UIImage, key: String) {
        let pixels = (image.cgImage?.width ?? 300) * (image.cgImage?.height ?? 300)
        memoryCache.setObject(image, forKey: key as NSString, cost: pixels * 4)
    }

    // MARK: - Write

    func writeToDisk(image: UIImage, key: String) async {
        storeInMemory(image, key: key)
        let url = cacheURL(for: key)
        if let data = image.pngData() {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Existence check

    func hasCached(tierID: Int, weightKg: Double, engravingText: String) -> Bool {
        let key = Self.cacheKey(tierID: tierID, weightKg: weightKg, engravingText: engravingText)
        if memoryImage(key: key) != nil { return true }
        return FileManager.default.fileExists(atPath: cacheURL(for: key).path)
    }

    // MARK: - Render

    private var renderingKeys: Set<String> = []
    /// The render running now; the next one starts after it.
    private var lastRender: Task<Void, Never>?
    private var holds = 0
    private var holdWaiters: [CheckedContinuation<Void, Never>] = []

    /// Renders wait until every hold is released. Rack scenes hold renders while they open.
    func holdRenders() {
        holds += 1
    }

    /// The open rack scene, while its owner plays: a touch down in the scene, a plate held or
    /// awake, a rain or a tidy. Renders wait for it to go quiet, and for `quietAfterPlay` after,
    /// so an offscreen render never competes with a thrown plate for the main thread or the GPU.
    weak var playActivity: (any RackPlayActivity)?
    static let quietAfterPlay: TimeInterval = 1.0
    private var quietUntil: TimeInterval = 0

    /// True while the scene is in play or was within the last `quietAfterPlay` seconds.
    var isPlayBusy: Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if playActivity?.isPlayActive == true {
            quietUntil = now + Self.quietAfterPlay
            return true
        }
        return now < quietUntil
    }

    /// A rack scene is opening, swinging a plate in, or in play.
    var isHeld: Bool { holds > 0 || isPlayBusy }

    func releaseRenders() {
        guard holds > 0 else { return }
        holds -= 1
        guard holds == 0 else { return }
        let waiters = holdWaiters
        holdWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func waitForRelease() async {
        while holds > 0 || isPlayBusy {
            if holds > 0 {
                await withCheckedContinuation { holdWaiters.append($0) }
            } else {
                // Play has no end event of its own (plates fall asleep on their own): look again
                // a few times a second, only while a render is waiting.
                RackWorkCounters.add(.rendersDeferredForPlay)
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    /// Points of a rendered thumbnail (at the screen's scale).
    static let thumbnailSide: CGFloat = 300

    func renderIfNeeded(tierID: Int, weightKg: Double, engravingText: String) async {
        let key = Self.cacheKey(tierID: tierID, weightKg: weightKg, engravingText: engravingText)
        guard !hasCached(tierID: tierID, weightKg: weightKg, engravingText: engravingText),
              !renderingKeys.contains(key) else { return }

        renderingKeys.insert(key)
        defer { renderingKeys.remove(key) }

        // One at a time, after any rack scene that is opening.
        let previous = lastRender
        let render = Task { @MainActor () -> UIImage? in
            await Self.waitForPrevious(previous)
            await waitForRelease()
            guard !hasCached(tierID: tierID, weightKg: weightKg, engravingText: engravingText) else { return nil }
            return await renderPlate(tierID: tierID, weightKg: weightKg, engravingText: engravingText)
        }
        lastRender = Task { _ = await render.value }
        guard let image = await render.value else { return }
        await writeToDisk(image: image, key: key)
    }

    /// Runs other offscreen plate renders (the rack rail's sprites) in this queue: one at a time,
    /// after the renders before them, and only while no rack scene is opening or swinging a plate in.
    func renderQueued(_ work: @escaping @MainActor () async -> UIImage?) async -> UIImage? {
        let previous = lastRender
        let render = Task { @MainActor () -> UIImage? in
            await Self.waitForPrevious(previous)
            await waitForRelease()
            return await work()
        }
        lastRender = Task { _ = await render.value }
        return await render.value
    }

    /// The longest a render waits for the one before it. A render that never finishes (a snapshot
    /// whose callback never comes) must not stop every later thumbnail, row picture and still.
    static let previousRenderTimeout: Duration = .seconds(20)

    /// Waits for the previous render, or `previousRenderTimeout`, whichever comes first.
    static func waitForPrevious(_ previous: Task<Void, Never>?, timeout: Duration = previousRenderTimeout) async {
        guard let previous else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await previous.value }
            group.addTask { try? await Task.sleep(for: timeout) }
            await group.next()
            group.cancelAll()
        }
    }

    private func renderPlate(tierID: Int, weightKg: Double, engravingText: String) async -> UIImage? {
        if RackPlateStyle.current == .lathe {
            let image = await RackRailSpriteService.renderThumbnail(tierID: tierID, weightKg: weightKg,
                                                                    engravingText: engravingText,
                                                                    side: Self.thumbnailSide)
            if image != nil { RackWorkCounters.add(.thumbnailsRendered) }
            return image
        }
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) else { return nil }

        let size = CGSize(width: Self.thumbnailSide, height: Self.thumbnailSide)
        let arView = ARView(
            frame: CGRect(x: -size.width - 10, y: -size.height - 10, width: size.width, height: size.height),
            cameraMode: .nonAR,
            automaticallyConfigureSession: false
        )
        arView.environment.background = .color(.clear)
        arView.backgroundColor = .clear
        arView.isOpaque = false
        window.addSubview(arView)

        defer { arView.removeFromSuperview() }

        let textures = await loadPlateTexturesAsync(forTierID: tierID)
        // A cancelled load may be partial; never cache a thumbnail rendered from it.
        guard !Task.isCancelled else { return nil }
        let material = buildMaterial(forTierID: tierID, textures: textures)
        let entity = makePlateEntity(
            tierID: tierID,
            textures: textures,
            material: material,
            weightKg: weightKg,
            engravingText: engravingText,
            options: .visualOnly()
        )

        let upright = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
        entity.transform = Transform(scale: .one, rotation: upright, translation: .zero)

        let anchor = AnchorEntity(world: .zero)
        anchor.addChild(entity)
        arView.scene.addAnchor(anchor)

        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 45
        camera.position = [0, 0, 0.65]
        let cameraAnchor = AnchorEntity(world: .zero)
        cameraAnchor.addChild(camera)
        arView.scene.addAnchor(cameraAnchor)

        if let ibl = await sharedIndoorEnvironmentResource() {
            let iblEntity = Entity()
            iblEntity.components.set(ImageBasedLightComponent(
                source: .single(ibl),
                intensityExponent: 8
            ))
            anchor.addChild(iblEntity)
            anchor.components.set(ImageBasedLightReceiverComponent(imageBasedLight: iblEntity))
        }

        try? await Task.sleep(for: .milliseconds(150))

        RackWorkCounters.add(.thumbnailsRendered)
        return await withCheckedContinuation { continuation in
            arView.snapshot(saveToHDR: false) { image in
                continuation.resume(returning: image)
            }
        }
    }
}

/// A decoded thumbnail handed from the decoding task to the main actor.
nonisolated struct PlateSnapshotImageBox: @unchecked Sendable {
    let image: UIImage
}

/// Whether a rack scene is in play (see PlateSnapshotService.playActivity).
@MainActor
protocol RackPlayActivity: AnyObject {
    var isPlayActive: Bool { get }
}
