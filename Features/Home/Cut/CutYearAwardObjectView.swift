//
//  CutYearAwardObjectView.swift
//  WRKT
//
//  The year award object on screen. A RealityRenderer draws the scene from
//  CutYearAwardObject.swift into a Metal layer only when the pose changes: tilting or dragging
//  turns the object while the studio stays put, so the reflections move across the steel.
//  When nothing moves, nothing is drawn. A Debug-only alternative to the SwiftUI plaque.
//

import Metal
import QuartzCore
import RealityKit
import SwiftUI
import UIKit

// MARK: - Stage

/// The renderer, the object and the camera. One per review; drawn into whichever texture asks.
@MainActor
final class CutYearAwardStage {
    let device: MTLDevice
    private let renderer: RealityRenderer
    private let pivot = Entity()
    private let camera = PerspectiveCamera()

    init(scene: CutYearAwardObjectBuilder.Scene, device: MTLDevice) throws {
        self.device = device
        renderer = try RealityRenderer()
        let root = Entity()
        pivot.addChild(scene.object)
        root.addChild(pivot)
        camera.camera.fieldOfViewInDegrees = CutYearAwardSlab.fieldOfView
        camera.camera.near = 0.05
        camera.camera.far = 20
        root.addChild(camera)
        renderer.entities.append(root)
        renderer.activeCamera = camera
        renderer.lighting.resource = scene.environment
        renderer.lighting.intensityExponent = 0
        renderer.cameraSettings.colorBackground = .color(CGColor(gray: 0, alpha: 0))
        renderer.cameraSettings.antialiasing = .multisample4X
        setPose(CutYearAwardLight.staticPose)
    }

    /// Yaw sends the right edge away, lean the top edge, as in the SwiftUI plaque.
    func setPose(_ pose: CutYearAwardPose, extraYaw: Double = 0) {
        let yaw = Float((pose.yaw + extraYaw) * .pi / 180)
        let lean = Float(pose.lean * .pi / 180)
        pivot.orientation = simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: -lean, axis: SIMD3(1, 0, 0))
    }

    /// Frames the camera so `viewHeight` points of view show the face at `fit` of its size.
    func frame(viewHeight: CGFloat, fit: CGFloat) {
        guard viewHeight > 0, fit > 0 else { return }
        let distance = CutYearAwardSlab.cameraDistance(viewHeight: Float(viewHeight / fit))
        camera.position = SIMD3(0, 0, distance + CutYearAwardSlab.thickness / 2)
    }

    func render(to texture: MTLTexture, deltaTime: TimeInterval,
                after actions: [RealityRenderer.MetalEventAction] = [],
                onComplete: (@Sendable (RealityRenderer) -> Void)? = nil) throws {
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        try renderer.updateAndRender(deltaTime: deltaTime, cameraOutput: output, onComplete: onComplete,
                                     actionsAfterRender: actions)
    }

    /// A still of the object in a pose, on a transparent ground. The share image could use this.
    func snapshot(pose: CutYearAwardPose, size: CGSize, fit: CGFloat, scale: CGFloat) async -> CGImage? {
        let width = Int(size.width * scale), height = Int(size.height * scale)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm_srgb, width: width,
                                                                  height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        let saved = (pivot.orientation, camera.position)
        setPose(pose)
        frame(viewHeight: size.height, fit: fit)
        defer { pivot.orientation = saved.0; camera.position = saved.1 }
        let done: Bool = await withCheckedContinuation { continuation in
            do {
                try render(to: texture, deltaTime: 0) { _ in continuation.resume(returning: true) }
            } catch {
                continuation.resume(returning: false)
            }
        }
        guard done else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// Builds the stage once per review, starting when the review opens so it is ready by the last
/// card. Released when the review closes.
@MainActor
final class CutYearAwardStageCache {
    static let shared = CutYearAwardStageCache()

    private var content: CutYearAwardContent?
    private var task: Task<CutYearAwardStage?, Never>?

    func prepare(_ content: CutYearAwardContent) {
        guard self.content != content || task == nil else { return }
        self.content = content
        task = Task { @MainActor in
            guard let device = MTLCreateSystemDefaultDevice() else { return nil }
            #if DEBUG
            let start = ContinuousClock.now
            #endif
            do {
                let scene = try await CutYearAwardObjectBuilder.build(content: content)
                let stage = try CutYearAwardStage(scene: scene, device: device)
                #if DEBUG
                print("[CutYearAward] object built in \(ContinuousClock.now - start)")
                #endif
                return stage
            } catch {
                #if DEBUG
                print("[CutYearAward] object failed: \(error)")
                #endif
                return nil
            }
        }
    }

    func stage(for content: CutYearAwardContent) async -> CutYearAwardStage? {
        prepare(content)
        return await task?.value
    }

    func release() {
        task?.cancel()
        task = nil
        content = nil
    }
}

// MARK: - Metal view

/// A Metal layer the stage draws into on request. No display link of its own: the controller
/// asks for a frame when the pose changes.
final class CutYearAwardMetalView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }

    private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }
    private var queue: MTLCommandQueue?
    private var event: MTLEvent?
    private var eventValue: UInt64 = 0
    private var hasPresented = false

    var stage: CutYearAwardStage? {
        didSet {
            guard let stage, stage !== oldValue else { return }
            metalLayer.device = stage.device
            queue = stage.device.makeCommandQueue()
            event = stage.device.makeEvent()
            onLayout?()
        }
    }
    var fit: CGFloat = 1
    /// Called once the first frame is on screen.
    var onFirstFrame: (() -> Void)?
    var onLayout: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isAccessibilityElement = false
        metalLayer.pixelFormat = .bgra8Unorm_srgb
        metalLayer.framebufferOnly = false
        metalLayer.isOpaque = false
        metalLayer.maximumDrawableCount = 3
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = window?.screen.scale ?? traitCollection.displayScale
        metalLayer.contentsScale = scale
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        if size.width >= 1, size.height >= 1, metalLayer.drawableSize != size {
            metalLayer.drawableSize = size
            onLayout?()
        }
    }

    func draw(deltaTime: TimeInterval) {
        guard let stage, let queue, let event, bounds.width >= 1, bounds.height >= 1,
              let drawable = metalLayer.nextDrawable() else { return }
        stage.frame(viewHeight: bounds.height, fit: fit)
        eventValue += 1
        let value = eventValue
        do {
            try stage.render(to: drawable.texture, deltaTime: deltaTime, after: [.signal(event, value: value)])
        } catch {
            return
        }
        // Present once the renderer has finished drawing into the drawable.
        guard let commands = queue.makeCommandBuffer() else { return }
        commands.encodeWaitForEvent(event, value: value)
        commands.present(drawable)
        if !hasPresented {
            hasPresented = true
            commands.addCompletedHandler { [weak self] _ in
                DispatchQueue.main.async { self?.onFirstFrame?() }
            }
        }
        commands.commit()
    }
}

// MARK: - Controller

/// Moves the object: springs the tilt toward the phone's tilt plus the drag, turns it in on
/// arrival, and draws a frame on each display refresh only while something is still moving.
@MainActor
@Observable
final class CutYearAwardObjectController {
    private(set) var isReady = false
    private(set) var hasArrived = false
    private(set) var failed = false

    @ObservationIgnored weak var view: CutYearAwardMetalView?
    @ObservationIgnored private var yaw = CutYearAwardSpring(value: 0)
    @ObservationIgnored private var lean = CutYearAwardSpring(value: 0)
    /// Extra yaw while turning in from the side.
    @ObservationIgnored private var arrival = CutYearAwardSpring(value: 0)
    @ObservationIgnored private var target: CutYearAwardTilt = .zero
    @ObservationIgnored private var dragging = false
    @ObservationIgnored private var releasing = false
    @ObservationIgnored private var reduceMotion = false
    @ObservationIgnored private var active = true
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var lastTimestamp: CFTimeInterval?

    /// The turn the object arrives from, in degrees: as the SwiftUI plaque did.
    static let arrivalYaw: Double = 75

    func load(_ content: CutYearAwardContent) async {
        guard view?.stage == nil else { return }
        guard let stage = await CutYearAwardStageCache.shared.stage(for: content) else {
            failed = true
            return
        }
        view?.stage = stage
        requestFrame()
    }

    func attach(_ view: CutYearAwardMetalView) {
        self.view = view
        view.onLayout = { [weak self] in self?.requestFrame() }
        view.onFirstFrame = { [weak self] in self?.isReady = true }
    }

    func configure(reduceMotion: Bool, active: Bool, fit: CGFloat) {
        self.reduceMotion = reduceMotion
        self.active = active
        view?.fit = fit
        if !active { stopLink() }
        requestFrame()
    }

    /// Turns the object in from the side, or places it at once under Reduce Motion.
    func arrive(animated: Bool) {
        guard !hasArrived else { return }
        hasArrived = true
        if animated && !reduceMotion {
            arrival.settle(at: Self.arrivalYaw)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { Haptics.rigid() }
        }
        requestFrame()
    }

    func setTilt(_ tilt: CutYearAwardTilt) {
        target = tilt
        requestFrame()
    }

    func dragChanged() { dragging = true; releasing = false }

    func dragEnded() {
        dragging = false
        releasing = true
    }

    func stop() {
        stopLink()
    }

    // MARK: Frames

    private func requestFrame() {
        guard active, view?.stage != nil else { return }
        if link == nil {
            let link = CADisplayLink(target: DisplayLinkTarget(self), selector: #selector(DisplayLinkTarget.tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            link.add(to: .main, forMode: .common)
            self.link = link
            lastTimestamp = nil
        }
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
        lastTimestamp = nil
    }

    fileprivate func tick(_ link: CADisplayLink) {
        let deltaTime = lastTimestamp.map { link.timestamp - $0 } ?? link.duration
        lastTimestamp = link.timestamp
        let pose: CutYearAwardPose
        if reduceMotion {
            pose = CutYearAwardLight.staticPose
            arrival.settle(at: 0)
        } else {
            let parameters: CutYearAwardSpring.Parameters = releasing ? .release : .follow
            yaw.step(toward: target.yaw, parameters: parameters, deltaTime: deltaTime)
            lean.step(toward: target.lean, parameters: parameters, deltaTime: deltaTime)
            arrival.step(toward: 0, parameters: .arrival, deltaTime: deltaTime)
            pose = CutYearAwardLight.pose(tilt: CutYearAwardTilt(yaw: yaw.value, lean: lean.value))
        }
        view?.stage?.setPose(pose, extraYaw: arrival.value)
        view?.draw(deltaTime: deltaTime)

        let settled = reduceMotion || (yaw.isSettled(at: target.yaw) && lean.isSettled(at: target.lean)
                                       && arrival.isSettled(at: 0))
        if settled && !dragging {
            releasing = false
            stopLink()
        }
    }
}

/// CADisplayLink holds its target strongly; this keeps it from holding the controller.
private final class DisplayLinkTarget: NSObject {
    weak var controller: CutYearAwardObjectController?

    init(_ controller: CutYearAwardObjectController) {
        self.controller = controller
    }

    @objc func tick(_ link: CADisplayLink) {
        MainActor.assumeIsolated {
            guard let controller else {
                link.invalidate()
                return
            }
            controller.tick(link)
        }
    }
}

private struct CutYearAwardMetalRepresentable: UIViewRepresentable {
    let controller: CutYearAwardObjectController

    func makeUIView(context: Context) -> CutYearAwardMetalView {
        let view = CutYearAwardMetalView(frame: .zero)
        controller.attach(view)
        return view
    }

    func updateUIView(_ uiView: CutYearAwardMetalView, context: Context) {}

    static func dismantleUIView(_ uiView: CutYearAwardMetalView, coordinator: ()) {
        uiView.stage = nil
    }
}

// MARK: - On screen

/// The award object in its space: a faint pool of light under it and a soft contact shadow, the
/// object above, turned by tilt and drag. VoiceOver reads it as one element, like the plaque.
struct CutYearAwardObjectPlaque: View {
    let content: CutYearAwardContent
    let motion: CutYearAwardMotion
    let reduceMotion: Bool
    let active: Bool
    /// How much the plaque is scaled to fit, as the SwiftUI plaque.
    let fit: CGFloat
    /// Debug: a fixed tilt instead of the phone's, with no arrival.
    var fixedTilt: CutYearAwardTilt?
    var onFailure: () -> Void = {}

    @State private var controller = CutYearAwardObjectController()
    @State private var drag: CutYearAwardTilt = .zero

    private var tilt: CutYearAwardTilt { (fixedTilt ?? motion.tilt) + drag }

    var body: some View {
        ZStack {
            CutYearAwardObjectGround(fit: fit)
                .opacity(controller.hasArrived ? 1 : 0)
            CutYearAwardMetalRepresentable(controller: controller)
                .accessibilityHidden(true)
                .opacity(controller.isReady && controller.hasArrived ? 1 : 0)
                .offset(y: controller.hasArrived ? 0 : -24)
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.8, dampingFraction: 0.8),
                   value: controller.hasArrived)
        .contentShape(Rectangle())
        .gesture(dragGesture, isEnabled: !reduceMotion)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(content.accessibilityText))
        .task {
            controller.configure(reduceMotion: reduceMotion, active: active, fit: fit)
            controller.setTilt(tilt)
            await controller.load(content)
        }
        .onChange(of: controller.isReady) { _, ready in
            guard ready else { return }
            controller.arrive(animated: fixedTilt == nil)
        }
        .onChange(of: controller.failed) { _, failed in if failed { onFailure() } }
        .onChange(of: tilt) { _, tilt in controller.setTilt(tilt) }
        .onChange(of: active) { configure() }
        .onChange(of: reduceMotion) { configure() }
        .onChange(of: fit) { configure() }
        .onDisappear { controller.stop() }
    }

    private func configure() {
        controller.configure(reduceMotion: reduceMotion, active: active, fit: fit)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                controller.dragChanged()
                drag = CutYearAwardLight.dragTilt(translation: value.translation)
            }
            .onEnded { _ in
                controller.dragEnded()
                drag = .zero
            }
    }
}

/// What the object sits over: a soft shadow just under its bottom edge on a faint pool of
/// light, so it stands in a space instead of floating on black.
private struct CutYearAwardObjectGround: View {
    let fit: CGFloat

    var body: some View {
        let width = CGFloat(CutYearAwardSlab.width * 1000) * fit
        let height = CGFloat(CutYearAwardSlab.height * 1000) * fit
        ZStack {
            Ellipse()
                .fill(RadialGradient(colors: [Color.white.opacity(0.05), Color.white.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: width * 0.7))
                .frame(width: width * 1.5, height: width * 0.4)
                .offset(y: height / 2 + 10 * fit)
            Ellipse()
                .fill(Color.black.opacity(0.85))
                .frame(width: width * 0.86, height: 18 * fit)
                .blur(radius: 9 * fit)
                .offset(y: height / 2 + 14 * fit)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
