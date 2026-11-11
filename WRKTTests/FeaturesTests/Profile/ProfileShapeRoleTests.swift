import Foundation
import SwiftUI
import Testing
@testable import WRKT

@MainActor
struct ProfileShapeRoleTests {
    #if DEBUG
    @Test func settingsAndPreferencesKeepLegacyPaths() throws {
        let source0 = try ShapeRoleTestSupport.source("Profile/Views/SettingsView.swift")
        #expect(source0.contains("DS.RoleShape(.card, legacy: ChamferedRectangle(.xl))"))
        let source1 = try ShapeRoleTestSupport.source("Profile/Views/PreferencesView.swift")
        #expect(source1.contains("DS.RoleShape(.card, legacy: ChamferedRectangle(.xl))"))
        #expect(source1.contains("DS.RoleShape(.control, legacy: RoundedRectangle(cornerRadius: 10, style: .continuous))"))
        for rect in ShapeRoleTestSupport.rects {
            ShapeRoleTestSupport.check(.card, legacy: ChamferedRectangle(.xl), expected: MainChamferedRectangle(.xl).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.control, legacy: RoundedRectangle(cornerRadius: 10, style: .continuous), expected: RoundedRectangle(cornerRadius: 10, style: .continuous).path(in: rect), rect: rect, radius: min(rect.width, rect.height) / 2)
        }
    }
    #endif
}
