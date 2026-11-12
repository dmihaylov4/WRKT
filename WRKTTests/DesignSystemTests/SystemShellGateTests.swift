import Foundation
import SwiftUI
import Testing
@testable import WRKT

@MainActor
struct SystemShellGateTests {
    @Test func gateRequiresRoundedShapesAndIOS26() {
        #expect(DS.Redesign.usesSystemShell(rounded: true, isIOS26: true))
        #expect(!DS.Redesign.usesSystemShell(rounded: true, isIOS26: false))
        #expect(!DS.Redesign.usesSystemShell(rounded: false, isIOS26: true))
        #expect(!DS.Redesign.usesSystemShell(rounded: false, isIOS26: false))
    }

    @Test func launchValueMatchesSwitchAndOS() {
        let isIOS26: Bool
        if #available(iOS 26, *) { isIOS26 = true } else { isIOS26 = false }
        #expect(DS.Redesign.usesSystemShell == (DS.Redesign.roundedShapesEnabled && isIOS26))
    }

    @Test func clearanceReturnsLegacyValueWhenGateIsOff() {
        #expect(DS.Redesign.tabBarClearance(legacy: 80, system: 60, systemShell: false) == 80)
        #expect(DS.Redesign.tabBarClearance(legacy: 56, system: 36, systemShell: false) == 56)
    }

    @Test func clearanceReturnsSystemValueWhenGateIsOn() {
        #expect(DS.Redesign.tabBarClearance(legacy: 80, system: 60, systemShell: true) == 60)
        #expect(DS.Redesign.tabBarClearance(legacy: 90, system: 119, systemShell: true) == 119)
    }

    @Test func productionClearanceFollowsLaunchGate() {
        let expected: CGFloat = DS.Redesign.usesSystemShell ? 60 : 80
        #expect(DS.Redesign.tabBarClearance(legacy: 80, system: 60) == expected)
    }
}
