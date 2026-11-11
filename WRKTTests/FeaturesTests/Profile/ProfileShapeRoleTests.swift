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
    @Test func progressOverviewAndAdherenceKeepLegacyPaths() throws {
        let source0 = try ShapeRoleTestSupport.source("Profile/Views/ProfileView.swift")
        #expect(source0.contains("DS.RoleShape(.iconTile, legacy: ChamferedRectangle(.medium))"))
        #expect(source0.contains("DS.RoleShape(.card, legacy: ChamferedRectangle(.large))"))
        #expect(source0.contains("DS.RoleShape(.control, legacy: ChamferedRectangle(.small))"))
        #expect(source0.contains("DS.RoleShape(.nested, legacy: RoundedRectangle(cornerRadius: 12))"))
        #expect(source0.contains("DS.RoleShape(.card, legacy: ChamferedRectangle(.xl))"))
        #expect(source0.contains("DS.RoleShape(.control, legacy: RoundedRectangle(cornerRadius: 10))"))
        let source1 = try ShapeRoleTestSupport.source("Profile/Views/Components/PlanAdherenceCard.swift")
        #expect(source1.contains("DS.RoleShape(.card, legacy: RoundedRectangle(cornerRadius: 12, style: .continuous))"))
        for rect in ShapeRoleTestSupport.rects {
            ShapeRoleTestSupport.check(.iconTile, legacy: ChamferedRectangle(.medium), expected: MainChamferedRectangle(.medium).path(in: rect), rect: rect, radius: min(rect.width, rect.height) * 0.225)
            ShapeRoleTestSupport.check(.card, legacy: ChamferedRectangle(.large), expected: MainChamferedRectangle(.large).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.control, legacy: ChamferedRectangle(.small), expected: MainChamferedRectangle(.small).path(in: rect), rect: rect, radius: min(rect.width, rect.height) / 2)
            ShapeRoleTestSupport.check(.nested, legacy: RoundedRectangle(cornerRadius: 12), expected: RoundedRectangle(cornerRadius: 12).path(in: rect), rect: rect, radius: 10)
            ShapeRoleTestSupport.check(.card, legacy: ChamferedRectangle(.xl), expected: MainChamferedRectangle(.xl).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.control, legacy: RoundedRectangle(cornerRadius: 10), expected: RoundedRectangle(cornerRadius: 10).path(in: rect), rect: rect, radius: min(rect.width, rect.height) / 2)
            ShapeRoleTestSupport.check(.card, legacy: RoundedRectangle(cornerRadius: 12, style: .continuous), expected: RoundedRectangle(cornerRadius: 12, style: .continuous).path(in: rect), rect: rect, radius: 26)
        }
    }
    #endif
}
