import Foundation
import Testing
@testable import WRKT

/// The TestFlight tester switch for the Cut redesign: App Store installs always get the old
/// design and no switch, whatever is stored; failed detection counts as the App Store.
@Suite("Cut tester switch")
struct CutTesterSwitchTests {
    // MARK: Decision table

    @Test func appStoreIsAlwaysOldDesignWithoutTheSwitch() {
        for applied in [nil, true, false] as [Bool?] {
            for debugNewDesign in [true, false] {
                let resolution = CutTesterSwitch.resolve(build: .release, install: .appStore,
                                                         applied: applied, debugNewDesign: debugNewDesign)
                #expect(resolution == CutDesignResolution(newDesign: false, showsTesterSwitch: false))
            }
        }
    }

    @Test func testFlightDefaultsToNewDesignAndShowsTheSwitch() {
        let resolution = CutTesterSwitch.resolve(build: .release, install: .testFlight, applied: nil, debugNewDesign: true)
        #expect(resolution == CutDesignResolution(newDesign: true, showsTesterSwitch: true))
    }

    @Test func testFlightFollowsTheStoredChoice() {
        for debugNewDesign in [true, false] {
            #expect(CutTesterSwitch.resolve(build: .release, install: .testFlight, applied: true,
                                            debugNewDesign: debugNewDesign)
                    == CutDesignResolution(newDesign: true, showsTesterSwitch: true))
            #expect(CutTesterSwitch.resolve(build: .release, install: .testFlight, applied: false,
                                            debugNewDesign: debugNewDesign)
                    == CutDesignResolution(newDesign: false, showsTesterSwitch: true))
        }
    }

    @Test func debugIgnoresInstallAndStoredChoiceAndNeverShowsTheSwitch() {
        for install in [CutInstallKind.appStore, .testFlight] {
            for applied in [nil, true, false] as [Bool?] {
                for debugNewDesign in [true, false] {
                    let resolution = CutTesterSwitch.resolve(build: .debug, install: install,
                                                             applied: applied, debugNewDesign: debugNewDesign)
                    #expect(resolution == CutDesignResolution(newDesign: debugNewDesign, showsTesterSwitch: false))
                }
            }
        }
    }

    @Test func failedDetectionResolvesAsAppStore() {
        for url in [nil, URL(string: "https://example.com/sandboxReceipt")] as [URL?] {
            let install = CutTesterSwitch.installKind(receiptURL: url)
            #expect(install == .appStore)
            for applied in [nil, true, false] as [Bool?] {
                #expect(CutTesterSwitch.resolve(build: .release, install: install, applied: applied, debugNewDesign: true)
                        == CutDesignResolution(newDesign: false, showsTesterSwitch: false))
            }
        }
    }

    // MARK: Detection

    @Test func receiptNameDecidesTheInstallKind() {
        let container = URL(fileURLWithPath: "/private/var/containers/Bundle/Application/ABC/StoreKit")
        #expect(CutTesterSwitch.installKind(receiptURL: container.appendingPathComponent("sandboxReceipt")) == .testFlight)
        #expect(CutTesterSwitch.installKind(receiptURL: container.appendingPathComponent("receipt")) == .appStore)
        // Anything unexpected is the App Store.
        for name in ["SandboxReceipt", "sandboxreceipt", "sandboxReceipt.old", "masReceipt", ""] {
            #expect(CutTesterSwitch.installKind(receiptURL: container.appendingPathComponent(name)) == .appStore)
        }
        #expect(CutTesterSwitch.installKind(receiptURL: nil) == .appStore)
    }

    @Test func simulatedInstallArgumentParsesOnlyKnownValues() {
        let argument = CutTesterSwitch.simulatedInstallArgument
        #expect(CutTesterSwitch.simulatedInstall(arguments: ["app", argument, "testFlight"]) == .testFlight)
        #expect(CutTesterSwitch.simulatedInstall(arguments: ["app", argument, "appStore"]) == .appStore)
        #expect(CutTesterSwitch.simulatedInstall(arguments: ["app", argument, "TestFlight"]) == nil)
        #expect(CutTesterSwitch.simulatedInstall(arguments: ["app", argument]) == nil)
        #expect(CutTesterSwitch.simulatedInstall(arguments: ["app"]) == nil)
    }

    @Test func launchInstallKindUsesTheReceiptWithoutTheArgument() {
        let sandbox = URL(fileURLWithPath: "/x/StoreKit/sandboxReceipt")
        let store = URL(fileURLWithPath: "/x/StoreKit/receipt")
        #expect(CutTesterSwitch.launchInstallKind(arguments: [], receiptURL: sandbox) == .testFlight)
        #expect(CutTesterSwitch.launchInstallKind(arguments: [], receiptURL: store) == .appStore)
        #expect(CutTesterSwitch.launchInstallKind(arguments: [], receiptURL: nil) == .appStore)
    }

    #if targetEnvironment(simulator)
    @Test func simulatorArgumentOverridesTheReceipt() {
        let argument = CutTesterSwitch.simulatedInstallArgument
        let store = URL(fileURLWithPath: "/x/StoreKit/receipt")
        let sandbox = URL(fileURLWithPath: "/x/StoreKit/sandboxReceipt")
        #expect(CutTesterSwitch.launchInstallKind(arguments: [argument, "testFlight"], receiptURL: store) == .testFlight)
        #expect(CutTesterSwitch.launchInstallKind(arguments: [argument, "appStore"], receiptURL: sandbox) == .appStore)
    }
    #endif

    @Test func storedValuesOfAnotherTypeCountAsUnset() throws {
        let defaults = try scratchDefaults()
        defaults.set("YES", forKey: CutTesterSwitch.appliedKey)
        #expect(CutTesterSwitch.storedBool(CutTesterSwitch.appliedKey, in: defaults) == nil)
        defaults.set(Data([1]), forKey: CutTesterSwitch.appliedKey)
        #expect(CutTesterSwitch.storedBool(CutTesterSwitch.appliedKey, in: defaults) == nil)
        defaults.set(true, forKey: CutTesterSwitch.appliedKey)
        #expect(CutTesterSwitch.storedBool(CutTesterSwitch.appliedKey, in: defaults) == true)
    }

    // MARK: Debug builds

    #if DEBUG
    @Test func debugBuildNeverShowsTheSwitch() {
        #expect(!CutTesterSwitch.showsSwitch)
        // The Debug gate is unchanged: the Debug key and default, nothing from the tester keys.
        let stored = UserDefaults.standard.object(forKey: DS.Redesign.cutPreferenceKey)
        let expected = stored == nil ? DS.Redesign.cutDefault : UserDefaults.standard.bool(forKey: DS.Redesign.cutPreferenceKey)
        #expect(DS.Redesign.cutEnabled == expected)
    }
    #else
    @Test func releaseGateIsTheLaunchResolution() {
        #expect(DS.Redesign.cutEnabled == CutTesterSwitch.launch.newDesign)
        #expect(DS.Redesign.roundedShapesEnabled == CutTesterSwitch.launch.newDesign)
        #expect(CutTesterSwitch.showsSwitch == CutTesterSwitch.launch.showsTesterSwitch)
        if CutTesterSwitch.launchInstallKind() == .appStore {
            #expect(!DS.Redesign.cutEnabled)
            #expect(!CutTesterSwitch.showsSwitch)
        }
    }
    #endif

    // MARK: Applying a choice

    @Test func choiceAppliesAtOnceWithoutAWorkout() throws {
        let defaults = try scratchDefaults()
        #expect(CutTesterSwitch.chosen(in: defaults))
        CutTesterSwitch.choose(false, workoutActive: false, in: defaults)
        #expect(!CutTesterSwitch.chosen(in: defaults))
        #expect(CutTesterSwitch.storedBool(CutTesterSwitch.appliedKey, in: defaults) == false)
        CutTesterSwitch.choose(true, workoutActive: false, in: defaults)
        #expect(CutTesterSwitch.chosen(in: defaults))
        #expect(CutTesterSwitch.storedBool(CutTesterSwitch.appliedKey, in: defaults) == true)
    }

    @Test func choiceDuringAWorkoutWaitsForItsEnd() throws {
        let defaults = try scratchDefaults()
        CutTesterSwitch.choose(true, workoutActive: true, in: defaults)
        #expect(CutTesterSwitch.chosen(in: defaults))
        #expect(CutTesterSwitch.storedBool(CutTesterSwitch.appliedKey, in: defaults) == nil)
        CutTesterSwitch.workoutActivityChanged(active: false, runningNewDesign: false, in: defaults)
        #expect(CutTesterSwitch.storedBool(CutTesterSwitch.appliedKey, in: defaults) == true)
    }

    @Test func relaunchDuringAWorkoutKeepsTheDesignItStartedUnder() throws {
        let defaults = try scratchDefaults()
        // Chosen without restarting, then a workout starts in the old design.
        CutTesterSwitch.choose(true, workoutActive: false, in: defaults)
        CutTesterSwitch.workoutActivityChanged(active: true, runningNewDesign: false, in: defaults)
        let applied = CutTesterSwitch.storedBool(CutTesterSwitch.appliedKey, in: defaults)
        #expect(applied == false)
        #expect(CutTesterSwitch.resolve(build: .release, install: .testFlight, applied: applied, debugNewDesign: false).newDesign == false)
        // The switch still shows the choice, and it applies once the workout ends.
        #expect(CutTesterSwitch.chosen(in: defaults))
        CutTesterSwitch.workoutActivityChanged(active: false, runningNewDesign: false, in: defaults)
        #expect(CutTesterSwitch.storedBool(CutTesterSwitch.appliedKey, in: defaults) == true)
    }

    @Test func workoutEndWithoutAChoiceWritesNothing() throws {
        let defaults = try scratchDefaults()
        CutTesterSwitch.workoutActivityChanged(active: false, runningNewDesign: true, in: defaults)
        #expect(defaults.object(forKey: CutTesterSwitch.appliedKey) == nil)
    }

    // MARK: Copy and Settings

    @Test func noteExplainsTheState() {
        #expect(CutTesterSwitch.title == "Try the new design")
        #expect(CutTesterSwitch.note(chosen: false, runningNewDesign: false, workoutActive: false)
                == "Unfinished: you can turn it off again here.")
        #expect(CutTesterSwitch.note(chosen: true, runningNewDesign: true, workoutActive: false)
                == "Unfinished: you can turn it off again here.")
        #expect(CutTesterSwitch.note(chosen: true, runningNewDesign: false, workoutActive: false)
                == "Close and reopen the app to switch.")
        #expect(CutTesterSwitch.note(chosen: false, runningNewDesign: true, workoutActive: false)
                == "Close and reopen the app to switch.")
        #expect(CutTesterSwitch.note(chosen: true, runningNewDesign: false, workoutActive: true)
                == "You can change this after your workout.")
        for note in [CutTesterSwitch.note(chosen: false, runningNewDesign: false, workoutActive: false),
                     CutTesterSwitch.note(chosen: true, runningNewDesign: false, workoutActive: false),
                     CutTesterSwitch.note(chosen: true, runningNewDesign: false, workoutActive: true)] {
            #expect(!note.contains("\u{2014}"))
        }
    }

    @Test func cutSettingsShowsTheSwitchOnlyWhenAllowed() {
        #expect(CutSettingsLogic.model(CutSettingsFacts(isLoggedIn: true)).testerSwitch == nil)
        let shown = CutSettingsLogic.model(CutSettingsFacts(isLoggedIn: true, showsTesterSwitch: true,
                                                            testerChoice: true, runningNewDesign: true))
        #expect(shown.testerSwitch == CutSettingsModel.TesterSwitch(
            note: "Unfinished: you can turn it off again here.", isEnabled: true))
        let duringWorkout = CutSettingsLogic.model(CutSettingsFacts(showsTesterSwitch: true, workoutActive: true))
        #expect(duringWorkout.testerSwitch?.isEnabled == false)
    }

    // MARK: Source policy

    @Test func simulatorSeamIsCompiledOutOfDeviceBuilds() throws {
        let source = try String(contentsOfFile: sourcePath("DesignSystem/Theme/CutTesterSwitch.swift"), encoding: .utf8)
        let body = try #require(source.range(of: "static func launchInstallKind").map { String(source[$0.lowerBound...]) })
        let end = try #require(body.range(of: "return installKind(receiptURL: receiptURL)"))
        let launch = String(body[..<end.lowerBound])
        #expect(launch.contains("#if targetEnvironment(simulator)\n        if let simulated = simulatedInstall(arguments: arguments) { return simulated }\n        #endif"))
        // The seam is read nowhere else.
        #expect(source.components(separatedBy: "simulatedInstall(arguments:").count == 3) // declaration + one call
    }

    @Test func releaseGateReadsTheTesterSwitchAndDebugGateDoesNot() throws {
        let source = try String(contentsOfFile: sourcePath("DesignSystem/Theme/DS.swift"), encoding: .utf8)
        let redesign = try #require(source.range(of: "public enum Redesign").map { String(source[$0.lowerBound...]) })
        #expect(redesign.contains("""
                #else
                public static let cutDefault = false
                // False for App Store installs whatever is stored; a TestFlight tester's choice from
                // Settings, read once at launch (CutTesterSwitch).
                public static let cutEnabled = CutTesterSwitch.launch.newDesign
                #endif
        """))
        #expect(redesign.contains("public static let roundedShapesEnabled = CutTesterSwitch.launch.newDesign\n        #endif"))
        let debugCut = try #require(redesign.range(of: "public static let cutPreferenceKey").map { String(redesign[$0.lowerBound...]) })
        let debugCutBlock = String(debugCut.prefix(while: { $0 != "#" }))
        #expect(!debugCutBlock.contains("CutTesterSwitch"))
    }

    @Test func testerSwitchHasNoEffectOnRunStorage() throws {
        let source = try String(contentsOfFile: sourcePath("DesignSystem/Theme/CutTesterSwitch.swift"), encoding: .utf8)
        for word in ["RunHistory", "RunsV3", "WorkoutStorage", "migration"] {
            #expect(!source.contains(word))
        }
    }

    // MARK: Helpers

    private func scratchDefaults() throws -> UserDefaults {
        let name = "CutTesterSwitchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func sourcePath(_ relativePath: String) -> String {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            url.deleteLastPathComponent()
        }
        return url.appendingPathComponent(relativePath).path
    }
}
