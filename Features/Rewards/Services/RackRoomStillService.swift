//
//  RackRoomStillService.swift
//  WRKT
//
//  The rack room as a still image for the Home hex portal: the bar-only room exactly as the live
//  rack screen's scene band shows it first (same view, same size, same loadout, same lighting,
//  with the band's floor shading baked in), so the portal's zoom can end on it and cross-fade to
//  the live scene invisibly. Two ways to get one: render the real BarbellRealityView offscreen
//  once (in PlateSnapshotService's render queue, so it never competes with a rack scene opening),
//  or take the live scene's last frame when the room closes. Stored in Caches only, keyed by
//  HomeHexPortalLogic.stillKey: a full-resolution JPEG for the zoom and a small PNG for the
//  window at rest. Only the latest key is kept.
//
//  RealityView on iOS draws through an ARView (checked on the iOS 27 simulator: the hosting view
//  holds an ARView whose ARRenderView has the CAMetalLayer); ARView.snapshot reads its frame.
//  If a future system draws RealityView differently, no ARView is found, no still is made, and
//  the window keeps its placeholder: nothing else depends on it.
//

import Combine
import os
import RealityKit
import SwiftUI
import UIKit

@MainActor
final class RackRoomStillService {
    static let shared = RackRoomStillService()

    /// The window's still for the current key, decoded once.
    private var rest: (key: String, image: UIImage)?
    private var rendering: Set<String> = []
    /// Offscreen renders and live captures made in this process (the harness counts them).
    private(set) var rendersDone = 0
    private(set) var capturesDone = 0

    private init() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: Files

    var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("rack_room_stills", isDirectory: true)
    }

    func fullURL(_ key: String) -> URL { directory.appendingPathComponent("\(key).jpg") }
    func restURL(_ key: String) -> URL { directory.appendingPathComponent("\(key)-rest.png") }
    private var metricsURL: URL { directory.appendingPathComponent("scene-band-v2.json") }

    func hasStill(_ key: String) -> Bool {
        FileManager.default.fileExists(atPath: fullURL(key).path) && FileManager.default.fileExists(atPath: restURL(key).path)
    }

    /// Bytes on disk for a key (both files), for the harness.
    func diskBytes(_ key: String) -> Int {
        [fullURL(key), restURL(key)].reduce(0) {
            $0 + ((try? FileManager.default.attributesOfItem(atPath: $1.path)[.size] as? Int) ?? 0)
        }
    }

    // MARK: Reads (decoded off the main thread)

    func memoryRest(_ key: String) -> UIImage? {
        rest?.key == key ? rest?.image : nil
    }

    func loadRest(_ key: String) async -> UIImage? {
        if let image = memoryRest(key) { return image }
        guard let image = await Self.decode(restURL(key)) else { return nil }
        rest = (key, image)
        return image
    }

    /// The full-resolution still, for one transition. Not kept here: the portal drops it when the
    /// room closes (about 9.6 MB decoded on a 3x phone).
    func loadFull(_ key: String) async -> UIImage? {
        await Self.decode(fullURL(key))
    }

    nonisolated private static func decode(_ url: URL) async -> UIImage? {
        await Task.detached(priority: .userInitiated) { () -> PlateSnapshotImageBox? in
            guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return nil }
            return PlateSnapshotImageBox(image: image.preparingForDisplay() ?? image)
        }.value?.image
    }

    // MARK: Writes

    /// Stores a full still and its small copy for the window, drops every other key's files and
    /// returns the small copy. Scaling and encoding run off the main thread.
    func store(_ full: UIImage, key: String, sceneSize: CGSize) async -> UIImage? {
        guard let small = await makeRest(full, sceneSize: sceneSize) else { return nil }
        guard await write(full, rest: small, key: key) else { return nil }
        return small
    }

    /// The window's small copy of a full still (a few milliseconds, off the main thread).
    func makeRest(_ full: UIImage, sceneSize: CGSize) async -> UIImage? {
        let restSize = HomeHexGeometry.restImageRect(sceneSize: sceneSize).size
        guard restSize.width > 0 else { return nil }
        let box = PlateSnapshotImageBox(image: full)
        return await Task.detached(priority: .userInitiated) { () -> PlateSnapshotImageBox in
            let format = UIGraphicsImageRendererFormat()
            format.scale = box.image.scale
            format.opaque = true
            let small = UIGraphicsImageRenderer(size: restSize, format: format).image { _ in
                box.image.draw(in: CGRect(origin: .zero, size: restSize))
            }
            return PlateSnapshotImageBox(image: small.preparingForDisplay() ?? small)
        }.value.image
    }

    /// Writes both files and removes every other key's. Returns whether both were written.
    @discardableResult
    func write(_ full: UIImage, rest small: UIImage, key: String) async -> Bool {
        let fullURL = fullURL(key), restURL = restURL(key), directory = directory
        let boxes = (PlateSnapshotImageBox(image: full), PlateSnapshotImageBox(image: small))
        let written = await Task.detached(priority: .utility) { () -> Bool in
            guard let fullData = boxes.0.image.jpegData(compressionQuality: 0.9), let restData = boxes.1.image.pngData() else { return false }
            do {
                try fullData.write(to: fullURL, options: .atomic)
                try restData.write(to: restURL, options: .atomic)
            } catch {
                return false
            }
            let keep: Set<String> = [fullURL.lastPathComponent, restURL.lastPathComponent, "scene-band-v2.json"]
            for file in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            where !keep.contains(file.lastPathComponent) {
                try? FileManager.default.removeItem(at: file)
            }
            return true
        }.value
        if written { rest = (key, small) }
        return written
    }

    // MARK: The scene band

    private struct Band: Codable {
        var screenWidth: Double, screenHeight: Double
        var x: Double, y: Double, width: Double, height: Double
    }

    /// The live rack's scene band as last measured in the portal on a screen of this size.
    func measuredBand(screen: CGSize) -> CGRect? {
        guard let data = try? Data(contentsOf: metricsURL), let band = try? JSONDecoder().decode(Band.self, from: data),
              abs(band.screenWidth - screen.width) < 0.5, abs(band.screenHeight - screen.height) < 0.5 else { return nil }
        return CGRect(x: band.x, y: band.y, width: band.width, height: band.height)
    }

    func recordBand(_ rect: CGRect, screen: CGSize) {
        guard rect.width > 0, rect.height > 0, measuredBand(screen: screen) != rect else { return }
        let band = Band(screenWidth: screen.width, screenHeight: screen.height,
                        x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
        if let data = try? JSONEncoder().encode(band) { try? data.write(to: metricsURL, options: .atomic) }
    }

    // MARK: Render offscreen

    /// What the offscreen room needs: the bar's plates and the cosmetic choices.
    struct RoomRequest {
        var racked: [EarnedPlate]
        var barSkin: Int
        var rackStyle: String
        var roomTheme: String
        var wallText: String?
        var sceneSize: CGSize
    }

    /// Renders the room offscreen and stores it under `key`; returns the window's small still.
    /// Waits in the plate render queue (one render at a time, never while a rack scene opens).
    func render(_ request: RoomRequest, key: String, shouldStart: @escaping @MainActor () -> Bool) async -> UIImage? {
        guard !rendering.contains(key), request.sceneSize.width > 0 else { return nil }
        rendering.insert(key)
        defer { rendering.remove(key) }
        let image = await PlateSnapshotService.shared.renderQueued { [weak self] in
            guard let self, shouldStart(), !Task.isCancelled else { return nil }
            return await self.renderNow(request)
        }
        guard let image, !Task.isCancelled else { return nil }
        return await store(image, key: key, sceneSize: request.sceneSize)
    }

    private func renderNow(_ request: RoomRequest) async -> UIImage? {
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows).first(where: \.isKeyWindow) else { return nil }
        let interval = barbellSignposter.beginInterval("RoomStill", id: barbellSignposter.makeSignpostID())
        defer { barbellSignposter.endInterval("RoomStill", interval) }
        let state = SceneState()
        let built = RoomStillFlag()
        let size = request.sceneSize
        let view = BarbellRealityView(
            mode: .rackRoom(rackedPlates: request.racked, floorPlates: [], onRack: { _ in }, onUnrack: { _ in }),
            sceneState: state,
            barSkinID: request.barSkin,
            rackStyleID: request.rackStyle,
            roomThemeID: request.roomTheme,
            roomWallText: request.wallText,
            allowsInteraction: false,
            barOnly: true,
            onSceneBuilt: { built.value = true }
        )
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, .dark)
        RackOpenTrace.mark("still.host")
        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = .clear
        // Inside the window but under everything in it and nearly transparent, so it is never
        // seen. Beside the screen (outside the window's bounds) its layer was never composited,
        // so RealityKit waited for drawables that never came back: a 1 s main-thread stall on
        // every render.
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.alpha = 0.01
        host.view.isUserInteractionEnabled = false
        host.view.accessibilityElementsHidden = true
        window.insertSubview(host.view, at: 0)
        RackOpenTrace.mark("still.added")
        defer {
            host.view.removeFromSuperview()
            state.pauseNonessentialRealityWork()
        }
        let deadline = CACurrentMediaTime() + 20
        while !built.value, CACurrentMediaTime() < deadline {
            guard !Task.isCancelled else { return nil }
            try? await Task.sleep(for: .milliseconds(30))
        }
        guard built.value, let scene = state.sceneRoot.scene else { return nil }
        RackOpenTrace.mark("still.built")
        // A few drawn frames, so the first frame's late work (shadows, probe) has settled.
        await Self.frames(8, in: scene)
        RackOpenTrace.mark("still.frames")
        try? await Task.sleep(for: .milliseconds(80))
        guard let arView = Self.arView(in: host.view, showing: scene) else { return nil }
        rendersDone += 1
        let image = await Self.snapshot(arView, sceneSize: size, background: Self.background(request.roomTheme, style: state.plateStyle))
        RackOpenTrace.mark("still.snapshot")
        return image
    }

    // MARK: The live scene's frame

    /// The live rack scene's current frame, composed like an offscreen still. nil when the scene's
    /// view cannot be found.
    func captureLive(_ state: SceneState, sceneSize: CGSize, roomTheme: String) async -> UIImage? {
        guard let scene = state.sceneRoot.scene else { return nil }
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        guard let arView = windows.lazy.compactMap({ Self.arView(in: $0, showing: scene) }).first else { return nil }
        capturesDone += 1
        return await Self.snapshot(arView, sceneSize: sceneSize, background: Self.background(roomTheme, style: state.plateStyle))
    }

    // MARK: Helpers

    static func arView(in view: UIView, showing scene: RealityKit.Scene) -> ARView? {
        if let arView = view as? ARView, arView.scene === scene { return arView }
        for child in view.subviews {
            if let found = arView(in: child, showing: scene) { return found }
        }
        return nil
    }

    private static func frames(_ count: Int, in scene: RealityKit.Scene) async {
        let counter = RoomStillCounter()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var subscription: (any Cancellable)?
            subscription = scene.subscribe(to: SceneEvents.Update.self) { _ in
                MainActor.assumeIsolated {
                    counter.value += 1
                    guard counter.value == count else { return }
                    subscription?.cancel()
                    subscription = nil
                    continuation.resume()
                }
            }
        }
    }

    /// The scene band's colour behind the room (the room view's own background).
    static func background(_ roomTheme: String, style: RackPlateStyle) -> UIColor {
        let theme = RoomThemePreset.preset(for: roomTheme)
        let mood = RackRoomMood.current(for: style, roomThemeID: roomTheme)
        let shown = mood.map { theme.dimmed(by: $0.roomBrightness, floor: $0.floorBrightness, floorRoughness: $0.floorRoughness) } ?? theme
        return UIColor(shown.swiftUIBackground)
    }

    /// ARView's frame over the room's background, with the rack screen's floor shading on top (a
    /// 20 pt fade from the screen's background at the top, the plate row's floor fade at the
    /// bottom), so the still matches the band as the screen draws it.
    private static func snapshot(_ arView: ARView, sceneSize: CGSize, background: UIColor) async -> UIImage? {
        let frame: UIImage? = await withCheckedContinuation { continuation in
            arView.snapshot(saveToHDR: false) { continuation.resume(returning: $0) }
        }
        guard let frame else { return nil }
        let screenBackground = UIColor(DS.Cut.Colors.background).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        let format = UIGraphicsImageRendererFormat()
        format.scale = frame.size.width > 0 ? frame.scale * frame.size.width / sceneSize.width : 3
        format.opaque = true
        let bottom = CutRackPlateRow<EmptyView>.belowFeet + 4
        return UIGraphicsImageRenderer(size: sceneSize, format: format).image { context in
            let cg = context.cgContext
            background.setFill()
            cg.fill(CGRect(origin: .zero, size: sceneSize))
            frame.draw(in: CGRect(origin: .zero, size: sceneSize))
            let space = CGColorSpaceCreateDeviceRGB()
            let solid = screenBackground.cgColor, clear = screenBackground.withAlphaComponent(0).cgColor
            if let top = CGGradient(colorsSpace: space, colors: [solid, clear] as CFArray, locations: [0, 1]) {
                cg.drawLinearGradient(top, start: .zero, end: CGPoint(x: 0, y: 20), options: [])
            }
            let mid = screenBackground.withAlphaComponent(0.7).cgColor
            if let floor = CGGradient(colorsSpace: space, colors: [clear, mid, solid] as CFArray, locations: [0, 0.4, 1]) {
                cg.drawLinearGradient(floor, start: CGPoint(x: 0, y: sceneSize.height - bottom),
                                      end: CGPoint(x: 0, y: sceneSize.height), options: [.drawsAfterEndLocation])
            }
        }
    }
}

@MainActor
private final class RoomStillFlag {
    var value = false
}

@MainActor
private final class RoomStillCounter {
    var value = 0
}
