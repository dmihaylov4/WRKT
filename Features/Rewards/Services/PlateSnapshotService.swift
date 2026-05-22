import UIKit
import RealityKit
import Foundation

@MainActor
final class PlateSnapshotService {
    static let shared = PlateSnapshotService()

    private var memoryCache: [String: UIImage] = [:]

    private init() {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
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

    static func cacheKey(tierID: Int, weightKg: Double, engravingText: String) -> String {
        let engravingHash = engravingText.isEmpty ? "none" : String(engravingText.hashValue & 0xFFFF_FFFF)
        return "v2_p\(tierID)_\(Int(weightKg * 10))_\(engravingHash)"
    }

    // MARK: - Read

    func cachedImage(tierID: Int, weightKg: Double, engravingText: String) -> UIImage? {
        let key = Self.cacheKey(tierID: tierID, weightKg: weightKg, engravingText: engravingText)
        if let mem = memoryCache[key] { return mem }
        return loadFromDisk(key: key)
    }

    func loadFromDisk(key: String) -> UIImage? {
        let url = cacheURL(for: key)
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else { return nil }
        memoryCache[key] = image
        return image
    }

    // MARK: - Write

    func writeToDisk(image: UIImage, key: String) async {
        memoryCache[key] = image
        let url = cacheURL(for: key)
        if let data = image.pngData() {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Existence check

    func hasCached(tierID: Int, weightKg: Double, engravingText: String) -> Bool {
        let key = Self.cacheKey(tierID: tierID, weightKg: weightKg, engravingText: engravingText)
        if memoryCache[key] != nil { return true }
        return FileManager.default.fileExists(atPath: cacheURL(for: key).path)
    }

    // MARK: - Render

    private var renderingKeys: Set<String> = []

    func renderIfNeeded(tierID: Int, weightKg: Double, engravingText: String) async {
        let key = Self.cacheKey(tierID: tierID, weightKg: weightKg, engravingText: engravingText)
        guard !hasCached(tierID: tierID, weightKg: weightKg, engravingText: engravingText),
              !renderingKeys.contains(key) else { return }

        renderingKeys.insert(key)
        defer { renderingKeys.remove(key) }

        guard let image = await renderPlate(tierID: tierID, weightKg: weightKg, engravingText: engravingText) else {
            return
        }
        await writeToDisk(image: image, key: key)
    }

    private func renderPlate(tierID: Int, weightKg: Double, engravingText: String) async -> UIImage? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) else { return nil }

        let size = CGSize(width: 300, height: 300)
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

        let textures = loadPlateTextures(forTierID: tierID)
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

        if let ibl = try? await EnvironmentResource(named: "IndoorHDRI") {
            let iblEntity = Entity()
            iblEntity.components.set(ImageBasedLightComponent(
                source: .single(ibl),
                intensityExponent: 8
            ))
            anchor.addChild(iblEntity)
            anchor.components.set(ImageBasedLightReceiverComponent(imageBasedLight: iblEntity))
        }

        try? await Task.sleep(for: .milliseconds(150))

        return await withCheckedContinuation { continuation in
            arView.snapshot(saveToHDR: false) { image in
                continuation.resume(returning: image)
            }
        }
    }
}
