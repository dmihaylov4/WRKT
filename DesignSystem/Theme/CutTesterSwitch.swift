//
//  CutTesterSwitch.swift
//  WRKT
//
//  The tester switch for the Cut redesign in Release builds.
//
//  App Store installs always get the old design and never see the switch: any stored choice is
//  ignored. TestFlight installs get the new design by default and a "Try the new design" switch
//  in Settings to turn it off. Debug builds keep their own Debug switches and never read this one.
//
//  The install source is read once per launch from the name of the App Store receipt file,
//  which is "sandboxReceipt" for builds signed for the sandbox environment (TestFlight, and also
//  App Review) and "receipt" for App Store downloads. A missing or unexpected receipt URL counts
//  as the App Store. The choice applies at the next launch, never in the middle of a workout.
//

import Foundation

/// Where this copy of the app came from, as far as the launch can tell.
nonisolated enum CutInstallKind: String, Equatable, Sendable {
    /// Also every case where detection fails or is uncertain.
    case appStore
    /// A sandbox-signed install: TestFlight, and App Review.
    case testFlight
}

nonisolated enum CutBuildConfiguration: Equatable, Sendable {
    case debug, release
}

/// What a launch shows.
nonisolated struct CutDesignResolution: Equatable, Sendable {
    /// The Cut screens (and, in Release, the rounded shapes and system shell they were built on).
    let newDesign: Bool
    /// The "Try the new design" row in Settings.
    let showsTesterSwitch: Bool
}

nonisolated enum CutTesterSwitch {
    /// Bool: the design the next launch uses. Written only at safe points (no workout running).
    static let appliedKey = "tester.newDesign.applied"
    /// Bool: what the switch in Settings shows, the tester's latest choice.
    static let chosenKey = "tester.newDesign.chosen"
    /// Simulator only: `-VoliaSimulatedInstall testFlight` (or `appStore`) stands in for the
    /// receipt. The code that reads it is compiled out of device builds.
    static let simulatedInstallArgument = "-VoliaSimulatedInstall"

    // MARK: Decisions (pure)

    /// The install source from the receipt URL. Anything but a file named "sandboxReceipt" is the
    /// App Store, including no URL at all.
    static func installKind(receiptURL: URL?) -> CutInstallKind {
        guard let receiptURL, receiptURL.isFileURL, receiptURL.lastPathComponent == "sandboxReceipt" else {
            return .appStore
        }
        return .testFlight
    }

    /// The simulator stand-in, parsed from launch arguments. Nil when absent or unreadable.
    static func simulatedInstall(arguments: [String]) -> CutInstallKind? {
        guard let index = arguments.firstIndex(of: simulatedInstallArgument),
              arguments.indices.contains(index + 1) else { return nil }
        return CutInstallKind(rawValue: arguments[index + 1])
    }

    /// What a TestFlight install shows before the tester has touched the switch.
    static let testFlightDefault = true

    /// The decision table. `applied` is the stored choice (nil when never set or not a Bool);
    /// `debugNewDesign` is what the Debug switches resolved to and is used only in Debug.
    static func resolve(build: CutBuildConfiguration, install: CutInstallKind, applied: Bool?,
                        debugNewDesign: Bool) -> CutDesignResolution {
        switch (build, install) {
        case (.debug, _):
            CutDesignResolution(newDesign: debugNewDesign, showsTesterSwitch: false)
        case (.release, .appStore):
            CutDesignResolution(newDesign: false, showsTesterSwitch: false)
        case (.release, .testFlight):
            CutDesignResolution(newDesign: applied ?? testFlightDefault, showsTesterSwitch: true)
        }
    }

    /// The stored Bool, or nil when it is unset or of another type.
    static func storedBool(_ key: String, in defaults: UserDefaults) -> Bool? {
        defaults.object(forKey: key) as? Bool
    }

    // MARK: Launch

    /// The install source for this launch. On a device this is the receipt alone.
    static func launchInstallKind(arguments: [String] = ProcessInfo.processInfo.arguments,
                                  receiptURL: URL? = currentReceiptURL()) -> CutInstallKind {
        #if targetEnvironment(simulator)
        if let simulated = simulatedInstall(arguments: arguments) { return simulated }
        #endif
        return installKind(receiptURL: receiptURL)
    }

    /// Read once at launch, like the design switches that depend on it. Release only: Debug
    /// builds never call it (DS.Redesign keeps its Debug switches).
    static let launch: CutDesignResolution = resolve(
        build: .release,
        install: launchInstallKind(),
        applied: storedBool(appliedKey, in: .standard),
        debugNewDesign: false)

    /// `Bundle.appStoreReceiptURL` is deprecated since iOS 18 in favour of the asynchronous
    /// `AppTransaction`, which cannot answer before the first view body is built.
    static func currentReceiptURL() -> URL? {
        let reader: any CutReceiptURLReading = CutReceiptURLReader()
        return reader.read()
    }

    /// Whether Settings shows the switch in this build and install: never in Debug, never for
    /// the App Store.
    static var showsSwitch: Bool {
        #if DEBUG
        false
        #else
        launch.showsTesterSwitch
        #endif
    }

    // MARK: The switch

    /// What the switch shows: the latest choice, else what is applied, else the TestFlight
    /// default (the switch is only ever shown there).
    static func chosen(in defaults: UserDefaults = .standard) -> Bool {
        storedBool(chosenKey, in: defaults) ?? storedBool(appliedKey, in: defaults) ?? testFlightDefault
    }

    /// The tester flips the switch. It applies at the next launch unless a workout is running,
    /// in which case it applies when the workout ends.
    static func choose(_ on: Bool, workoutActive: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(on, forKey: chosenKey)
        if !workoutActive {
            defaults.set(on, forKey: appliedKey)
        }
    }

    /// A workout started or ended. While one runs, the next launch keeps the design it started
    /// under, so a relaunch mid-workout never switches design; when it ends, the latest choice
    /// applies again.
    static func workoutActivityChanged(active: Bool, runningNewDesign: Bool,
                                       in defaults: UserDefaults = .standard) {
        if active {
            defaults.set(runningNewDesign, forKey: appliedKey)
        } else if let chosen = storedBool(chosenKey, in: defaults) {
            defaults.set(chosen, forKey: appliedKey)
        }
    }

    // MARK: Copy

    static let title = "Try the new design"

    /// The one line under the switch.
    static func note(chosen: Bool, runningNewDesign: Bool, workoutActive: Bool) -> String {
        if workoutActive {
            return "You can change this after your workout."
        }
        if chosen != runningNewDesign {
            return "Close and reopen the app to switch."
        }
        return "Unfinished: you can turn it off again here."
    }
}

/// Reads the deprecated receipt URL through a protocol, so the one deprecation is contained here.
nonisolated private protocol CutReceiptURLReading {
    func read() -> URL?
}

nonisolated private struct CutReceiptURLReader: CutReceiptURLReading {
    @available(iOS, deprecated: 18.0)
    func read() -> URL? {
        Bundle.main.appStoreReceiptURL
    }
}
