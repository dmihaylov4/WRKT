import Foundation
import Testing
@testable import WRKT

/// The new rack room's one switch (RackRoomRelease) from the install to what the room shows:
/// App Store Release builds keep the legacy plates and the card tray, TestFlight testers on the
/// new design get the lathe plates, the rail and the home gym room, and testers who switched the
/// new design off get the App Store room. No launch override reaches a Release build.
@MainActor
@Suite struct RackRoomReleaseTests {
    private struct Room: Equatable {
        var plates: RackPlateStyle
        var tray: CutRackTrayStyle
        var mood: Bool
    }

    /// What a Release launch shows for an install and stored tester choice, with every override a
    /// launch could pass.
    private static func releaseRoom(install: CutInstallKind, applied: Bool?) -> [Room] {
        let design = CutTesterSwitch.resolve(build: .release, install: install, applied: applied, debugNewDesign: true)
        let newRoom = RackRoomRelease.resolve(build: .release, newDesign: design.newDesign)
        let environments: [[String: String]] = [
            [:],
            [RackPlateStyle.overrideKey: "lathe", CutRackTrayStyle.overrideKey: "rail"],
            [RackPlateStyle.overrideKey: "legacy", CutRackTrayStyle.overrideKey: "card"]
        ]
        return environments.map { environment in
            let plates = RackPlateStyle.resolve(newRoom: newRoom, allowsOverrides: false, environment: environment)
            return Room(plates: plates,
                        tray: CutRackTrayStyle.resolve(newRoom: newRoom, allowsOverrides: false, environment: environment),
                        mood: RackRoomMood.current(for: plates) != nil)
        }
    }

    private static let appStoreRoom = Room(plates: .legacy, tray: .card, mood: false)
    private static let newRoom = Room(plates: .lathe, tray: .rail, mood: true)

    @Test func appStoreReleaseKeepsTheLegacyPlatesAndTheCardTray() {
        for applied in [nil, true, false] as [Bool?] {
            #expect(Self.releaseRoom(install: .appStore, applied: applied).allSatisfy { $0 == Self.appStoreRoom })
        }
    }

    @Test func testFlightOnTheNewDesignGetsTheNewRoom() {
        for applied in [nil, true] as [Bool?] {
            #expect(Self.releaseRoom(install: .testFlight, applied: applied).allSatisfy { $0 == Self.newRoom })
        }
    }

    @Test func testFlightWithTheNewDesignSwitchedOffGetsTheAppStoreRoom() {
        #expect(Self.releaseRoom(install: .testFlight, applied: false).allSatisfy { $0 == Self.appStoreRoom })
    }

    @Test func debugBuildsAlwaysGetTheNewRoom() {
        #expect(RackRoomRelease.resolve(build: .debug, newDesign: false))
        #expect(RackRoomRelease.resolve(build: .debug, newDesign: true))
        #expect(RackRoomRelease.isNewRoomEnabled)
        #expect(RackRoomRelease.allowsLaunchOverrides)
    }

    @Test func theRoomsPiecesFollowTheSwitch() {
        // This test run is a Debug build with no overrides: every piece is the new room's.
        #expect(RackPlateStyle.current == RackPlateStyle.resolve(newRoom: RackRoomRelease.isNewRoomEnabled, allowsOverrides: true,
                                                                 environment: ProcessInfo.processInfo.environment))
        #expect(CutRackTrayStyle.current == CutRackTrayStyle.resolve(newRoom: RackRoomRelease.isNewRoomEnabled, allowsOverrides: true,
                                                                     environment: ProcessInfo.processInfo.environment))
        // Pieces whose Debug override has the same default as Release.
        #expect(RackTidyStyle.resolve(isDebugBuild: true, argument: nil, environment: [:]) == RackTidyStyle.standard)
        #expect(RackFloorStyle.resolve(nil) == RackFloorStyle.defaultStyle)
        #expect(CutRackRailTap.resolve(environment: [:]) == .load)
        #expect(RackHexPlacement.resolve(nil) == RackHexPlacement.defaultPlacement)
    }
}
