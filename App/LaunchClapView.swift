import Combine
import SwiftUI

/// The single, deterministic clock model used by launch and the Debug replay.
/// Times supplied to the angle function are fractions of the 1.2 second clap.
enum LaunchClapTimeline {
    static let clapDuration = 1.2
    static let holdDuration = 1.9
    static let fadeDuration = 0.55
    static let impacts = [0.34, 0.60]
    /// The design holds the still mark for the first 14 percent. The launch screen has
    /// already shown it at rest, so the clock starts after that hold.
    static let skippedLeadIn = 0.14 * clapDuration

    static func progress(elapsed: Double, start: Double, duration: Double) -> Double {
        min(1, max(0, (elapsed - start) / duration))
    }

    /// Solve the Bezier's x coordinate before evaluating y. Evaluating y(t) alone
    /// would give a different acceleration from the design's cubic-bezier curve.
    static func bezier(_ fraction: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        let fraction = min(1, max(0, fraction))
        guard fraction > 0, fraction < 1 else { return fraction }
        func component(_ t: Double, _ a: Double, _ b: Double) -> Double {
            let u = 1 - t
            return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
        }
        var lower = 0.0
        var upper = 1.0
        for _ in 0..<24 {
            let midpoint = (lower + upper) / 2
            if component(midpoint, x1, x2) < fraction { lower = midpoint } else { upper = midpoint }
        }
        return component((lower + upper) / 2, y1, y2)
    }

    /// Evenly spaced values of a timeline curve between two times, both ends included.
    /// The Core Animation player plays these back, so it follows the same curves.
    static func samples(from start: Double, to end: Double, rate: Double = 120,
                        _ value: (Double) -> Double) -> [Double] {
        let steps = max(1, Int(((end - start) * rate).rounded(.up)))
        return (0...steps).map { value(start + (end - start) * Double($0) / Double(steps)) }
    }

    static func leftAngle(at fraction: Double, reduceMotion: Bool = false) -> Double {
        guard !reduceMotion else { return 0 }
        switch fraction {
        case ..<0.14: return 0
        case ..<0.20:
            return -5 * bezier((fraction - 0.14) / 0.06, 0.42, 0, 0.58, 1)
        case ..<0.28:
            return -5 + 27.5 * bezier((fraction - 0.20) / 0.08, 0.85, 0, 1, 0.45)
        case ..<0.34: return 22.5
        case ..<0.42:
            return 22.5 - 19.5 * bezier((fraction - 0.34) / 0.08, 0.2, 0.8, 0.4, 1)
        case ..<0.50:
            return 3 + 19.5 * bezier((fraction - 0.42) / 0.08, 0.85, 0, 1, 0.45)
        case ..<0.62: return 22.5
        case ..<1:
            return 22.5 * (1 - bezier((fraction - 0.62) / 0.38, 0.2, 0.9, 0.25, 1.12))
        default: return 0
        }
    }

    static func rightAngle(at fraction: Double, reduceMotion: Bool = false) -> Double {
        -leftAngle(at: fraction, reduceMotion: reduceMotion)
    }

    static func canRevealShell(animationFinished: Bool, sessionReady: Bool) -> Bool {
        animationFinished && sessionReady
    }

    static func thump(elapsed: Double, reduceMotion: Bool) -> CGSize {
        guard !reduceMotion else { return CGSize(width: 1, height: 1) }
        // The most recent impact owns the squash when the two 260 ms thumps touch.
        guard let impact = impacts.last(where: { $0 <= elapsed }), elapsed < impact + 0.26 else {
            return CGSize(width: 1, height: 1)
        }
        let time = elapsed - impact
        let keys: [(Double, Double, Double)] = [(0, 1, 1), (0.06, 1.07, 0.93), (0.15, 0.98, 1.02), (0.26, 1, 1)]
        for index in 1..<keys.count where time <= keys[index].0 {
            let a = keys[index - 1], b = keys[index]
            let p = progress(elapsed: time, start: a.0, duration: b.0 - a.0)
            return CGSize(width: a.1 + (b.1 - a.1) * p, height: a.2 + (b.2 - a.2) * p)
        }
        return CGSize(width: 1, height: 1)
    }
}

/// Animation clock that pauses through hitches instead of skipping ahead.
/// Launch work blocks the main thread for long stretches; a wall clock would
/// jump past the claps and show only the tail of the animation.
final class LaunchClapClock {
    static let maxStep = 1.0 / 30

    private(set) var elapsed: Double
    private var lastTick: Date?

    init(startingAt elapsed: Double = 0) {
        self.elapsed = elapsed
    }

    static func step(for interval: TimeInterval) -> Double {
        min(max(0, interval), maxStep)
    }

    func advance(to date: Date) -> Double {
        if let lastTick {
            elapsed += Self.step(for: date.timeIntervalSince(lastTick))
        }
        lastTick = date
        return elapsed
    }
}

/// Launch splash state shared by the app root, which draws the clap from the first
/// SwiftUI frame, and the shell, which reports when the session check is done and
/// holds its startup prompts until the splash is gone.
@MainActor
final class LaunchSplashState: ObservableObject {
    static let shared = LaunchSplashState()

    @Published var isDismissed = false
    @Published var isContentReady = false
}

struct LaunchClapView: View {
    let sessionReady: Bool
    var onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clock = LaunchClapClock(startingAt: LaunchClapTimeline.skippedLeadIn)
    @State private var fadeStartedAt: Double?
    @State private var didComplete = false

    // Fixed positions allow exact impact screenshots of the real SwiftUI view.
    // This launch argument has no effect in Release.
    private var snapshotTime: Double? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-LaunchClapTime"), arguments.indices.contains(index + 1) {
            return Double(arguments[index + 1])
        }
        #endif
        return nil
    }

    var body: some View {
        Group {
            if reduceMotion || snapshotTime != nil {
                // Reduce Motion only fades the still mark in, and fixed screenshot
                // times need a clock that can be held: both stay on the SwiftUI clock.
                timelineBody
            } else {
                LaunchClapPlayer(sessionReady: sessionReady, onComplete: onComplete)
                    .ignoresSafeArea()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("VOLIA")
        .accessibilityAddTraits(.isImage)
        .statusBarHidden()
    }

    private var timelineBody: some View {
        TimelineView(.animation(paused: didComplete || snapshotTime != nil)) { context in
            let elapsed = snapshotTime ?? clock.advance(to: context.date)
            let canReveal = LaunchClapTimeline.canRevealShell(
                animationFinished: elapsed >= LaunchClapTimeline.holdDuration,
                sessionReady: sessionReady
            ) && snapshotTime == nil
            let fade = fadeStartedAt.map {
                LaunchClapTimeline.progress(elapsed: elapsed - $0, start: 0,
                                            duration: LaunchClapTimeline.fadeDuration)
            } ?? 0
            ZStack {
                Color.black
                LaunchClapMark(elapsed: elapsed, reduceMotion: reduceMotion)
                    .opacity(reduceMotion ? LaunchClapTimeline.progress(elapsed: elapsed, start: 0, duration: 0.4) : 1)
            }
            .ignoresSafeArea()
            .opacity(1 - fade)
            .onChange(of: canReveal, initial: true) { _, ready in
                if ready {
                    if fadeStartedAt == nil { fadeStartedAt = elapsed }
                } else {
                    fadeStartedAt = nil
                }
            }
            .onChange(of: fade >= 1) { _, finished in
                guard finished, !didComplete else { return }
                didComplete = true
                onComplete()
            }
        }
    }

}

// MARK: - Core Animation player

/// Hosts the layer-based clap in SwiftUI.
private struct LaunchClapPlayer: UIViewRepresentable {
    let sessionReady: Bool
    let onComplete: () -> Void

    func makeUIView(context: Context) -> LaunchClapPlayerView {
        let view = LaunchClapPlayerView()
        view.onComplete = onComplete
        view.sessionReady = sessionReady
        return view
    }

    func updateUIView(_ view: LaunchClapPlayerView, context: Context) {
        view.onComplete = onComplete
        view.sessionReady = sessionReady
    }
}

/// Plays the clap as Core Animation layers. The whole animation is handed to the
/// render server in one commit, so it keeps its frame rate while launch work blocks
/// the main thread. `LaunchClapTimeline` stays the source of every angle and timing:
/// the arm and thump curves are sampled from it.
final class LaunchClapPlayerView: UIView {
    static let markSide: CGFloat = 160
    /// Logo coordinates are a 1024 square; layers are built at their final size so
    /// nothing is drawn large and scaled down.
    private static let scale = markSide / 1024
    private static let origin = LaunchClapTimeline.skippedLeadIn
    private static let total = LaunchClapTimeline.holdDuration - origin

    var onComplete: (() -> Void)?
    var sessionReady = false {
        didSet { updateFade() }
    }

    /// Carries the impact squash; every other layer sits inside it.
    private let markLayer = CALayer()
    private var pendingAnimations: [(layer: CALayer, animation: CAAnimation)] = []
    private var didStart = false
    private var holdFinished = false
    private var isFading = false
    private var didComplete = false
    private var fadeGeneration = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        markLayer.bounds = CGRect(x: 0, y: 0, width: Self.markSide, height: Self.markSide)
        layer.addSublayer(markLayer)
        buildLayers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        let displayScale = window?.screen.scale ?? traitCollection.displayScale
        markLayer.sublayers?.forEach { $0.contentsScale = displayScale }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        markLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
        if !didStart, window != nil, !bounds.isEmpty {
            didStart = true
            play()
        }
    }

    // MARK: Layers

    private func buildLayers() {
        let brand = UIColor(DS.Semantic.brand).cgColor
        let origin = Self.origin
        let clap = LaunchClapTimeline.clapDuration

        // Arms. Each begins at commit time, where the launch screen left the still mark.
        let arms: [([CGPoint], Double)] = [(VMarkShape.leftArm, 1), (VMarkShape.rightArm, -1)]
        for (points, direction) in arms {
            let arm = armLayer(points, color: brand)
            markLayer.addSublayer(arm)
            let rotation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            rotation.values = LaunchClapTimeline.samples(from: origin, to: clap) {
                direction * LaunchClapTimeline.leftAngle(at: $0 / clap) * .pi / 180
            }
            rotation.calculationMode = .linear
            rotation.duration = clap - origin
            pendingAnimations.append((arm, rotation))
        }

        // Impact squash on the whole mark. This group runs for the full hold and
        // reports when the animation is over.
        if let first = LaunchClapTimeline.impacts.first, let last = LaunchClapTimeline.impacts.last {
            let end = last + 0.26
            let squash: [CAAnimation] = ["transform.scale.x", "transform.scale.y"].map { keyPath in
                let animation = CAKeyframeAnimation(keyPath: keyPath)
                animation.values = LaunchClapTimeline.samples(from: first, to: end) {
                    let thump = LaunchClapTimeline.thump(elapsed: $0, reduceMotion: false)
                    return keyPath.hasSuffix("x") ? thump.width : thump.height
                }
                animation.calculationMode = .linear
                animation.beginTime = first - origin
                animation.duration = end - first
                return animation
            }
            let hold = group(squash)
            hold.delegate = LaunchClapStopDelegate { [weak self] in
                self?.holdFinished = true
                self?.updateFade()
            }
            pendingAnimations.append((markLayer, hold))
        }

        // Ripple, burst and flash for each impact, hidden outside their window.
        let centre = CGPoint(x: 554 * Self.scale, y: 520 * Self.scale)
        for impact in LaunchClapTimeline.impacts {
            let start = impact - origin

            let ripple = CAShapeLayer()
            let rippleSide = 240 * Self.scale
            ripple.bounds = CGRect(x: 0, y: 0, width: rippleSide, height: rippleSide)
            ripple.path = CGPath(ellipseIn: ripple.bounds, transform: nil)
            ripple.fillColor = nil
            ripple.strokeColor = brand
            ripple.lineWidth = 6 * Self.scale
            ripple.position = centre
            ripple.opacity = 0
            markLayer.addSublayer(ripple)
            pendingAnimations.append((ripple, group([
                basic("transform.scale", from: 0.2, to: 1.9, at: start, duration: 0.5),
                basic("opacity", from: 1, to: 0, at: start, duration: 0.5)
            ])))

            // 1 - (1 - t)^3, the burst's travel curve, as an exact cubic Bezier.
            let easeOutCubic = CAMediaTimingFunction(controlPoints: 1.0 / 3, 1, 2.0 / 3, 1)
            for index in 0..<16 {
                let angle = Double(index) * .pi / 8
                let distance = Double(120 + (index * 67) % 231) * Self.scale
                let radius = Double(16 + (index * 7) % 16) * Self.scale
                let particle = disc(radius: radius, color: brand, at: centre)
                markLayer.addSublayer(particle)
                let target = CGPoint(x: centre.x + cos(angle) * distance, y: centre.y + sin(angle) * distance)
                pendingAnimations.append((particle, group([
                    basic("position", from: NSValue(cgPoint: centre), to: NSValue(cgPoint: target),
                          at: start, duration: 0.62, timing: easeOutCubic),
                    basic("transform.scale", from: 1, to: 0.15, at: start, duration: 0.62),
                    basic("opacity", from: 1, to: 0, at: start, duration: 0.62)
                ])))
            }

            let flash = disc(radius: 90 * Self.scale, color: UIColor.white.cgColor, at: centre)
            markLayer.addSublayer(flash)
            pendingAnimations.append((flash, group([
                basic("transform.scale", from: 0.3, to: 1.1, at: start, duration: 0.22),
                basic("opacity", from: 0.9, to: 0, at: start, duration: 0.22)
            ])))
        }
    }

    private func armLayer(_ points: [CGPoint], color: CGColor) -> CAShapeLayer {
        let arm = CAShapeLayer()
        arm.bounds = markLayer.bounds
        // Both arms turn about the foot of the V.
        arm.anchorPoint = CGPoint(x: 582.0 / 1024, y: 587.0 / 1024)
        arm.position = CGPoint(x: 582 * Self.scale, y: 587 * Self.scale)
        let path = CGMutablePath()
        path.addLines(between: points.map { CGPoint(x: $0.x * Self.scale, y: $0.y * Self.scale) })
        path.closeSubpath()
        arm.path = path
        arm.fillColor = color
        return arm
    }

    private func disc(radius: CGFloat, color: CGColor, at centre: CGPoint) -> CALayer {
        let disc = CALayer()
        disc.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
        disc.cornerRadius = radius
        disc.backgroundColor = color
        disc.position = centre
        disc.opacity = 0
        return disc
    }

    /// A linear animation inside a group; `start` is seconds after the clap begins.
    private func basic(_ keyPath: String, from: Any, to: Any, at start: Double, duration: Double,
                       timing: CAMediaTimingFunction? = nil) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.beginTime = start
        animation.duration = duration
        animation.timingFunction = timing
        return animation
    }

    /// A group begins when it is committed, which keeps every layer in step even if
    /// the main thread stalls between building the animation and showing it.
    private func group(_ animations: [CAAnimation]) -> CAAnimationGroup {
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = Self.total
        return group
    }

    // MARK: Playback

    private func play() {
        for (index, pending) in pendingAnimations.enumerated() {
            pending.layer.add(pending.animation, forKey: "launchClap\(index)")
        }
        pendingAnimations = []
    }

    private func updateFade() {
        let shouldFade = LaunchClapTimeline.canRevealShell(animationFinished: holdFinished,
                                                           sessionReady: sessionReady)
        guard shouldFade != isFading, !didComplete else { return }
        isFading = shouldFade
        fadeGeneration += 1
        guard shouldFade else {
            layer.removeAnimation(forKey: "launchClapFade")
            return
        }
        let generation = fadeGeneration
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.fadeGeneration == generation, !self.didComplete else { return }
            self.didComplete = true
            self.onComplete?()
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = LaunchClapTimeline.fadeDuration
        // The view is removed when the fade completes; holding the last frame avoids a flash.
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        layer.add(fade, forKey: "launchClapFade")
        CATransaction.commit()
    }
}

private final class LaunchClapStopDelegate: NSObject, CAAnimationDelegate {
    private let onStop: () -> Void

    init(onStop: @escaping () -> Void) {
        self.onStop = onStop
    }

    // Also called with `finished == false` when the app is backgrounded mid-clap;
    // the mark is at rest either way, so the splash may move on.
    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        onStop()
    }
}

/// Also used while history loads, so the first SwiftUI frame matches the launch storyboard.
struct LaunchClapMark: View {
    let elapsed: Double
    let reduceMotion: Bool

    var body: some View {
        let thump = LaunchClapTimeline.thump(elapsed: elapsed, reduceMotion: reduceMotion)
        return ZStack {
            arm(.left, angle: LaunchClapTimeline.leftAngle(at: elapsed / LaunchClapTimeline.clapDuration, reduceMotion: reduceMotion))
            arm(.right, angle: LaunchClapTimeline.rightAngle(at: elapsed / LaunchClapTimeline.clapDuration, reduceMotion: reduceMotion))
            if !reduceMotion {
                ForEach(LaunchClapTimeline.impacts, id: \.self) { impact in
                    impactEffects(age: elapsed - impact)
                }
            }
        }
        .frame(width: 1024, height: 1024)
        .scaleEffect(x: thump.width, y: thump.height)
        .scaleEffect(160.0 / 1024)
        .frame(width: 160, height: 160)
    }

    private func arm(_ arm: VMarkShape.Arm, angle: Double) -> some View {
        VMarkShape(arm: arm)
            .fill(DS.Semantic.brand)
            // VMarkShape fits its cropped viewBox. Restore that box to the full logo
            // coordinates so the 160 pt frame represents the complete 1024 square.
            .frame(width: 758, height: 457)
            .rotationEffect(.degrees(angle), anchor: UnitPoint(x: (582.0 - 132) / 758, y: (587.0 - 285) / 457))
            .position(x: 511, y: 513.5)
    }

    @ViewBuilder
    private func impactEffects(age: Double) -> some View {
        if age >= 0, age < 0.62 {
            let flash = LaunchClapTimeline.progress(elapsed: age, start: 0, duration: 0.22)
            let ripple = LaunchClapTimeline.progress(elapsed: age, start: 0, duration: 0.5)
            let burst = LaunchClapTimeline.progress(elapsed: age, start: 0, duration: 0.62)
            Circle()
                .stroke(DS.Semantic.brand, lineWidth: 6)
                .frame(width: 240, height: 240)
                .scaleEffect(0.2 + 1.7 * ripple)
                .opacity(1 - ripple)
                .position(x: 554, y: 520)
            ForEach(0..<16) { index in
                let angle = Double(index) * .pi / 8
                let distance = Double(120 + (index * 67) % 231)
                let radius = Double(16 + (index * 7) % 16)
                let travel = 1 - pow(1 - burst, 3)
                Circle()
                    .fill(DS.Semantic.brand)
                    .frame(width: radius * 2, height: radius * 2)
                    .scaleEffect(1 - 0.85 * burst)
                    .opacity(1 - burst)
                    .position(x: 554 + cos(angle) * distance * travel,
                              y: 520 + sin(angle) * distance * travel)
            }
            Circle()
                .fill(.white)
                .frame(width: 180, height: 180)
                .scaleEffect(0.3 + 0.8 * flash)
                .opacity(0.9 * (1 - flash))
                .position(x: 554, y: 520)
        }
    }
}
