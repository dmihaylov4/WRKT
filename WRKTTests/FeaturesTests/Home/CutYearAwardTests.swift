import CoreGraphics
import Foundation
import simd
import Testing
@testable import WRKT

/// The year award plaque: what is engraved on it and how tilt becomes its pose.
struct CutYearAwardContentTests {
    @Test func sampleYearFillsThePlaque() {
        let stats = CutYearReviewStats.sample(year: 2026)
        let cards = CutYearReviewLogic.cards(for: stats)
        let content = CutYearAwardLogic.content(stats: stats, unit: .kg, cards: cards)
        #expect(content.yearText == "2026")
        #expect(content.title == "Your 2026 award")
        #expect(content.shareTitle == "My 2026 in Volia")
        #expect(content.shareFileName == "Volia 2026 award.png")
        // The first card's share line, balanced on two lines, without its full stop.
        #expect(content.headlineLines == ["I lifted the", "Riesenrad"])
        // All four cards: time gives way, three rows in card order.
        #expect(cards == [.lifted, .distance, .time, .streak])
        #expect(content.rows.map(\.id) == ["lifted", "distance", "streak"])
        #expect(content.rows[0].value == CutYearReviewLogic.liftedText(kg: 430_000, unit: .kg))
        #expect(content.rows[0].label == "one giant wheel")
        #expect(content.rows[1].value == CutYearReviewLogic.distanceText(km: 486))
        #expect(content.rows[1].label == "11.5 marathons")
        #expect(content.rows[2].value == "9 weeks")
        #expect(content.rows[2].label == "longest streak")
        #expect(content.footer == "142 workouts, 23 records")
    }

    @Test func headlineMatchesTheShareLine() {
        var stats = CutYearReviewStats(year: 2026, workouts: 40)
        stats.liftedKg = 410_000
        let content = CutYearAwardLogic.content(stats: stats, unit: .kg, cards: CutYearReviewLogic.cards(for: stats))
        let shareLine = CutYearReviewLogic.lifted(kg: 410_000, unit: .kg).shareLine
        #expect(content.headlineLines.joined(separator: " ") + "." == shareLine)
        #expect(content.headlineLines.count == 2)
    }

    @Test func threeCardsOrFewerKeepEveryRow() {
        #expect(CutYearAwardLogic.rowCards([.lifted, .time, .streak]) == [.lifted, .time, .streak])
        #expect(CutYearAwardLogic.rowCards([.time]) == [.time])
        #expect(CutYearAwardLogic.rowCards([]).isEmpty)
        #expect(CutYearAwardLogic.rowCards(CutYearReviewCard.allCases) == [.lifted, .distance, .streak])
    }

    @Test func sparseYearStillReads() {
        let thin = CutYearReviewStats(year: 2026, workouts: 3)
        let content = CutYearAwardLogic.content(stats: thin, unit: .kg, cards: CutYearReviewLogic.cards(for: thin))
        #expect(content.rows.isEmpty)
        #expect(content.headlineLines == ["I trained", "all year"])
        #expect(content.footer == "3 workouts")

        let empty = CutYearReviewStats(year: 2025)
        let nothing = CutYearAwardLogic.content(stats: empty, unit: .lb, cards: [])
        #expect(nothing.yearText == "2025")
        #expect(nothing.rows.isEmpty)
        #expect(nothing.headlineLines == ["Ready for", "next year"])
        #expect(nothing.footer == "0 workouts")
    }

    @Test func poundsFollowTheUnit() {
        var stats = CutYearReviewStats(year: 2026, workouts: 10)
        stats.liftedKg = 25_000
        let content = CutYearAwardLogic.content(stats: stats, unit: .lb, cards: CutYearReviewLogic.cards(for: stats))
        #expect(content.rows.first?.value.hasSuffix(" lb") == true)
    }

    @Test func engravingDropsTheFullStop() {
        #expect(CutYearAwardLogic.engraved("I trained 9 weeks in a row.") == "I trained 9 weeks in a row")
        #expect(CutYearAwardLogic.engraved("No stop") == "No stop")
    }

    @Test func accessibilityReadsEverything() {
        let stats = CutYearReviewStats.sample(year: 2026)
        let content = CutYearAwardLogic.content(stats: stats, unit: .kg, cards: CutYearReviewLogic.cards(for: stats))
        #expect(content.accessibilityText.hasPrefix("Volia, year award. 2026. I lifted the Riesenrad."))
        #expect(content.accessibilityText.hasSuffix("142 workouts, 23 records"))
    }

    @Test func socialPostRidesOnTheYearsLastWorkout() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Vienna")!
        func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
        }
        let march = CompletedWorkout(date: day(2026, 3, 2), entries: [])
        let nextYear = CompletedWorkout(date: day(2027, 1, 3), entries: [])
        let june = Run(date: day(2026, 6, 1), distanceKm: 10, durationSec: 3000)
        let picked = CutYearAwardLogic.socialWorkout(year: 2026, workouts: [march, nextYear], runs: [june],
                                                     calendar: calendar)
        #expect(picked?.date == june.date)
        #expect(CutYearAwardLogic.socialWorkout(year: 2026, workouts: [nextYear], runs: [], calendar: calendar) == nil)
        #expect(CutYearAwardLogic.socialWorkout(year: 2026, workouts: [march], runs: [], calendar: calendar)?.id == march.id)
    }
}

struct CutYearAwardLightTests {
    @Test func levelPhoneRestsInTheMockPose() {
        let pose = CutYearAwardLight.pose(tilt: .zero)
        #expect(pose.yaw == CutYearAwardLight.restYaw)
        #expect(pose.lean == CutYearAwardLight.restLean)
        #expect(pose.band == CutYearAwardLight.restBand)
        #expect(pose.highlight == CGSize(width: 0, height: 1))
    }

    @Test func tiltTurnsThePlaqueAndMovesTheLight() {
        let right = CutYearAwardLight.pose(tilt: CutYearAwardTilt(yaw: 4, lean: 0))
        #expect(right.yaw > CutYearAwardLight.restYaw)
        #expect(right.band > CutYearAwardLight.restBand)
        let left = CutYearAwardLight.pose(tilt: CutYearAwardTilt(yaw: -4, lean: 0))
        #expect(left.band < CutYearAwardLight.restBand)
        let back = CutYearAwardLight.pose(tilt: CutYearAwardTilt(yaw: 0, lean: 6))
        #expect(back.lean > CutYearAwardLight.restLean)
        #expect(back.band > CutYearAwardLight.restBand)
    }

    @Test func anglesAreClamped() {
        let limit = CutYearAwardLight.maxAngle
        let far = CutYearAwardLight.pose(tilt: CutYearAwardTilt(yaw: 200, lean: -200))
        #expect(far.yaw == limit)
        #expect(far.lean == -limit)
        let farOther = CutYearAwardLight.pose(tilt: CutYearAwardTilt(yaw: -200, lean: 200))
        #expect(farOther.yaw == -limit)
        #expect(farOther.lean == limit)
        #expect(CutYearAwardLight.bandRange.contains(far.band))
        #expect(CutYearAwardLight.bandRange.contains(farOther.band))
        #expect(CutYearAwardLight.clamp(.nan) == 0)
        #expect(CutYearAwardLight.clamp(.infinity) == limit)
        #expect(CutYearAwardLight.clamp(-.infinity) == -limit)
        #expect(CutYearAwardLight.clamp(3) == 3)
        // A huge input moves the band no further than the clamped one.
        let edge = CutYearAwardLight.pose(tilt: CutYearAwardTilt(yaw: limit, lean: 0))
        let beyond = CutYearAwardLight.pose(tilt: CutYearAwardTilt(yaw: limit * 5, lean: 0))
        #expect(edge.band == beyond.band)
    }

    @Test func restGivesWaySoBothDirectionsReachTheLimit() {
        let limit = CutYearAwardLight.maxAngle
        #expect(CutYearAwardLight.turned(rest: -9, by: 0) == -9)
        #expect(CutYearAwardLight.turned(rest: -9, by: limit) == limit)
        #expect(CutYearAwardLight.turned(rest: -9, by: -limit) == -limit)
        // Monotonic: more turn never turns the plaque back.
        var previous = -Double.infinity
        for step in stride(from: -limit, through: limit, by: 0.5) {
            let yaw = CutYearAwardLight.turned(rest: -9, by: step)
            #expect(yaw >= previous)
            previous = yaw
        }
    }

    @Test func reduceMotionIsStatic() {
        let tilted = CutYearAwardLight.pose(tilt: CutYearAwardTilt(yaw: 12, lean: -9), reduceMotion: true)
        #expect(tilted == CutYearAwardLight.staticPose)
        #expect(CutYearAwardLight.pose(tilt: .zero, reduceMotion: true) == CutYearAwardLight.staticPose)
    }

    @Test func exportIsFlatAndFrontOn() {
        let pose = CutYearAwardLight.exportPose
        #expect(pose.yaw == 0)
        #expect(pose.lean == 0)
        #expect((0...1).contains(pose.band))
    }

    @Test func highlightSwitchesSidePastAThreshold() {
        #expect(CutYearAwardLight.highlight(for: CutYearAwardTilt(yaw: 3, lean: 0)) == CGSize(width: 0, height: 1))
        #expect(CutYearAwardLight.highlight(for: CutYearAwardTilt(yaw: 8, lean: 0)).width < 0)
        #expect(CutYearAwardLight.highlight(for: CutYearAwardTilt(yaw: -8, lean: 0)).width > 0)
        #expect(CutYearAwardLight.highlight(for: CutYearAwardTilt(yaw: 0, lean: -12)).height == -1)
    }

    @Test func dragTiltsAndIsClamped() {
        let drag = CutYearAwardLight.dragTilt(translation: CGSize(width: 30, height: -12))
        #expect(drag.yaw == 30 / CutYearAwardLight.dragPointsPerDegree)
        #expect(drag.lean == 12 / CutYearAwardLight.dragPointsPerDegree)
        let fling = CutYearAwardLight.dragTilt(translation: CGSize(width: 900, height: 900))
        #expect(fling == CutYearAwardTilt(yaw: CutYearAwardLight.maxAngle, lean: -CutYearAwardLight.maxAngle))
    }

    @Test func motionIsRelativeToTheStartAndClamped() {
        let still = CutYearAwardLight.motionTilt(roll: 0.3, pitch: 0.8, baselineRoll: 0.3, baselinePitch: 0.8)
        #expect(still == .zero)
        let turned = CutYearAwardLight.motionTilt(roll: 0.3 + .pi / 18, pitch: 0.8, baselineRoll: 0.3, baselinePitch: 0.8)
        #expect(abs(turned.yaw - 10 * CutYearAwardLight.motionGain) < 0.0001)
        let wild = CutYearAwardLight.motionTilt(roll: 3, pitch: -3, baselineRoll: 0, baselinePitch: 0)
        #expect(wild == CutYearAwardTilt(yaw: CutYearAwardLight.maxAngle, lean: CutYearAwardLight.maxAngle))
    }

    @Test func lowPassMovesPartWay() {
        let step = CutYearAwardLight.smoothed(.zero, toward: CutYearAwardTilt(yaw: 10, lean: -10), factor: 0.25)
        #expect(step == CutYearAwardTilt(yaw: 2.5, lean: -2.5))
        var value = CutYearAwardTilt.zero
        for _ in 0..<200 { value = CutYearAwardLight.smoothed(value, toward: CutYearAwardTilt(yaw: 6, lean: 2)) }
        #expect(abs(value.yaw - 6) < 0.001)
        #expect(abs(value.lean - 2) < 0.001)
    }
}

/// The 3D award object: which award shows, what is cut into it, how it moves and its shape.
struct CutYearAwardObjectTests {
    @Test func releaseBuildsNeverShowTheObject() {
        #expect(!CutYearAwardRendering.usesObject(stored: nil, isDebug: false))
        #expect(!CutYearAwardRendering.usesObject(stored: true, isDebug: false))
    }

    @Test func debugBuildsDefaultToTheObjectAndFollowTheSwitch() {
        #expect(CutYearAwardRendering.usesObject(stored: nil, isDebug: true))
        #expect(CutYearAwardRendering.usesObject(stored: true, isDebug: true))
        #expect(!CutYearAwardRendering.usesObject(stored: false, isDebug: true))
    }

    @Test func storedChoiceIsReadFromDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: "CutYearAwardObjectTests"))
        defaults.removePersistentDomain(forName: "CutYearAwardObjectTests")
        #if DEBUG
        #expect(CutYearAwardRendering.usesObject(defaults: defaults))
        defaults.set(false, forKey: CutYearAwardRendering.objectKey)
        #expect(!CutYearAwardRendering.usesObject(defaults: defaults))
        // A launch argument arrives as a string.
        defaults.set("YES", forKey: CutYearAwardRendering.objectKey)
        #expect(CutYearAwardRendering.usesObject(defaults: defaults))
        #else
        #expect(!CutYearAwardRendering.usesObject(defaults: defaults))
        #endif
        defaults.removePersistentDomain(forName: "CutYearAwardObjectTests")
    }

    @Test func objectCarriesOneQuietLine() {
        let stats = CutYearReviewStats.sample(year: 2026)
        let content = CutYearAwardLogic.content(stats: stats, unit: .kg, cards: CutYearReviewLogic.cards(for: stats))
        #expect(content.objectLine == "142 workouts, 23 records")
        #expect(content.objectLine == content.footer)
        // VoiceOver keeps reading the whole award, rows included.
        #expect(content.accessibilityText.contains("one giant wheel"))
    }

    @Test func sharedObjectCarriesTheRowsInItsCaption() {
        let stats = CutYearReviewStats.sample(year: 2026)
        let content = CutYearAwardLogic.content(stats: stats, unit: .kg, cards: CutYearReviewLogic.cards(for: stats))
        let lines = content.objectShareCaption.components(separatedBy: "\n")
        #expect(lines.first == content.shareTitle)
        #expect(lines.count == 1 + content.rows.count)
        // Numbers only: the comparisons ("one giant wheel") stay out of the caption.
        #expect(lines[1] == content.rows[0].value)
        #expect(lines[3] == "9 weeks")
        #expect(!content.objectShareCaption.contains("giant wheel"))
    }

    @Test func sharedObjectWithoutRowsIsJustTheTitle() {
        let content = CutYearAwardContent(year: 2026, headlineLines: ["Ready for", "next year"], rows: [],
                                          footer: "0 workouts")
        #expect(content.objectShareCaption == "My 2026 in Volia")
    }

    @Test func sharePoseIsCalmerThanRestAndWithinTheLimits() {
        let share = CutYearAwardLight.sharePose, rest = CutYearAwardLight.staticPose
        #expect(abs(share.yaw) <= abs(rest.yaw))
        #expect(abs(share.lean) <= abs(rest.lean))
        #expect(share.yaw != 0)
        #expect(abs(share.yaw) <= CutYearAwardLight.maxAngle)
        #expect(CutYearAwardRendering.sharePadding > 0)
    }

    @Test func fixedTiltIsParsedAndClamped() {
        #expect(CutYearAwardRendering.fixedTilt(arguments: ["app"]) == nil)
        #expect(CutYearAwardRendering.fixedTilt(arguments: ["-CutYearAwardTilt"]) == nil)
        #expect(CutYearAwardRendering.fixedTilt(arguments: ["-CutYearAwardTilt", "nope"]) == nil)
        #expect(CutYearAwardRendering.fixedTilt(arguments: ["-CutYearAwardTilt", "-6, 3"])
                == CutYearAwardTilt(yaw: -6, lean: 3))
        #expect(CutYearAwardRendering.fixedTilt(arguments: ["-CutYearAwardTilt", "40,-40"])
                == CutYearAwardTilt(yaw: CutYearAwardLight.maxAngle, lean: -CutYearAwardLight.maxAngle))
    }

    @Test func springReachesItsTargetAndSettles() {
        var spring = CutYearAwardSpring(value: 75)
        for _ in 0..<120 { spring.step(toward: 0, parameters: .arrival, deltaTime: 1.0 / 60) }
        #expect(spring.isSettled(at: 0))
        #expect(!CutYearAwardSpring(value: 1).isSettled(at: 0))
    }

    @Test func releaseSpringOvershootsLikeTheSwiftUISpringBack() {
        var spring = CutYearAwardSpring(value: 10)
        var lowest = spring.value
        for _ in 0..<120 {
            spring.step(toward: 0, parameters: .release, deltaTime: 1.0 / 60)
            lowest = min(lowest, spring.value)
        }
        #expect(lowest < -0.5)
        var follow = CutYearAwardSpring(value: 10)
        var followLowest = follow.value
        for _ in 0..<120 {
            follow.step(toward: 0, parameters: .follow, deltaTime: 1.0 / 60)
            followLowest = min(followLowest, follow.value)
        }
        #expect(followLowest > -0.01)
    }

    @Test func aLongFrameDoesNotBlowTheSpringUp() {
        var spring = CutYearAwardSpring(value: 14)
        spring.step(toward: 0, parameters: .follow, deltaTime: 2)
        #expect(spring.value.isFinite)
        #expect(abs(spring.value) < 14)
        var still = CutYearAwardSpring(value: 3)
        still.step(toward: 0, parameters: .follow, deltaTime: 0)
        still.step(toward: 0, parameters: .follow, deltaTime: .nan)
        #expect(still.value == 3)
    }

    @Test func outlineHasTheCutCornerAtFortyFiveDegrees() {
        let outline = CutYearAwardSlab.outline
        #expect(outline.count == 5)
        let cut = outline[3] - outline[4]
        #expect(abs(cut.x - CutYearAwardSlab.cut) < 1e-6)
        #expect(abs(cut.y - CutYearAwardSlab.cut) < 1e-6)
    }

    @Test func insetMovesEveryEdgeInByTheSameDistance() {
        let distance: Float = 0.007
        let inset = CutYearAwardSlab.inset(CutYearAwardSlab.outline, by: distance)
        let w = CutYearAwardSlab.width / 2, h = CutYearAwardSlab.height / 2
        #expect(abs(inset[0].x - (-w + distance)) < 1e-5)
        #expect(abs(inset[0].y - (-h + distance)) < 1e-5)
        #expect(abs(inset[2].x - (w - distance)) < 1e-5)
        #expect(abs(inset[2].y - (h - distance)) < 1e-5)
        // The cut stays at 45 degrees and is as far from the original cut as the other edges.
        let cut = inset[3] - inset[4]
        #expect(abs(cut.x - cut.y) < 1e-5)
        let normal = simd_normalize(SIMD2<Float>(1, -1))
        let gap = simd_dot(inset[4] - CutYearAwardSlab.outline[4], normal)
        #expect(abs(gap - distance) < 1e-5)
        #expect(CutYearAwardSlab.inset(CutYearAwardSlab.outline, by: 0) == CutYearAwardSlab.outline)
    }

    @Test func crownFallsAwayTowardTheEdges() {
        let centre = CutYearAwardSlab.crownNormal(at: .zero)
        #expect(centre == SIMD3<Float>(0, 0, 1))
        let side = CutYearAwardSlab.crownNormal(at: SIMD2(CutYearAwardSlab.width / 2, 0))
        let angle = acos(side.z) * 180 / .pi
        #expect(abs(angle - CutYearAwardSlab.crownSideAngle) < 0.01)
        #expect(CutYearAwardSlab.crownNormal(at: SIMD2(-0.1, 0)).x < 0)
        #expect(CutYearAwardSlab.crownNormal(at: SIMD2(0, 0.2)).y > 0)
    }

    @Test func cameraShowsTheViewHeightAtTheObjectPlane() {
        let distance = CutYearAwardSlab.cameraDistance(viewHeight: 476, fieldOfView: 24)
        let visible = 2 * distance * tan(12 * Float.pi / 180)
        #expect(abs(visible - 0.476) < 1e-5)
    }
}
