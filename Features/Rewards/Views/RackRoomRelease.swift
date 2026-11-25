// Features/Rewards/Views/RackRoomRelease.swift
//
// The one switch for the new rack room: lathe plates, the home gym mood (honeycomb light wall,
// rubber floor, sign), the plates row ("rail") under the scene, and the lathe thumbnails.
//
// - Debug builds: always on. The DEBUG launch-environment overrides (VOLIA_RACK_PLATES,
//   VOLIA_RACK_TRAY, VOLIA_RACK_MOOD, VOLIA_RACK_FLOOR, VOLIA_RACK_LIGHT, ...) still apply there.
// - Release builds: on when this launch shows the new design (CutTesterSwitch.launch.newDesign):
//   off for App Store installs, on for TestFlight testers unless they switched the new design off.
//   No override is read.
//
// Resolved once per launch and never changes in a session, like the design switch it follows.
// Another feature that should ship with the new room reads `RackRoomRelease.isNewRoomEnabled`
// in place of its own `#if DEBUG` switch.
//
// Simulator only, for checking a Release build: `-VoliaSimulatedInstall testFlight` stands in
// for the TestFlight receipt (CutTesterSwitch; compiled out of device builds).

import Foundation

nonisolated enum RackRoomRelease {
    /// The rule, separated from the build flag so tests can pin every case.
    static func resolve(build: CutBuildConfiguration, newDesign: Bool) -> Bool {
        switch build {
        case .debug: true
        case .release: newDesign
        }
    }

    /// Whether this launch shows the new rack room. Read once.
    static let isNewRoomEnabled: Bool = {
        #if DEBUG
        resolve(build: .debug, newDesign: true)
        #else
        resolve(build: .release, newDesign: CutTesterSwitch.launch.newDesign)
        #endif
    }()

    /// Whether the DEBUG launch-environment overrides are read. Never in Release.
    static var allowsLaunchOverrides: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    /// The launch environment the overrides read: empty in Release, so nothing a launch passes
    /// can change a Release build.
    static var overrideEnvironment: [String: String] {
        allowsLaunchOverrides ? ProcessInfo.processInfo.environment : [:]
    }
}
