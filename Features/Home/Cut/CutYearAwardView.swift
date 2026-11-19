//
//  CutYearAwardView.swift
//  WRKT
//
//  The year award: a brushed steel plaque with the year engraved, the last card of the year
//  in review. Layered SwiftUI only: a polished rim, a brushed face, the engraving, and a light
//  band that moves across the metal as the phone tilts or the plaque is dragged.
//  The numbers and the pose come from CutYearAwardModel.swift.
//

import CoreMotion
import SwiftUI

// MARK: - Plaque

/// The plaque, flat. The live screen turns it in 3D; the shared picture renders it as is.
struct CutYearAwardPlaque: View {
    let content: CutYearAwardContent
    /// Where the light band crosses the face, see `CutYearAwardPose.band`.
    let band: Double
    /// Offset of the light lip under the engraving.
    let highlight: CGSize

    static let size = CGSize(width: 318, height: 476)
    static let cut: CGFloat = 52
    static let rim: CGFloat = 5

    static var outline: CutCornerShape { CutCornerShape(corner: .topLeading, cut: .points(cut)) }
    static var face: CutCornerShape { outline.inset(by: rim) }

    var body: some View {
        ZStack {
            CutYearAwardRim()
            CutYearAwardBand(band: band, strength: 1)
                .clipShape(Self.outline)
            CutYearAwardFace()
            CutYearAwardEngraving(content: content, highlight: highlight)
                .padding(Self.rim)
            CutYearAwardBand(band: band, strength: 0.7)
                .clipShape(Self.face)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        // The plaque is an object with a fixed size: its type does not follow Dynamic Type.
        // VoiceOver reads it as one phrase.
        .dynamicTypeSize(.large)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(content.accessibilityText))
    }
}

/// The steel colours, taken from the approved mock.
private enum CutYearAwardMetal {
    static let ink = Color(hex: "#24272B")
    static let secondaryInk = Color(hex: "#33373C")
    static let highlight = Color.white.opacity(0.65)

    /// The polished rim, at 135 degrees.
    static let rim = LinearGradient(
        stops: [.init(color: Color(hex: "#F4F6F9"), location: 0),
                .init(color: Color(hex: "#7B8088"), location: 0.22),
                .init(color: Color(hex: "#D9DDE3"), location: 0.48),
                .init(color: Color(hex: "#5C6168"), location: 0.74),
                .init(color: Color(hex: "#B9BEC6"), location: 1)],
        startPoint: UnitPoint(x: -0.12, y: 0.08), endPoint: UnitPoint(x: 1.12, y: 0.92))

    /// The brushed face, at 112 degrees.
    static let face = LinearGradient(
        stops: [.init(color: Color(hex: "#8D929A"), location: 0),
                .init(color: Color(hex: "#E6EAEF"), location: 0.16),
                .init(color: Color(hex: "#A3A8B0"), location: 0.30),
                .init(color: Color(hex: "#F3F5F8"), location: 0.46),
                .init(color: Color(hex: "#9499A1"), location: 0.60),
                .init(color: Color(hex: "#D5D9DF"), location: 0.76),
                .init(color: Color(hex: "#7E838B"), location: 1)],
        startPoint: UnitPoint(x: -0.19, y: 0.32), endPoint: UnitPoint(x: 1.19, y: 0.68))
}

private struct CutYearAwardRim: View {
    var body: some View {
        CutYearAwardPlaque.outline
            .fill(CutYearAwardMetal.rim)
            .shadow(color: .black.opacity(0.75), radius: 15, x: 0, y: 26)
    }
}

private struct CutYearAwardFace: View {
    var body: some View {
        let face = CutYearAwardPlaque.face
        face.fill(CutYearAwardMetal.face)
            .overlay { CutYearAwardBrush().clipShape(face) }
            // The seam where the face meets the polished rim.
            .overlay { face.stroke(Color.black.opacity(0.28), lineWidth: 1) }
    }
}

/// Fine horizontal grain. Seeded, so every render draws the same metal; it has no inputs, so
/// SwiftUI does not redraw it while the plaque moves.
private struct CutYearAwardBrush: View {
    var body: some View {
        Canvas { context, size in
            var seed: UInt64 = 0x5EED_2026
            func next() -> CGFloat {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return CGFloat(seed >> 40) / CGFloat(1 << 24)
            }
            var y: CGFloat = 0
            while y < size.height {
                let height = 0.4 + next() * 0.8
                let alpha = 0.025 + next() * 0.06
                let light = next() > 0.45
                let start = (next() - 0.3) * size.width
                let length = size.width * (0.4 + next() * 0.9)
                context.fill(Path(CGRect(x: start, y: y, width: length, height: height)),
                             with: .color(light ? .white.opacity(alpha) : .black.opacity(alpha)))
                y += height + next() * 1.1
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The light: a soft wide sheen with a brighter core, crossing the metal on the diagonal.
private struct CutYearAwardBand: View {
    let band: Double
    let strength: Double

    var body: some View {
        ZStack {
            sheen(halfWidth: 0.22, peak: 0.75 * strength)
                .blendMode(.overlay)
            sheen(halfWidth: 0.07, peak: 0.32 * strength)
                .blendMode(.screen)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func sheen(halfWidth: Double, peak: Double) -> LinearGradient {
        LinearGradient(
            stops: [.init(color: .white.opacity(0), location: 0),
                    .init(color: .white.opacity(peak * 0.4), location: 0.3),
                    .init(color: .white.opacity(peak), location: 0.5),
                    .init(color: .white.opacity(peak * 0.4), location: 0.7),
                    .init(color: .white.opacity(0), location: 1)],
            startPoint: UnitPoint(x: band - halfWidth, y: band - halfWidth),
            endPoint: UnitPoint(x: band + halfWidth, y: band + halfWidth))
    }
}

/// Engraved: dark ink with a light lip on the side away from the light.
private extension View {
    func engraved(_ highlight: CGSize, ink: Color = CutYearAwardMetal.ink, depth: CGFloat = 1) -> some View {
        foregroundStyle(ink)
            .shadow(color: CutYearAwardMetal.highlight, radius: 0,
                    x: highlight.width * depth, y: highlight.height * depth)
    }
}

/// The etched mark: a dark cut edge on the light side, a bright lip on the other, no outline.
private struct CutYearAwardMark: View {
    let highlight: CGSize

    var body: some View {
        ZStack {
            VMarkShape()
                .fill(Color.white.opacity(0.75))
                .offset(x: highlight.width * 1.6, y: highlight.height * 1.2)
            VMarkShape()
                .fill(Color(hex: "#15171A"))
                .offset(x: -highlight.width, y: -highlight.height * 0.7)
            VMarkShape()
                .fill(Color(hex: "#4A4E55"))
        }
        .accessibilityHidden(true)
    }
}

private struct CutYearAwardEngraving: View {
    let content: CutYearAwardContent
    let highlight: CGSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                // The mark alone names the plaque: no label is engraved beside it.
                Spacer(minLength: 0)
                CutYearAwardMark(highlight: highlight)
                    .frame(width: 66, height: 42)
            }
            // Clear of the cut corner.
            .padding(.leading, 40)

            Text(content.yearText)
                .font(DS.Cut.Typography.condensed(size: 132, monospacedDigits: true))
                .tracking(-2)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.vertical, Self.tightening(size: 132, lineHeight: 0.86))
                .foregroundStyle(CutYearAwardMetal.ink)
                .shadow(color: .black.opacity(0.55), radius: 0, x: -highlight.width, y: -highlight.height)
                .shadow(color: Color.white.opacity(0.7), radius: 0, x: highlight.width * 2, y: highlight.height * 2)
                .padding(.top, 18)

            VStack(alignment: .leading, spacing: Self.lineGap(size: 27, lineHeight: 0.98)) {
                ForEach(Array(content.headlineLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(DS.Cut.Typography.condensed(size: 27, relativeTo: .title2))
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .engraved(highlight)
            .padding(.top, 10)

            if !content.rows.isEmpty {
                VStack(spacing: 0) {
                    groove
                    ForEach(Array(content.rows.enumerated()), id: \.element.id) { index, row in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(row.value)
                                .font(DS.Cut.Typography.condensed(size: 26, relativeTo: .title2, monospacedDigits: true))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .layoutPriority(1)
                                .engraved(highlight)
                            Spacer(minLength: 0)
                            // Wraps rather than shrinking below 15 pt or truncating.
                            Text(row.label)
                                .font(DS.Typography.custom(size: 15, weight: .bold, relativeTo: .subheadline))
                                .multilineTextAlignment(.trailing)
                                .lineLimit(2)
                                .engraved(highlight, ink: CutYearAwardMetal.secondaryInk)
                        }
                        .padding(.vertical, 8)
                        if index < content.rows.count - 1 { groove }
                    }
                }
                .padding(.top, 16)
            }

            Spacer(minLength: 8)

            Text(content.footer)
                .font(DS.Typography.custom(size: 15, weight: .bold, relativeTo: .subheadline))
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .engraved(highlight, ink: CutYearAwardMetal.secondaryInk)
        }
        .padding(EdgeInsets(top: 24, leading: 22, bottom: 20, trailing: 22))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// An engraved hairline: a dark cut with a light edge under it.
    private var groove: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.black.opacity(0.32)).frame(height: 1)
            Rectangle().fill(Color.white.opacity(0.55)).frame(height: 1)
        }
        .accessibilityHidden(true)
    }

    /// Negative vertical padding that sets one line of Barlow at the mock's CSS line height.
    private static func tightening(size: CGFloat, lineHeight: CGFloat) -> CGFloat {
        min(0, (lineHeight - DS.Cut.Typography.naturalLineHeight) * size / 2)
    }

    private static func lineGap(size: CGFloat, lineHeight: CGFloat) -> CGFloat {
        (lineHeight - DS.Cut.Typography.naturalLineHeight) * size
    }
}

// MARK: - Motion

/// Device tilt for the plaque, from CoreMotion device motion (no permission prompt).
/// Relative to how the phone was held when updates started, low pass filtered and clamped.
/// Runs only between `start()` and `stop()`; the screen stops it when it leaves or the app
/// is not active.
@MainActor
@Observable
final class CutYearAwardMotion {
    private(set) var tilt: CutYearAwardTilt = .zero

    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private var baseline: (roll: Double, pitch: Double)?
    @ObservationIgnored private var filtered: CutYearAwardTilt = .zero

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        baseline = nil
        filtered = .zero
        manager.deviceMotionUpdateInterval = 1.0 / 60
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let attitude = motion?.attitude else { return }
            let roll = attitude.roll
            let pitch = attitude.pitch
            MainActor.assumeIsolated { self?.receive(roll: roll, pitch: pitch) }
        }
    }

    func stop() {
        if manager.isDeviceMotionActive { manager.stopDeviceMotionUpdates() }
        baseline = nil
        filtered = .zero
        if tilt != .zero { tilt = .zero }
    }

    private func receive(roll: Double, pitch: Double) {
        let base = baseline ?? (roll, pitch)
        baseline = base
        let sample = CutYearAwardLight.motionTilt(roll: roll, pitch: pitch,
                                                  baselineRoll: base.roll, baselinePitch: base.pitch)
        filtered = CutYearAwardLight.smoothed(filtered, toward: sample)
        // Skip changes too small to see, so a phone lying still does not redraw the plaque.
        if abs(filtered.yaw - tilt.yaw) > 0.05 || abs(filtered.lean - tilt.lean) > 0.05 {
            tilt = filtered
        }
    }
}

// MARK: - Live plaque

/// The plaque in one pose: turned in 3D, the light and the highlight placed for it.
struct CutYearAwardPosedPlaque: View {
    let content: CutYearAwardContent
    let pose: CutYearAwardPose

    var body: some View {
        CutYearAwardPlaque(content: content, band: pose.band, highlight: pose.highlight)
            .animation(.easeOut(duration: 0.2), value: pose.highlight)
            // In SwiftUI a positive angle sends the right edge (y axis) or the top edge (x axis)
            // away, matching the pose's yaw and lean. The rest pose matches the mock's CSS
            // rotateY(-9deg) rotateX(4deg): right edge and bottom nearer.
            .rotation3DEffect(.degrees(pose.lean), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
            .rotation3DEffect(.degrees(pose.yaw), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
    }
}

/// The plaque on screen: turned by tilt and drag, the light following. Only this view reads
/// the motion, so a motion sample redraws the band and the transform, nothing else.
private struct CutYearAwardLivePlaque: View {
    let content: CutYearAwardContent
    let motion: CutYearAwardMotion
    let reduceMotion: Bool
    var fixedTilt: CutYearAwardTilt?

    @State private var drag: CutYearAwardTilt = .zero

    var body: some View {
        let pose = reduceMotion
            ? CutYearAwardLight.staticPose
            : CutYearAwardLight.pose(tilt: (fixedTilt ?? motion.tilt) + drag)
        CutYearAwardPosedPlaque(content: content, pose: pose)
            .contentShape(Rectangle())
            .gesture(dragGesture, isEnabled: !reduceMotion)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in drag = CutYearAwardLight.dragTilt(translation: value.translation) }
            .onEnded { _ in
                withAnimation(.spring(response: 0.55, dampingFraction: 0.6)) { drag = .zero }
            }
    }
}

// MARK: - Screen

/// The last card of the year in review: the plaque, Share to Social and the system share.
struct CutYearAwardStep: View {
    let stats: CutYearReviewStats
    let unit: WeightUnit
    let cards: [CutYearReviewCard]
    let done: () -> Void

    @Environment(\.dependencies) private var deps
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var motion = CutYearAwardMotion()
    @State private var image: UIImage?
    @State private var landed = false
    @State private var canPost = false
    @State private var composing = false
    @State private var postWorkout: CompletedWorkout?
    /// Debug builds can show the RealityKit object instead of the SwiftUI plaque.
    @State private var usesObject = CutYearAwardRendering.usesObject()
    @State private var objectFailed = false
    /// Whether `image` is the 3D object's still rather than the SwiftUI plaque's picture.
    @State private var imageIsObject = false

    /// Debug screenshots: a fixed tilt, no motion and no arrival.
    private static let fixedTilt: CutYearAwardTilt? = {
        #if DEBUG
        CutYearAwardRendering.fixedTilt(arguments: ProcessInfo.processInfo.arguments)
        #else
        nil
        #endif
    }()

    private var showsObject: Bool { usesObject && !objectFailed }

    private var content: CutYearAwardContent {
        CutYearAwardLogic.content(stats: stats, unit: unit, cards: cards)
    }

    var body: some View {
        let content = content
        VStack(spacing: 22) {
            header(content)
            GeometryReader { proxy in
                let fit = min(1, proxy.size.width / CutYearAwardPlaque.size.width,
                              proxy.size.height / (CutYearAwardPlaque.size.height + 12))
                if showsObject {
                    CutYearAwardObjectPlaque(content: content, motion: motion, reduceMotion: reduceMotion,
                                             active: scenePhase == .active && !composing, fit: fit,
                                             fixedTilt: Self.fixedTilt, onFailure: objectDidFail,
                                             onShareImage: { objectDidDrawShareImage($0, content: content) })
                        .frame(width: proxy.size.width, height: proxy.size.height)
                } else {
                    CutYearAwardLivePlaque(content: content, motion: motion, reduceMotion: reduceMotion,
                                           fixedTilt: Self.fixedTilt)
                        .rotation3DEffect(.degrees(landed ? 0 : 75), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                        .offset(y: landed ? 0 : -24)
                        .opacity(landed ? 1 : 0)
                        .scaleEffect(fit)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
            actions(content)
        }
        .padding(.top, 16)
        .padding(.bottom, 8)
        .frame(maxHeight: .infinity)
        .onAppear(perform: arrive)
        .onDisappear { motion.stop() }
        .onChange(of: scenePhase) { updateMotion() }
        .onChange(of: composing) { updateMotion() }
        .onChange(of: reduceMotion) { updateMotion() }
        .task { prepare(content) }
        .sheet(isPresented: $composing) {
            if let image {
                PostCreationView(attachedImage: image,
                                 caption: imageIsObject ? content.objectShareCaption : content.shareTitle,
                                 workout: postWorkout, title: "Share Award")
                    .environment(\.dependencies, deps)
            }
        }
    }

    private func header(_ content: CutYearAwardContent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(content.title)
                .cutHero(.xs)
                .accessibilityAddTraits(.isHeader)
            Text(reduceMotion ? "Yours to keep, engraved in steel." : "Tilt your phone to catch the light.")
                .font(DS.Typography.custom(size: 16, weight: .medium, relativeTo: .callout))
                .foregroundStyle(DS.Cut.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(DS.Cut.Colors.textPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func actions(_ content: CutYearAwardContent) -> some View {
        VStack(spacing: 4) {
            if canPost {
                Button("Share to Social") { composing = true }
                    .buttonStyle(CutActionPillButtonStyle())
                    .disabled(image == nil)
                HStack(spacing: 0) {
                    systemShare(content) { Text("Share image") }
                        .font(DS.Cut.Typography.font(.buttonCompact))
                        .foregroundStyle(DS.Cut.Colors.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                    doneButton
                        .frame(maxWidth: .infinity)
                }
            } else {
                systemShare(content) { Text("Share your award") }
                    .buttonStyle(CutActionPillButtonStyle())
                doneButton
            }
        }
    }

    @ViewBuilder
    private func systemShare<Label: View>(_ content: CutYearAwardContent, @ViewBuilder label: () -> Label) -> some View {
        if let image {
            let picture = Image(uiImage: image)
            ShareLink(item: picture, preview: SharePreview(content.shareTitle, image: picture), label: label)
        } else {
            Button(action: {}, label: label).disabled(true)
        }
    }

    private var doneButton: some View {
        Button("Done", action: done)
            .font(DS.Cut.Typography.font(.buttonCompact))
            .foregroundStyle(DS.Cut.Colors.textPrimary)
            .frame(minWidth: 88, minHeight: 48)
    }

    /// The plaque arrives once, turning in from the side, with one tap as it lands.
    private func arrive() {
        updateMotion()
        // The object turns itself in once it is ready.
        guard !landed, !showsObject else { return }
        guard !reduceMotion, Self.fixedTilt == nil else {
            landed = true
            return
        }
        withAnimation(.spring(response: 0.8, dampingFraction: 0.8).delay(0.1)) { landed = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { Haptics.rigid() }
    }

    /// The object could not be built: the SwiftUI plaque takes its place and arrives as usual.
    private func objectDidFail() {
        objectFailed = true
        imageIsObject = false
        image = Self.renderShareImage(content)
        arrive()
    }

    /// The object's still arrived: it is what gets shared. Without one, the SwiftUI picture.
    private func objectDidDrawShareImage(_ still: UIImage?, content: CutYearAwardContent) {
        imageIsObject = still != nil
        image = still ?? Self.renderShareImage(content)
    }

    private func updateMotion() {
        if !reduceMotion, scenePhase == .active, !composing, Self.fixedTilt == nil {
            motion.start()
        } else {
            motion.stop()
        }
    }

    /// Renders the shared picture and checks whether a Social post is possible.
    private func prepare(_ content: CutYearAwardContent) {
        // The 3D object hands over its own picture once it has landed.
        if !showsObject { image = Self.renderShareImage(content) }
        canPost = deps.authService.currentUser != nil
        postWorkout = CutYearAwardLogic.socialWorkout(year: stats.year, workouts: deps.workoutStore.completedWorkouts,
                                                      runs: deps.workoutStore.runs)
    }

    /// The plaque flat and front on, on black so the cut corner survives apps that flatten
    /// transparency, with the light in a fixed spot. Rendered at 3x for a sharp picture.
    static func renderShareImage(_ content: CutYearAwardContent) -> UIImage? {
        let pose = CutYearAwardLight.exportPose
        let picture = CutYearAwardPlaque(content: content, band: pose.band, highlight: pose.highlight)
            .padding(40)
            .background(Color.black)
        let renderer = ImageRenderer(content: picture)
        renderer.scale = 3
        return renderer.uiImage
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Year award") {
    let stats = CutYearReviewStats.sample(year: 2026)
    CutYearAwardStep(stats: stats, unit: .kg, cards: CutYearReviewLogic.cards(for: stats)) {}
        .padding(.horizontal, 24)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
}
#endif
