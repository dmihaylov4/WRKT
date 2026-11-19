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
import OSLog
import QuartzCore
import RealityKit
import SwiftUI
import UIKit

// MARK: - Stage

/// The renderer, the object and the camera. One per review; drawn into whichever texture asks.
@MainActor
final class CutYearAwardStage {
    let device: MTLDevice
    /// The studio, kept for the shared picture's own renderer.
    let environment: EnvironmentResource
    private let renderer: RealityRenderer
    private let pivot = Entity()
    private let camera = PerspectiveCamera()

    init(scene: CutYearAwardObjectBuilder.Scene, device: MTLDevice) throws {
        self.device = device
        environment = scene.environment
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
        // 4x multisampling (the only other mode is none): without it the bright chamfer steps
        // visibly against the black on the cut corner's diagonal and crawls as the object turns.
        // The lettering is in textures and does not need it. Drawing at 2x instead of the
        // screen's 3x softens the small line, so the layer keeps the screen's scale and the
        // cost is kept down by keeping the view only as large as the turned object.
        renderer.cameraSettings.antialiasing = .multisample4X
        setPose(CutYearAwardLight.staticPose)
    }

    /// Yaw sends the right edge away, lean the top edge, as in the SwiftUI plaque.
    func setPose(_ pose: CutYearAwardPose, extraYaw: Double = 0) {
        pivot.orientation = Self.orientation(for: pose, extraYaw: extraYaw)
    }

    static func orientation(for pose: CutYearAwardPose, extraYaw: Double = 0) -> simd_quatf {
        let yaw = Float((pose.yaw + extraYaw) * .pi / 180)
        let lean = Float(pose.lean * .pi / 180)
        return simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: -lean, axis: SIMD3(1, 0, 0))
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

    /// The on-screen layer's format. The shared picture uses it too, so it reuses the screen's
    /// compiled pipelines: a new format costs about a second of shader work on the main thread.
    static let pixelFormat: MTLPixelFormat = .bgra8Unorm_srgb
}

/// Builds the stage once per review, starting when the review opens so it is ready by the last
/// card. Released when the review closes.
@MainActor
final class CutYearAwardStageCache {
    static let shared = CutYearAwardStageCache()
    static let log = Logger(subsystem: "com.dmihaylov.trak", category: "YearAward")

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
                #if DEBUG
                let stageStart = ContinuousClock.now
                #endif
                let stage = try CutYearAwardStage(scene: scene, device: device)
                #if DEBUG
                Self.log.info("Year award object built in \(ContinuousClock.now - start, privacy: .public) (renderer \(ContinuousClock.now - stageStart, privacy: .public) on the main thread), \(CutYearAwardMemory.summary, privacy: .public)")
                #endif
                return stage
            } catch {
                #if DEBUG
                Self.log.error("Year award object failed: \(error.localizedDescription, privacy: .public)")
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
    /// Called when the renderer refuses to draw.
    var onRenderFailure: (() -> Void)?
    var onLayout: (() -> Void)?
    #if DEBUG
    /// Debug: when each frame reached the screen (0 if it was dropped), on the main thread.
    var onPresented: ((CFTimeInterval) -> Void)?
    /// Debug: how long the last frame waited for a drawable.
    private(set) var drawableWait: Duration = .zero
    #endif

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isAccessibilityElement = false
        metalLayer.pixelFormat = CutYearAwardStage.pixelFormat
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
        guard let stage, let queue, let event, bounds.width >= 1, bounds.height >= 1 else { return }
        #if DEBUG
        let waitStart = ContinuousClock.now
        #endif
        // Blocks while all drawables are still with the GPU or the display.
        let next = metalLayer.nextDrawable()
        #if DEBUG
        drawableWait = ContinuousClock.now - waitStart
        #endif
        guard let drawable = next else { return }
        stage.frame(viewHeight: bounds.height, fit: fit)
        eventValue += 1
        let value = eventValue
        do {
            #if DEBUG
            // Tests the fallback when the object builds but cannot be drawn.
            if ProcessInfo.processInfo.arguments.contains("-CutYearAwardFailRender") { throw CancellationError() }
            #endif
            try stage.render(to: drawable.texture, deltaTime: deltaTime, after: [.signal(event, value: value)])
        } catch {
            onRenderFailure?()
            return
        }
        // Present once the renderer has finished drawing into the drawable.
        guard let commands = queue.makeCommandBuffer() else { return }
        commands.encodeWaitForEvent(event, value: value)
        #if DEBUG
        if onPresented != nil {
            #if targetEnvironment(simulator)
            // The simulator has no presentation times: the present's completion stands in.
            commands.addCompletedHandler { [weak self] _ in
                let time = CACurrentMediaTime()
                DispatchQueue.main.async { self?.onPresented?(time) }
            }
            #else
            drawable.addPresentedHandler { [weak self] drawable in
                let time = drawable.presentedTime
                DispatchQueue.main.async { self?.onPresented?(time) }
            }
            #endif
        }
        #endif
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
/// The tilt is read here, on each frame, not through SwiftUI: a motion sample or a drag only
/// asks for a frame, so the view's body is not run for every sample.
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
    @ObservationIgnored private weak var motion: CutYearAwardMotion?
    @ObservationIgnored private var fixedTilt: CutYearAwardTilt?
    @ObservationIgnored private var drag: CutYearAwardTilt = .zero
    @ObservationIgnored private var dragging = false
    @ObservationIgnored private var releasing = false
    @ObservationIgnored private var reduceMotion = false
    @ObservationIgnored private var active = true
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var lastTimestamp: CFTimeInterval?
    #if DEBUG
    /// Debug: the frames drawn since the last summary, for the device log.
    @ObservationIgnored private var frameStats = CutYearAwardFrameStats()
    @ObservationIgnored private var loggedFirstFrame = false
    #endif

    /// The turn the object arrives from, in degrees: as the SwiftUI plaque did.
    static let arrivalYaw: Double = 75

    private var target: CutYearAwardTilt { (fixedTilt ?? motion?.tilt ?? .zero) + drag }

    /// Builds or fetches the stage and draws a first, hidden frame. With `arrives`, that frame
    /// already shows the start of the turn, so any first-use GPU work happens before the reveal.
    func load(_ content: CutYearAwardContent, arrives: Bool) async {
        guard view?.stage == nil else { return }
        if arrives && !reduceMotion { arrival.settle(at: Self.arrivalYaw) }
        guard let stage = await CutYearAwardStageCache.shared.stage(for: content) else {
            failed = true
            return
        }
        view?.stage = stage
        requestFrame()
        // A stage that never gets a frame on screen would leave the card empty: give up on the
        // object and let the SwiftUI plaque take over. Only counts time while the app is active.
        var waited: Duration = .zero
        while !isReady && !failed && waited < Self.firstFrameTimeout {
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            if active { waited += .milliseconds(250) }
        }
        if !isReady { failed = true }
    }

    /// How long the first frame may take once the stage exists.
    static let firstFrameTimeout: Duration = .seconds(3)

    func attach(_ view: CutYearAwardMetalView) {
        self.view = view
        view.onLayout = { [weak self] in self?.requestFrame() }
        view.onFirstFrame = { [weak self] in self?.isReady = true }
        view.onRenderFailure = { [weak self] in
            guard let self, !self.isReady else { return }
            self.failed = true
            self.stopLink()
        }
        #if DEBUG
        view.onPresented = { [weak self] time in self?.frameStats.recordPresented(at: time) }
        #endif
    }

    /// Follows the phone's tilt, or holds `fixedTilt` instead.
    func follow(_ motion: CutYearAwardMotion, fixedTilt: CutYearAwardTilt?) {
        self.motion = motion
        self.fixedTilt = fixedTilt
        motion.onTiltChange = { [weak self] in self?.requestFrame() }
        requestFrame()
    }

    func configure(reduceMotion: Bool, active: Bool, fit: CGFloat) {
        self.reduceMotion = reduceMotion
        self.active = active
        view?.fit = fit
        if !active {
            stopLink()
            #if DEBUG
            logFrames("paused")
            #endif
        }
        requestFrame()
    }

    /// Turns the object in from the side, or places it at once under Reduce Motion.
    func arrive(animated: Bool) {
        guard !hasArrived else { return }
        hasArrived = true
        if animated && !reduceMotion && arrival.value != 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { Haptics.rigid() }
        } else {
            arrival.settle(at: 0)
        }
        requestFrame()
    }

    func dragChanged(_ tilt: CutYearAwardTilt) {
        dragging = true
        releasing = false
        drag = tilt
        requestFrame()
    }

    func dragEnded() {
        dragging = false
        releasing = true
        drag = .zero
        requestFrame()
    }

    /// Leaving the card: stops drawing and, in Debug builds, logs the frames drawn on it.
    func stop() {
        stopLink()
        #if DEBUG
        logFrames("left the card")
        #endif
    }

    /// The shared picture: a landscape plate in the object's steel, rendered by a renderer of
    /// its own that is gone again when this returns. See `CutYearAwardSharePicture`.
    func shareImage(_ content: CutYearAwardContent) async -> UIImage? {
        guard let stage = view?.stage else { return nil }
        #if DEBUG
        let style = CutYearAwardShare.style(arguments: ProcessInfo.processInfo.arguments)
        #else
        let style = CutYearAwardShare.Style.face
        #endif
        return await CutYearAwardSharePicture.render(content: content, environment: stage.environment,
                                                     device: stage.device, style: style)
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
        #if DEBUG
        frameStats.pause()
        #endif
        link?.invalidate()
        link = nil
        lastTimestamp = nil
    }

    #if DEBUG
    private func logFrames(_ reason: String) {
        guard frameStats.drawn > 0 else { return }
        CutYearAwardStageCache.log.info("\(self.frameStats.summary(reason), privacy: .public)")
        frameStats.reset()
    }
    #endif

    fileprivate func tick(_ link: CADisplayLink) {
        // A hitch slows the motion down instead of skipping it.
        let deltaTime = min(lastTimestamp.map { link.timestamp - $0 } ?? link.duration, 1.0 / 30)
        lastTimestamp = link.timestamp
        let target = target

        let pose: CutYearAwardPose
        if reduceMotion {
            pose = CutYearAwardLight.staticPose
            arrival.settle(at: 0)
        } else {
            let parameters: CutYearAwardSpring.Parameters = releasing ? .release : .follow
            yaw.step(toward: target.yaw, parameters: parameters, deltaTime: deltaTime)
            lean.step(toward: target.lean, parameters: parameters, deltaTime: deltaTime)
            // The turn in waits, held at its start, until the object is revealed.
            if hasArrived { arrival.step(toward: 0, parameters: .arrival, deltaTime: deltaTime) }
            pose = CutYearAwardLight.pose(tilt: CutYearAwardTilt(yaw: yaw.value, lean: lean.value))
        }
        view?.stage?.setPose(pose, extraYaw: arrival.value)
        #if DEBUG
        let frameStart = ContinuousClock.now
        #endif
        view?.draw(deltaTime: deltaTime)
        #if DEBUG
        let cost = (ContinuousClock.now - frameStart).seconds
        let wait = (view?.drawableWait ?? .zero).seconds
        if !loggedFirstFrame {
            // The hidden first frame compiles the pipelines: logged apart from the rest.
            loggedFirstFrame = true
            CutYearAwardStageCache.log.info("Year award first frame: main thread \(String(format: "%.1f ms", cost * 1000), privacy: .public)")
        } else {
            frameStats.recordDrawn(at: link.timestamp, main: cost, wait: wait)
            if frameStats.isDue(at: link.timestamp) { logFrames("every \(Int(CutYearAwardFrameStats.interval)) s") }
        }
        #endif

        let settled = reduceMotion || (yaw.isSettled(at: target.yaw) && lean.isSettled(at: target.lean)
                                       && (arrival.isSettled(at: 0) || !hasArrived))
        if settled && !dragging {
            releasing = false
            stopLink()
            #if DEBUG
            if frameStats.isDue(at: link.timestamp) { logFrames("at rest") }
            #endif
        }
    }
}

#if DEBUG
private extension Duration {
    var seconds: Double {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
#endif

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
    /// Receives the shared picture once the object has landed, or nil if it could not be drawn.
    var onShareImage: (UIImage?) -> Void = { _ in }

    @State private var controller = CutYearAwardObjectController()
    /// Room round the face for the turned object, in points: the near edge grows by about 15
    /// percent in the arrival turn.
    static let margin: CGFloat = 40

    var body: some View {
        ZStack {
            CutYearAwardObjectGround(fit: fit)
                .opacity(controller.hasArrived ? 1 : 0)
            // Only as large as the turned object needs: the drawables and the multisampled
            // targets scale with this area.
            CutYearAwardMetalRepresentable(controller: controller)
                .frame(width: (CGFloat(CutYearAwardSlab.width * 1000) + Self.margin * 2) * fit,
                       height: (CGFloat(CutYearAwardSlab.height * 1000) + Self.margin * 2) * fit)
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
            controller.follow(motion, fixedTilt: fixedTilt)
            await controller.load(content, arrives: fixedTilt == nil)
        }
        .onChange(of: controller.isReady) { _, ready in
            guard ready else { return }
            controller.arrive(animated: fixedTilt == nil)
        }
        .task(id: controller.isReady) {
            guard controller.isReady else { return }
            // After the arrival has settled: the large still costs a frame or two of GPU time
            // and must not land in the middle of the turn. Cancelled if the card goes away.
            do { try await Task.sleep(for: .seconds(1.6)) } catch { return }
            #if DEBUG
            let start = ContinuousClock.now
            #endif
            let image = await controller.shareImage(content)
            guard !Task.isCancelled else { return }
            onShareImage(image)
            #if DEBUG
            CutYearAwardStageCache.log.info("Year award share image \(image.map { "\(Int($0.size.width * $0.scale))x\(Int($0.size.height * $0.scale))" } ?? "failed", privacy: .public) in \(ContinuousClock.now - start, privacy: .public), \(CutYearAwardMemory.summary, privacy: .public)")
            // `-CutYearAwardStill` also writes it to the app's tmp folder.
            if ProcessInfo.processInfo.arguments.contains("-CutYearAwardStill") {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("award3d-share.png")
                try? image?.pngData()?.write(to: url)
            }
            #endif
        }
        .onChange(of: controller.failed) { _, failed in if failed { onFailure() } }
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
            .onChanged { value in controller.dragChanged(CutYearAwardLight.dragTilt(translation: value.translation)) }
            .onEnded { _ in controller.dragEnded() }
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
            // A circle of light squashed flat, so the pool fades out on every side.
            Circle()
                .fill(RadialGradient(colors: [Color.white.opacity(0.11), Color.white.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: width * 0.75))
                .frame(width: width * 1.5, height: width * 1.5)
                .scaleEffect(x: 1, y: 0.22)
                .offset(y: height / 2 + 10 * fit)
            // A hint of the steel on the floor: a soft fade of light under the bottom edge.
            Rectangle()
                .fill(LinearGradient(colors: [Color(white: 0.75).opacity(0.10), Color.white.opacity(0)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: width * 0.94, height: 46 * fit)
                .blur(radius: 6 * fit)
                .offset(y: height / 2 + 36 * fit)
            // The contact shadow, tight under the edge.
            Ellipse()
                .fill(Color.black.opacity(0.9))
                .frame(width: width * 0.9, height: 12 * fit)
                .blur(radius: 6 * fit)
                .offset(y: height / 2 + 12 * fit)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
