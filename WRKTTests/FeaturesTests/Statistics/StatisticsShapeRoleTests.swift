import Foundation
import SwiftUI
import Testing
@testable import WRKT

@MainActor
struct StatisticsShapeRoleTests {
    #if DEBUG
    @Test func exerciseStatisticsKeepLegacyPaths() throws {
        let source0 = try ShapeRoleTestSupport.source("Statistics/Views/ExerciseStatisticsView.swift")
        #expect(source0.contains("DS.RoleShape(.control, legacy: ChamferedRectangleAlt(.micro))"))
        #expect(source0.contains("DS.RoleShape(.card, legacy: ChamferedRectangle(.large))"))
        #expect(source0.contains("DS.RoleShape(.tile, legacy: ChamferedRectangleAlt(.large))"))
        #expect(source0.contains("DS.RoleShape(.tile, legacy: ChamferedRectangle(.large))"))
        #expect(source0.contains("DS.RoleShape(.control, legacy: ChamferedRectangle(.large))"))
        for rect in ShapeRoleTestSupport.rects {
            ShapeRoleTestSupport.check(.control, legacy: ChamferedRectangleAlt(.micro), expected: MainChamferedRectangleAlt(.micro).path(in: rect), rect: rect, radius: min(rect.width, rect.height) / 2)
            ShapeRoleTestSupport.check(.card, legacy: ChamferedRectangle(.large), expected: MainChamferedRectangle(.large).path(in: rect), rect: rect, radius: 26)
            ShapeRoleTestSupport.check(.tile, legacy: ChamferedRectangleAlt(.large), expected: MainChamferedRectangleAlt(.large).path(in: rect), rect: rect, radius: 16)
            ShapeRoleTestSupport.check(.tile, legacy: ChamferedRectangle(.large), expected: MainChamferedRectangle(.large).path(in: rect), rect: rect, radius: 16)
            ShapeRoleTestSupport.check(.control, legacy: ChamferedRectangle(.large), expected: MainChamferedRectangle(.large).path(in: rect), rect: rect, radius: min(rect.width, rect.height) / 2)
        }
    }
    #endif
}
