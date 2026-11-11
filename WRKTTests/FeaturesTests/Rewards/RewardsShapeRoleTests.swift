import Foundation
import SwiftUI
import Testing
@testable import WRKT

@MainActor
struct RewardsShapeRoleTests {
    #if DEBUG
    @Test func barbellWelcomeAndEditorKeepLegacyPaths() throws {
        let source0 = try ShapeRoleTestSupport.source("Rewards/Views/BarbellWelcomeView.swift")
        #expect(source0.contains("DS.RoleShape(.control, legacy: ChamferedRectangle(.large))"))
        #expect(source0.contains("DS.RoleShape(.card, legacy: ChamferedRectangle(.xl))"))
        #expect(source0.contains("DS.RoleShape(.control, legacy: ChamferedRectangle(.medium))"))
        let source1 = try ShapeRoleTestSupport.source("Rewards/Views/BarbellEditorView.swift")
        #expect(source1.contains("DS.RoleShape(.nested, legacy: RoundedRectangle(cornerRadius: 8))"))
        #expect(source1.contains("DS.RoleShape(.card, legacy: RoundedRectangle(cornerRadius: 8))"))
        #expect(source1.contains("DS.RoleShape(.control, legacy: RoundedRectangle(cornerRadius: 8))"))
        #expect(source1.contains("DS.RoleShape(.tile, legacy: RoundedRectangle(cornerRadius: 8))"))
        #expect(source1.contains("DS.RoleShape(.iconTile, legacy: RoundedRectangle(cornerRadius: 6))"))
        let source2 = try ShapeRoleTestSupport.source("Rewards/Views/BarbellMomentView.swift")
        #expect(source2.contains("DS.RoleShape(.control, legacy: ChamferedRectangle(.medium))"))
        for rect in ShapeRoleTestSupport.rects {
            ShapeRoleTestSupport.check(.control, legacy: ChamferedRectangle(.large), expected: MainChamferedRectangle(.large).path(in: rect), rect: rect, radius: min(rect.width, rect.height) / 2)
            ShapeRoleTestSupport.check(.card, legacy: ChamferedRectangle(.xl), expected: MainChamferedRectangle(.xl).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.control, legacy: ChamferedRectangle(.medium), expected: MainChamferedRectangle(.medium).path(in: rect), rect: rect, radius: min(rect.width, rect.height) / 2)
            ShapeRoleTestSupport.check(.nested, legacy: RoundedRectangle(cornerRadius: 8), expected: RoundedRectangle(cornerRadius: 8).path(in: rect), rect: rect, radius: 10)
            ShapeRoleTestSupport.check(.card, legacy: RoundedRectangle(cornerRadius: 8), expected: RoundedRectangle(cornerRadius: 8).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.control, legacy: RoundedRectangle(cornerRadius: 8), expected: RoundedRectangle(cornerRadius: 8).path(in: rect), rect: rect, radius: min(rect.width, rect.height) / 2)
            ShapeRoleTestSupport.check(.tile, legacy: RoundedRectangle(cornerRadius: 8), expected: RoundedRectangle(cornerRadius: 8).path(in: rect), rect: rect, radius: 16)
            ShapeRoleTestSupport.check(.iconTile, legacy: RoundedRectangle(cornerRadius: 6), expected: RoundedRectangle(cornerRadius: 6).path(in: rect), rect: rect, radius: min(rect.width, rect.height) * 0.225)
        }
    }
    @Test func winScreenKeepsLegacyPaths() throws {
        let source0 = try ShapeRoleTestSupport.source("Rewards/Views/WinScreen.swift")
        #expect(source0.contains("DS.RoleShape(.control, legacy: ChamferedRectangle(.medium))"))
        #expect(source0.contains("DS.RoleShape(.control, legacy: ChamferedRectangle(.small))"))
        #expect(source0.contains("DS.RoleShape(.tile, legacy: ChamferedRectangle(.small))"))
        #expect(source0.contains("DS.RoleShape(.card, legacy: ChamferedRectangle(.medium))"))
        #expect(source0.contains("DS.RoleShape(.iconTile, legacy: ChamferedRectangle(.small))"))
        #expect(source0.contains("DS.RoleShape(.tile, legacy: RoundedRectangle(cornerRadius: 4))"))
        #expect(source0.contains("DS.RoleShape(.card, legacy: ChamferedRectangle(.large))"))
        for rect in ShapeRoleTestSupport.rects {
            ShapeRoleTestSupport.check(.control, legacy: ChamferedRectangle(.medium), expected: MainChamferedRectangle(.medium).path(in: rect), rect: rect, radius: min(rect.width, rect.height) / 2)
            ShapeRoleTestSupport.check(.control, legacy: ChamferedRectangle(.small), expected: MainChamferedRectangle(.small).path(in: rect), rect: rect, radius: min(rect.width, rect.height) / 2)
            ShapeRoleTestSupport.check(.tile, legacy: ChamferedRectangle(.small), expected: MainChamferedRectangle(.small).path(in: rect), rect: rect, radius: 16)
            ShapeRoleTestSupport.check(.card, legacy: ChamferedRectangle(.medium), expected: MainChamferedRectangle(.medium).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.iconTile, legacy: ChamferedRectangle(.small), expected: MainChamferedRectangle(.small).path(in: rect), rect: rect, radius: min(rect.width, rect.height) * 0.225)
            ShapeRoleTestSupport.check(.tile, legacy: RoundedRectangle(cornerRadius: 4), expected: RoundedRectangle(cornerRadius: 4).path(in: rect), rect: rect, radius: 16)
            ShapeRoleTestSupport.check(.card, legacy: ChamferedRectangle(.large), expected: MainChamferedRectangle(.large).path(in: rect), rect: rect, radius: 26)
        }
    }
    #endif
}
