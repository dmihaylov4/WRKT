//
//  HomeHexPortalModel.swift
//  WRKT
//
//  The hex portal: one cell of the rack room's honeycomb in the cut corner of the Train tab's
//  field, showing a still of the owner's room, that opens the room by flying through the cell.
//  This file holds the plain values and the pure rules: the build flag, when the window shows,
//  what VoiceOver reads, where the cell sits, the geometry of the fly-through at any progress,
//  the still's cache key and refresh rule, and the transition's phases. HomeHexPortalHost feeds
//  it; HomeHexPortalView draws it.
//

import CoreGraphics
import CryptoKit
import Foundation

// MARK: - Flag

/// Ships with the new rack room (RackRoomRelease): on in Debug builds and for TestFlight testers
/// on the new design, off for App Store installs and testers who switched the new design off.
/// VOLIA_HOME_HEX_PORTAL=0 turns it off in a Debug build, =1 keeps it on; Release builds never
/// read it.
enum HomeHexPortalFlag {
    static let overrideKey = "VOLIA_HOME_HEX_PORTAL"

    /// The rule, separated from the build flag so tests can pin every case. The override is read
    /// only when `allowsOverrides` (Debug builds), and can only turn the portal off or keep it on.
    static func resolve(newRoom: Bool, allowsOverrides: Bool, environment: [String: String]) -> Bool {
        guard newRoom else { return false }
        guard allowsOverrides else { return true }
        switch environment[overrideKey]?.lowercased() {
        case "0", "off", "false", "no": return false
        default: return true
        }
    }

    /// This launch's value, resolved once.
    static let isEnabled: Bool = resolve(newRoom: RackRoomRelease.isNewRoomEnabled,
                                         allowsOverrides: RackRoomRelease.allowsLaunchOverrides,
                                         environment: RackRoomRelease.overrideEnvironment)
}

// MARK: - Window

/// What the window on Home shows and says.
struct HomeHexPortalWindowModel: Equatable {
    var isShown: Bool
    var accessibilityLabel = HomeHexPortalLogic.accessibilityLabel
    var accessibilityValue: String
    var accessibilityHint = HomeHexPortalLogic.accessibilityHint
}

/// One plate on the bar as the still's cache key needs it: everything that changes its look.
struct HomeHexStillPlate: Equatable, Sendable {
    var id: String
    var tierID: Int
    var weightKg: Double
    var engraving: String
    var rackPosition: Int?
    var progressionTier: String
    var liftTypeID: String?
}

/// Everything the room's first frame depends on: the loadout, the bar, rack and room, the plate
/// style, the scene's size on screen and the display scale.
struct HomeHexStillFacts: Equatable, Sendable {
    var plates: [HomeHexStillPlate]
    var barSkin: Int
    var rackStyle: String
    var roomTheme: String
    var wallText: String?
    var plateStyle: String
    var sceneSize: CGSize
    var displayScale: CGFloat
}

enum HomeHexPortalLogic {
    static let accessibilityLabel = "Your bar"
    static let accessibilityHint = "Opens your barbell room"
    /// Bumped whenever the still's look changes (framing, shading baked into it).
    static let stillVersion = 2

    /// The window shows in every state of the field that is not a workout in progress: planned,
    /// rest day, done today and no plan. Every state keeps the cut corner, so the window is
    /// always in the same place. During a workout (live or resting) it is hidden: the field is
    /// the workout's controls then, and the room's 3D scene would compete with the workout for
    /// the phone. The Me tab's "Your barbell" row shows for every user, plates or not, so the
    /// window does too (a brand-new user sees the empty bar).
    static func isShown(for hero: CutTrainHero, flag: Bool = HomeHexPortalFlag.isEnabled) -> Bool {
        guard flag else { return false }
        switch hero {
        case .planned, .restDay, .doneToday, .noPlan: return true
        case .live, .resting: return false
        }
    }

    /// "140 kilograms on the bar, 3 plates". The total is the room's own: the 20 kg bar plus
    /// each loaded plate on both sleeves.
    static func accessibilityValue(loadedKg: [Double], unit: WeightUnit, locale: Locale = .current) -> String {
        let total = CutRackLogic.barWeightKg + loadedKg.reduce(0, +) * 2
        let weight = CutRackLogic.spokenWeight(total, unit: unit, locale: locale)
        let plates: String
        switch loadedKg.count {
        case 0: plates = "no plates"
        case 1: plates = "1 plate"
        default: plates = "\(loadedKg.count) plates"
        }
        return "\(weight) on the bar, \(plates)"
    }

    static func window(hero: CutTrainHero, loadedKg: [Double], unit: WeightUnit, flag: Bool = HomeHexPortalFlag.isEnabled,
                       locale: Locale = .current) -> HomeHexPortalWindowModel {
        HomeHexPortalWindowModel(isShown: isShown(for: hero, flag: flag),
                                 accessibilityValue: accessibilityValue(loadedKg: loadedKg, unit: unit, locale: locale))
    }

    // MARK: Still

    /// The still's cache key: a digest of every fact, independent of plate order on the query.
    static func stillKey(_ facts: HomeHexStillFacts) -> String {
        let plates = facts.plates.sorted { ($0.rackPosition ?? .max, $0.id) < ($1.rackPosition ?? .max, $1.id) }
        var text = "v\(stillVersion)|\(facts.plateStyle)|\(facts.barSkin)|\(facts.rackStyle)|\(facts.roomTheme)|\(facts.wallText ?? "")"
        text += "|\(Int(facts.sceneSize.width.rounded()))x\(Int(facts.sceneSize.height.rounded()))@\(facts.displayScale)"
        for plate in plates {
            text += "|\(plate.id),\(plate.tierID),\(plate.weightKg.bitPattern),\(plate.engraving),"
                + "\(plate.rackPosition.map(String.init) ?? "-"),\(plate.progressionTier),\(plate.liftTypeID ?? "")"
        }
        let digest = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        return "v\(stillVersion)_" + digest.prefix(32)
    }

    /// What to do about the still.
    enum StillAction: Equatable {
        /// The cached still matches: show it.
        case show
        /// The still is missing or stale: render one now.
        case render
        /// The still is missing or stale but now is not the moment: keep what is shown and ask again.
        case wait
    }

    /// The refresh rule. A still is rendered only when it is missing or stale, and never while Home
    /// is not on screen, is scrolling, a workout is running or starting, or the room is open (the
    /// room's own frame replaces the still when it closes). Nor before the room has been drawn once
    /// in this install (`roomDrawnBefore`): the first room drawn compiles RealityKit's shaders,
    /// seconds of main-thread stalls on a fresh install, which belong to the first visit to the
    /// room (behind its loading state), not to Home. Until then the window keeps its placeholder,
    /// and the first visit's last frame becomes the still.
    static func stillAction(cachedKey: String?, currentKey: String, homeVisible: Bool, scrolling: Bool,
                            workoutBusy: Bool, portalIdle: Bool, roomDrawnBefore: Bool = true) -> StillAction {
        if cachedKey == currentKey { return .show }
        guard homeVisible, !scrolling, !workoutBusy, portalIdle, roomDrawnBefore else { return .wait }
        return .render
    }

    /// After a visit: the live scene's last frame becomes the still when the bar changed or there
    /// is no still for it yet, and the frame shows the room as it opens next time (no plates lying
    /// on the floor, none moving).
    static func capturesLiveFrameOnClose(keyAtOpen: String?, keyAtClose: String, floorPlates: Int, platesMoving: Int,
                                         stillCached: Bool = true) -> Bool {
        (keyAtOpen != keyAtClose || !stillCached) && floorPlates == 0 && platesMoving == 0
    }
}

// MARK: - Geometry

/// The cell and the fly-through. Coordinates are the cover's: its safe area's top left is the
/// origin (the rack screen lays out in the safe area), the screen's edges lie outside it.
enum HomeHexGeometry {
    /// Across the cell, corner to corner (flat-topped, like the room's honeycomb).
    static let width: CGFloat = 72
    static var radius: CGFloat { width / 2 }
    /// Flat top to flat bottom.
    static var height: CGFloat { width * 3.0.squareRoot() / 2 }
    /// The cell's centre from the field's trailing and bottom edges. The field's 112 pt cut runs
    /// from (trailing, bottom - 112) to (trailing - 112, bottom): with these the left corner
    /// touches the cut and the upper left edge crosses it by about 9 pt, as in the mock; the top
    /// stays 11 pt below the bottom of the field's buttons (their row ends 72 pt above the field's
    /// bottom), and the bottom sits 1 pt past the field's bottom edge, on the page background.
    static let centerFromTrailing: CGFloat = 46
    static let centerFromBottom: CGFloat = 30
    /// The point of the still centred in the cell: just above the bar, between it and the logo.
    static let focus = CGPoint(x: 0.5, y: 0.45)
    /// The loaded bar spans about 89% of the scene's width; at rest it spans about 82% of the
    /// cell, so the outer plates sit inside the cell's left and right corners.
    static func restScale(sceneWidth: CGFloat) -> CGFloat {
        guard sceneWidth > 0 else { return 0.2 }
        return width * 0.92 / sceneWidth
    }

    /// The cell's frame inside the field: offsets from the field's bottom trailing corner.
    static var trailingPadding: CGFloat { centerFromTrailing - radius }
    static var bottomOverhang: CGFloat { height / 2 - centerFromBottom }

    /// The six corners of a flat-topped hexagon, starting at the top left, clockwise.
    static func corners(center: CGPoint, radius: CGFloat) -> [CGPoint] {
        let k = radius * 3.0.squareRoot() / 2
        return [CGPoint(x: center.x - radius / 2, y: center.y - k), CGPoint(x: center.x + radius / 2, y: center.y - k),
                CGPoint(x: center.x + radius, y: center.y), CGPoint(x: center.x + radius / 2, y: center.y + k),
                CGPoint(x: center.x - radius / 2, y: center.y + k), CGPoint(x: center.x - radius, y: center.y)]
    }

    /// The radius at which a hexagon centred at `center` covers every corner of `bounds`.
    static func coverRadius(center: CGPoint, bounds: CGRect) -> CGFloat {
        let far = [CGPoint(x: bounds.minX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.minY),
                   CGPoint(x: bounds.minX, y: bounds.maxY), CGPoint(x: bounds.maxX, y: bounds.maxY)]
            .map { hypot($0.x - center.x, $0.y - center.y) }.max() ?? 1
        // The inscribed circle (radius times sqrt3/2) must reach the farthest corner.
        return far / (3.0.squareRoot() / 2) * 1.04
    }

    /// The room reaches its full size at this progress; after it only the cell keeps growing.
    static let roomArrives: CGFloat = 0.75
    /// The cell starts to outrun the room here (before, it frames the room as on Home).
    static let cellOutruns: CGFloat = 0.68

    /// One frame of the fly-through.
    struct Frame: Equatable {
        /// The cell's centre and radius (the mask and the tube).
        var center: CGPoint
        var radius: CGFloat
        /// The room layer's scale.
        var scale: CGFloat
        /// The room layer's transform: x -> scale * x + offset.
        var offset: CGPoint
    }

    /// At progress 0 the room layer is the still in the cell on Home; at 1 the room fills the
    /// screen exactly as the live room lays it out. Two movements, overlapping: the camera pushes
    /// in on the cell with the room framed in it exactly as on Home (geometric scale, so it reads
    /// as a constant-speed push), the room reaching its full size at `roomArrives`; from
    /// `cellOutruns` the cell's edge accelerates past the screen's corners, so you pass through it.
    /// The cell never outruns the room while the room is small: the room's scene band ends at
    /// its side walls, and a cell larger than the band would show the band's edges.
    /// `bounds` is the whole screen in the same coordinates as `source` and `scene`.
    static func frame(progress p: CGFloat, source: CGRect, scene: CGRect, bounds: CGRect) -> Frame {
        let p = min(max(p, 0), 1)
        let focusFinal = CGPoint(x: scene.minX + focus.x * scene.width, y: scene.minY + focus.y * scene.height)
        let source = source.isEmpty ? CGRect(x: focusFinal.x - radius, y: focusFinal.y - height / 2, width: width, height: height) : source
        let start = CGPoint(x: source.midX, y: source.midY)
        let s0 = restScale(sceneWidth: scene.width)
        let q = min(1, p / roomArrives)
        let scale = s0 * pow(1 / s0, q)
        let center = CGPoint(x: start.x + (focusFinal.x - start.x) * q, y: start.y + (focusFinal.y - start.y) * q)
        // The cell as framed on Home, scaled with the room, then the sweep (accelerating).
        let framed = source.width / 2 * scale / s0
        let cover = coverRadius(center: focusFinal, bounds: bounds)
        let t = max(0, (p - cellOutruns) / (1 - cellOutruns))
        let radius = framed * pow(max(cover / framed, 1), t * t)
        let offset = CGPoint(x: center.x - scale * focusFinal.x, y: center.y - scale * focusFinal.y)
        return Frame(center: center, radius: radius, scale: scale, offset: offset)
    }

    /// Where the still sits inside the cell at rest (Home's window, in the window's own
    /// coordinates): the whole scene at the rest scale, its focus on the cell's centre. The same
    /// numbers as frame(progress: 0), so the cover's first frame covers the window exactly.
    static func restImageRect(sceneSize: CGSize) -> CGRect {
        let s = restScale(sceneWidth: sceneSize.width)
        let size = CGSize(width: sceneSize.width * s, height: sceneSize.height * s)
        return CGRect(x: radius - focus.x * size.width, y: height / 2 - focus.y * size.height,
                      width: size.width, height: size.height)
    }

    /// Before the room has ever been opened from Home: the live room's scene band in the safe
    /// area's coordinates (measured on iPhone 17 Pro: header 56 pt, footer 59 pt). Replaced by the
    /// measured band after the first open.
    static func estimatedScene(safeSize: CGSize) -> CGRect {
        CGRect(x: 0, y: 56, width: safeSize.width, height: max(200, safeSize.height - 56 - 59))
    }
}

// MARK: - Transition phases

/// The transition's state. The host drives animations from the changes between states; the rules
/// themselves are pure so tests can walk every path.
struct HomeHexPortalPhase: Equatable {
    enum Stage: Equatable {
        /// The window rests on Home.
        case idle
        /// A finger is down on the window: it presses in and the room starts preparing.
        case pressed
        /// The cover is up and the cell is growing.
        case opening
        /// The zoom has ended; the room is on screen.
        case open
        /// The room is shrinking back into the cell.
        case closing
    }

    var stage: Stage = .idle
    /// The live scene has drawn its first frames.
    var liveReady = false
    /// The still covers the live scene (false once handed off).
    var stillShown = true
    /// The room's own controls (title bar, footer) are visible.
    var controlsShown = false

    enum Event: Equatable {
        case touchDown, touchCancelled, tap, zoomEnded, liveFrame, back, closeEnded
    }

    /// The live scene can show and take touches.
    var isInteractive: Bool { stage == .open && controlsShown }

    mutating func handle(_ event: Event) {
        switch (event, stage) {
        case (.touchDown, .idle):
            stage = .pressed
        case (.touchCancelled, .pressed):
            stage = .idle
        case (.tap, .idle), (.tap, .pressed):
            self = HomeHexPortalPhase(stage: .opening)
        case (.liveFrame, _):
            liveReady = true
            // Ready early: the cross-fade runs during the zoom (still and live scene share one
            // transform, so they line up at every frame); the controls wait for the zoom's end.
            if stage == .opening || stage == .open { stillShown = false }
            if stage == .open { controlsShown = true }
        case (.zoomEnded, .opening):
            stage = .open
            if liveReady {
                stillShown = false
                controlsShown = true
            }
        case (.back, .opening), (.back, .open):
            stage = .closing
            stillShown = true
            controlsShown = false
        case (.closeEnded, .closing):
            self = HomeHexPortalPhase()
        default:
            break
        }
    }
}

// MARK: - Diagnostics

/// Debug counters for the timing harness (body evaluations of the Train view).
@MainActor
enum HomeHexPortalDiagnostics {
    static var trainBodies = 0

    static func countTrainBody() {
        #if DEBUG
        trainBodies += 1
        #endif
    }
}
