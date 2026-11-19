//
//  CutYearAwardModel.swift
//  WRKT
//
//  The year award: the steel plaque that ends the year in review. What is engraved on it,
//  built from the year's stats, and how device tilt turns into the plaque's pose and the
//  light band on its face. Pure values only: the view and the motion source live in
//  CutYearAwardView.swift.
//

import CoreGraphics
import simd
import Foundation

// MARK: - Content

/// Everything engraved on the plaque, from the same stats and cards as the rest of the review.
struct CutYearAwardContent: Equatable {
    struct Row: Equatable, Identifiable {
        let id: String
        /// The big engraved value: "430,000 kg".
        let value: String
        /// The few words beside it: "one giant wheel".
        let label: String
    }

    let year: Int
    /// The claim on two balanced lines, without the closing full stop.
    let headlineLines: [String]
    let rows: [Row]
    /// "142 workouts, 23 records".
    let footer: String

    /// Spoken by VoiceOver in place of the etched mark. Not drawn on the plaque.
    static let engraving = "Volia, year award"
    /// The plaque has room for three rows under the headline.
    static let maxRows = 3

    var yearText: String { String(year) }
    /// The screen title above the plaque.
    var title: String { "Your \(yearText) award" }
    /// The share sheet title and the prefilled Social caption.
    var shareTitle: String { "My \(yearText) in Volia" }

    /// One phrase for VoiceOver: the plaque is read as a whole.
    var accessibilityText: String {
        var parts = [Self.engraving, yearText, headlineLines.joined(separator: " ")]
        parts += rows.map { "\($0.value), \($0.label)" }
        parts.append(footer)
        return parts.joined(separator: ". ")
    }
}

enum CutYearAwardLogic {
    /// The plaque's content. The headline is the first card's share line, as the old share card
    /// had it; the rows are the same cards, at most three.
    static func content(stats: CutYearReviewStats, unit: WeightUnit,
                        cards: [CutYearReviewCard]) -> CutYearAwardContent {
        let claim: String
        if let first = cards.first {
            claim = CutYearReviewLogic.comparison(first, stats: stats, unit: unit).shareLine
        } else {
            claim = stats.hasAnything ? "I trained all year." : "Ready for next year."
        }
        let rows = rowCards(cards).map { card in
            CutYearAwardContent.Row(
                id: card.id,
                value: CutYearReviewLogic.valueText(card, stats: stats, unit: unit),
                label: CutYearReviewLogic.comparison(card, stats: stats, unit: unit).short)
        }
        return CutYearAwardContent(
            year: stats.year,
            headlineLines: CutHeroText.lines(of: CutHeroText.balancedLines(engraved(claim))),
            rows: rows,
            footer: CutYearReviewLogic.footer(stats: stats))
    }

    /// The cards that get a row. With all four, time gives way: hours are the least telling
    /// number next to the weight, the distance and the streak.
    static func rowCards(_ cards: [CutYearReviewCard]) -> [CutYearReviewCard] {
        guard cards.count > CutYearAwardContent.maxRows else { return cards }
        let kept = cards.filter { $0 != .time }
        return Array(kept.prefix(CutYearAwardContent.maxRows))
    }

    /// An engraving carries no closing full stop.
    static func engraved(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespaces)
        while text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// The workout a Social post of the award is attached to: the year's most recent one.
    /// A feed post always carries a workout, so the award rides on the last one; the user can
    /// change it before posting. Runs already attached to a logged workout are not counted twice.
    static func socialWorkout(year: Int, workouts: [CompletedWorkout], runs: [Run],
                              calendar: Calendar = .current) -> CompletedWorkout? {
        guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else { return nil }
        let range = start..<end
        let matched = Set(workouts.compactMap(\.matchedHealthKitUUID))
        let logged = workouts.filter { range.contains($0.date) }
        let outings = runs
            .filter { range.contains($0.date) && !($0.healthKitUUID.map(matched.contains) ?? false) }
            .map { $0.toCompletedWorkout() }
        return (logged + outings).max { $0.date < $1.date }
    }
}

// MARK: - Light and pose

/// How far the plaque is turned, in degrees. Positive `yaw` sends the right edge away from
/// the viewer, positive `lean` sends the top edge away.
struct CutYearAwardTilt: Equatable {
    var yaw: Double
    var lean: Double

    static let zero = CutYearAwardTilt(yaw: 0, lean: 0)

    static func + (lhs: CutYearAwardTilt, rhs: CutYearAwardTilt) -> CutYearAwardTilt {
        CutYearAwardTilt(yaw: lhs.yaw + rhs.yaw, lean: lhs.lean + rhs.lean)
    }
}

/// What the plaque shows for one tilt: its rotation, where the light band crosses the face
/// and which side the engraved highlight sits on.
struct CutYearAwardPose: Equatable {
    var yaw: Double
    var lean: Double
    /// Centre of the light band along the face's diagonal: 0 the top leading corner, 1 the
    /// bottom trailing one. It may run a little past either end, off the face.
    var band: Double
    /// Offset of the light lip under engraved text and the etched mark, in points.
    var highlight: CGSize
}

enum CutYearAwardLight {
    /// No angle on the plaque goes past this, in degrees.
    static let maxAngle: Double = 14
    /// The resting pose from the approved mock: turned a little to the left and tipped back.
    static let restYaw: Double = -9
    static let restLean: Double = 4
    /// Where the light band rests on the face.
    static let restBand: Double = 0.42
    /// How far the band travels per degree of turn.
    static let bandPerDegree: Double = 0.03
    static let bandRange: ClosedRange<Double> = -0.25...1.25
    /// The phone turns this much more than the plaque does.
    static let motionGain: Double = 0.6
    /// Points of drag per degree of turn.
    static let dragPointsPerDegree: Double = 6
    /// Weight of a new motion sample in the low pass filter.
    static let smoothing: Double = 0.15
    /// Past this turn the engraved highlight moves to the other side.
    static let highlightSwitch: Double = 5

    /// Clamps an angle to the plaque's range. NaN reads as level.
    static func clamp(_ degrees: Double, limit: Double = maxAngle) -> Double {
        guard degrees.isFinite else { return degrees.isNaN ? 0 : (degrees > 0 ? limit : -limit) }
        return min(max(degrees, -limit), limit)
    }

    static func clamp(_ tilt: CutYearAwardTilt) -> CutYearAwardTilt {
        CutYearAwardTilt(yaw: clamp(tilt.yaw), lean: clamp(tilt.lean))
    }

    /// The pose for a tilt. Reduce Motion always gets the static pose.
    static func pose(tilt: CutYearAwardTilt, reduceMotion: Bool = false) -> CutYearAwardPose {
        guard !reduceMotion else { return staticPose }
        let turn = clamp(tilt)
        let yaw = turned(rest: restYaw, by: turn.yaw)
        let lean = turned(rest: restLean, by: turn.lean)
        let travel = (turn.yaw + turn.lean * 0.6) * bandPerDegree
        let band = min(max(restBand + travel, bandRange.lowerBound), bandRange.upperBound)
        return CutYearAwardPose(yaw: yaw, lean: lean, band: band, highlight: highlight(for: turn))
    }

    /// The resting angle gives way as the turn grows, so the plaque reaches the full angle
    /// either way: rest at no turn, plus or minus `maxAngle` at a full turn, monotonic between.
    static func turned(rest: Double, by turn: Double) -> Double {
        let share = min(abs(turn) / maxAngle, 1)
        return clamp(rest * (1 - share) + turn)
    }

    /// The highlight sits under the engraving and leans away from the light. It only changes
    /// side past a threshold, so the engraved layers are not redrawn for every motion sample.
    static func highlight(for tilt: CutYearAwardTilt) -> CGSize {
        let dx: CGFloat = tilt.yaw > highlightSwitch ? -0.6 : tilt.yaw < -highlightSwitch ? 0.6 : 0
        let dy: CGFloat = tilt.lean < -highlightSwitch * 1.6 ? -1 : 1
        return CGSize(width: dx, height: dy)
    }

    /// Reduce Motion: the mock's resting pose with a fixed highlight.
    static let staticPose = CutYearAwardPose(yaw: restYaw, lean: restLean, band: restBand,
                                             highlight: CGSize(width: 0, height: 1))

    /// The 3D object's shared picture: a little less turned than at rest, so the face reads
    /// square on while the band and the chamfer still show it is steel.
    static let sharePose = CutYearAwardPose(yaw: -7, lean: 3, band: restBand, highlight: CGSize(width: 0, height: 1))

    /// The shared picture: flat and front on, the band in a fixed spot across the year.
    static let exportPose = CutYearAwardPose(yaw: 0, lean: 0, band: 0.36,
                                             highlight: CGSize(width: 0, height: 1))

    /// A drag on the plaque as a tilt: dragging right sends the right edge away, dragging down
    /// brings the top edge forward, as if spinning the plaque by its face.
    static func dragTilt(translation: CGSize) -> CutYearAwardTilt {
        clamp(CutYearAwardTilt(yaw: translation.width / dragPointsPerDegree,
                               lean: -translation.height / dragPointsPerDegree))
    }

    /// Device attitude relative to how the phone was held when the plaque appeared, in
    /// radians, as a tilt. Roll turns the right edge away; pitching the top towards you
    /// (positive pitch) brings the plaque's top forward.
    static func motionTilt(roll: Double, pitch: Double, baselineRoll: Double, baselinePitch: Double) -> CutYearAwardTilt {
        let degrees = 180 / Double.pi
        return clamp(CutYearAwardTilt(yaw: (roll - baselineRoll) * degrees * motionGain,
                                      lean: -(pitch - baselinePitch) * degrees * motionGain))
    }

    /// One step of the low pass filter.
    static func smoothed(_ previous: CutYearAwardTilt, toward sample: CutYearAwardTilt,
                         factor: Double = smoothing) -> CutYearAwardTilt {
        CutYearAwardTilt(yaw: previous.yaw + (sample.yaw - previous.yaw) * factor,
                         lean: previous.lean + (sample.lean - previous.lean) * factor)
    }
}

// MARK: - The 3D object

/// Which award the screen shows: the layered SwiftUI plaque or the RealityKit object.
/// Release builds always show the plaque; the object is a Debug-only prototype for now.
enum CutYearAwardRendering {
    /// Bool in UserDefaults: true for the 3D object. Unset means the build's default.
    static let objectKey = "cut.yearAward.object3D"

    static func usesObject(stored: Bool?, isDebug: Bool) -> Bool {
        guard isDebug else { return false }
        return stored ?? true
    }

    /// Launch argument for screenshots: `-CutYearAwardTilt -6,3` holds the award at that tilt,
    /// with no arrival and no device motion. Read in Debug builds only.
    static let fixedTiltArgument = "-CutYearAwardTilt"

    static func fixedTilt(arguments: [String]) -> CutYearAwardTilt? {
        guard let index = arguments.firstIndex(of: fixedTiltArgument), arguments.indices.contains(index + 1) else {
            return nil
        }
        let parts = arguments[index + 1].split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2 else { return nil }
        return CutYearAwardLight.clamp(CutYearAwardTilt(yaw: parts[0], lean: parts[1]))
    }

    /// Room round the object in the shared picture, in points.
    static let sharePadding: CGFloat = 64

    static func usesObject(defaults: UserDefaults = .standard) -> Bool {
        #if DEBUG
        // `bool(forKey:)` also reads a launch argument such as `-cut.yearAward.object3D NO`.
        usesObject(stored: defaults.object(forKey: objectKey) == nil ? nil : defaults.bool(forKey: objectKey),
                   isDebug: true)
        #else
        false
        #endif
    }
}

extension CutYearAwardContent {
    /// The single quiet line under the headline on the 3D object. The year's count reads as a
    /// record of effort without turning the object into a table: the rows stay on the cards.
    var objectLine: String { footer }

    /// The prefilled Social caption when the 3D object is shared. Its picture carries only the
    /// year, the headline and the quiet line, so the stat rows ride in the caption instead,
    /// one per line, where the user can still edit them before posting.
    var objectShareCaption: String {
        ([shareTitle] + rows.map { "\($0.value), \($0.label)" }).joined(separator: "\n")
    }
}

/// A damped spring on one value, stepped per frame. Response and damping follow SwiftUI's
/// `.spring(response:dampingFraction:)`, so the 3D object moves like the SwiftUI plaque did.
struct CutYearAwardSpring: Equatable {
    struct Parameters: Equatable {
        var response: Double
        var damping: Double

        /// Following a finger or the phone: quick, no overshoot.
        static let follow = Parameters(response: 0.14, damping: 1)
        /// Letting go of a drag: the SwiftUI plaque's spring back.
        static let release = Parameters(response: 0.55, damping: 0.6)
        /// Turning in from the side when the screen opens.
        static let arrival = Parameters(response: 0.8, damping: 0.8)
    }

    var value: Double
    var velocity: Double = 0

    /// Below these the spring counts as at rest, in degrees and degrees per second.
    static let restDistance = 0.02
    static let restSpeed = 0.05

    /// Advances toward `target`. Long frames are split so a hitch cannot blow the spring up.
    mutating func step(toward target: Double, parameters: Parameters, deltaTime: Double) {
        guard deltaTime > 0, deltaTime.isFinite else { return }
        let stiffness = pow(2 * Double.pi / max(parameters.response, 0.01), 2)
        let friction = 4 * Double.pi * parameters.damping / max(parameters.response, 0.01)
        var remaining = min(deltaTime, 0.25)
        while remaining > 0 {
            let dt = min(remaining, 1.0 / 240)
            velocity += (-stiffness * (value - target) - friction * velocity) * dt
            value += velocity * dt
            remaining -= dt
        }
    }

    func isSettled(at target: Double) -> Bool {
        abs(value - target) < Self.restDistance && abs(velocity) < Self.restSpeed
    }

    mutating func settle(at target: Double) {
        value = target
        velocity = 0
    }
}

/// The object's shape in metres, one point of the SwiftUI plaque to one millimetre, so the
/// camera can frame it at the plaque's on-screen size. y points up, the origin is the centre.
enum CutYearAwardSlab {
    static let width: Float = 0.318
    static let height: Float = 0.476
    static let cut: Float = 0.052
    /// Thick enough to read as a block of steel when it turns, not a card.
    static let thickness: Float = 0.016
    /// The 45 degree chamfer round the face, and a smaller one at the back.
    static let frontChamfer: Float = 0.007
    static let backChamfer: Float = 0.002

    /// The outline counterclockwise from the bottom leading corner, the top leading corner cut.
    static var outline: [SIMD2<Float>] {
        let w = width / 2, h = height / 2
        return [SIMD2(-w, -h), SIMD2(w, -h), SIMD2(w, h), SIMD2(-w + cut, h), SIMD2(-w, h - cut)]
    }

    /// A convex counterclockwise polygon moved inward by `distance` on every edge.
    static func inset(_ polygon: [SIMD2<Float>], by distance: Float) -> [SIMD2<Float>] {
        let count = polygon.count
        guard count >= 3, distance != 0 else { return polygon }
        // Each edge as a point and a direction, shifted along its inward (left) normal.
        let lines: [(point: SIMD2<Float>, direction: SIMD2<Float>)] = (0..<count).map { index in
            let a = polygon[index], b = polygon[(index + 1) % count]
            let direction = simd_normalize(b - a)
            let inward = SIMD2(-direction.y, direction.x)
            return (a + inward * distance, direction)
        }
        return (0..<count).map { index in
            let previous = lines[(index + count - 1) % count], next = lines[index]
            // previous.point + s * previous.direction meets next.point + t * next.direction.
            let cross = previous.direction.x * next.direction.y - previous.direction.y * next.direction.x
            guard abs(cross) > 1e-6 else { return next.point }
            let delta = next.point - previous.point
            let s = (delta.x * next.direction.y - delta.y * next.direction.x) / cross
            return previous.point + previous.direction * s
        }
    }

    /// The face is flat but its normals fall away toward the edges, a few degrees, as a machined
    /// plaque's crown does. A dead flat face reflects one direction everywhere and changes all
    /// at once; the crown spreads the reflection so a band of light can cross it.
    static let crownSideAngle: Float = 8
    static let crownTopAngle: Float = 3

    static func crownNormal(at point: SIMD2<Float>) -> SIMD3<Float> {
        let x = point.x / (width / 2), y = point.y / (height / 2)
        let sx = tan(crownSideAngle * .pi / 180) * x, sy = tan(crownTopAngle * .pi / 180) * y
        return simd_normalize(SIMD3(sx, sy, 1))
    }

    /// Vertical field of view of the camera, in degrees. Narrow, like a long lens, so the
    /// object keeps its shape and the turn shows the edge rather than distorting the face.
    static let fieldOfView: Float = 24

    /// Camera distance that shows `viewHeight` points of view height as `viewHeight` mm at the
    /// object's plane, so the face at rest is drawn at the SwiftUI plaque's size.
    static func cameraDistance(viewHeight: Float, fieldOfView: Float = fieldOfView) -> Float {
        let visible = viewHeight / 1000
        return visible / 2 / tan(fieldOfView / 2 * .pi / 180)
    }
}
