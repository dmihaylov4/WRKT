import Foundation
import SwiftUI
import Testing
@testable import WRKT

@MainActor
struct PlannerShapeRoleTests {
    #if DEBUG
    @Test func calendarSurfacesKeepLegacyPathsAndNestedDayCells() throws {
        #expect(try ShapeRoleTestSupport.source("Planner/Components/CalendarGrid.swift").contains("DS.RoleShape(.nested, legacy: TopLeftChamferedRectangle(.small, cornerRadius: 10))"))
        #expect(try ShapeRoleTestSupport.source("Planner/CalendarMonthView.swift").contains("DS.RoleShape(.control, legacy: ChamferedRectangle(.small))"))
        let banners = try ShapeRoleTestSupport.source("Planner/Components/CalendarBanners.swift")
        #expect(banners.contains("DS.RoleShape(.card, legacy: RoundedRectangle(cornerRadius: 10, style: .continuous))"))
        for rect in ShapeRoleTestSupport.rects + [CGRect(x: 3, y: 7, width: 42, height: 52)] {
            ShapeRoleTestSupport.check(.nested, legacy: TopLeftChamferedRectangle(.small, cornerRadius: 10), expected: MainTopLeftChamferedRectangle(chamferSize: 8, cornerRadius: 10).path(in: rect), rect: rect, radius: 10)
            ShapeRoleTestSupport.check(.card, legacy: ChamferedRectangleAlt(.large), expected: MainChamferedRectangleAlt(.large).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.card, legacy: RoundedRectangle(cornerRadius: 10, style: .continuous), expected: RoundedRectangle(cornerRadius: 10, style: .continuous).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.control, legacy: ChamferedRectangle(.small), expected: MainChamferedRectangle(.small).path(in: rect), rect: rect, radius: min(rect.width, rect.height) / 2)
        }
    }
    #endif
}
