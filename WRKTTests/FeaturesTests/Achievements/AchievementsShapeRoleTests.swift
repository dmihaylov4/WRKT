import Foundation
import SwiftUI
import Testing
@testable import WRKT

@MainActor
struct AchievementsShapeRoleTests {
    #if DEBUG
    @Test func dexAndAchievementListKeepLegacyPaths() throws {
        let source0 = try ShapeRoleTestSupport.source("Achievements/Views/AchievementsDexView.swift")
        #expect(source0.contains("DS.RoleShape(.control, legacy: ChamferedRectangle(.small))"))
        #expect(source0.contains("DS.RoleShape(.card, legacy: ChamferedRectangle(.medium))"))
        #expect(source0.contains("DS.RoleShape(.nested, legacy: ChamferedRectangle(.small))"))
        #expect(source0.contains("DS.RoleShape(.control, legacy: ChamferedRectangle(.medium))"))
        #expect(source0.contains("DS.RoleShape(.card, legacy: ChamferedRectangle(.xl))"))
        #expect(source0.contains("DS.RoleShape(.iconTile, legacy: ChamferedRectangleAlt(.medium))"))
        let source1 = try ShapeRoleTestSupport.source("Achievements/Views/DexTile.swift")
        #expect(source1.contains("DS.RoleShape(.tile, legacy: ChamferedRectangle(.large))"))
        #expect(source1.contains("DS.RoleShape(.iconTile, legacy: ChamferedRectangleAlt(.medium))"))
        let source2 = try ShapeRoleTestSupport.source("Achievements/Views/AchievementsView.swift")
        #expect(source2.contains("DS.RoleShape(.card, legacy: ChamferedRectangle(.xl))"))
        #expect(source2.contains("DS.RoleShape(.iconTile, legacy: ChamferedRectangleAlt(.small))"))
        for rect in ShapeRoleTestSupport.rects {
            ShapeRoleTestSupport.check(.control, legacy: ChamferedRectangle(.small), expected: MainChamferedRectangle(.small).path(in: rect), rect: rect, radius: min(rect.width, rect.height) / 2)
            ShapeRoleTestSupport.check(.card, legacy: ChamferedRectangle(.medium), expected: MainChamferedRectangle(.medium).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.nested, legacy: ChamferedRectangle(.small), expected: MainChamferedRectangle(.small).path(in: rect), rect: rect, radius: 10)
            ShapeRoleTestSupport.check(.control, legacy: ChamferedRectangle(.medium), expected: MainChamferedRectangle(.medium).path(in: rect), rect: rect, radius: min(rect.width, rect.height) / 2)
            ShapeRoleTestSupport.check(.card, legacy: ChamferedRectangle(.xl), expected: MainChamferedRectangle(.xl).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.iconTile, legacy: ChamferedRectangleAlt(.medium), expected: MainChamferedRectangleAlt(.medium).path(in: rect), rect: rect, radius: min(rect.width, rect.height) * 0.225)
            ShapeRoleTestSupport.check(.tile, legacy: ChamferedRectangle(.large), expected: MainChamferedRectangle(.large).path(in: rect), rect: rect, radius: 16)
            ShapeRoleTestSupport.check(.iconTile, legacy: ChamferedRectangleAlt(.small), expected: MainChamferedRectangleAlt(.small).path(in: rect), rect: rect, radius: min(rect.width, rect.height) * 0.225)
        }
    }
    #endif
}
