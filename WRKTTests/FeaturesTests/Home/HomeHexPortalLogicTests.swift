import CoreGraphics
import Foundation
import Testing
@testable import WRKT

@Suite("Home hex portal: flag")
struct HomeHexPortalFlagTests {
    /// A Release launch's portal for an install and stored tester choice, with every override a
    /// launch could pass.
    private static func releasePortal(install: CutInstallKind, applied: Bool?) -> [Bool] {
        let design = CutTesterSwitch.resolve(build: .release, install: install, applied: applied, debugNewDesign: true)
        let newRoom = RackRoomRelease.resolve(build: .release, newDesign: design.newDesign)
        return [[:], [HomeHexPortalFlag.overrideKey: "1"], [HomeHexPortalFlag.overrideKey: "0"]].map {
            HomeHexPortalFlag.resolve(newRoom: newRoom, allowsOverrides: false, environment: $0)
        }
    }

    @Test func appStoreReleaseNeverShowsThePortal() {
        for applied in [nil, true, false] as [Bool?] {
            #expect(Self.releasePortal(install: .appStore, applied: applied).allSatisfy { !$0 })
        }
    }

    @Test func testFlightOnTheNewDesignShowsThePortal() {
        for applied in [nil, true] as [Bool?] {
            #expect(Self.releasePortal(install: .testFlight, applied: applied).allSatisfy { $0 })
        }
    }

    @Test func testFlightWithTheNewDesignSwitchedOffHasNoPortal() {
        #expect(Self.releasePortal(install: .testFlight, applied: false).allSatisfy { !$0 })
    }

    @Test func debugIsOnUnlessTurnedOff() {
        #expect(HomeHexPortalFlag.resolve(newRoom: true, allowsOverrides: true, environment: [:]))
        #expect(HomeHexPortalFlag.resolve(newRoom: true, allowsOverrides: true, environment: [HomeHexPortalFlag.overrideKey: "1"]))
        #expect(HomeHexPortalFlag.resolve(newRoom: true, allowsOverrides: true, environment: [HomeHexPortalFlag.overrideKey: "0"]) == false)
        #expect(HomeHexPortalFlag.resolve(newRoom: true, allowsOverrides: true, environment: [HomeHexPortalFlag.overrideKey: "off"]) == false)
        #expect(HomeHexPortalFlag.resolve(newRoom: false, allowsOverrides: true, environment: [HomeHexPortalFlag.overrideKey: "1"]) == false)
    }

    @Test func thisBuildMatchesItsConfiguration() {
        let expected = ProcessInfo.processInfo.environment[HomeHexPortalFlag.overrideKey] != "0"
        #expect(HomeHexPortalFlag.isEnabled == expected)
    }
}

@Suite("Home hex portal: window")
struct HomeHexPortalWindowTests {
    static let next = PlanOutlook.Session(name: "Lower Body", date: Date(timeIntervalSince1970: 1_790_000_000))

    @Test func showsInEveryStateButAWorkoutInProgress() {
        #expect(HomeHexPortalLogic.isShown(for: .planned(name: "Upper Body", exerciseCount: 6), flag: true))
        #expect(HomeHexPortalLogic.isShown(for: .restDay(next: Self.next), flag: true))
        #expect(HomeHexPortalLogic.isShown(for: .doneToday(next: nil), flag: true))
        #expect(HomeHexPortalLogic.isShown(for: .noPlan, flag: true))
        #expect(!HomeHexPortalLogic.isShown(for: .live(name: "Upper Body", exercisesDone: 1, exerciseCount: 4, startDate: .now), flag: true))
        #expect(!HomeHexPortalLogic.isShown(for: .resting(nextLine: nil, countdown: .fixed(60)), flag: true))
    }

    @Test func hiddenEverywhereWhenTheFlagIsOff() {
        #expect(!HomeHexPortalLogic.isShown(for: .planned(name: "Upper Body", exerciseCount: 6), flag: false))
        #expect(!HomeHexPortalLogic.isShown(for: .noPlan, flag: false))
    }

    @Test func accessibilityReadsTheRoomsTotalAndPlateCount() {
        let english = Locale(identifier: "en_US")
        #expect(HomeHexPortalLogic.accessibilityValue(loadedKg: [25, 20, 20], unit: .kg, locale: english)
                == "150 kilograms on the bar, 3 plates")
        #expect(HomeHexPortalLogic.accessibilityValue(loadedKg: [20], unit: .kg, locale: english)
                == "60 kilograms on the bar, 1 plate")
        #expect(HomeHexPortalLogic.accessibilityValue(loadedKg: [], unit: .kg, locale: english)
                == "20 kilograms on the bar, no plates")
        let window = HomeHexPortalLogic.window(hero: .noPlan, loadedKg: [], unit: .kg, flag: true, locale: english)
        #expect(window.accessibilityLabel == "Your bar")
        #expect(window.accessibilityHint == "Opens your barbell room")
        #expect(window.isShown)
    }

    @Test func accessibilityInPounds() {
        let value = HomeHexPortalLogic.accessibilityValue(loadedKg: [20], unit: .lb, locale: Locale(identifier: "en_US"))
        #expect(value.hasSuffix("pounds on the bar, 1 plate"))
    }
}

@Suite("Home hex portal: still")
struct HomeHexPortalStillTests {
    static func plate(_ id: String, slot: Int?, engraving: String = "") -> HomeHexStillPlate {
        HomeHexStillPlate(id: id, tierID: 14, weightKg: 20, engraving: engraving, rackPosition: slot,
                          progressionTier: "steel", liftTypeID: nil)
    }

    static func facts(_ plates: [HomeHexStillPlate], size: CGSize = CGSize(width: 402, height: 663),
                      room: String = "dark_gym") -> HomeHexStillFacts {
        HomeHexStillFacts(plates: plates, barSkin: 0, rackStyle: "matte_black", roomTheme: room, wallText: nil,
                          plateStyle: "lathe", sceneSize: size, displayScale: 3)
    }

    @Test func keyIgnoresQueryOrderButNotTheLook() {
        let a = Self.plate("a", slot: 0), b = Self.plate("b", slot: 1)
        let key = HomeHexPortalLogic.stillKey(Self.facts([a, b]))
        #expect(key == HomeHexPortalLogic.stillKey(Self.facts([b, a])))
        #expect(key.hasPrefix("v\(HomeHexPortalLogic.stillVersion)_"))
        #expect(key != HomeHexPortalLogic.stillKey(Self.facts([a])))
        #expect(key != HomeHexPortalLogic.stillKey(Self.facts([Self.plate("a", slot: 2), b])))
        #expect(key != HomeHexPortalLogic.stillKey(Self.facts([Self.plate("a", slot: 0, engraving: "PR"), b])))
        #expect(key != HomeHexPortalLogic.stillKey(Self.facts([a, b], size: CGSize(width: 375, height: 500))))
        #expect(key != HomeHexPortalLogic.stillKey(Self.facts([a, b], room: "neon_garage")))
    }

    @Test func refreshRule() {
        func action(cached: String?, visible: Bool = true, scrolling: Bool = false, busy: Bool = false, idle: Bool = true)
            -> HomeHexPortalLogic.StillAction {
            HomeHexPortalLogic.stillAction(cachedKey: cached, currentKey: "k", homeVisible: visible, scrolling: scrolling,
                                           workoutBusy: busy, portalIdle: idle)
        }
        #expect(action(cached: "k") == .show)
        #expect(action(cached: "k", scrolling: true) == .show)
        #expect(action(cached: nil) == .render)
        #expect(action(cached: "old") == .render)
        #expect(action(cached: nil, visible: false) == .wait)
        #expect(action(cached: nil, scrolling: true) == .wait)
        #expect(action(cached: nil, busy: true) == .wait)
        #expect(action(cached: nil, idle: false) == .wait)
    }

    @Test func liveFrameBecomesTheStillOnlyWhenTheBarChangedAndTheRoomIsTidy() {
        #expect(HomeHexPortalLogic.capturesLiveFrameOnClose(keyAtOpen: "a", keyAtClose: "b", floorPlates: 0, platesMoving: 0))
        #expect(!HomeHexPortalLogic.capturesLiveFrameOnClose(keyAtOpen: "a", keyAtClose: "a", floorPlates: 0, platesMoving: 0))
        #expect(!HomeHexPortalLogic.capturesLiveFrameOnClose(keyAtOpen: "a", keyAtClose: "b", floorPlates: 2, platesMoving: 0))
        #expect(!HomeHexPortalLogic.capturesLiveFrameOnClose(keyAtOpen: "a", keyAtClose: "b", floorPlates: 0, platesMoving: 1))
    }
}

@Suite("Home hex portal: geometry")
struct HomeHexPortalGeometryTests {
    /// Safe area coordinates on a 402 x 874 pt phone (62 pt top, 34 pt bottom insets).
    static let bounds = CGRect(x: 0, y: -62, width: 402, height: 874)
    static let scene = CGRect(x: 0, y: 56, width: 402, height: 663)
    static let source = CGRect(x: 320, y: 326, width: HomeHexGeometry.width, height: HomeHexGeometry.height)

    @Test func cellIsARegularFlatToppedHexagon() {
        let corners = HomeHexGeometry.corners(center: .zero, radius: 10)
        #expect(corners.count == 6)
        for corner in corners { #expect(abs(hypot(corner.x, corner.y) - 10) < 0.0001) }
        #expect(corners[0].y == corners[1].y)
        #expect(abs(HomeHexGeometry.height - HomeHexGeometry.width * 3.0.squareRoot() / 2) < 0.0001)
    }

    @Test func cellStaysClearOfTheFieldsButtonsAndInTheCut() {
        // The field's buttons end 72 pt above its bottom edge.
        let top = HomeHexGeometry.centerFromBottom + HomeHexGeometry.height / 2
        #expect(top <= 72 - 8)
        // The cut runs where dx + dy == 112 (from the field's bottom trailing corner): the left
        // corner touches it, the cell's centre is well inside the notch.
        #expect(HomeHexGeometry.centerFromTrailing + HomeHexGeometry.centerFromBottom < DS.Cut.Metrics.fieldCut)
        let left = HomeHexGeometry.centerFromTrailing + HomeHexGeometry.radius + HomeHexGeometry.centerFromBottom
        #expect(abs(left - DS.Cut.Metrics.fieldCut) <= 2)
        // On screen, with room for the halo.
        #expect(HomeHexGeometry.trailingPadding >= 8)
        #expect(HomeHexGeometry.width >= DS.Cut.Metrics.minTouchTarget)
        #expect(HomeHexGeometry.height >= DS.Cut.Metrics.minTouchTarget)
    }

    @Test func startsExactlyOnTheWindow() {
        let frame = HomeHexGeometry.frame(progress: 0, source: Self.source, scene: Self.scene, bounds: Self.bounds)
        #expect(abs(frame.center.x - Self.source.midX) < 0.001 && abs(frame.center.y - Self.source.midY) < 0.001)
        #expect(abs(frame.radius - HomeHexGeometry.radius) < 0.001)
        // The room layer at progress 0 puts the still where the window draws it.
        let rest = HomeHexGeometry.restImageRect(sceneSize: Self.scene.size)
        let mapped = CGRect(x: frame.scale * Self.scene.minX + frame.offset.x, y: frame.scale * Self.scene.minY + frame.offset.y,
                            width: frame.scale * Self.scene.width, height: frame.scale * Self.scene.height)
        #expect(abs(mapped.minX - (Self.source.minX + rest.minX)) < 0.001)
        #expect(abs(mapped.minY - (Self.source.minY + rest.minY)) < 0.001)
        #expect(abs(mapped.width - rest.width) < 0.001)
    }

    @Test func endsOnTheLiveRoomWithTheCellPastEveryCorner() {
        let frame = HomeHexGeometry.frame(progress: 1, source: Self.source, scene: Self.scene, bounds: Self.bounds)
        #expect(abs(frame.scale - 1) < 0.0001)
        #expect(abs(frame.offset.x) < 0.001 && abs(frame.offset.y) < 0.001)
        let inradius = frame.radius * 3.0.squareRoot() / 2
        for corner in [CGPoint(x: 0, y: -62), CGPoint(x: 402, y: -62), CGPoint(x: 0, y: 812), CGPoint(x: 402, y: 812)] {
            #expect(hypot(corner.x - frame.center.x, corner.y - frame.center.y) < inradius)
        }
    }

    @Test func theCellFramesTheRoomThenSweepsPastIt() {
        let rest = HomeHexGeometry.frame(progress: 0, source: Self.source, scene: Self.scene, bounds: Self.bounds)
        var last = rest
        for step in 1...20 {
            let p = CGFloat(step) / 20
            let frame = HomeHexGeometry.frame(progress: p, source: Self.source, scene: Self.scene, bounds: Self.bounds)
            #expect(frame.radius > last.radius)
            #expect(frame.scale >= last.scale)
            let ratio = frame.radius / frame.scale, restRatio = rest.radius / rest.scale
            if p <= HomeHexGeometry.cellOutruns {
                // Framed exactly as on Home: the cell never shows past the room's side walls.
                #expect(abs(ratio - restRatio) < 0.001)
            } else {
                #expect(ratio > restRatio)
            }
            if p >= HomeHexGeometry.roomArrives { #expect(abs(frame.scale - 1) < 0.0001) }
            last = frame
        }
    }
}

@Suite("Home hex portal: phases")
struct HomeHexPortalPhaseTests {
    @Test func coldOpenHoldsTheStillUntilTheLiveFrame() {
        var phase = HomeHexPortalPhase()
        phase.handle(.touchDown)
        #expect(phase.stage == .pressed)
        phase.handle(.tap)
        #expect(phase.stage == .opening && phase.stillShown && !phase.controlsShown)
        phase.handle(.zoomEnded)
        #expect(phase.stage == .open && phase.stillShown && !phase.controlsShown && !phase.isInteractive)
        phase.handle(.liveFrame)
        #expect(!phase.stillShown && phase.controlsShown && phase.isInteractive)
    }

    @Test func warmOpenHandsOffDuringTheZoomAndShowsControlsAtItsEnd() {
        var phase = HomeHexPortalPhase()
        phase.handle(.tap)
        phase.handle(.liveFrame)
        #expect(phase.stage == .opening && !phase.stillShown && !phase.controlsShown)
        phase.handle(.zoomEnded)
        #expect(phase.controlsShown && phase.isInteractive)
    }

    @Test func aCancelledPressReturnsToRest() {
        var phase = HomeHexPortalPhase()
        phase.handle(.touchDown)
        phase.handle(.touchCancelled)
        #expect(phase == HomeHexPortalPhase())
    }

    @Test func backBringsTheStillBackAndCanInterruptTheZoom() {
        var phase = HomeHexPortalPhase()
        phase.handle(.tap)
        phase.handle(.back)
        #expect(phase.stage == .closing && phase.stillShown && !phase.controlsShown)
        // A late live frame or zoom end while closing changes nothing visible.
        phase.handle(.zoomEnded)
        phase.handle(.liveFrame)
        #expect(phase.stage == .closing && phase.stillShown && !phase.controlsShown)
        phase.handle(.closeEnded)
        #expect(phase == HomeHexPortalPhase())
    }

    @Test func ignoresEventsOutOfOrder() {
        var phase = HomeHexPortalPhase()
        phase.handle(.back)
        phase.handle(.closeEnded)
        phase.handle(.zoomEnded)
        #expect(phase.stage == .idle)
        phase.handle(.tap)
        phase.handle(.tap)
        #expect(phase.stage == .opening)
    }
}
