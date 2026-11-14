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

    /// The small engraving next to the mark.
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
